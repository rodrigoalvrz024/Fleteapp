"""Offline recovery-key verification. Requires Python 3.11+ and cryptography.

Never contacts production, extracts private files, or prints keys/passwords.
This file can accompany the encrypted backup without the application or DPAPI.
"""

import argparse
import base64
import getpass
import hashlib
import io
import json
from pathlib import Path
import re
import secrets
import sys
import warnings
import zipfile

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id


FORMAT = "muvv-recovery-v1"
KDF = {"name": "argon2id", "iterations": 3, "lanes": 4, "memory_kib": 65536}
PROJECT = "vlyolrdjtkxabtcbrulg"
MAX_ARCHIVE_BYTES = 180 * 1024 * 1024
MAX_CONTENT_BYTES = 128 * 1024 * 1024
MAX_KEY_BYTES = 8192
RUN_PATTERN = r"\d{8}T\d{6}Z-[a-f0-9]{8}"


def json_bytes(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True).encode("ascii")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_limited(path, maximum):
    with Path(path).open("rb") as source:
        value = source.read(maximum + 1)
    if len(value) > maximum:
        raise ValueError("File exceeds recovery limit")
    return value


def read_passphrase(confirm=False):
    if not sys.stdin.isatty():
        raise RuntimeError("Open an interactive terminal; do not pipe the password")
    # getpass must fail closed instead of falling back to visible input.
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        password = getpass.getpass("Contrasena de recuperacion (no se muestra): ")
        validate_passphrase(password)
        if confirm and password != getpass.getpass("Repite la contrasena: "):
            raise ValueError("Passwords do not match")
    return password


def validate_passphrase(password):
    if not isinstance(password, str) or len(password) < 20 or len(password.encode("utf8")) > 1024:
        raise ValueError("Use a unique passphrase of at least 20 characters")
    if len(set(password)) < 5:
        raise ValueError("Use a randomly generated passphrase")


def password_cipher(password, salt):
    validate_passphrase(password)
    if len(salt) != 16:
        raise ValueError("Invalid recovery salt")
    kdf = Argon2id(salt=salt, length=32, iterations=KDF["iterations"],
                  lanes=KDF["lanes"], memory_cost=KDF["memory_kib"])
    return Fernet(base64.urlsafe_b64encode(kdf.derive(password.encode("utf8"))))


def protect_key(key, password, run, encrypted):
    if not re.fullmatch(RUN_PATTERN, run):
        raise ValueError("Invalid backup identity")
    Fernet(key)
    salt = secrets.token_bytes(16)
    # Bind the secret key to the exact encrypted snapshot inside the MAC.
    payload = {"format": FORMAT, "run": run, "backup_sha256": sha(encrypted),
               "key": key.decode("ascii")}
    token = password_cipher(password, salt).encrypt(json_bytes(payload))
    return json_bytes({"format": FORMAT, "kdf": KDF,
                       "salt": base64.b64encode(salt).decode("ascii"),
                       "token": token.decode("ascii")})


def unlock_key(envelope, password, encrypted):
    if len(envelope) > MAX_KEY_BYTES or len(encrypted) > MAX_ARCHIVE_BYTES:
        raise ValueError("Recovery input exceeds limit")
    data = json.loads(envelope)
    if set(data) != {"format", "kdf", "salt", "token"} or data["format"] != FORMAT or data["kdf"] != KDF:
        raise ValueError("Unsupported recovery format")
    # Only the fixed versioned KDF parameters are accepted, not arbitrary costs.
    salt = base64.b64decode(data["salt"], validate=True)
    payload = json.loads(password_cipher(password, salt).decrypt(data["token"].encode("ascii")))
    if (set(payload) != {"format", "run", "backup_sha256", "key"}
            or payload["format"] != FORMAT
            or not re.fullmatch(RUN_PATTERN, payload["run"])
            or payload["backup_sha256"] != sha(encrypted)):
        raise ValueError("Recovery key does not match this backup")
    key = payload["key"].encode("ascii")
    Fernet(key)
    return key, payload["run"]


def verify_content(key, encrypted, run):
    if len(encrypted) > MAX_ARCHIVE_BYTES:
        raise ValueError("Encrypted backup exceeds limit")
    content = Fernet(key).decrypt(encrypted)
    if len(content) > MAX_CONTENT_BYTES:
        raise ValueError("Decrypted backup exceeds limit")
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        entries = archive.infolist()
        if (len({e.filename for e in entries}) != len(entries)
                or sum(e.file_size for e in entries) > MAX_CONTENT_BYTES
                or len(entries) > 10002):
            raise ValueError("Invalid archive size or duplicate entries")
        manifest = json.loads(archive.read("manifest.json"))
        if (manifest["format"] not in (1, 2) or manifest["project"] != PROJECT
                or manifest["run"] != run):
            raise ValueError("Backup identity mismatch")
        dump = archive.read("database/full.dump")
        if not dump.startswith(b"PGDMP") or sha(dump) != manifest["database_sha256"]:
            raise ValueError("Database dump integrity mismatch")
        members = set()
        total = 0
        for item in manifest["objects"]:
            member = item["member"]
            if not re.fullmatch(r"storage/\d{6}\.bin", member) or member in members:
                raise ValueError("Invalid private file member")
            members.add(member)
            data = archive.read(member)
            if sha(data) != item["sha256"] or len(data) != int(item["metadata"]["size"]):
                raise ValueError("Private file integrity mismatch")
            total += len(data)
        if {e.filename for e in entries} != members | {"manifest.json", "database/full.dump"}:
            raise ValueError("Unexpected backup members")
        return {"run": run, "encrypted_sha256": sha(encrypted),
                "public_tables": len(manifest["tables"]), "private_files": len(members),
                "private_bytes": total, "portable_decryption_verified": True,
                "database_restore_performed": False}


def verify_directory(directory, password):
    directory = Path(directory)
    encrypted = read_limited(directory / "backup.fernet", MAX_ARCHIVE_BYTES)
    envelope = read_limited(directory / "recovery-key.json", MAX_KEY_BYTES)
    key, run = unlock_key(envelope, password, encrypted)
    return verify_content(key, encrypted, run)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    try:
        result = verify_directory(args.directory, read_passphrase())
        print("Verificacion portable correcta. No se escribieron datos privados sin cifrar.")
        print(json.dumps(result, sort_keys=True))
        return 0
    except KeyboardInterrupt:
        print("Verificacion cancelada.")
        return 1
    except Exception as error:
        print(f"No se pudo verificar ({type(error).__name__}). Revisa la contrasena y los archivos.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
