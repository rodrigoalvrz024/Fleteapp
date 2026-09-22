import gzip
import importlib.util
import os
from pathlib import Path
import stat
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "docker/configure_runtime.py"
if SOURCE.exists():
    spec = importlib.util.spec_from_file_location("runtime_data_setup", SOURCE)
    setup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(setup)


def tzif(offset=0):
    # One fixed-offset type, no transitions; a complete synthetic TZif v1 file.
    return (b"TZif\x00" + b"\x00" * 15 + struct.pack(">6I", 0, 0, 0, 0, 1, 4)
            + struct.pack(">iBB", offset, 0, 0) + b"UTC\x00")


@unittest.skipUnless(SOURCE.exists(), "DHI build helper not mounted in this candidate")
class RuntimeDataTests(unittest.TestCase):
    def test_validates_utc_and_rejects_non_utc_or_invalid_data(self):
        setup.validate_utc(tzif())
        for data in (b"bad", tzif(3600), tzif(-10800)):
            with self.subTest(data=data), self.assertRaises(ValueError):
                setup.validate_utc(data)

    def test_metadata_rejects_untrusted_owner_type_and_permissions(self):
        for directory, kind in ((False, stat.S_IFREG), (True, stat.S_IFDIR)):
            setup.validate_metadata(SimpleNamespace(st_mode=kind | 0o755, st_uid=0), directory=directory)
            for mode, uid in ((kind | 0o777, 0), (kind | 0o4755, 0),
                              (kind | 0o644, 65532), (stat.S_IFLNK | 0o777, 0),
                              (stat.S_IFIFO | 0o644, 0)):
                with self.subTest(mode=mode, uid=uid), self.assertRaises(ValueError):
                    setup.validate_metadata(SimpleNamespace(st_mode=mode, st_uid=uid), directory=directory)

    def fixture(self, root):
        for directory in ("etc", "usr/share/zoneinfo/Etc", "usr/share/doc/base-files"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        (root / "usr/share/zoneinfo/Etc/UTC").write_bytes(tzif())
        docs = root / "usr/share/doc/base-files"
        (docs / "README.gz").write_bytes(gzip.compress(b"Package documentation\n"))
        (docs / "FAQ").write_text("placeholder for mocked symlink metadata")

    def run_fixture(self, root, *, target="README", mutate_metadata=None):
        real_lstat = Path.lstat
        real_fstat = os.fstat
        real_open = os.open
        faq = root / "usr/share/doc/base-files/FAQ"

        def metadata(value, path=None):
            # Windows and non-root Linux tests cannot manufacture root-owned
            # inodes. Simulate only ownership/permission metadata, not contents,
            # gzip parsing, exclusive writes or traversal decisions.
            mode = stat.S_IFMT(value.st_mode) | (0o755 if stat.S_ISDIR(value.st_mode) else 0o644)
            if path == faq:
                mode = stat.S_IFLNK | 0o777
            result = SimpleNamespace(st_mode=mode, st_uid=0, st_size=value.st_size)
            if mutate_metadata:
                mutate_metadata(path, result)
            return result

        def open_file(path, flags, mode=0o777):
            return real_open(path, flags, mode)

        with patch.object(Path, "lstat", lambda path: metadata(real_lstat(path), path)), \
                patch.object(setup.os, "fstat", lambda fd: metadata(real_fstat(fd))), \
                patch.object(setup.os, "readlink", return_value=target), \
                patch.object(setup.os, "O_NOFOLLOW", getattr(os, "O_NOFOLLOW", 0), create=True), \
                patch.object(setup.os, "fchmod", getattr(os, "fchmod", lambda *_: None), create=True), \
                patch.object(setup.os, "open", side_effect=open_file):
            return setup.configure(root)

    def test_repairs_missing_files_without_removing_compressed_doc_or_link(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            result = self.run_fixture(root)
            self.assertEqual(result["created"], ["etc/localtime", "usr/share/doc/base-files/README"])
            self.assertEqual((root / "etc/localtime").read_bytes(), tzif())
            self.assertEqual((root / "usr/share/doc/base-files/README").read_bytes(), b"Package documentation\n")
            self.assertTrue((root / "usr/share/doc/base-files/README.gz").exists())
            self.assertTrue((root / "usr/share/doc/base-files/FAQ").exists())
            self.assertEqual(result["removed_documentation_aliases"], [])
            self.assertFalse(result["security_findings_waived"])
            self.assertEqual(self.run_fixture(root)["created"], [])

    def test_invalid_faq_or_source_blocks_before_any_write(self):
        for failure in ("target", "gzip", "oversized", "not_utf8", "crc"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root)
                compressed = root / "usr/share/doc/base-files/README.gz"
                if failure == "gzip":
                    compressed.write_bytes(b"not-gzip")
                elif failure == "oversized":
                    compressed.write_bytes(gzip.compress(b"x" * (setup.MAX_DATA + 1)))
                elif failure == "not_utf8":
                    compressed.write_bytes(gzip.compress(b"\xff"))
                elif failure == "crc":
                    data = bytearray(compressed.read_bytes())
                    data[-8] ^= 1
                    compressed.write_bytes(data)
                with self.assertRaises((OSError, ValueError, EOFError)):
                    self.run_fixture(root, target="/etc/secret" if failure == "target" else "README")
                self.assertFalse((root / "etc/localtime").exists())
                self.assertFalse((root / "usr/share/doc/base-files/README").exists())

    def test_removes_only_verified_orphan_doc_alias_when_both_sources_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            docs = root / "usr/share/doc/base-files"
            (docs / "README.gz").unlink()
            (docs / "copyright").write_bytes(b"License data retained")
            result = self.run_fixture(root)
            self.assertEqual(result["removed_documentation_aliases"], ["usr/share/doc/base-files/FAQ"])
            self.assertFalse((docs / "FAQ").exists())
            self.assertFalse((docs / "README").exists())
            self.assertEqual((docs / "copyright").read_bytes(), b"License data retained")
            self.assertEqual((root / "etc/localtime").read_bytes(), tzif())

    def test_missing_compressed_doc_does_not_allow_removing_unknown_link(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            docs = root / "usr/share/doc/base-files"
            (docs / "README.gz").unlink()
            with self.assertRaises(ValueError):
                self.run_fixture(root, target="/etc/secret")
            self.assertTrue((docs / "FAQ").exists())
            self.assertFalse((root / "etc/localtime").exists())

    def test_refuses_existing_different_localtime_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "etc/localtime").write_bytes(tzif(3600))
            with self.assertRaises(ValueError):
                self.run_fixture(root)
            self.assertEqual((root / "etc/localtime").read_bytes(), tzif(3600))
            self.assertFalse((root / "usr/share/doc/base-files/README").exists())

    def test_refuses_symlink_ancestors_and_source_files(self):
        for relative in ("etc", "usr/share", "usr/share/zoneinfo/Etc/UTC",
                         "usr/share/doc/base-files/README.gz"):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root)
                def mutate(path, metadata):
                    if path == root / relative:
                        metadata.st_mode = stat.S_IFLNK | 0o777
                with self.assertRaises(ValueError):
                    self.run_fixture(root, mutate_metadata=mutate)
                self.assertFalse((root / "etc/localtime").exists())


if __name__ == "__main__":
    unittest.main()
