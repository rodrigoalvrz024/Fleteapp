"""Test the release MFA migration and concurrent TOTP use on disposable PostgreSQL."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import sysconfig
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]


def python_environment(env):
    result = dict(env)
    if sys.platform == "linux" and sysconfig.get_config_var("Py_ENABLE_SHARED"):
        prefix = Path(sys.base_prefix).resolve(strict=True)
        directory = Path(sysconfig.get_config_var("LIBDIR")).resolve(strict=True)
        name = sysconfig.get_config_var("LDLIBRARY")
        if not isinstance(name, str) or Path(name).name != name:
            raise RuntimeError("Invalid runtime library name")
        library = (directory / name).resolve(strict=True)
        if not directory.is_relative_to(prefix) or not library.is_relative_to(directory) or not library.is_file():
            raise RuntimeError("Library must belong to this Python runtime")
        result["LD_LIBRARY_PATH"] = str(directory)
    return result


def worker():
    from sqlalchemy import create_engine, text
    from sqlalchemy.engine import make_url
    from sqlalchemy.orm import Session
    from alembic import command
    from alembic.config import Config
    from cryptography.hazmat.primitives.hashes import SHA1
    from cryptography.hazmat.primitives.twofactor.totp import TOTP
    from fastapi import HTTPException

    url = make_url(os.environ["DATABASE_URL"])
    assert url.host == "127.0.0.1" and url.username == "muvv_mfa_owner"
    assert url.database == "muvv_mfa_fixture" and os.environ["APP_ENV"] == "test"
    sys.path.insert(0, str(ROOT / "backend"))
    from app.database import Base, engine as app_engine
    import app.models
    from app.models.admin_second_factor import AdminSecondFactor
    from app.models.user import User, UserRole
    from app.services.admin_mfa_service import seal_secret, verify_factor
    from app.services.row_lock_service import lock_first

    engine = create_engine(url)
    try:
        # Reproduce the deployed schema; do not run legacy migrations on real data.
        Base.metadata.create_all(engine, tables=[t for n, t in Base.metadata.tables.items()
                                               if n != "admin_second_factors"])
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE users DROP COLUMN session_version"))
            conn.execute(text("CREATE TABLE unrelated_fixture (value INTEGER NOT NULL)"))
            conn.execute(text("INSERT INTO unrelated_fixture VALUES (42)"))
        config = Config(str(ROOT / "backend/alembic.ini"))
        config.set_main_option("script_location", str(ROOT / "backend/alembic"))
        command.stamp(config, "b2e4f6a81047")
        command.upgrade(config, "head")
        with engine.begin() as conn:
            assert conn.execute(text("SELECT version_num FROM alembic_version")).scalar() == "f30c6a8b210d"
            assert conn.execute(text("SELECT value FROM unrelated_fixture")).scalar() == 42
            assert conn.execute(text("SELECT relrowsecurity FROM pg_class WHERE oid = 'admin_second_factors'::regclass")).scalar()
            for role in ("anon", "authenticated"):
                for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE"):
                    assert not conn.execute(text("SELECT has_table_privilege(:role, 'admin_second_factors', :p)"),
                                            {"role": role, "p": privilege}).scalar()
            assert not conn.execute(text("SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname = current_user")).scalar()
        print("PASS: migration, unchanged sentinel, private RLS and non-superuser backend")

        now = datetime.now(timezone.utc)
        secret = b"12345678901234567890"  # Published RFC fixture, never a real account.
        with Session(engine) as db:
            user = User(id=1, email="synthetic@example.com", phone="56900000000", full_name="Fixture",
                        hashed_password="synthetic-unused", role=UserRole.admin, account_roles=["admin"])
            db.add(user)
            db.flush()
            db.add(AdminSecondFactor(user_id=1, encrypted_secret=seal_secret(1, secret),
                                     last_counter=-1, failures=0, activated_at=now))
            db.commit()
            assert user.session_version == 0

        def concurrent(codes):
            barrier = threading.Barrier(len(codes))

            def attempt(code):
                with Session(engine) as db:
                    barrier.wait(timeout=10)
                    try:
                        lock_first(db.query(User).filter(User.id == 1))
                        factor = lock_first(db.query(AdminSecondFactor).filter(AdminSecondFactor.user_id == 1))
                        verify_factor(db, factor, code, now)
                        db.commit()
                        return 200
                    except HTTPException as exc:
                        db.rollback()
                        return exc.status_code

            with ThreadPoolExecutor(max_workers=len(codes)) as pool:
                return sorted(pool.map(attempt, codes))

        code = TOTP(secret, 6, SHA1(), 30).generate(int(now.timestamp())).decode()
        assert concurrent([code, code]) == [200, 401]
        print("PASS: simultaneous reuse produces exactly one success and one rejection")
        with Session(engine) as db:
            factor = db.get(AdminSecondFactor, 1)
            factor.failures = 0
            db.commit()
        assert concurrent(["invalid"] * 5) == [401] * 5
        with Session(engine) as db:
            factor = db.get(AdminSecondFactor, 1)
            assert factor.failures == 5 and factor.locked_until > now
        assert concurrent([code]) == [429]
        print("PASS: concurrent failures persist and enforce lockout")
        command.upgrade(config, "head")
        with Session(engine) as db:
            assert db.get(AdminSecondFactor, 1).failures == 5
        print("PASS: repeated migration preserves enrolled factor and lockout")
    finally:
        engine.dispose()
        app_engine.dispose()


def parent(pg_bin):
    from cryptography.fernet import Fernet
    import psycopg2
    from sqlalchemy import URL

    suffix = ".exe" if os.name == "nt" else ""
    binaries = {name: pg_bin.resolve(strict=True) / (name + suffix) for name in ("initdb", "pg_ctl")}
    if not all(p.is_file() for p in binaries.values()):
        raise RuntimeError("PostgreSQL binaries missing")
    scratch = (ROOT / ".local-tools/mfa-tests").resolve()
    if not scratch.is_relative_to(ROOT):
        raise RuntimeError("Scratch path outside workspace")
    scratch.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="run-", dir=scratch)).resolve()
    data = run / "data"
    password = secrets.token_urlsafe(32)
    pwfile = run / "password.txt"
    pwfile.write_text(password, encoding="ascii")
    pwfile.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k.upper() in {"SYSTEMROOT", "WINDIR", "PATH", "TEMP", "TMP"}}
    hidden = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    def pg(name, *args):
        with (run / (name + ".log")).open("a", encoding="utf8") as out:
            subprocess.run([str(binaries[name]), *map(str, args)], env=env, stdin=subprocess.DEVNULL,
                           stdout=out, stderr=subprocess.STDOUT, creationflags=hidden, timeout=90, check=True)

    try:
        pg("initdb", "-D", data, "-U", "muvv_test_superuser", "--auth=scram-sha-256",
           "--pwfile", pwfile, "--encoding=UTF8", "--locale=C")
        with (data / "postgresql.conf").open("a", encoding="ascii") as file:
            file.write(f"\nlisten_addresses = '127.0.0.1'\nport = {port}\nunix_socket_directories = ''\n")
        pg("pg_ctl", "-D", data, "-l", run / "server.log", "-w", "-t", "30", "start")
        options = dict(host="127.0.0.1", hostaddr="127.0.0.1", port=port, dbname="postgres",
                       user="muvv_test_superuser", password=password, connect_timeout=5)
        owner_password = secrets.token_urlsafe(32)
        conn = psycopg2.connect(**options)
        try:
            conn.autocommit = True
            with conn.cursor() as cursor:
                cursor.execute("CREATE ROLE anon NOLOGIN NOSUPERUSER NOBYPASSRLS")
                cursor.execute("CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOBYPASSRLS")
                cursor.execute("CREATE ROLE muvv_mfa_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS PASSWORD %s", (owner_password,))
                cursor.execute("CREATE DATABASE muvv_mfa_fixture OWNER muvv_mfa_owner")
        finally:
            conn.close()
        child = dict(python_environment(env), APP_ENV="test", RUN_STARTUP_MIGRATIONS="false", PYTHONIOENCODING="utf-8",
                     SECRET_KEY=secrets.token_urlsafe(48), ADMIN_MFA_ENCRYPTION_KEY=Fernet.generate_key().decode(),
                     PGOPTIONS="-c statement_timeout=20000 -c lock_timeout=5000",
                     DATABASE_URL=URL.create("postgresql+psycopg2", username="muvv_mfa_owner", password=owner_password,
                         host="127.0.0.1", port=port, database="muvv_mfa_fixture").render_as_string(hide_password=False))
        result = subprocess.run([sys.executable, "-B", str(Path(__file__).resolve()), "--worker"],
                                cwd=run, env=child, creationflags=hidden, timeout=180, check=False,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8")
        output = result.stdout
        for private in (owner_password, password, child["SECRET_KEY"], child["ADMIN_MFA_ENCRYPTION_KEY"]):
            output = output.replace(private, "[redacted]")
        print(output, end="")
        return result.returncode
    finally:
        if (data / "postmaster.pid").exists():
            pg("pg_ctl", "-D", data, "-m", "fast", "-w", "-t", "60", "stop")
        if run.parent != scratch or not run.name.startswith("run-"):
            raise RuntimeError("Unexpected cleanup target")
        shutil.rmtree(run)
        print("Disposable cluster stopped and removed; no external database used.")


if __name__ == "__main__":
    if not __debug__:
        raise SystemExit("Run tests without Python optimization; assertions are mandatory.")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        worker()
    elif args.pg_bin:
        safe_env = {k: v for k, v in os.environ.items() if k.upper() in {"SYSTEMROOT", "WINDIR", "PATH", "TEMP", "TMP"}}
        os.environ.clear()
        os.environ.update(safe_env)
        raise SystemExit(parent(args.pg_bin))
    else:
        parser.error("--pg-bin required")
