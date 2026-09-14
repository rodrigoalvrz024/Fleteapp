import importlib.util
import io
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


path = Path(__file__).resolve().parents[2] / "scripts" / "verify-runtime-image.py"
spec = importlib.util.spec_from_file_location("runtime_image_security", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class RuntimeImageSecurityTests(unittest.TestCase):
    def test_profiles_preserve_classic_and_cover_dhi_python_and_venv(self):
        self.assertEqual(checker.runtime_paths("classic"), (checker.PROTECTED_ROOTS, checker.SCAN_ROOTS))
        protected, scanned = checker.runtime_paths("dhi")
        self.assertEqual({str(path) for path in protected}, {str(Path("/app")), str(Path("/usr")), str(Path("/opt/muvv-venv"))})
        self.assertIn(Path("/opt"), scanned)
        with self.assertRaises(ValueError):
            checker.runtime_paths("skip")

    def test_legacy_openssl_names_include_bundled_wheel_libraries(self):
        for name in ("libssl.so.1.1", "libcrypto-7d0e8add.so.1.1", "libssl-hash.so.1.0.0", "libcrypto.so.1.0.2"):
            self.assertTrue(checker.is_legacy_openssl_library(name))
        for name in ("libssl.so.3", "libcrypto-fb8d5b21.so.3", "libcrypto.so", "other.so.1.1", "libcryptographer.so.1.1"):
            self.assertFalse(checker.is_legacy_openssl_library(name))

    def inspect(self, mode=stat.S_IFREG | 0o644, uid=0, **kwargs):
        options = {"protected": True, "writable": False, "capability": False, **kwargs}
        return checker.file_violations(SimpleNamespace(st_mode=mode, st_uid=uid), **options)

    def test_root_owned_code_is_allowed(self):
        self.assertEqual(self.inspect(), [])

    def test_app_owned_code_is_rejected_even_without_write_bit(self):
        self.assertIn("code_not_root_owned", self.inspect(mode=stat.S_IFREG | 0o444, uid=100))

    def test_group_and_world_writes_are_rejected(self):
        for mode in (0o664, 0o646):
            self.assertIn("code_group_or_world_writable", self.inspect(mode=stat.S_IFREG | mode))

    def test_effective_write_access_is_rejected(self):
        self.assertIn("code_writable_by_app", self.inspect(writable=True))

    def test_setid_is_rejected_outside_protected_code(self):
        for mode in (stat.S_ISUID, stat.S_ISGID):
            self.assertIn("setid_file", self.inspect(mode=stat.S_IFREG | 0o755 | mode, protected=False))

    def test_file_capabilities_are_rejected(self):
        self.assertIn("file_capability", self.inspect(capability=True, protected=False))

    def test_symlink_mode_is_not_treated_as_target_write_permission(self):
        self.assertEqual(self.inspect(mode=stat.S_IFLNK | 0o777), [])
        self.assertIn("code_writable_by_app", self.inspect(mode=stat.S_IFLNK | 0o777, writable=True))

    def test_proc_security_fields_are_allowlisted(self):
        result = checker.process_security("CapEff:\t0000\nCapPrm:\t0000\nNoNewPrivs:\t1\nPrivate:\tignored")
        self.assertEqual(result, {"effective_capabilities": 0, "permitted_capabilities": 0,
                                  "no_new_privileges": 1})

    def test_partial_or_invalid_proc_status_cannot_pass(self):
        for status in ("CapEff:0", "CapEff:bad-value\nCapPrm:0\nNoNewPrivs:1"):
            with self.assertRaises((KeyError, ValueError)):
                checker.process_security(status)

    def test_removed_tool_rejects_even_root_only_inaccessible_files_and_links(self):
        for uid, mode in ((0, stat.S_IFREG | 0o700), (0, stat.S_IFREG),
                          (100, stat.S_IFREG | 0o700), (0, stat.S_IFLNK | 0o777)):
            path = Mock()
            path.lstat.return_value = SimpleNamespace(st_mode=mode, st_uid=uid)
            with patch.object(checker.os, "access", return_value=False):
                self.assertEqual(checker.inspect_removed_tool(path), {"present": True, "blocked": True})

    def test_missing_removed_tool_is_allowed_but_inspection_failure_is_not(self):
        path = Mock()
        path.lstat.side_effect = FileNotFoundError()
        self.assertEqual(checker.inspect_removed_tool(path), {"present": False, "blocked": False})
        path.lstat.side_effect = PermissionError()
        with self.assertRaises(PermissionError):
            checker.inspect_removed_tool(path)

    def test_perl_probe_uses_fixed_command_and_clean_environment(self):
        for answer, expected in (("present\n", True), ("absent\n", False)):
            with patch.object(checker.subprocess, "run", return_value=SimpleNamespace(stdout=answer)) as run:
                self.assertEqual(checker.perl_archive_tar_readable(), expected)
                self.assertEqual(run.call_args.args[0][:2], ["/usr/bin/perl", "-e"])
                self.assertEqual(run.call_args.kwargs["env"], {"PATH": "/usr/bin:/bin", "LC_ALL": "C"})
                self.assertNotIn("shell", run.call_args.kwargs)

    def test_unknown_component_probe_output_is_not_absence(self):
        with patch.object(checker.subprocess, "run", return_value=SimpleNamespace(stdout="unexpected")):
            with self.assertRaises(RuntimeError):
                checker.perl_archive_tar_readable()

    def test_component_presence_controls_runtime_verdict_and_exit_code(self):
        for readable, removed_present in ((False, False), (True, False), (False, True), (True, True)):
            removed_path = Mock(name="removed_path")
            removed_path.name = "nsenter"
            with (
                self.subTest(readable=readable, removed_present=removed_present),
                patch.object(checker.sys, "platform", "linux"),
                patch.object(checker, "Path") as path,
                patch.object(checker.os, "geteuid", return_value=100, create=True),
                patch.object(checker.os, "getegid", return_value=101, create=True),
                patch.object(checker.os, "getgroups", return_value=[101], create=True),
                patch.object(checker.shutil, "which", return_value=None),
                patch.object(checker, "REMOVED_TOOL_PATHS", (removed_path,)),
                patch.object(checker, "inspect_removed_tool", return_value={
                    "present": removed_present, "blocked": removed_present}),
                patch.object(checker, "SCAN_ROOTS", ()),
                patch.object(checker, "perl_archive_tar_readable", return_value=readable),
            ):
                path.return_value.read_text.return_value = "CapEff:0\nCapPrm:0\nNoNewPrivs:1"
                result = checker.inspect_runtime()
            blocked = readable or removed_present
            self.assertEqual(result["blocked"], blocked)
            reasons = {}
            if readable:
                reasons["perl_archive_tar_readable"] = 1
            if removed_present:
                reasons["removed_system_tool_present"] = 1
            self.assertEqual(result["violation_counts"], reasons)
            with (
                patch.object(checker, "inspect_runtime", return_value=result),
                patch.object(checker.sys, "argv", ["verify-runtime-image.py"]),
                patch.object(checker.sys, "stdout", new_callable=io.StringIO),
            ):
                self.assertEqual(checker.main(), 1 if blocked else 0)
