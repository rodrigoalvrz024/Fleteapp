import importlib.util
import hashlib
import ctypes
import io
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


path = Path(__file__).resolve().parents[2] / "scripts" / "verify-python-backports.py"
spec = importlib.util.spec_from_file_location("python_backport_checker", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ReviewedVersion(tuple):
    releaselevel = "final"


class PythonBackportVerifierTests(unittest.TestCase):
    def test_capi_probe_checks_compiled_version_and_required_pointer(self):
        for minor, address, ready in ((8, 123, True), (8, None, False), (7, 123, False)):
            api = checker.ExpatCapi(size=ctypes.sizeof(checker.ExpatCapi), major=2, minor=minor,
                                   micro=3, SetHashSalt16Bytes=address)
            calls = SimpleNamespace(PyCapsule_IsValid=Mock(return_value=1),
                                    PyCapsule_GetPointer=Mock(return_value=456))
            with patch.object(checker.sys, "platform", "linux"), \
                    patch.object(checker.sys, "version_info", ReviewedVersion((3, 11, 16))), \
                    patch.object(checker.ctypes, "pythonapi", calls), \
                    patch.object(checker, "capi_snapshot", return_value=api):
                result = checker.expat_capi_evidence()
            self.assertIs(result["ready"], ready)
            self.assertFalse(result["hash_salt_call_path_proven"])
            self.assertEqual(result["compiled_expat_version"], [2, minor, 3])
            self.assertNotIn("123", str(result))

    def test_capi_probe_rejects_invalid_capsule_before_getting_pointer(self):
        calls = SimpleNamespace(PyCapsule_IsValid=Mock(return_value=0), PyCapsule_GetPointer=Mock())
        with patch.object(checker.sys, "platform", "linux"), \
                patch.object(checker.sys, "version_info", ReviewedVersion((3, 11, 16))), \
                patch.object(checker.ctypes, "pythonapi", calls), self.assertRaises(ValueError):
            checker.expat_capi_evidence()
        calls.PyCapsule_GetPointer.assert_not_called()

    def test_capi_snapshot_reads_metadata_without_modifying_it(self):
        magic = ctypes.create_string_buffer(checker.EXPAT_CAPI_MAGIC)
        api = checker.ExpatCapi(magic=ctypes.addressof(magic), size=ctypes.sizeof(checker.ExpatCapi),
                               major=2, minor=8, micro=3, SetHashSalt16Bytes=123)
        original = bytes(api)
        result = checker.capi_snapshot(ctypes.addressof(api))
        self.assertEqual((result.major, result.minor, result.micro), (2, 8, 3))
        self.assertEqual(result.SetHashSalt16Bytes, 123)
        self.assertEqual(bytes(api), original)

    def test_capi_snapshot_rejects_null_truncated_or_changed_layout(self):
        with self.assertRaises(ValueError):
            checker.capi_snapshot(0)
        for size in (0, ctypes.sizeof(checker.ExpatCapi) - 8, ctypes.sizeof(checker.ExpatCapi) + 8):
            api = checker.ExpatCapiHeader(size=size)
            with self.assertRaises(ValueError):
                checker.capi_snapshot(ctypes.addressof(api))
        magic = ctypes.create_string_buffer(b"x" * len(checker.EXPAT_CAPI_MAGIC))
        api = checker.ExpatCapi(magic=ctypes.addressof(magic), size=ctypes.sizeof(checker.ExpatCapi))
        with self.assertRaises(ValueError):
            checker.capi_snapshot(ctypes.addressof(api))

    def test_capi_probe_rejects_unreviewed_runtime_before_reading_memory(self):
        with patch.object(checker.sys, "platform", "win32"), \
                patch.object(checker, "capi_snapshot") as snapshot, self.assertRaises(RuntimeError):
            checker.expat_capi_evidence()
        snapshot.assert_not_called()

    def test_native_module_identity_hashes_bounded_content(self):
        path = Mock()
        module = SimpleNamespace(__file__="synthetic.so")
        with patch.object(checker, "Path", return_value=path):
            path.resolve.return_value = path
            path.open.return_value.__enter__ = Mock(return_value=io.BytesIO(b"native-test"))
            path.open.return_value.__exit__ = Mock(return_value=False)
            result = checker.module_identity(module)
        self.assertEqual(result["sha256"], hashlib.sha256(b"native-test").hexdigest())
        self.assertEqual(result["size"], 11)

    def test_native_module_identity_rejects_empty_or_excessive_content(self):
        for content in (b"", b"too-large"):
            path = Mock()
            path.resolve.return_value = path
            path.open.return_value.__enter__ = Mock(return_value=io.BytesIO(content))
            path.open.return_value.__exit__ = Mock(return_value=False)
            with patch.object(checker, "Path", return_value=path), \
                    patch.object(checker, "MAX_NATIVE_MODULE_BYTES", 4), self.assertRaises(ValueError):
                checker.module_identity(SimpleNamespace(__file__="synthetic.so"))

    def test_both_native_parsers_work_without_claiming_hash_salt_execution(self):
        with patch.object(checker, "module_identity", return_value={"sha256": "synthetic"}):
            result = checker.xml_native_evidence()
        self.assertEqual(set(result["modules"]), {"pyexpat", "_elementtree"})
        self.assertEqual(result["parse_checks"], {"pyexpat": True, "_elementtree": True})
        self.assertFalse(result["hash_salt_call_path_proven"])

    def test_native_identity_error_fails_closed_without_leaking_paths(self):
        with patch.object(checker, "cookie_checks", return_value={"all": True}), \
                patch.object(checker, "xml_recursion_is_bounded", return_value=True), \
                patch.object(checker, "module_identity", side_effect=OSError("private-path")), \
                patch.object(checker.sys, "stdout", new_callable=io.StringIO) as output:
            self.assertEqual(checker.main([]), 2)
        self.assertNotIn("private-path", output.getvalue())

    def test_failed_native_parse_blocks_evidence(self):
        for failed in ("pyexpat", "_elementtree"):
            evidence = {"parse_checks": {"pyexpat": True, "_elementtree": True}}
            evidence["parse_checks"][failed] = False
            with patch.object(checker, "cookie_checks", return_value={"all": True}), \
                    patch.object(checker, "xml_recursion_is_bounded", return_value=True), \
                    patch.object(checker, "version_requirements", return_value={"all": True}), \
                    patch.object(checker, "expat_capi_evidence", return_value={"ready": True}), \
                    patch.object(checker, "xml_native_evidence", return_value=evidence):
                self.assertTrue(checker.collect_evidence()["blocked"])

    def test_reviewed_versions_required_without_accepting_other_series(self):
        self.assertTrue(all(checker.version_requirements("cpython", (3, 11, 16), "final", (2, 8, 3)).values()))
        for implementation, version, level, expat in (
            ("cpython", (3, 11, 15), "final", (2, 8, 3)),
            ("cpython", (3, 12, 16), "final", (2, 8, 3)),
            ("cpython", (3, 14, 7), "final", (2, 8, 3)),
            ("pypy", (3, 11, 16), "final", (2, 8, 3)),
            ("cpython", (3, 11, 16), "candidate", (2, 8, 3)),
            ("cpython", (3, 11, 16), "final", (2, 7, 0)),
        ):
            self.assertFalse(all(checker.version_requirements(implementation, version, level, expat).values()))

    def test_cookie_cases_cover_all_control_bytes_and_valid_input(self):
        with patch.object(checker, "cookie_rejects", return_value=True) as probe:
            results = checker.cookie_checks()
        self.assertTrue(all(results.values()))
        self.assertEqual(probe.call_count, 7 * 33)
        self.assertEqual(set(checker.CONTROL_CHARACTERS), set(map(chr, (*range(32), 127))))

    def test_cookie_check_does_not_accept_an_unpatched_path(self):
        with patch.object(checker, "cookie_rejects", side_effect=lambda case, char: case != "merge"):
            results = checker.cookie_checks()
        self.assertFalse(results["merge"])
        self.assertTrue(results["valid_cookie_preserved"])

    def test_cookie_javascript_accepts_both_complete_formats(self):
        expected = "session=synthetic; HttpOnly; Path=/"
        for expression in (checker.json.dumps(expected),
                           f'decodeURIComponent({checker.json.dumps(checker.quote(expected, safe=""))})'):
            output = ('<script type="text/javascript">\n<!-- begin hiding\n'
                      f'document.cookie = {expression};\n// end hiding -->\n</script>')
            self.assertTrue(checker.valid_cookie_javascript(output, expected))

    def test_cookie_javascript_rejects_missing_altered_or_extra_content(self):
        expected = "session=synthetic; HttpOnly; Path=/"
        template = ('<script type="text/javascript">\n<!-- begin hiding\n'
                    'document.cookie = %s;\n// end hiding -->\n</script>')
        for output in (
            "", expected, template % '"session=changed; HttpOnly; Path=/"',
            template % '"session=synthetic"',
            template % 'decodeURIComponent("session%3Dsynthetic")',
            template % 'decodeURIComponent("session%3Dsynthetic"',
            template % checker.json.dumps(expected) + '\nextra();',
            template % ('decodeURIComponent(' + checker.json.dumps(
                checker.quote(expected.replace("Path=/", "Path=/changed"), safe="")) + ')'),
        ):
            with self.subTest(output=output):
                self.assertFalse(checker.valid_cookie_javascript(output, expected))

    def test_cookie_probe_only_accepts_the_expected_exception(self):
        morsel = Mock()
        with patch.object(checker.cookies, "Morsel", return_value=morsel):
            self.assertFalse(checker.cookie_rejects("update", "\r"))
            morsel.update.side_effect = checker.cookies.CookieError()
            self.assertTrue(checker.cookie_rejects("update", "\r"))
            morsel.update.side_effect = RuntimeError("synthetic-private-value")
            with self.assertRaises(RuntimeError):
                checker.cookie_rejects("update", "\r")

    def test_xml_probe_is_small_and_restores_the_recursion_limit(self):
        for error, expected in ((None, False), (RecursionError(), True)):
            parser = Mock()
            parser.Parse.side_effect = error
            with patch.object(checker.pyexpat, "ParserCreate", return_value=parser), \
                    patch.object(checker.sys, "getrecursionlimit", return_value=1000), \
                    patch.object(checker.sys, "setrecursionlimit") as limit:
                self.assertIs(checker.xml_recursion_is_bounded(), expected)
            self.assertLess(len(parser.Parse.call_args.args[0]), 1024)
            self.assertEqual([call.args[0] for call in limit.call_args_list], [64, 1000])

    def test_xml_other_errors_fail_and_restore_the_limit(self):
        parser = Mock()
        parser.Parse.side_effect = ValueError("synthetic-private-value")
        with patch.object(checker.pyexpat, "ParserCreate", return_value=parser), \
                patch.object(checker.sys, "getrecursionlimit", return_value=1000), \
                patch.object(checker.sys, "setrecursionlimit") as limit:
            with self.assertRaises(ValueError):
                checker.xml_recursion_is_bounded()
        limit.assert_called_with(1000)

    def test_any_failed_probe_blocks_and_does_not_waive_findings(self):
        for cookies, xml, capi_ready in (({"all": True}, True, True), ({"all": False}, True, True),
                                         ({"all": True}, False, True), ({"all": True}, True, False)):
            with patch.object(checker, "cookie_checks", return_value=cookies), \
                    patch.object(checker, "xml_recursion_is_bounded", return_value=xml), \
                    patch.object(checker, "expat_capi_evidence", return_value={"ready": capi_ready}), \
                    patch.object(checker, "version_requirements", return_value={"all": True}):
                result = checker.collect_evidence()
            self.assertEqual(result["blocked"], not (cookies["all"] and xml and capi_ready))
            self.assertFalse(result["scanner_findings_waived"])
            self.assertFalse(result["xml_hash_entropy_behavior_tested"])

    def test_cli_failure_is_safe_and_cannot_pass(self):
        with patch.object(checker, "collect_evidence", side_effect=RuntimeError("synthetic-private-value")), \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(checker.main([]), 2)
        self.assertNotIn("synthetic-private-value", output.getvalue())

    def test_cli_returns_blocked_or_passed_without_scanner_override(self):
        for blocked, expected in ((True, 1), (False, 0)):
            with patch.object(checker, "collect_evidence", return_value={"blocked": blocked}), \
                    patch("sys.stdout", new_callable=io.StringIO) as output:
                self.assertEqual(checker.main(["--github-annotation"]), expected)
            self.assertIn("title=Python backport checks", output.getvalue())
