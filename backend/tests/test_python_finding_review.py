import copy
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest


path = Path(__file__).resolve().parents[2] / "scripts" / "review-python-findings.py"
spec = importlib.util.spec_from_file_location("python_finding_review", path)
reviewer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reviewer)
IMAGE = "sha256:" + "a" * 64


def fixture():
    modules = {name: {"path": f"/{name}.so", "sha256": digest, "size": 100}
               for name, digest in reviewer.MODULE_HASHES.items()}
    backport = {
        "python": "3.11.16", "expat": "2.8.3", "blocked": False,
        "scanner_findings_waived": False, "cookie_controls_tested": 33,
        "cookie_checks": {name: True for name in reviewer.COOKIE_CHECKS},
        "xml_recursion_guard": True,
        "xml_capi_evidence": {"ready": True, "salt_16_bytes_available": True,
                              "compiled_expat_version": [2, 8, 3], "reviewed_layout_size": 224},
        "xml_native_evidence": {"modules": modules,
                                "parse_checks": {"pyexpat": True, "_elementtree": True}},
    }
    trace = {
        "image_id": IMAGE, "scanner_findings_waived": False,
        "status": "synthetic_call_path_observed_not_security_approval",
        "checks": [{"parser": name, "modules": modules, "hardware_breakpoints": True,
                    "salt_values_read": False, "salt16_hits": 3, "legacy_hits": 0,
                    "parse_successes": 3, "exit_code": 0} for name in modules],
    }
    rows = [["High", cve, "python", "3.11.16", "binary", "fixed", [], "nvd:cpe", ["stock-matcher"]]
            for cve in reviewer.REVIEWED_CVES]
    rows.append(["High", "CVE-unresolved", "libc6", "2.41", "deb", "not-fixed", [],
                 "debian:distro:debian:13", ["dpkg-matcher"]])
    annotations = {
        "Image vulnerability audit": {
            "image_id": IMAGE, "scanner": "0.118.0", "blocked": True,
            "total_findings": 4, "annotated_findings": 4,
            "counts": {name: 4 if name == "High" else 0 for name in reviewer.SEVERITIES}},
        "Image vulnerability details 1": {"columns": reviewer.COLUMNS, "rows": rows},
        "Python backport checks": backport,
        "XML execution trace (not approval)": trace,
    }
    return {"schema": 1, "run": {"id": 123, "head_sha": "b" * 40, "status": "completed",
                                   "html_url": "https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/123"},
            "annotations": [{"title": name, "message": json.dumps(value)}
                            for name, value in annotations.items()]}


def change(data, title, edit):
    entry = next(entry for entry in data["annotations"] if entry["title"] == title)
    value = json.loads(entry["message"])
    edit(value)
    entry["message"] = json.dumps(value)


class PythonFindingReviewTests(unittest.TestCase):
    def test_three_specific_candidates_preserve_gate_and_other_findings(self):
        data = fixture()
        original = copy.deepcopy(data)
        result = reviewer.review(data)
        self.assertEqual(result["candidate_cves"], list(reviewer.REVIEWED_CVES))
        self.assertEqual(result["remaining_high_cves"], ["CVE-unresolved"])
        self.assertEqual(result["original_counts"]["High"], 4)
        self.assertEqual(result["high_matches_after_separate_approval"], 1)
        self.assertFalse(result["scanner_gate_changed"])
        self.assertFalse(result["deployment_approved"])
        self.assertEqual(data, original)

    def test_truncated_annotation_batch_is_rejected(self):
        data = fixture()
        change(data, "Image vulnerability details 1", lambda item: item["rows"].pop())
        with self.assertRaises(ValueError):
            reviewer.review(data)

    def test_duplicate_titles_or_missing_evidence_are_rejected(self):
        for duplicate in (False, True):
            data = fixture()
            if duplicate:
                data["annotations"].append(copy.deepcopy(data["annotations"][0]))
            else:
                data["annotations"].pop()
            with self.assertRaises((KeyError, ValueError)):
                reviewer.review(data)

    def test_wrong_image_version_or_hash_rejects_review(self):
        cases = [
            ("XML execution trace (not approval)", lambda item: item.update(image_id="sha256:" + "c" * 64)),
            ("Python backport checks", lambda item: item.update(python="3.11.17")),
            ("Python backport checks", lambda item: item["xml_native_evidence"]["modules"]["pyexpat"].update(sha256="c" * 64)),
        ]
        for title, edit in cases:
            with self.subTest(title=title):
                data = fixture()
                change(data, title, edit)
                with self.assertRaises(ValueError):
                    reviewer.review(data)

    def test_each_cookie_regression_must_pass_with_all_controls(self):
        for name in reviewer.COOKIE_CHECKS:
            data = fixture()
            change(data, "Python backport checks", lambda item: item["cookie_checks"].update({name: False}))
            with self.assertRaises(ValueError):
                reviewer.review(data)
        data = fixture()
        change(data, "Python backport checks", lambda item: item.update(cookie_controls_tested=32))
        with self.assertRaises(ValueError):
            reviewer.review(data)

    def test_capi_availability_is_not_a_substitute_for_hardware_trace(self):
        for field, value in (("hardware_breakpoints", False), ("legacy_hits", 1),
                             ("salt16_hits", 0), ("parse_successes", 0), ("exit_code", 1)):
            data = fixture()
            change(data, "XML execution trace (not approval)",
                   lambda item: item["checks"][1].update({field: value}))
            with self.assertRaises(ValueError):
                reviewer.review(data)

    def test_recursion_and_compilation_conditions_required(self):
        for edit in (lambda item: item.update(xml_recursion_guard=False),
                     lambda item: item["xml_capi_evidence"].update(compiled_expat_version=[2, 7, 0]),
                     lambda item: item["xml_capi_evidence"].update(ready=False)):
            data = fixture()
            change(data, "Python backport checks", edit)
            with self.assertRaises(ValueError):
                reviewer.review(data)

    def test_same_cve_in_different_package_or_matcher_is_not_exempted(self):
        for index, value in ((2, "other-package"), (3, "3.11.15"), (4, "deb"),
                             (7, "other-namespace"), (8, ["other-matcher"])):
            data = fixture()
            change(data, "Image vulnerability details 1", lambda item: item["rows"][0].__setitem__(index, value))
            with self.assertRaises(ValueError):
                reviewer.review(data)

    def test_incomplete_run_or_wrong_provenance_rejected(self):
        for field, value in (("status", "in_progress"), ("head_sha", "main"),
                             ("html_url", "https://example.invalid/123")):
            data = fixture()
            data["run"][field] = value
            with self.assertRaises(ValueError):
                reviewer.review(data)

    def test_cli_failure_does_not_publish_input_or_write_result(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "input.json", Path(directory) / "output.json"
            source.write_text('{"private":"do-not-print"}', encoding="utf-8")
            with redirect_stdout(io.StringIO()) as captured:
                self.assertEqual(reviewer.main([str(source), "--output", str(output)]), 2)
            self.assertNotIn("do-not-print", captured.getvalue())
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
