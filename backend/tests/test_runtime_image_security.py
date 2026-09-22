import importlib.util
import errno
from contextlib import ExitStack
import io
import json
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch


path = Path(__file__).resolve().parents[2] / "scripts" / "verify-runtime-image.py"
spec = importlib.util.spec_from_file_location("runtime_image_security", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
SAFE_STATUS = "CapInh:0\nCapPrm:0\nCapEff:0\nCapAmb:0\nNoNewPrivs:1"


class RuntimeImageSecurityTests(unittest.TestCase):
    def test_annotations_keep_bounded_diagnostics_for_both_profiles(self):
        for profile in ("classic", "dhi"):
            result = {"profile": profile, "blocked": True, "violations": [
                {"reason": "symlink_external_directory_unreviewed", "path": "/usr/" + "a" * 300}
                for _ in range(12)]}
            with (
                patch.object(checker, "inspect_runtime", return_value=result),
                patch.object(checker.sys, "argv", ["check", "--profile", profile, "--github-annotation"]),
                patch.object(checker.sys, "stdout", new_callable=io.StringIO) as output,
            ):
                self.assertEqual(checker.main(), 1)
            line = next(line for line in output.getvalue().splitlines() if line.startswith("::error"))
            payload = json.loads(line.split("::", 2)[2])
            self.assertEqual(len(payload["violation_examples"]), 8)
            self.assertEqual(len(payload["violation_examples"][0]["path"]), 200)
            self.assertNotIn("violations", payload)

    def test_profiles_preserve_classic_and_cover_dhi_python_and_venv(self):
        self.assertEqual(checker.runtime_paths("classic"), (checker.PROTECTED_ROOTS, checker.SCAN_ROOTS))
        protected, scanned = checker.runtime_paths("dhi")
        self.assertEqual(set(protected), {Path("/app"), Path("/usr"), Path("/opt/muvv-venv"), checker.CERTIFICATE_ROOT})
        self.assertIn(Path("/opt"), scanned)
        with self.assertRaises(ValueError):
            checker.runtime_paths("skip")

    def test_classic_protects_system_libraries_and_their_parent_directory(self):
        protected, scanned = checker.runtime_paths("classic")
        for name in ("/usr", "/usr/lib", "/usr/lib/libacl.so.1", "/usr/bin/cp",
                     "/usr/local/lib/python3.14", "/app/app/server.py"):
            with self.subTest(path=name):
                path = Path(name)
                self.assertTrue(any(path.is_relative_to(root) for root in protected))
                self.assertTrue(any(path.is_relative_to(root) for root in scanned))

    def test_public_certificate_tree_is_explicit_in_both_profiles_not_all_etc(self):
        for profile in ('classic', 'dhi'):
            protected, scanned = checker.runtime_paths(profile)
            self.assertIn(Path('/etc/ssl/certs'), protected)
            self.assertIn(Path('/etc/ssl/certs'), scanned)
            for path in (Path('/etc'), Path('/etc/ssl'), Path('/etc/ssl/private')):
                self.assertNotIn(path, scanned)

    def test_certificate_ancestors_are_checked_from_root_without_following_links(self):
        expected = [Path(p) for p in ('/', '/etc', '/etc/ssl', '/etc/ssl/certs')]
        touched = []

        def metadata(path):
            touched.append(path)
            return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)

        with patch.object(Path, 'lstat', metadata), patch.object(checker.os, 'access', return_value=False) as access:
            checker.verify_certificate_ancestors()
        self.assertEqual(touched, expected)
        self.assertTrue(all(call.kwargs == {'effective_ids': True} for call in access.call_args_list))

    def test_unsafe_certificate_ancestor_stops_before_later_metadata(self):
        expected = [Path(p) for p in ('/', '/etc', '/etc/ssl', '/etc/ssl/certs')]
        for index, unsafe in enumerate(expected):
            for mode, uid in ((stat.S_IFLNK | 0o777, 0), (stat.S_IFDIR | 0o777, 0),
                              (stat.S_IFDIR | 0o755, 100), (stat.S_IFREG | 0o644, 0)):
                touched = []

                def metadata(path):
                    touched.append(path)
                    return SimpleNamespace(st_mode=mode if path == unsafe else stat.S_IFDIR | 0o755,
                                           st_uid=uid if path == unsafe else 0)

                with (
                    self.subTest(path=unsafe, mode=mode, uid=uid),
                    patch.object(Path, 'lstat', metadata),
                    patch.object(checker.os, 'access', return_value=False),
                    self.assertRaises(RuntimeError),
                ):
                    checker.verify_certificate_ancestors()
                self.assertEqual(touched, expected[:index + 1])

    def test_missing_certificate_ancestor_or_unsupported_access_is_incomplete(self):
        for error in (FileNotFoundError(), PermissionError()):
            with patch.object(Path, 'lstat', side_effect=error), self.assertRaises(OSError):
                checker.verify_certificate_ancestors()
        with (
            patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)),
            patch.object(checker.os, 'access', side_effect=NotImplementedError()),
            self.assertRaises(RuntimeError),
        ):
            checker.verify_certificate_ancestors()

    def test_certificate_enumeration_checks_children_with_the_global_entry_budget(self):
        root, file = checker.CERTIFICATE_ROOT, checker.CERTIFICATE_ROOT / 'test.pem'
        tree = {Path(name): SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
                for name in ('/', '/etc', '/etc/ssl', '/etc/ssl/certs')}
        tree[file] = SimpleNamespace(st_mode=stat.S_IFREG | 0o666, st_uid=0)
        listing = MagicMock()
        with (
            patch.object(Path, 'lstat', lambda path: tree[path]),
            patch.object(checker.os, 'scandir', return_value=listing) as scan,
            patch.object(checker.os, 'access', return_value=False),
            patch.object(Path, 'open', side_effect=AssertionError('certificate contents opened')),
        ):
            listing.__enter__.return_value = iter([SimpleNamespace(path=str(file))])
            result = self.inspect_process(scan_roots=(root,), protected_roots=(root,))
            self.assertEqual(result['violation_counts'], {'code_group_or_world_writable': 1})
            self.assertEqual(result['inspected_certificate_entries'], 2)
            scan.assert_called_once_with(root)
            listing.__enter__.return_value = iter([SimpleNamespace(path=str(file))])
            with patch.object(checker, 'MAX_RUNTIME_ENTRIES', 1), self.assertRaisesRegex(RuntimeError, 'entry limit'):
                self.inspect_process(scan_roots=(root,), protected_roots=(root,))

    def test_private_boundary_is_reported_separately_without_claiming_content_review(self):
        root = Path('/usr')
        link, target = Path('/usr/lib/ssl/private'), Path('/etc/ssl/private')
        tree = {Path(name): SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
                for name in ('/', '/usr', '/usr/lib', '/usr/lib/ssl', '/etc', '/etc/ssl')}
        tree[link] = SimpleNamespace(st_mode=stat.S_IFLNK | 0o777, st_uid=0)
        tree[target] = SimpleNamespace(st_mode=stat.S_IFDIR | 0o700, st_uid=0)
        children = {root: Path('/usr/lib'), Path('/usr/lib'): Path('/usr/lib/ssl'),
                    Path('/usr/lib/ssl'): link}

        def listing(path):
            self.assertIn(path, children, 'private tree must not be enumerated')
            context = MagicMock()
            context.__enter__.return_value = iter([SimpleNamespace(path=str(children[path]))])
            return context

        for profile in ('classic', 'dhi'):
            for granted in (None, checker.os.R_OK, checker.os.W_OK, checker.os.X_OK):
                with (
                    self.subTest(profile=profile, granted=granted),
                    patch.object(Path, 'lstat', lambda path: tree[path]),
                    patch.object(checker.os, 'scandir', side_effect=listing),
                    patch.object(checker.os, 'readlink', return_value=target.as_posix()),
                    patch.object(checker.os, 'access', side_effect=lambda path, mode, **kw: path == target and mode == granted),
                    patch.object(Path, 'open', side_effect=AssertionError('private read')),
                    patch('builtins.open', side_effect=AssertionError('private read')),
                ):
                    result = self.inspect_process(scan_roots=(root,), protected_roots=(root,), profile=profile)
                self.assertEqual(result['blocked'], granted is not None)
                self.assertEqual(result['private_ssl_boundary_verified'], granted is None)
                self.assertEqual(result['private_ssl_scope'], 'inaccessibility_only_not_content_review')
                self.assertEqual(result['inspected_certificate_entries'], 0)
                self.assertEqual(result['inspected_symlinks'], 1)
                if granted is None:
                    self.assertEqual(result['symlink_diagnostics'][0]['scope'], 'inaccessible_private_boundary_only')
                json.dumps(result)

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
        result = checker.process_security(SAFE_STATUS + "\nPrivate:ignored")
        self.assertEqual(result, {"effective_capabilities": 0, "permitted_capabilities": 0,
                                  "inheritable_capabilities": 0, "ambient_capabilities": 0,
                                  "no_new_privileges": 1})

    def test_partial_or_invalid_proc_status_cannot_pass(self):
        for status in ("CapEff:0", "CapEff:bad-value\nCapPrm:0\nNoNewPrivs:1"):
            with self.assertRaises((KeyError, ValueError)):
                checker.process_security(status)

    def test_each_capability_field_is_required_and_hexadecimal(self):
        for field in checker.CAPABILITY_FIELDS.values():
            with self.subTest(field=field):
                with self.assertRaises(KeyError):
                    checker.process_security(SAFE_STATUS.replace(field + ":0\n", ""))
                with self.assertRaises(ValueError):
                    checker.process_security(SAFE_STATUS.replace(field + ":0", field + ":invalid"))

    def inspect_process(self, status=SAFE_STATUS, uids=(100, 100, 100),
                        gids=(101, 101, 101), groups=(101,), scan_roots=(),
                        protected_roots=(), profile="classic"):
        with ExitStack() as stack:
            stack.enter_context(patch.object(checker.sys, "platform", "linux"))
            stack.enter_context(patch.object(Path, "read_text", return_value=status))
            for name, value in (("geteuid", uids[1]), ("getegid", gids[1]),
                                ("getresuid", uids), ("getresgid", gids),
                                ("getgroups", groups)):
                stack.enter_context(patch.object(checker.os, name, return_value=value, create=True))
            stack.enter_context(patch.object(checker.shutil, "which", return_value=None))
            stack.enter_context(patch.object(checker, "REMOVED_TOOL_PATHS", ()))
            stack.enter_context(patch.object(checker, "runtime_paths", return_value=(protected_roots, scan_roots)))
            stack.enter_context(patch.object(checker, "has_file_capability", return_value=False))
            stack.enter_context(patch.object(checker, "perl_archive_tar_readable", return_value=False))
            return checker.inspect_runtime(profile)

    def test_module_copy_outside_perl_include_paths_blocks_both_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "custom" / "Archive"
            archive.mkdir(parents=True)
            module = archive / "Tar.pm"
            module.write_text("fixture, never executed", encoding="utf-8")
            for profile in ("classic", "dhi"):
                with self.subTest(profile=profile):
                    result = self.inspect_process(scan_roots=(root,), profile=profile)
                    self.assertTrue(result["blocked"])
                    self.assertEqual(result["violation_counts"], {"perl_archive_tar_named_file": 1})
            module.rename(archive / "Unrelated.pm")
            self.assertFalse(self.inspect_process(scan_roots=(root,))["blocked"])

    def test_missing_scan_root_is_not_an_empty_successful_scan(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "Missing runtime directory"):
                self.inspect_process(scan_roots=(Path(directory) / "absent",))

    def test_walk_rejects_unsafe_library_or_parent_and_cli_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lib = root / "lib"
            lib.mkdir()
            binary = lib / "libacl.so.1"
            binary.write_bytes(b"fixture, never loaded")
            original_lstat = Path.lstat
            for target, mode in ((lib, stat.S_IFDIR | 0o777),
                                 (binary, stat.S_IFREG | 0o666)):
                def metadata(path, *args, **kwargs):
                    if path == target:
                        return SimpleNamespace(st_mode=mode, st_uid=0)
                    original = original_lstat(path, *args, **kwargs)
                    return SimpleNamespace(st_mode=original.st_mode & ~0o022, st_uid=0)

                with (self.subTest(target=target.name), patch.object(Path, "lstat", metadata),
                      patch.object(checker.os, "access", return_value=False)):
                    result = self.inspect_process(scan_roots=(root,), protected_roots=(root,))
                self.assertTrue(result["blocked"])
                self.assertIn({"reason": "code_group_or_world_writable", "path": str(target)},
                              result["violations"])
                with (
                    patch.object(checker, "inspect_runtime", return_value=result),
                    patch.object(checker.sys, "argv", ["verify-runtime-image.py"]),
                    patch.object(checker.sys, "stdout", new_callable=io.StringIO),
                ):
                    self.assertEqual(checker.main(), 1)

    def test_enumeration_never_classifies_or_stats_symlink_destination(self):
        root = Path("/usr")
        node = Mock(path="/usr/link")
        node.is_dir.side_effect = AssertionError("destination classified")
        node.stat.side_effect = AssertionError("destination statted")
        tree = {"/": stat.S_IFDIR | 0o755, "/usr": stat.S_IFDIR | 0o755,
                "/usr/link": stat.S_IFLNK | 0o777}
        touched = []

        def metadata(path):
            name = path.as_posix()
            touched.append(name)
            return SimpleNamespace(st_mode=tree[name], st_uid=0)

        listing = MagicMock()
        listing.__enter__.return_value = iter([node])
        with (
            patch.object(Path, "lstat", metadata),
            patch.object(checker.os, "scandir", return_value=listing) as scan,
            patch.object(checker.os, "access", return_value=False),
            patch.object(checker.os, "readlink", return_value="/proc/self/fd/3"),
        ):
            result = self.inspect_process(scan_roots=(root,), protected_roots=(root,))
        self.assertEqual(result["violation_counts"], {"symlink_virtual_target": 1})
        self.assertNotIn("/proc", touched)
        node.is_dir.assert_not_called()
        node.stat.assert_not_called()
        scan.assert_called_once_with(root)

    def test_unsafe_directory_is_blocked_without_enumerating_it(self):
        root = Path("/usr")
        with (
            patch.object(Path, "lstat", return_value=SimpleNamespace(st_mode=stat.S_IFDIR | 0o777, st_uid=0)),
            patch.object(checker.os, "access", return_value=False),
            patch.object(checker.os, "scandir") as scan,
        ):
            result = self.inspect_process(scan_roots=(root,), protected_roots=(root,))
        self.assertTrue(result["blocked"])
        scan.assert_not_called()

    def test_entry_budget_cannot_report_partial_scan_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "file").touch()
            with patch.object(checker, "MAX_RUNTIME_ENTRIES", 1):
                with self.assertRaisesRegex(RuntimeError, "Runtime entry limit exceeded"):
                    self.inspect_process(scan_roots=(root,))

    def test_walk_propagates_unreviewed_symlink_to_blocking_verdict(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            link = root / "link"
            link.touch()
            original_lstat = Path.lstat

            def metadata(path, *args, **kwargs):
                if path == link:
                    return SimpleNamespace(st_mode=stat.S_IFLNK | 0o777, st_uid=0)
                return original_lstat(path, *args, **kwargs)

            with (
                patch.object(Path, "lstat", metadata),
                patch.object(checker, "inspect_symlink", return_value=["symlink_external_directory_unreviewed"]) as inspect,
            ):
                result = self.inspect_process(scan_roots=(root,))
            inspect.assert_called_once_with(link, (), (root,), diagnostic={})
            self.assertTrue(result["blocked"])
            self.assertEqual(result["inspected_symlinks"], 1)
            self.assertEqual(result["violation_counts"], {"symlink_external_directory_unreviewed": 1})

    def test_symlink_scan_root_is_rejected_before_walking(self):
        root = Mock()
        root.lstat.return_value = SimpleNamespace(st_mode=stat.S_IFLNK | 0o777)
        with patch.object(checker.os, "scandir") as walk:
            with self.assertRaisesRegex(RuntimeError, "Missing runtime directory"):
                self.inspect_process(scan_roots=(root,))
        walk.assert_not_called()

    def test_link_diagnostics_are_bounded_and_preserve_blocking_annotation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            links = [root / ('link-' + str(i)) for i in range(12)]
            for link in links:
                link.touch()
            original_lstat = Path.lstat

            def metadata(path, *args, **kwargs):
                if path in links:
                    return SimpleNamespace(st_mode=stat.S_IFLNK | 0o777, st_uid=0)
                return original_lstat(path, *args, **kwargs)

            def inspect(path, protected, scanned, *, diagnostic):
                diagnostic['resolution_issue'] = 'missing'
                return ['symlink_unresolved']

            with patch.object(Path, 'lstat', metadata), patch.object(checker, 'inspect_symlink', inspect):
                result = self.inspect_process(scan_roots=(root,))
            self.assertTrue(result['blocked'])
            self.assertEqual(result['violation_counts'], {'symlink_unresolved': 12})
            self.assertEqual(len(result['symlink_diagnostics']), 8)
            for item in result['symlink_diagnostics']:
                self.assertEqual(item['resolution_issue'], 'missing')
                self.assertLessEqual(len(item['path']), 200)
            with (
                patch.object(checker, 'inspect_runtime', return_value=result),
                patch.object(checker.sys, 'argv', ['check', '--github-annotation']),
                patch.object(checker.sys, 'stdout', new_callable=io.StringIO) as output,
            ):
                self.assertEqual(checker.main(), 1)
            annotation = next(line for line in output.getvalue().splitlines() if line.startswith('::error'))
            payload = json.loads(annotation.split('::', 2)[2])
            self.assertEqual(payload['symlink_diagnostics'], result['symlink_diagnostics'])

    def test_real_effective_saved_and_supplementary_root_identities_block(self):
        self.assertFalse(self.inspect_process()["blocked"])
        for field, baseline in (("uids", (100, 100, 100)), ("gids", (101, 101, 101))):
            for position in range(3):
                ids = list(baseline)
                ids[position] = 0
                with self.subTest(field=field, position=position):
                    result = self.inspect_process(**{field: tuple(ids)})
                    self.assertTrue(result["blocked"])
                    self.assertEqual(result["violation_counts"], {"root_identity": 1})
        self.assertTrue(self.inspect_process(groups=(101, 0))["blocked"])

    def test_each_nonzero_capability_blocks_even_when_effective_is_zero(self):
        for field in checker.CAPABILITY_FIELDS.values():
            with self.subTest(field=field):
                result = self.inspect_process(SAFE_STATUS.replace(field + ":0", field + ":0000000000000020"))
                self.assertTrue(result["blocked"])
                self.assertEqual(result["violation_counts"], {"process_capabilities": 1})

    def test_missing_capability_is_incomplete_not_approved_and_cli_redacts(self):
        with self.assertRaises(KeyError):
            self.inspect_process(SAFE_STATUS.replace("CapAmb:0\n", ""))
        with (
            patch.object(checker, "inspect_runtime", side_effect=KeyError("private-payload")),
            patch.object(checker.sys, "argv", ["verify-runtime-image.py"]),
            patch.object(checker.sys, "stdout", new_callable=io.StringIO) as output,
        ):
            self.assertEqual(checker.main(), 2)
        self.assertNotIn("private-payload", output.getvalue())

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
                patch.object(checker.os, "getresuid", return_value=(100, 100, 100), create=True),
                patch.object(checker.os, "getresgid", return_value=(101, 101, 101), create=True),
                patch.object(checker.shutil, "which", return_value=None),
                patch.object(checker, "REMOVED_TOOL_PATHS", (removed_path,)),
                patch.object(checker, "inspect_removed_tool", return_value={
                    "present": removed_present, "blocked": removed_present}),
                patch.object(checker, "SCAN_ROOTS", ()),
                patch.object(checker, "perl_archive_tar_readable", return_value=readable),
            ):
                path.return_value.read_text.return_value = SAFE_STATUS
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


class SymlinkSecurityTests(unittest.TestCase):
    def inspect(self, target, *, nodes=None, links=None, writable=(), capabilities=(), visited=None,
                diagnostic=None, source="/usr/lib/link", access_grants=(), access_checks=None):
        directory = (stat.S_IFDIR | 0o755, 0)
        regular = (stat.S_IFREG | 0o644, 0)
        tree = {name: directory for name in ("/", "/usr", "/usr/lib", "/usr/lib/ssl", "/app", "/etc", "/etc/ssl")}
        tree.update({"/usr/lib/ok.so": regular, "/etc/ssl/ca.pem": regular})
        tree.update(nodes or {})
        targets = {source: target, **(links or {})}
        for name in targets:
            tree.setdefault(name, (stat.S_IFLNK | 0o777, 0))

        def metadata(path):
            name = path.as_posix()
            if visited is not None:
                visited.append(name)
            if name not in tree:
                raise FileNotFoundError("not logged")
            item = tree[name]
            if isinstance(item, Exception):
                raise item
            return SimpleNamespace(st_mode=item[0], st_uid=item[1])

        def access(path, mode, **kwargs):
            if access_checks is not None:
                access_checks.append((path.as_posix(), mode, kwargs))
            return ((mode == checker.os.W_OK and path.as_posix() in writable)
                    or (path.as_posix(), mode) in access_grants)

        with (
            patch.object(Path, "lstat", metadata),
            patch.object(checker.os, "readlink", side_effect=lambda p: targets[p.as_posix()]),
            patch.object(checker.os, "access", side_effect=access),
            patch.object(checker, "has_file_capability", side_effect=lambda p: p.as_posix() in capabilities),
        ):
            roots = (Path("/usr"), Path("/app"))
            return checker.inspect_symlink(Path(source), roots, roots, diagnostic=diagnostic)

    def test_exact_private_boundary_requires_effective_read_write_and_search_denial(self):
        diagnostic, access_checks = {}, []
        with (
            patch.object(checker.os, 'scandir', side_effect=AssertionError('private enumeration')),
            patch.object(Path, 'open', side_effect=AssertionError('private read')),
            patch('builtins.open', side_effect=AssertionError('private read')),
        ):
            result = self.inspect('/etc/ssl/private', source='/usr/lib/ssl/private',
                                  nodes={'/etc/ssl/private': (stat.S_IFDIR | 0o700, 0)},
                                  diagnostic=diagnostic, access_checks=access_checks)
        self.assertEqual(result, [])
        self.assertEqual(diagnostic['scope'], 'inaccessible_private_boundary_only')
        self.assertEqual([item for item in access_checks if item[2]], [
            ('/etc/ssl/private', mode, {'effective_ids': True})
            for mode in (checker.os.R_OK, checker.os.W_OK, checker.os.X_OK)])

    def test_any_effective_private_access_keeps_the_link_blocked(self):
        for mode in (checker.os.R_OK, checker.os.W_OK, checker.os.X_OK):
            with self.subTest(mode=mode):
                result = self.inspect('/etc/ssl/private', source='/usr/lib/ssl/private',
                                      nodes={'/etc/ssl/private': (stat.S_IFDIR | 0o700, 0)},
                                      access_grants=(('/etc/ssl/private', mode),))
                self.assertTrue(result)

    def test_private_boundary_does_not_allow_other_sources_targets_or_modes(self):
        cases = [('/usr/lib/link', '/etc/ssl/private', 0o700, 0),
                 ('/usr/lib/ssl/private', '/etc/other', 0o700, 0),
                 ('/usr/lib/ssl/private', '/etc/ssl/private', 0o750, 0),
                 ('/usr/lib/ssl/private', '/etc/ssl/private', 0o755, 0),
                 ('/usr/lib/ssl/private', '/etc/ssl/private', 0o1700, 0),
                 ('/usr/lib/ssl/private', '/etc/ssl/private', 0o700, 100)]
        for source, target, mode, uid in cases:
            with self.subTest(source=source, target=target, mode=mode, uid=uid):
                self.assertTrue(self.inspect(target, source=source,
                                             nodes={target: (stat.S_IFDIR | mode, uid)}))

    def test_private_boundary_still_checks_all_ancestors_and_never_reads_children(self):
        for unsafe in ('/', '/etc', '/etc/ssl', '/usr', '/usr/lib', '/usr/lib/ssl'):
            with self.subTest(ancestor=unsafe):
                result = self.inspect('/etc/ssl/private', source='/usr/lib/ssl/private', nodes={
                    '/etc/ssl/private': (stat.S_IFDIR | 0o700, 0), unsafe: (stat.S_IFDIR | 0o777, 0)})
                self.assertTrue(result)
        visited = []
        result = self.inspect('/etc/ssl/private/key.pem', source='/usr/lib/ssl/private',
                              nodes={'/etc/ssl/private': PermissionError(errno.EACCES, 'not logged')},
                              visited=visited)
        self.assertTrue(result)
        self.assertNotIn('/etc/ssl/private/key.pem', visited)

    def test_private_boundary_probe_errors_cannot_be_treated_as_access_denied(self):
        with patch.object(checker, 'private_ssl_boundary', side_effect=OSError(errno.EIO, 'secret')):
            diagnostic = {}
            self.assertEqual(self.inspect('/etc/ssl/private', source='/usr/lib/ssl/private',
                             nodes={'/etc/ssl/private': (stat.S_IFDIR | 0o700, 0)}, diagnostic=diagnostic),
                             ['symlink_unresolved'])
            self.assertNotIn('scope', diagnostic)

    def test_diagnostics_distinguish_os_errors_without_payload_or_target_path(self):
        cases = ((errno.ENOENT, "missing"), (errno.EACCES, "denied"),
                 (errno.EPERM, "denied"), (errno.ENOTDIR, "not_directory"),
                 (errno.ELOOP, "loop"), (errno.EIO, "io_error"))
        for number, kind in cases:
            with self.subTest(kind=kind, number=number):
                diagnostic = {}
                error = OSError(number, "private exception payload", "/private/secret-name")
                result = self.inspect("/etc/secret-name", nodes={"/etc/secret-name": error},
                                      diagnostic=diagnostic)
                self.assertEqual(result, ["symlink_unresolved"])
                self.assertEqual(diagnostic, {"resolution_issue": kind})
                self.assertNotIn("secret", json.dumps(diagnostic))

    def test_ssl_directory_diagnostic_does_not_enumerate_or_open_keys(self):
        for target, expected in (("/etc/ssl/certs", "ssl_certificates"),
                                 ("/etc/ssl/private", "ssl_private"),
                                 ("/etc/other-private-dir", "other_external_directory")):
            diagnostic = {}
            with (
                patch.object(checker.os, "scandir", side_effect=AssertionError("directory enumerated")),
                patch("builtins.open", side_effect=AssertionError("content opened")),
                patch.object(Path, "open", side_effect=AssertionError("content opened")),
            ):
                result = self.inspect(target, nodes={target: (stat.S_IFDIR | 0o750, 0)},
                                      diagnostic=diagnostic)
            self.assertEqual(result, ["symlink_external_directory_unreviewed"])
            self.assertEqual(diagnostic, {"target_class": expected, "target_uid": 0, "target_mode": "0750"})
            self.assertNotIn(target, json.dumps(diagnostic))

    def test_diagnostic_does_not_approve_or_hide_unsafe_ssl_target(self):
        diagnostic = {}
        result = self.inspect("/etc/ssl/private", nodes={"/etc/ssl/private": (stat.S_IFDIR | 0o777, 0)},
                              diagnostic=diagnostic)
        self.assertIn("symlink_target_code_group_or_world_writable", result)
        self.assertEqual(diagnostic, {})

    def test_non_directory_resolution_has_safe_diagnostic(self):
        diagnostic = {}
        self.assertEqual(self.inspect("ok.so/child", diagnostic=diagnostic), ["symlink_unresolved"])
        self.assertEqual(diagnostic, {"resolution_issue": "not_directory"})

    def test_success_does_not_emit_a_failure_diagnostic(self):
        diagnostic = {}
        self.assertEqual(self.inspect("ok.so", diagnostic=diagnostic), [])
        self.assertEqual(diagnostic, {})

    def test_relative_absolute_and_multihop_targets_are_checked(self):
        for target in ("ok.so", "/usr/lib/ok.so", "../lib/ok.so"):
            self.assertEqual(self.inspect(target), [])
        self.assertEqual(self.inspect("second", links={"/usr/lib/second": "ok.so"}), [])

    def test_internal_directory_is_covered_but_external_directory_is_not(self):
        self.assertEqual(self.inspect("/app"), [])
        self.assertEqual(self.inspect("/etc/ssl"), ["symlink_external_directory_unreviewed"])
        self.assertEqual(self.inspect("/"), ["symlink_external_directory_unreviewed"])

    def test_secure_external_file_metadata_can_pass(self):
        self.assertEqual(self.inspect("/etc/ssl/ca.pem"), [])

    def test_each_intermediate_directory_and_final_file_must_be_secure(self):
        for name in ("/", "/etc", "/etc/ssl", "/etc/ssl/ca.pem"):
            kind = stat.S_IFREG if name.endswith(".pem") else stat.S_IFDIR
            for mode, uid, reason in ((0o777, 0, "code_group_or_world_writable"),
                                      (0o755, 100, "code_not_root_owned")):
                with self.subTest(name=name, mode=mode, uid=uid):
                    self.assertIn("symlink_target_" + reason,
                                  self.inspect("/etc/ssl/ca.pem", nodes={name: (kind | mode, uid)}))
            self.assertIn("symlink_target_code_writable_by_app",
                          self.inspect("/etc/ssl/ca.pem", writable=(name,)))

    def test_unsafe_intermediate_link_cannot_be_hidden_by_safe_final_target(self):
        self.assertIn("symlink_target_code_not_root_owned", self.inspect("second",
                      links={"/usr/lib/second": "ok.so"},
                      nodes={"/usr/lib/second": (stat.S_IFLNK | 0o777, 100)}))
        visited = []
        self.assertIn("symlink_target_code_group_or_world_writable", self.inspect("/tmp/redirect",
                      links={"/tmp/redirect": "/usr/lib/ok.so"},
                      nodes={"/tmp": (stat.S_IFDIR | 0o1777, 0)}, visited=visited))
        self.assertNotIn("/tmp/redirect", visited)

    def test_link_before_dotdot_is_resolved_before_parent_traversal(self):
        # Lexically collapsing jump/.. would incorrectly select /usr/lib/ok.so.
        self.assertEqual(self.inspect("jump/../ok.so", links={"/usr/lib/jump": "/etc/ssl"}),
                         ["symlink_unresolved"])

    def test_file_with_trailing_slash_dot_or_parent_is_not_valid(self):
        for target in ("ok.so/", "ok.so/.", "ok.so/..", "ok.so/../ok.so"):
            with self.subTest(target=target):
                self.assertEqual(self.inspect(target), ["symlink_unresolved"])

    def test_cycles_and_limits_block(self):
        self.assertEqual(self.inspect("link"), ["symlink_resolution_limit"])
        self.assertEqual(self.inspect("second", links={"/usr/lib/second": "link"}),
                         ["symlink_resolution_limit"])
        with patch.object(checker, "MAX_LINK_STEPS", 1):
            self.assertEqual(self.inspect("ok.so"), ["symlink_resolution_limit"])
        with patch.object(checker, "MAX_LINK_HOPS", 0):
            self.assertEqual(self.inspect("ok.so"), ["symlink_resolution_limit"])

    def test_broken_and_inaccessible_links_block_without_error_payload(self):
        for item in (None, PermissionError("private-value")):
            nodes = {} if item is None else {"/usr/lib/missing": item}
            self.assertEqual(self.inspect("missing", nodes=nodes), ["symlink_unresolved"])

    def test_virtual_targets_rejected_without_reading_their_metadata(self):
        for target in ("/proc/self/fd/3", "/dev/fd/3", "/sys/firmware", "/run/secrets"):
            visited = []
            self.assertEqual(self.inspect(target, visited=visited), ["symlink_virtual_target"])
            self.assertNotIn("/" + target.split("/")[1], visited)

    def test_special_files_are_not_opened_or_approved(self):
        for kind in (stat.S_IFIFO, stat.S_IFSOCK, stat.S_IFCHR):
            self.assertEqual(self.inspect("special", nodes={"/usr/lib/special": (kind | 0o600, 0)}),
                             ["symlink_special_target"])

    def test_final_file_setid_and_capabilities_block(self):
        self.assertIn("symlink_target_setid_file", self.inspect("ok.so",
                      nodes={"/usr/lib/ok.so": (stat.S_IFREG | 0o4755, 0)}))
        self.assertIn("symlink_target_file_capability", self.inspect("ok.so", capabilities=("/usr/lib/ok.so",)))

    def test_external_target_keeps_component_checks(self):
        self.assertEqual(self.inspect("/etc/libssl.so.1.1",
                         nodes={"/etc/libssl.so.1.1": (stat.S_IFREG | 0o644, 0)}), ["legacy_openssl_library"])
        self.assertEqual(self.inspect("/etc/Archive/Tar.pm", nodes={
                         "/etc/Archive": (stat.S_IFDIR | 0o755, 0),
                         "/etc/Archive/Tar.pm": (stat.S_IFREG | 0o644, 0)}), ["perl_archive_tar_named_file"])

    def test_invalid_and_oversized_link_targets_block(self):
        for target in ("", "//usr/lib/ok.so", "private\nvalue", "a" * (checker.MAX_LINK_PATH + 1)):
            self.assertEqual(self.inspect(target), ["symlink_invalid_target"])
