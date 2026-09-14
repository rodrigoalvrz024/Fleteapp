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
            if isinstance(data, tarfile.TarInfo):
                data.name = name
                archive.addfile(data)
            elif data is None:
                member.type = tarfile.SYMTYPE
                member.linkname = "/outside/not-read"
                archive.addfile(member)
            else:
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
    result.seek(0)
    return result


class NativeSymbolReportTests(unittest.TestCase):
    def test_component_inventory_distinguishes_tools_from_libraries_and_counts_aliases(self):
        with patch.object(reporter, "inspect_elf", return_value={"imports": [], "exports": []}):
            result = self.collect([("usr/lib/libacl.so", ELF), ("usr/bin/getfacl", ELF),
                                   ("usr/bin/nsenter", None), ("opt/Archive/Tar.pm", b"module"),
                                   ("other/Tar.pm", b"unrelated"), ("opt/infocmp", ELF)])
        components = result["component_inventory"]
        self.assertEqual(components["getfacl"], ["/usr/bin/getfacl"])
        self.assertEqual(components["nsenter"], ["/usr/bin/nsenter"])
        self.assertEqual(components["infocmp"], ["/opt/infocmp"])
        self.assertEqual(components["perl_archive_tar"], ["/opt/Archive/Tar.pm"])
        self.assertEqual(components["setfacl"], [])
        self.assertEqual(components["chacl"], [])

    def test_component_annotation_retains_scope_counts_and_bounded_paths(self):
        report = {"image_id": IMAGE, "counts": {"elf_files": 1}, "files": [],
                  "component_inventory": {"infocmp": [f"/copy{i}/infocmp" for i in range(15)]}}
        with patch.object(reporter.sys, "stdout", new_callable=io.StringIO) as output:
            reporter.annotations(report)
        payload = json.loads(output.getvalue().splitlines()[0].split("::", 2)[2])
        self.assertEqual(payload["scope"], "known_names_in_effective_filesystem")
        self.assertEqual(payload["components"]["infocmp"]["count"], 15)
        self.assertEqual(len(payload["components"]["infocmp"]["paths"]), 12)

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
        self.assertEqual(reporter.SYMBOL_GROUPS["xml_hash"], {
            "XML_SetHashSalt", "XML_SetHashSalt16Bytes",
            "PyExpat_XML_SetHashSalt", "PyExpat_XML_SetHashSalt16Bytes"})
        self.assertIn("__fp_nquery", reporter.WATCHED)
        self.assertIn("dlsym", reporter.SYMBOL_GROUPS["dynamic_lookup"])
        self.assertIn("gz_vacate", reporter.WATCHED)

    def test_xml_provider_export_is_not_reported_as_a_caller(self):
        symbol = "XML_SetHashSalt16Bytes"
        report = {"image_id": IMAGE, "counts": {"elf_files": 2}, "files": [
            {"path": "/provider.so", "imports": [], "exports": [symbol]},
            {"path": "/pyexpat.so", "imports": [symbol], "exports": []},
        ]}
        with patch.object(reporter.sys, "stdout", new_callable=io.StringIO) as output:
            reporter.annotations(report)
        line = next(line for line in output.getvalue().splitlines() if '"group": "xml_hash"' in line)
        payload = json.loads(line.split("::", 2)[2])
        self.assertEqual(payload["caller_files"], 1)
        self.assertEqual(payload["callers"][0]["path"], "/pyexpat.so")
        self.assertIn("do not prove the selected runtime branch", reporter.summary(report))

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

    def test_all_entry_types_reject_duplicate_paths_in_either_order(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.DIRTYPE,
                     tarfile.FIFOTYPE, tarfile.CHRTYPE):
            for reverse in (False, True):
                member = tarfile.TarInfo()
                member.type = kind
                member.linkname = "usr/target"
                entries = [("./usr/test", ELF), ("usr/test", member)]
                if reverse:
                    entries.reverse()
                with (
                    self.subTest(kind=kind, reverse=reverse),
                    patch.object(reporter, "inspect_elf", return_value={}),
                    self.assertRaisesRegex(ValueError, "Duplicate archive path"),
                ):
                    self.collect(entries)

    def test_nonregular_entries_reject_unsafe_names(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.DIRTYPE, tarfile.FIFOTYPE):
            for name in ("../file", "/etc/file", "usr/../file", "a\nname"):
                member = tarfile.TarInfo()
                member.type = kind
                member.linkname = "usr/target"
                with (
                    self.subTest(kind=kind, name=name),
                    patch.object(reporter, "inspect_elf", return_value={}),
                    self.assertRaisesRegex(ValueError, "Invalid archive path"),
                ):
                    self.collect([("usr/valid", ELF), (name, member)])

    def test_distinct_directories_and_link_aliases_remain_allowed(self):
        directory = tarfile.TarInfo()
        directory.type = tarfile.DIRTYPE
        hardlink = tarfile.TarInfo()
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = "usr/test"
        with patch.object(reporter, "inspect_elf", return_value={}) as inspect:
            result = self.collect([("usr", directory), ("usr/test", ELF),
                                   ("usr/hard", hardlink), ("usr/soft", None)])
        inspect.assert_called_once_with(ELF)
        self.assertEqual(result["counts"], {"archive_members": 4, "regular_files": 1,
                                           "link_aliases_not_resolved": 2, "elf_files": 1})

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
        report = {"image_id": IMAGE, "counts": {"elf_files": 20}, "files": [{"path": f"/file{i}%\n", "imports": ["gzwrite"]} for i in range(20)]}
        with patch.object(reporter.sys, "stdout", new_callable=io.StringIO) as output:
            reporter.annotations(report)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), len(reporter.SYMBOL_GROUPS))
        gzip_line = next(line for line in lines if '"group": "gzip_write"' in line)
        self.assertIn('"omitted_from_annotation": 8', gzip_line)
        self.assertIn("%25", gzip_line)

    def test_annotations_prioritize_application_extensions_in_bounded_preview(self):
        files = [{"path": f"/usr/bin/file{i}", "imports": ["dlsym"]} for i in range(20)]
        files.append({"path": "/usr/local/lib/python/extension.so", "imports": ["dlsym"]})
        report = {"image_id": IMAGE, "counts": {"elf_files": 21}, "files": files}
        with patch.object(reporter.sys, "stdout", new_callable=io.StringIO) as output:
            reporter.annotations(report)
        line = next(line for line in output.getvalue().splitlines() if '"group": "dynamic_lookup"' in line)
        payload = json.loads(line.split("::", 2)[2])
        self.assertEqual(payload["callers"][0]["path"], "/usr/local/lib/python/extension.so")
        self.assertEqual(payload["elf_files"], 21)


if __name__ == "__main__":
    unittest.main()
