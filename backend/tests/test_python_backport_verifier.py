import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import Mock, patch


path = Path(__file__).resolve().parents[2] / "scripts" / "verify-python-backports.py"
spec = importlib.util.spec_from_file_location("python_backport_checker", path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class PythonBackportVerifierTests(unittest.TestCase):
    def test_reviewed_versions_required_without_accepting_other_series(self):
        self.assertTrue(all(checker.version_requirements("cpython", (3, 11, 16), "final", (2, 8, 3)).values()))
        for implementation, version, level, expat in (
            ("cpython", (3, 11, 15), "final", (2, 8, 3)),
            ("cpython", (3, 12, 16), "final", (2, 8, 3)),
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
        for cookies, xml in (({"all": True}, True), ({"all": False}, True), ({"all": True}, False)):
            with patch.object(checker, "cookie_checks", return_value=cookies), \
                    patch.object(checker, "xml_recursion_is_bounded", return_value=xml), \
                    patch.object(checker, "version_requirements", return_value={"all": True}):
                result = checker.collect_evidence()
            self.assertEqual(result["blocked"], not (cookies["all"] and xml))
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
