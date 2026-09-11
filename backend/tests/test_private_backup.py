import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import MagicMock, patch

from cryptography.fernet import Fernet, InvalidToken


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("private_backup", ROOT / "scripts/backup-muvv-private.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class PrivateBackupTests(unittest.TestCase):
    def test_missing_input_identifies_only_the_expected_local_path(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.backup.dpapi"
            with self.assertRaises(backup.BackupInputError) as caught:
                backup.read_backup_input(missing, "la clave protegida DPAPI")
            self.assertIn(str(missing), str(caught.exception))
            self.assertIn("No se encuentra", str(caught.exception))

    def test_denied_input_is_not_reported_as_missing(self):
        with patch.object(Path, "open", side_effect=PermissionError("private diagnostic hidden")):
            with self.assertRaises(backup.BackupInputError) as caught:
                backup.read_backup_input(Path("synthetic.dpapi"), "la clave protegida DPAPI")
        self.assertIn("Acceso denegado", str(caught.exception))
        self.assertNotIn("private diagnostic hidden", str(caught.exception))

    def test_key_file_override_does_not_depend_on_localappdata(self):
        key = Fernet.generate_key()
        explicit = Path("synthetic/selected.backup.dpapi")
        with patch.object(backup, "read_backup_input", return_value=b"protected") as read, \
                patch.object(backup, "dpapi", return_value=key) as dpapi:
            self.assertEqual(backup.read_backup_key("20260908T000000Z-12345678", explicit), key)
        self.assertEqual(read.call_args.args[0], explicit)
        dpapi.assert_called_once_with(b"protected", decrypt=True)

    def test_default_key_path_is_preserved(self):
        run = "20260908T000000Z-12345678"
        with patch.object(backup, "read_backup_input", return_value=b"protected") as read, \
                patch.object(backup, "dpapi", return_value=Fernet.generate_key()):
            backup.read_backup_key(run)
        self.assertEqual(read.call_args.args[0], backup.KEYS / f"{run}.backup.dpapi")

    def test_wrong_windows_profile_does_not_expose_dpapi_error(self):
        with patch.object(backup, "read_backup_input", return_value=b"protected"), \
                patch.object(backup, "dpapi", side_effect=RuntimeError("private data")):
            with self.assertRaises(backup.BackupInputError) as caught:
                backup.read_backup_key("20260908T000000Z-12345678")
        self.assertIn("perfil Windows", str(caught.exception))
        self.assertNotIn("private data", str(caught.exception))

    def test_empty_or_oversized_key_file_is_rejected_before_dpapi(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "synthetic.dpapi"
            for content in (b"", b"x" * 8193):
                target.write_bytes(content)
                with patch.object(backup, "dpapi") as dpapi:
                    with self.assertRaises(backup.BackupInputError):
                        backup.read_backup_key("20260908T000000Z-12345678", target)
                    dpapi.assert_not_called()

    def test_run_identifier_cannot_escape_backup_root(self):
        for run in ("../outside", r"..\outside", "C:\\Windows", "", "20260908T000000Z-12345678/child"):
            with self.subTest(run=run), self.assertRaises(ValueError):
                backup.run_path(run)
        self.assertEqual(backup.run_path("20260908T000000Z-12345678").parent, backup.BACKUPS)

    def test_source_must_be_expected_project_and_uses_session_pooler(self):
        dsn = (f"postgresql://postgres.{backup.PROJECT}:synthetic@"
               "aws-1-us-west-1.pooler.supabase.com:6543/postgres")
        with patch.object(backup, "dotenv_values", return_value={"DATABASE_URL": dsn}):
            options = backup.source_options()
        self.assertEqual(options["port"], 5432)
        self.assertEqual(options["sslmode"], "require")
        with patch.object(backup, "dotenv_values", return_value={"DATABASE_URL": "postgresql://other:fake@elsewhere/db"}):
            with self.assertRaises(ValueError):
                backup.source_options()

    def test_cleanup_rejects_parent_and_sibling_paths(self):
        root = backup.BACKUPS / "20260908T000000Z-12345678"
        with patch.object(backup.shutil, "rmtree") as remove:
            for target in (root, root.parent, root / "unrecognized", root.parent / "drill-elsewhere"):
                with self.subTest(target=target), self.assertRaises(RuntimeError):
                    backup.safe_remove_drill(target, root)
            remove.assert_not_called()

    def test_cipher_authenticates_before_restoration(self):
        cipher = Fernet(Fernet.generate_key())
        original = b"synthetic private backup"
        encrypted = cipher.encrypt(original)
        self.assertEqual(cipher.decrypt(encrypted), original)
        with self.assertRaises(InvalidToken):
            cipher.decrypt(encrypted[:-8] + b"tampered")
        with self.assertRaises(InvalidToken):
            Fernet(Fernet.generate_key()).decrypt(encrypted)

    def test_fingerprints_use_explicit_numeric_serialization(self):
        for digits in (0, 3):
            with self.subTest(digits=digits):
                conn = MagicMock()
                cursor = conn.cursor.return_value.__enter__.return_value
                cursor.fetchall.return_value = []
                self.assertEqual(backup.public_fingerprints(conn, extra_float_digits=digits), {})
                self.assertEqual(cursor.execute.call_args_list[0].args,
                                 ("SELECT set_config('extra_float_digits', %s, true)", (str(digits),)))


if __name__ == "__main__":
    unittest.main()
