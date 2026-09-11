"""Explicit, Windows-only encrypted backup and loopback restore drill for Muvv.

No scheduler, production writes, remote restore, or application startup.
Private data and credentials never belong in this repository or stdout.
"""

import argparse
import base64
import csv
import ctypes
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
import zipfile

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from dotenv import dotenv_values
import httpx
import psycopg2
from psycopg2 import sql


REPO = Path(__file__).resolve().parents[1]
PROJECT = "vlyolrdjtkxabtcbrulg"
BUCKET = "muvv-private"
BASE = f"https://{PROJECT}.supabase.co"
PG_BIN = Path(r"C:\Program Files\PostgreSQL\18\bin")
BACKUPS = Path.home() / "MuvvBackups"
KEYS = Path(os.environ.get("LOCALAPPDATA", "")) / "MuvvBackupKeys"
MAX_BYTES = 128 * 1024 * 1024
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class BackupInputError(Exception):
    """A safe local-file diagnostic, never raw provider or decrypted content."""


def read_backup_input(path, label, maximum=MAX_BYTES * 2):
    path = Path(path)
    try:
        with path.open("rb") as source:
            content = source.read(maximum + 1)
    except FileNotFoundError:
        raise BackupInputError(f"No se encuentra {label}: {path}") from None
    except PermissionError:
        raise BackupInputError(f"Acceso denegado a {label}: {path}. Usa el usuario Windows propietario.") from None
    if not content or len(content) > maximum:
        raise BackupInputError(f"Tamano no valido para {label}: {path}")
    return content


def read_backup_key(run, key_file=None):
    run_path(run)
    path = Path(key_file) if key_file is not None else KEYS / f"{run}.backup.dpapi"
    protected = read_backup_input(path, "la clave protegida DPAPI", maximum=8192)
    try:
        key = dpapi(protected, decrypt=True)
        Fernet(key)
    except Exception:
        raise BackupInputError(
            "La clave DPAPI no pudo abrirse con este perfil Windows; no generes otra clave para este respaldo."
        ) from None
    return key


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, default=str).encode()


def dpapi(data, decrypt=False):
    if os.name != "nt":
        raise RuntimeError("Windows is required")

    class Blob(ctypes.Structure):
        _fields_ = [("size", ctypes.c_ulong), ("data", ctypes.c_void_p)]

    memory = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(memory, ctypes.c_void_p))
    target = Blob()
    crypt = ctypes.WinDLL("crypt32", use_last_error=True)
    function = crypt.CryptUnprotectData if decrypt else crypt.CryptProtectData
    description = None if decrypt else ctypes.c_wchar_p("Muvv private backup")
    if not function(ctypes.byref(source), description, None, None, None, 1, ctypes.byref(target)):
        raise RuntimeError("Windows key protection failed")
    try:
        return ctypes.string_at(target.data, target.size)
    finally:
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.LocalFree.argtypes = [ctypes.c_void_p]
        kernel.LocalFree(ctypes.c_void_p(target.data))


def secure_root(path):
    if os.name != "nt" or path.resolve().is_relative_to(REPO.resolve()):
        raise RuntimeError("Private files must remain outside the repository")
    if path.exists() and not (path / ".muvv-private-root").is_file():
        raise RuntimeError("Refusing an unrecognized existing directory")
    if path.is_symlink() or path.absolute() != path.resolve():
        raise RuntimeError("Redirected private directory refused")
    path.mkdir(parents=True, exist_ok=True)
    account = subprocess.run(["whoami", "/user", "/fo", "csv", "/nh"],
                             capture_output=True, text=True, check=True, timeout=10,
                             creationflags=HIDDEN)
    sid = next(csv.reader(io.StringIO(account.stdout)))[1]
    subprocess.run(["icacls", str(path), "/inheritance:r", "/grant:r",
                    f"*{sid}:(OI)(CI)F", "*S-1-5-18:(OI)(CI)F"],
                   capture_output=True, check=True, timeout=10, creationflags=HIDDEN)
    (path / ".muvv-private-root").write_text("Muvv private backup files\n", encoding="ascii")


def run_path(run):
    if not re.fullmatch(r"\d{8}T\d{6}Z-[a-f0-9]{8}", run):
        raise ValueError("Invalid backup identifier")
    target = BACKUPS / run
    if target.resolve().parent != BACKUPS.resolve():
        raise ValueError("Backup path escaped its root")
    return target


def oaep():
    return padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None)


def initialize():
    secure_root(BACKUPS)
    secure_root(KEYS)
    run = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + secrets.token_hex(4)
    path = run_path(run)
    path.mkdir()
    private = rsa.generate_private_key(public_exponent=65537, key_size=4096)
    (KEYS / f"{run}.ingest.dpapi").write_bytes(dpapi(private.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())))
    public = private.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    (path / "ingest-public.pem").write_bytes(public)
    (KEYS / f"{run}.backup.dpapi").write_bytes(dpapi(Fernet.generate_key()))
    print(json.dumps({"run": run, "public_key": str(path / "ingest-public.pem"),
                      "backup_directory": str(path), "key_directory": str(KEYS)}))


def capture_key(run, ciphertext):
    run_path(run)
    private = serialization.load_pem_private_key(
        dpapi((KEYS / f"{run}.ingest.dpapi").read_bytes(), decrypt=True), password=None)
    key = private.decrypt(base64.b64decode(ciphertext, validate=True), oaep())
    if key.startswith(b"eyJ"):
        parts = key.split(b".")
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + b"=" * (-len(parts[1]) % 4)))
        if claims.get("role") != "service_role" or claims.get("ref") != PROJECT:
            raise ValueError("Wrong credential role or project")
    elif not key.startswith(b"sb_secret_"):
        raise ValueError("Server credential required")
    (KEYS / f"{run}.storage.dpapi").write_bytes(dpapi(key))
    print("Storage credential protected by Windows; no value displayed.")


def source_options():
    raw = dotenv_values(REPO / "backend/.env").get("DATABASE_URL", "")
    values = psycopg2.extensions.parse_dsn(raw)
    host = values.get("host", "")
    user = values.get("user", "")
    if host != "aws-1-us-west-1.pooler.supabase.com" or user != f"postgres.{PROJECT}":
        raise ValueError("Unexpected source database")
    # pg_dump needs the documented session pooler, not transaction pooling.
    return {"host": host, "port": 5432, "dbname": values.get("dbname", "postgres"),
            "user": user, "password": values["password"], "sslmode": "require",
            "connect_timeout": 10}


def pg_env(options):
    env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
    for key, value in options.items():
        variable = {"dbname": "PGDATABASE", "connect_timeout": "PGCONNECT_TIMEOUT"}.get(key, "PG" + key.upper())
        env[variable] = str(value)
    return env


def read_transaction(conn):
    conn.set_session(isolation_level="REPEATABLE READ", readonly=True, autocommit=False)
    with conn.cursor() as c:
        c.execute("SET LOCAL statement_timeout='30s'")
        c.execute("SET LOCAL lock_timeout='5s'")
        c.execute("SET LOCAL timezone='UTC'")
        c.execute("SHOW transaction_read_only")
        if c.fetchone() != ("on",):
            raise RuntimeError("Read-only source transaction required")


def public_fingerprints(conn, extra_float_digits=3):
    result = {}
    with conn.cursor() as c:
        c.execute("SELECT set_config('extra_float_digits', %s, true)", (str(extra_float_digits),))
        c.execute("SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity, pg_get_userbyid(c.relowner) "
                  "FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
                  "WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname")
        tables = c.fetchall()
        for name, rls, force, owner in tables:
            c.execute(sql.SQL("SELECT count(*) FROM public.{}").format(sql.Identifier(name)))
            count = c.fetchone()[0]
            data = io.BytesIO()
            c.copy_expert(sql.SQL("COPY (SELECT row_to_json(t)::text FROM public.{} t "
                                 "ORDER BY row_to_json(t)::text COLLATE \"C\") TO STDOUT").format(
                                     sql.Identifier(name)).as_string(conn), data)
            result[name] = {"rows": count, "sha256": sha(data.getvalue()),
                            "rls": rls, "force_rls": force, "owner": owner}
    return result


def storage_inventory(conn):
    with conn.cursor() as c:
        c.execute("SELECT id::text, name, metadata, updated_at::text FROM storage.objects "
                  "WHERE bucket_id=%s ORDER BY name", (BUCKET,))
        return [dict(zip(("id", "name", "metadata", "updated_at"), row)) for row in c.fetchall()]


def backup(run):
    path = run_path(run)
    if (path / "backup.fernet").exists():
        raise ValueError("Backup already exists; refusing overwrite")
    key = dpapi((KEYS / f"{run}.storage.dpapi").read_bytes(), decrypt=True).decode()
    headers = {"apikey": key}
    if not key.startswith("sb_secret_"):
        headers["Authorization"] = "Bearer " + key
    options = source_options()
    conn = psycopg2.connect(**options)
    try:
        read_transaction(conn)
        with conn.cursor() as c:
            c.execute("SELECT pg_export_snapshot()")
            snapshot = c.fetchone()[0]
            c.execute("SELECT version_num FROM public.alembic_version")
            revisions = [r[0] for r in c.fetchall()]
            c.execute("SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' ORDER BY rolname")
            roles = [r[0] for r in c.fetchall()]
        inventory = storage_inventory(conn)
        if sum(int(o["metadata"].get("size", 0)) for o in inventory) > MAX_BYTES // 2:
            raise ValueError("Backup size exceeds this manual tool's limit")
        print("Reading database snapshot (no production writes).", flush=True)
        dump = subprocess.run([str(PG_BIN / "pg_dump.exe"), "--format=custom", "--no-password",
                               "--lock-wait-timeout=10000", "--snapshot=" + snapshot],
                              env=pg_env(options), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=180, creationflags=HIDDEN)
        if dump.returncode:
            raise RuntimeError("pg_dump failed; private output was not printed")
        if not dump.stdout.startswith(b"PGDMP") or len(dump.stdout) > MAX_BYTES // 2:
            raise ValueError("Invalid or oversized database dump")
        fingerprints = public_fingerprints(conn)
        manifest = {"format": 2, "project": PROJECT, "bucket": BUCKET, "run": run,
                    "snapshot_at": datetime.now(timezone.utc).isoformat(),
                    "revisions": revisions, "roles": roles, "tables": fingerprints,
                    "database_sha256": sha(dump.stdout), "objects": []}
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as output:
            output.writestr("database/full.dump", dump.stdout)
            with httpx.Client(base_url=BASE, headers=headers, follow_redirects=False,
                              timeout=httpx.Timeout(45, connect=10)) as client:
                bucket = client.get(f"/storage/v1/bucket/{BUCKET}")
                if bucket.status_code != 200 or bucket.json().get("public") is not False:
                    raise RuntimeError("Private bucket could not be confirmed")
                manifest["bucket_settings"] = bucket.json()
                for index, item in enumerate(inventory):
                    from urllib.parse import quote
                    url = f"/storage/v1/object/authenticated/{BUCKET}/" + quote(item["name"], safe="/")
                    response = client.get(url)
                    if response.status_code != 200:
                        raise RuntimeError(f"Private download rejected ({response.status_code})")
                    content = response.content
                    if len(content) != int(item["metadata"]["size"]):
                        raise RuntimeError("Storage object size changed")
                    member = f"storage/{index:06d}.bin"
                    output.writestr(member, content)
                    manifest["objects"].append({**item, "member": member, "sha256": sha(content)})
                    print(f"Private files copied: {index + 1}/{len(inventory)}", flush=True)
                # A second GET detects object changes during the bounded copy.
                for item in manifest["objects"]:
                    response = client.get(f"/storage/v1/object/authenticated/{BUCKET}/" + quote(item["name"], safe="/"))
                    if response.status_code != 200 or sha(response.content) != item["sha256"]:
                        raise RuntimeError("Storage changed during backup; new snapshot required")
            output.writestr("manifest.json", json_bytes(manifest))
        with psycopg2.connect(**options) as check:
            read_transaction(check)
            if storage_inventory(check) != inventory:
                raise RuntimeError("Storage inventory changed during backup")
        if archive.tell() > MAX_BYTES:
            raise ValueError("Archive exceeds size limit")
        backup_key = dpapi((KEYS / f"{run}.backup.dpapi").read_bytes(), decrypt=True)
        encrypted = Fernet(backup_key).encrypt(archive.getvalue())
        (path / "backup.fernet").write_bytes(encrypted)
        report = {"run": run, "project": PROJECT, "status": "encrypted_backup_created",
                  "public_tables": len(fingerprints), "private_files": len(inventory),
                  "private_bytes": sum(int(o["metadata"]["size"]) for o in inventory),
                  "encrypted_bytes": len(encrypted), "sha256": sha(encrypted),
                  "restore_verified": False, "key_portability": "Windows current user via DPAPI"}
        (path / "report.json").write_bytes(json_bytes(report))
        print(json.dumps(report))
    finally:
        conn.close()


def safe_remove_drill(path, root):
    resolved = path.resolve()
    if resolved.parent != root.resolve() or not resolved.name.startswith("drill-") or path.is_symlink():
        raise RuntimeError("Unsafe restore cleanup path")
    shutil.rmtree(resolved)


def verify_restore(run, recovery_key=None):
    path = run_path(run)
    encrypted = read_backup_input(path / "backup.fernet", "el respaldo cifrado")
    key = recovery_key if recovery_key is not None else read_backup_key(run)
    # Authentication is complete before parsing or writing decrypted content.
    archive = zipfile.ZipFile(io.BytesIO(Fernet(key).decrypt(encrypted)))
    manifest = json.loads(archive.read("manifest.json"))
    if manifest["run"] != run or manifest["project"] != PROJECT:
        raise ValueError("Backup identity mismatch")
    dump = archive.read("database/full.dump")
    if sha(dump) != manifest["database_sha256"]:
        raise ValueError("Database integrity mismatch")
    drill = path / ("drill-" + secrets.token_hex(8))
    secure_root(drill)
    data = drill / "pgdata"
    password = secrets.token_urlsafe(32)
    password_file = drill / "password"
    password_file.write_text(password, encoding="ascii")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    local = {"host": "127.0.0.1", "port": port, "dbname": "postgres", "user": "muvv_restore",
             "password": password, "connect_timeout": 5, "sslmode": "disable"}
    child_env = pg_env(local)
    started = False

    def pg(name, *args):
        with (drill / (name + ".log")).open("ab") as log:
            result = subprocess.run([str(PG_BIN / name), *map(str, args)], env=child_env,
                                    stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                    timeout=180, creationflags=HIDDEN)
        if result.returncode:
            raise RuntimeError(f"Local {name} failed; private log withheld")

    try:
        (drill / "database.dump").write_bytes(dump)
        for item in manifest["objects"]:
            if not re.fullmatch(r"storage/\d{6}\.bin", item["member"]):
                raise ValueError("Invalid archive object path")
            content = archive.read(item["member"])
            if sha(content) != item["sha256"]:
                raise ValueError("Private file integrity mismatch")
            destination = drill / Path(item["member"]).name
            destination.write_bytes(content)
            if sha(destination.read_bytes()) != item["sha256"]:
                raise ValueError("Restored file differs")
        pg("initdb.exe", "-D", data, "-U", local["user"], "--auth=scram-sha-256",
           "--pwfile", password_file, "--encoding=UTF8", "--locale=C")
        pg("pg_ctl.exe", "-D", data, "-l", drill / "server.log", "-o",
           f"-h 127.0.0.1 -p {port}", "-w", "-t", "30", "start")
        started = True
        with psycopg2.connect(**local) as conn:
            with conn.cursor() as c:
                c.execute("SELECT rolname FROM pg_roles")
                existing = {r[0] for r in c.fetchall()}
                for role in manifest["roles"]:
                    if role not in existing and not role.startswith("pg_"):
                        c.execute(sql.SQL("CREATE ROLE {} NOLOGIN NOSUPERUSER NOBYPASSRLS").format(sql.Identifier(role)))
        pg("pg_restore.exe", "--dbname=postgres", "--schema=public", "--no-password",
           "--single-transaction", "--exit-on-error", "--no-publications", "--no-subscriptions",
           drill / "database.dump")
        with psycopg2.connect(**local) as conn:
            read_transaction(conn)
            # The first snapshot used the source's verified setting (0).
            # New snapshots explicitly use round-trip numeric serialization (3).
            precision = 0 if manifest["format"] == 1 else 3
            restored = public_fingerprints(conn, extra_float_digits=precision)
            if restored != manifest["tables"]:
                comparison = {"expected": manifest["tables"], "restored": restored}
                (path / "restore-comparison.fernet").write_bytes(Fernet(key).encrypt(json_bytes(comparison)))
                raise ValueError("Restored public tables differ from snapshot")
            with conn.cursor() as c:
                c.execute("SELECT version_num FROM public.alembic_version")
                if [r[0] for r in c.fetchall()] != manifest["revisions"]:
                    raise ValueError("Restored migration revision differs")
        report = json.loads((path / "report.json").read_bytes())
        report.update({"restore_verified": True, "restored_tables": len(restored),
                       "restored_files": len(manifest["objects"]),
                       "restore_scope": "public application schema with owners/ACLs and private file bytes",
                       "managed_supabase_schemas_restored": False,
                       "comparison_extra_float_digits": precision,
                       "verified_at": datetime.now(timezone.utc).isoformat()})
        (path / "report.json").write_bytes(json_bytes(report))
        print(json.dumps(report))
    except Exception as error:
        diagnostic = {f.name: f.read_text(encoding="utf8", errors="replace")[-12000:]
                      for f in drill.glob("*.log")}
        diagnostic["operation_error"] = type(error).__name__ + ": " + str(error)
        (path / "restore-diagnostic.fernet").write_bytes(Fernet(key).encrypt(json_bytes(diagnostic)))
        raise
    finally:
        archive.close()
        if started or (data / "postmaster.pid").exists():
            pg("pg_ctl.exe", "-D", data, "-m", "fast", "-w", "-t", "30", "stop")
        safe_remove_drill(drill, path)
        print("Local restore instance stopped; temporary plaintext files removed.")


def check_backup(run, key_file=None):
    from muvv_backup_portable import verify_content

    path = run_path(run)
    encrypted = read_backup_input(path / "backup.fernet", "el respaldo cifrado")
    key = read_backup_key(run, key_file)
    result = verify_content(key, encrypted, run)
    print("Respaldo y clave original comprobados. No se extrajeron datos ni se creo la copia portable.")
    print(json.dumps({"run": run, "backup_file": str(path / "backup.fernet"),
                      "key_file": str(key_file if key_file is not None else KEYS / f"{run}.backup.dpapi"),
                      "original_key_verified": True, "encrypted_sha256": result["encrypted_sha256"],
                      "public_tables": result["public_tables"], "private_files": result["private_files"]}))


def export_portable(run, key_file=None):
    from muvv_backup_portable import protect_key, read_passphrase, unlock_key, verify_content

    path = run_path(run)
    destination = path / f"muvv-recovery-{run}.zip"
    if destination.exists():
        raise ValueError("Portable package already exists; refusing overwrite")
    encrypted = read_backup_input(path / "backup.fernet", "el respaldo cifrado")
    source_report = read_backup_input(path / "report.json", "el informe del respaldo", maximum=65536)
    key = read_backup_key(run, key_file)
    verify_content(key, encrypted, run)
    print("Guarda una contrasena unica en tu gestor: 6 palabras aleatorias o 24 caracteres aleatorios.")
    print("No la envies al chat, no la guardes junto al ZIP. Minimo aceptado: 20 caracteres.")
    password = read_passphrase(confirm=True)
    envelope = protect_key(key, password, run, encrypted)
    # Exercise only the portable envelope here; DPAPI is not used to verify it.
    recovered, recovered_run = unlock_key(envelope, password, encrypted)
    report = verify_content(recovered, encrypted, recovered_run)
    readme = (
        "Muvv - Recuperacion portable\n\n"
        f"Respaldo: {run}\n"
        "Este ZIP NO usa una contrasena ZIP. Los datos y la clave interior ya estan cifrados.\n"
        "Extrae estos archivos juntos en una carpeta privada, fuera de Git.\n"
        "No contiene la contrasena: recuperala de tu gestor o copia fisica segura.\n\n"
        "Comprobar en otro equipo (Python 3.11+, sin credenciales de produccion):\n"
        "  python -m pip install cryptography==46.0.6\n"
        "  python muvv_backup_portable.py\n"
        "La contrasena se pide de forma oculta; nunca la pongas como argumento.\n"
        "Verifica la clave, el volcado y los archivos solo en memoria, sin restaurar SQL.\n\n"
        "Restauracion de la base en Windows: requiere el proyecto confiable, sus\n"
        "dependencias y PostgreSQL 18. Copia backup.fernet, recovery-key.json y report.json\n"
        f"a %USERPROFILE%\\MuvvBackups\\{run} y sigue docs/private-backup-recovery.md.\n"
        "Nunca restaures un volcado de origen desconocido ni sobre produccion para probar.\n\n"
        "Guarda el ZIP en una carpeta privada de nube, sin enlaces publicos y con MFA.\n"
        "Descarga una copia nueva desde la nube y verifica ESA copia. Una carpeta\n"
        "sincronizada en el PC no acredita por si sola que los bytes esten en la nube.\n"
        "Perder la contrasena y la clave DPAPI impide recuperar este respaldo.\n"
    )
    package = io.BytesIO()
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_STORED) as output:
        output.writestr("backup.fernet", encrypted)
        output.writestr("recovery-key.json", envelope)
        output.writestr("muvv_backup_portable.py", (REPO / "scripts/muvv_backup_portable.py").read_bytes())
        output.writestr("RECUPERAR.txt", readme.encode("ascii"))
        output.writestr("report.json", source_report)
    payload = package.getvalue()
    with destination.open("xb") as output:
        output.write(payload)
    if sha(destination.read_bytes()) != sha(payload):
        raise ValueError("Portable package write verification failed")
    report.update({"package": destination.name, "package_sha256": sha(payload),
                   "key_protection": "Argon2id + Fernet; user-held passphrase",
                   "offsite_copy_verified": False, "second_computer_tested": False,
                   "created_at": datetime.now(timezone.utc).isoformat()})
    (path / "portable-report.json").write_bytes(json_bytes(report))
    print("Paquete portable creado y descifrado verificado. Aun falta subirlo y verificar la descarga.")
    print("Archivo para subir: " + str(destination))
    print(json.dumps(report))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("init", "capture-key", "backup", "check", "verify", "forget-storage-key", "export-portable"))
    parser.add_argument("--run")
    parser.add_argument("--ciphertext")
    parser.add_argument("--portable-key", type=Path, help="Encrypted recovery-key.json, only with verify")
    parser.add_argument("--key-file", type=Path, help="Existing protected DPAPI file, only with check/export-portable/verify")
    args = parser.parse_args()
    try:
        if args.portable_key and args.action != "verify":
            raise ValueError("Portable key is only supported for verification")
        if args.key_file and (args.action not in ("check", "export-portable", "verify") or args.portable_key):
            raise ValueError("Choose only one key source for a supported action")
        if args.action == "init":
            initialize()
            return 0
        run_path(args.run or "")
        if args.action == "capture-key":
            capture_key(args.run, args.ciphertext or "")
        elif args.action == "backup":
            backup(args.run)
        elif args.action == "check":
            check_backup(args.run, key_file=args.key_file)
        elif args.action == "verify":
            recovery_key = None
            if args.portable_key:
                from muvv_backup_portable import MAX_KEY_BYTES, read_limited, read_passphrase, unlock_key
                encrypted = (run_path(args.run) / "backup.fernet").read_bytes()
                recovery_key, recovered_run = unlock_key(
                    read_limited(args.portable_key, MAX_KEY_BYTES), read_passphrase(), encrypted)
                if recovered_run != args.run:
                    raise ValueError("Recovery key is for another snapshot")
            elif args.key_file:
                recovery_key = read_backup_key(args.run, args.key_file)
            verify_restore(args.run, recovery_key=recovery_key)
        elif args.action == "export-portable":
            export_portable(args.run, key_file=args.key_file)
        else:
            for suffix in ("storage.dpapi", "ingest.dpapi"):
                (KEYS / f"{args.run}.{suffix}").unlink(missing_ok=True)
            print("Temporary Storage credential and ingest key removed; backup recovery key retained.")
        return 0
    except KeyboardInterrupt:
        print("Operacion cancelada; no se modifico produccion.")
        return 1
    except BackupInputError as error:
        print(str(error))
        print("No se cambiaron claves ni datos. Revisa las rutas; no ejecutes init para reemplazar esta clave.")
        return 1
    except Exception as error:
        print(f"Backup operation failed ({type(error).__name__}); no private values displayed.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
