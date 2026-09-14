import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch


path = Path(__file__).resolve().parents[2] / "scripts" / "report-native-symbols.py"
spec = importlib.util.spec_from_file_location("native_symbol_report", path)
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)
IMAGE = "sha256:" + "a" * 64
ELF = b"\x7fELFsynthetic"


def archive_bytes(entries):
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode="w") as archive:
        for name, data in entries:
            member = tarfile.TarInfo(name)
            if data is None:
                member.type = tarfile.SYMTYPE
                member.linkname = "/outside/not-read"
                archive.addfile(member)
            else:
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
    result.seek(0)
    return result


class NativeSymbolReportTests(unittest.TestCase):
    def collect(self, entries, image=IMAGE):
        with tarfile.open(fileobj=archive_bytes(entries), mode="r:") as archive:
            return reporter.collect(archive, image)

    def test_exports_are_not_confused_with_imports_and_versions_are_normalized(self):
        class Symbol(dict):
            def __init__(self, name, index):
                super().__init__(st_shndx=index)
                self.name = name

        class Section(dict):
            def iter_symbols(self):
                return iter([Symbol("gzwrite@ZLIB_1", "SHN_UNDEF"), Symbol("ns_printrr", 12), Symbol("unrelated", "SHN_UNDEF")])

        result = reporter.symbol_evidence([{"sh_type": "SHT_PROGBITS"}, Section(sh_type="SHT_DYNSYM")])
        self.assertEqual(result, {"symbol_tables": 1, "imports": ["gzwrite"], "exports": ["ns_printrr"]})
        self.assertEqual(reporter.symbol_evidence([])["symbol_tables"], 0)

    def test_known_symbols_include_aliases_and_runtime_lookup(self):
        self.assertIn("__fp_nquery", reporter.WATCHED)
        self.assertIn("dlsym", reporter.SYMBOL_GROUPS["dynamic_lookup"])
        self.assertIn("gz_vacate", reporter.WATCHED)

    def test_inventory_records_hashes_and_does_not_follow_links_or_read_non_elf_contents(self):
        evidence = {"symbol_tables": 0, "imports": [], "exports": [], "needed": []}
        with patch.object(reporter, "inspect_elf", return_value=evidence) as inspect:
            result = self.collect([("./usr/lib/test.so", ELF), ("alias", None), ("app/config", b"private-not-ELF")])
        inspect.assert_called_once_with(ELF)
        self.assertEqual(result["counts"]["link_aliases_not_resolved"], 1)
        self.assertEqual(result["files"][0]["path"], "/usr/lib/test.so")
        self.assertEqual(len(result["files"][0]["sha256"]), 64)
        self.assertNotIn("private-not-ELF", json.dumps(result))
        self.assertEqual(result["status"], "evidence_only_not_security_approval")

    def test_rejects_invalid_identity(self):
        for identity in ("latest", "sha256:abc", "sha256:" + "A" * 64):
            with self.assertRaises(ValueError):
                self.collect([], identity)

    def test_rejects_empty_inventory(self):
        with self.assertRaises(ValueError):
            self.collect([("plain", b"not ELF")])

    def test_rejects_unsafe_paths_and_duplicate_canonical_names(self):
        for name in ("../file", "/etc/file", "usr/../file", "a\nname", "."):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.collect([(name, b"data")])
        with self.assertRaises(ValueError):
            self.collect([("./usr/test", b"x"), ("usr/test", b"y")])

    def test_bounds_elf_size_and_archive_members(self):
        with patch.object(reporter, "MAX_ELF_BYTES", 4), self.assertRaises(ValueError):
            self.collect([("file", ELF)])
        with patch.object(reporter, "MAX_MEMBERS", 1), self.assertRaises(ValueError):
            self.collect([("one", b"x"), ("two", b"y")])

    def test_parser_failure_is_not_reported_as_absence(self):
        with patch.object(reporter, "inspect_elf", side_effect=ValueError("bad ELF")), self.assertRaises(ValueError):
            self.collect([("broken", ELF)])

    def test_summary_retains_limits_and_counts_only_imports(self):
        report = {"image_id": IMAGE, "counts": {"elf_files": 2}, "files": [
            {"path": "/provider", "imports": [], "exports": ["gzwrite"]},
            {"path": "/consumer", "imports": ["gzwrite"], "exports": []},
        ]}
        output = reporter.summary(report)
        self.assertIn("gzip_write: 1 files", output)
        self.assertIn("No import is NOT proof", output)
        self.assertIn("not approval", output)

    def test_cli_failure_redacts_internal_errors_and_does_not_write_success(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            with patch.object(reporter.tarfile, "open", side_effect=OSError("private-credential")), patch.object(reporter.sys, "stderr", new_callable=io.StringIO) as errors:
                result = reporter.main(["missing.tar", "--image-id", IMAGE, "--output", str(output)])
            self.assertEqual(result, 2)
            self.assertFalse(output.exists())
            self.assertNotIn("private-credential", errors.getvalue())

    def test_annotations_are_bounded_and_report_omissions(self):
        report = {"image_id": IMAGE, "files": [{"path": f"/file{i}%\n", "imports": ["gzwrite"]} for i in range(20)]}
        with patch.object(reporter.sys, "stdout", new_callable=io.StringIO) as output:
            reporter.annotations(report)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 4)
        gzip_line = next(line for line in lines if '"group": "gzip_write"' in line)
        self.assertIn('"omitted_from_annotation": 8', gzip_line)
        self.assertIn("%25", gzip_line)


if __name__ == "__main__":
    unittest.main()
