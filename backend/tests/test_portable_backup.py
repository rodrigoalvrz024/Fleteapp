import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from cryptography.fernet import Fernet, InvalidToken


ROOT = Path(__file__).resolve().parents[2]


def load_script(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


portable = load_script("muvv_backup_portable", "muvv_backup_portable.py")
backup = load_script("backup_for_portable_test", "backup-muvv-private.py")
RUN = "20260908T000000Z-12345678"
PASSWORD = "synthetic-only-phrase-for-tests-9284"


def fixture(key, *, member="storage/000000.bin", wrong_hash=False):
    dump = b"PGDMP synthetic dump; not a real database"
    image = b"synthetic file, no personal data"
    manifest = {"format": 2, "run": RUN, "project": portable.PROJECT,
                "database_sha256": portable.sha(dump), "tables": {"example": {}},
                "objects": [{"member": member, "metadata": {"size": len(image)},
                             "sha256": "0" * 64 if wrong_hash else portable.sha(image)}]}
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("manifest.json", portable.json_bytes(manifest))
        archive.writestr("database/full.dump", dump)
        archive.writestr(member, image)
    return Fernet(key).encrypt(buffer.getvalue())


class PortableBackupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = Fernet.generate_key()
        cls.encrypted = fixture(cls.key)
        cls.envelope = portable.protect_key(cls.key, PASSWORD, RUN, cls.encrypted)

    def test_round_trip_without_dpapi_or_database(self):
        with patch.object(backup, "dpapi", side_effect=AssertionError("No DPAPI")), \
                patch.object(backup.psycopg2, "connect", side_effect=AssertionError("No SQL")):
            key, run = portable.unlock_key(self.envelope, PASSWORD, self.encrypted)
            result = portable.verify_content(key, self.encrypted, run)
        self.assertEqual(key, self.key)
        self.assertEqual(result["private_files"], 1)
        self.assertEqual(result["public_tables"], 1)
        self.assertFalse(result["database_restore_performed"])

    def test_wrong_password_is_rejected(self):
        with self.assertRaises(InvalidToken):
            portable.unlock_key(self.envelope, PASSWORD + "wrong", self.encrypted)

    def test_tampered_token_is_rejected(self):
        data = json.loads(self.envelope)
        token = bytearray(base64.urlsafe_b64decode(data["token"]))
        token[-1] ^= 1
        data["token"] = base64.urlsafe_b64encode(token).decode()
        with self.assertRaises(InvalidToken):
            portable.unlock_key(portable.json_bytes(data), PASSWORD, self.encrypted)

    def test_envelope_is_bound_to_exact_backup(self):
        with self.assertRaises(ValueError):
            portable.unlock_key(self.envelope, PASSWORD, fixture(self.key))

    def test_untrusted_kdf_parameters_cannot_increase_cost(self):
        data = json.loads(self.envelope)
        data["kdf"]["memory_kib"] *= 1000
        with patch.object(portable, "password_cipher") as derive:
            with self.assertRaises(ValueError):
                portable.unlock_key(portable.json_bytes(data), PASSWORD, self.encrypted)
        derive.assert_not_called()

    def test_fresh_salt_and_ciphertext_for_each_export(self):
        second = portable.protect_key(self.key, PASSWORD, RUN, self.encrypted)
        self.assertNotEqual(self.envelope, second)
        self.assertNotEqual(json.loads(self.envelope)["salt"], json.loads(second)["salt"])
        self.assertNotIn(self.key, second)
        self.assertNotIn(PASSWORD.encode(), second)

    def test_long_unicode_passphrase_is_not_truncated(self):
        password = "\u00e1rbol-\u00f1and\u00fa-" + PASSWORD
        envelope = portable.protect_key(self.key, password, RUN, self.encrypted)
        self.assertEqual(portable.unlock_key(envelope, password, self.encrypted)[0], self.key)

    def test_weak_passphrases_are_refused(self):
        for value in ("easy123", " " * 30, "a" * 40, "x" * 1025):
            with self.subTest(value_length=len(value)), self.assertRaises(ValueError):
                portable.validate_passphrase(value)

    def test_backup_identity_is_checked_after_authentication(self):
        with self.assertRaises(ValueError):
            portable.verify_content(self.key, self.encrypted, "20260908T000000Z-87654321")

    def test_private_file_hash_is_checked(self):
        with self.assertRaises(ValueError):
            portable.verify_content(self.key, fixture(self.key, wrong_hash=True), RUN)

    def test_unsafe_archive_members_are_rejected_without_extraction(self):
        with self.assertRaises(ValueError):
            portable.verify_content(self.key, fixture(self.key, member="../outside"), RUN)

    def test_limited_reader_rejects_oversized_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.bin"
            path.write_bytes(b"12345")
            with self.assertRaises(ValueError):
                portable.read_limited(path, 4)

    def test_password_input_requires_hidden_interactive_terminal(self):
        with patch.object(portable.sys.stdin, "isatty", return_value=False), \
                patch.object(portable.getpass, "getpass") as prompt:
            with self.assertRaises(RuntimeError):
                portable.read_passphrase()
            prompt.assert_not_called()
        with patch.object(portable.sys.stdin, "isatty", return_value=True), \
                patch.object(portable.getpass, "getpass", side_effect=portable.getpass.GetPassWarning("echo")):
            with self.assertRaises(portable.getpass.GetPassWarning):
                portable.read_passphrase()

    def test_password_confirmation_must_match(self):
        with patch.object(portable.sys.stdin, "isatty", return_value=True), \
                patch.object(portable.getpass, "getpass", side_effect=[PASSWORD, PASSWORD + "x"]):
            with self.assertRaises(ValueError):
                portable.read_passphrase(confirm=True)

    def test_export_contains_only_ciphertext_and_recovery_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / RUN
            source.mkdir()
            keys = root / "keys"
            keys.mkdir()
            (source / "backup.fernet").write_bytes(self.encrypted)
            (source / "report.json").write_text('{"restore_verified": true}', encoding="ascii")
            (keys / f"{RUN}.backup.dpapi").write_bytes(b"synthetic dpapi")
            output = io.StringIO()
            with patch.object(backup, "BACKUPS", root), patch.object(backup, "KEYS", keys), \
                    patch.object(backup, "dpapi", return_value=self.key) as dpapi, \
                    patch.dict(sys.modules, {"muvv_backup_portable": portable}), \
                    patch.object(portable, "read_passphrase", return_value=PASSWORD), \
                    contextlib.redirect_stdout(output):
                backup.export_portable(RUN)
                dpapi.assert_called_once()
                with self.assertRaises(ValueError):
                    backup.export_portable(RUN)
            self.assertEqual((source / "backup.fernet").read_bytes(), self.encrypted)
            self.assertNotIn(PASSWORD, output.getvalue())
            self.assertNotIn(self.key.decode(), output.getvalue())
            result = json.loads((source / "portable-report.json").read_bytes())
            self.assertFalse(result["offsite_copy_verified"])
            self.assertFalse(result["second_computer_tested"])
            package = source / result["package"]
            self.assertEqual(portable.sha(package.read_bytes()), result["package_sha256"])
            with zipfile.ZipFile(package) as archive:
                self.assertEqual(set(archive.namelist()), {"backup.fernet", "recovery-key.json",
                                                         "report.json", "RECUPERAR.txt", "muvv_backup_portable.py"})
                extracted = root / "synthetic-download"
                extracted.mkdir()
                for name in ("backup.fernet", "recovery-key.json"):
                    (extracted / name).write_bytes(archive.read(name))
            self.assertTrue(portable.verify_directory(extracted, PASSWORD)["portable_decryption_verified"])


if __name__ == "__main__":
    unittest.main()
