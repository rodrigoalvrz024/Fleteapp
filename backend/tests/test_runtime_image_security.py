import importlib.util
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

    def test_restricted_tool_is_unreadable_and_unexecutable_by_app(self):
        path = Mock()
        path.lstat.return_value = SimpleNamespace(st_mode=stat.S_IFREG | 0o700, st_uid=0)
        with patch.object(checker.os, "access", return_value=False):
            self.assertFalse(checker.inspect_restricted_command(path)["blocked"])
        for access in ((True, False), (False, True)):
            with patch.object(checker.os, "access", side_effect=access):
                self.assertTrue(checker.inspect_restricted_command(path)["blocked"])

    def test_restricted_tool_rejects_wrong_owner_permissions_and_symlink(self):
        for uid, mode in ((100, stat.S_IFREG | 0o700), (0, stat.S_IFREG | 0o750),
                          (0, stat.S_IFLNK | 0o777)):
            path = Mock()
            path.lstat.return_value = SimpleNamespace(st_mode=mode, st_uid=uid)
            with patch.object(checker.os, "access", return_value=False):
                self.assertTrue(checker.inspect_restricted_command(path)["blocked"])

    def test_missing_restricted_tool_is_allowed_but_inspection_failure_is_not(self):
        path = Mock()
        path.lstat.side_effect = FileNotFoundError()
        self.assertEqual(checker.inspect_restricted_command(path), {"present": False, "blocked": False})
        path.lstat.side_effect = PermissionError()
        with self.assertRaises(PermissionError):
            checker.inspect_restricted_command(path)

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
