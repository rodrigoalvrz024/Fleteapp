import copy
from contextlib import redirect_stdout
from datetime import date
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


policy = load("image_policy", ROOT / "scripts/evaluate-image-policy.py")
fixtures = load("policy_review_fixture", Path(__file__).with_name("test_python_finding_review.py"))
IMAGE = fixtures.IMAGE
COMMIT = "b" * 40


def inputs():
    data = fixtures.fixture()
    annotations = {entry["title"]: json.loads(entry["message"]) for entry in data["annotations"]}
    rows = annotations["Image vulnerability details 1"]["rows"]
    report = {"descriptor": {"name": "grype", "version": "0.118.0", "db": {"status": "valid"},
                             "timestamp": "2026-09-15T05:00:00Z"},
              "source": {"type": "image", "target": {"imageID": IMAGE}}, "matches": []}
    for row in rows:
        report["matches"].append({
            "vulnerability": {"severity": row[0], "id": row[1], "namespace": row[7],
                              "dataSource": "https://example.invalid/advisory",
                              "fix": {"state": row[5], "versions": row[6]}},
            "artifact": {"name": row[2], "version": row[3], "type": row[4]},
            "matchDetails": [{"matcher": item} for item in row[8]],
        })
    backport = annotations["Python backport checks"]
    backport["ci_identity"] = {"image_id": IMAGE, "commit": COMMIT, "run_id": "123"}
    return report, backport, annotations["XML execution trace (not approval)"]


def evaluate(values, **kwargs):
    return policy.evaluate(*values, image_id=IMAGE, commit=COMMIT, run_id="123",
                           today=kwargs.get("today", date(2026, 9, 15)))


class ImagePolicyTests(unittest.TestCase):
    def test_preserves_all_findings_and_only_subtracts_three(self):
        values = inputs()
        before = copy.deepcopy(values)
        original, result = evaluate(values)
        self.assertEqual(values, before)
        self.assertEqual(len(original["findings"]), 4)
        self.assertEqual(result["original_counts"]["High"], 4)
        self.assertEqual(result["remaining_counts"]["High"], 1)
        self.assertEqual(len(result["recognized_corrections"]), 3)
        self.assertTrue(original["blocked"])
        self.assertTrue(result["blocked"])
        self.assertFalse(result["deployment_approved"])

    def test_only_three_corrected_findings_can_clear_high_gate_not_release(self):
        values = inputs()
        values[0]["matches"].pop()
        original, result = evaluate(values)
        self.assertTrue(original["blocked"])
        self.assertFalse(result["blocked"])
        self.assertFalse(result["deployment_approved"])

    def test_new_python_finding_is_not_covered_by_old_approval(self):
        values = inputs()
        new_finding = copy.deepcopy(values[0]["matches"][0])
        new_finding["vulnerability"]["id"] = "CVE-2026-82049"
        values[0]["matches"].append(new_finding)
        original, result = evaluate(values)
        self.assertEqual(original["counts"]["High"], 5)
        self.assertEqual(result["remaining_counts"]["High"], 2)
        self.assertTrue(result["blocked"])
        self.assertNotIn("CVE-2026-82049",
                         [row["id"] for row in result["recognized_corrections"]])
        values[0]["matches"] = [new_finding]
        with self.assertRaises(policy.reviewer.ReviewedFindingSetMismatch):
            evaluate(values)

    def test_drift_diagnoses_missing_findings_and_changed_binary_together(self):
        values = inputs()
        values[0]["matches"] = values[0]["matches"][-1:]
        values[1]["xml_native_evidence"]["modules"]["pyexpat"]["sha256"] = "c" * 64
        before = copy.deepcopy(values)
        original = policy.audit.inspect_report(values[0], IMAGE)
        drift = policy.evidence_drift(original["findings"], values[1])
        self.assertEqual(drift["missing_reviewed_findings"], list(policy.reviewer.REVIEWED_CVES))
        self.assertEqual(drift["changed_or_missing_modules"], ["pyexpat"])
        self.assertEqual(drift["duplicate_reviewed_findings"], [])
        self.assertFalse(drift["scanner_findings_waived"])
        self.assertFalse(drift["deployment_approved"])
        self.assertEqual(values, before)
        with self.assertRaises(policy.reviewer.ReviewedFindingSetMismatch):
            evaluate(values)

    def test_drift_is_bounded_and_does_not_echo_untrusted_evidence(self):
        for evidence in (None, [], "never-print", {"xml_native_evidence": []},
                         {"xml_native_evidence": {"modules": {"never-print": "secret"}}}):
            drift = policy.evidence_drift([], evidence)
            self.assertEqual(drift["changed_or_missing_modules"], list(policy.reviewer.MODULE_HASHES))
            self.assertNotIn("never-print", json.dumps(drift))
            self.assertNotIn("secret", json.dumps(drift))
        values = inputs()
        original = policy.audit.inspect_report(values[0], IMAGE)
        drift = policy.evidence_drift(original["findings"] * 2, values[1])
        self.assertEqual(drift["duplicate_reviewed_findings"], list(policy.reviewer.REVIEWED_CVES))
        self.assertEqual(drift["changed_or_missing_modules"], [])

    def test_other_severities_and_eol_remain_unapproved(self):
        for severity in policy.audit.SEVERITIES:
            values = inputs()
            values[0]["matches"][-1]["vulnerability"]["severity"] = severity
            original, result = evaluate(values)
            self.assertEqual(result["remaining_counts"][severity], 1)
            self.assertEqual(result["blocked"], severity in ("High", "Critical"))
            self.assertFalse(result["deployment_approved"])
        values = inputs()
        values[0]["matches"].pop()
        values[0]["alertsByPackage"] = [{"alerts": [{"type": "eol"}]}]
        self.assertTrue(evaluate(values)[1]["blocked"])

    def test_expired_or_not_yet_valid_approval_blocks(self):
        for day in (date(2026, 9, 14), date(2026, 10, 15), date(2027, 1, 1)):
            with self.subTest(day=day), self.assertRaises(ValueError):
                evaluate(inputs(), today=day)
        self.assertTrue(evaluate(inputs(), today=date(2026, 10, 14))[1]["blocked"])

    def test_image_commit_and_run_must_all_match(self):
        for field, value in (("image_id", "sha256:" + "c" * 64), ("commit", "c" * 40), ("run_id", "124")):
            values = inputs()
            values[1]["ci_identity"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                evaluate(values)
        for index in (0, 2):
            values = inputs()
            if index == 0:
                values[0]["source"]["target"]["imageID"] = "sha256:" + "c" * 64
            else:
                values[2]["image_id"] = "sha256:" + "c" * 64
            with self.assertRaises(ValueError):
                evaluate(values)

    def test_no_matching_by_cve_alone_or_duplicate_dispositions(self):
        for section, field, value in (("artifact", "name", "other"), ("artifact", "version", "3.11.15"),
                                      ("artifact", "type", "deb"), ("vulnerability", "namespace", "other")):
            values = inputs()
            values[0]["matches"][0][section][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                evaluate(values)
        values = inputs()
        values[0]["matches"].append(copy.deepcopy(values[0]["matches"][0]))
        with self.assertRaises(ValueError):
            evaluate(values)

    def test_missing_hash_or_failed_cookie_xml_trace_blocks(self):
        edits = (
            lambda v: v[1]["xml_native_evidence"]["modules"]["pyexpat"].update(sha256="c" * 64),
            lambda v: v[1]["cookie_checks"].update(update=False),
            lambda v: v[1].update(xml_recursion_guard=False),
            lambda v: v[2]["checks"][0].update(legacy_hits=1),
            lambda v: v[2].update(checks=[]),
            lambda v: v[0].update(ignoredMatches=[{}]),
            lambda v: v[0]["matches"].pop(0),
        )
        for edit in edits:
            values = inputs()
            edit(values)
            with self.assertRaises(ValueError):
                evaluate(values)

    def test_cli_missing_evidence_fails_closed_without_disclosing_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text('{"secret":"never-print"}', encoding="utf-8")
            with redirect_stdout(io.StringIO()) as captured:
                result = policy.main([str(path), "--backports", str(path), "--trace", str(path),
                                      "--image-id", IMAGE, "--commit", COMMIT, "--run-id", "123",
                                      "--github-annotation"])
            self.assertEqual(result, 2)
            self.assertNotIn("never-print", captured.getvalue())
            self.assertIn('"blocked": true', captured.getvalue())
            self.assertIn('"reason": "invalid_missing_or_expired_evidence"', captured.getvalue())

    def test_cli_preserves_raw_annotations_and_blocks_unresolved(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / f"{i}.json" for i in range(3)]
            for path, value in zip(paths, inputs()):
                path.write_text(json.dumps(value), encoding="utf-8")
            real_evaluate = policy.evaluate
            def at_approval_date(*args, **kwargs):
                return real_evaluate(*args, **kwargs, today=date(2026, 9, 15))
            with patch.object(policy, "evaluate", side_effect=at_approval_date), redirect_stdout(io.StringIO()) as captured:
                result = policy.main([str(paths[0]), "--backports", str(paths[1]), "--trace", str(paths[2]),
                                      "--image-id", IMAGE, "--commit", COMMIT, "--run-id", "123",
                                      "--github-annotation"])
            self.assertEqual(result, 1)
            self.assertIn("title=Image vulnerability audit::", captured.getvalue())
            self.assertIn("CVE-unresolved", captured.getvalue())
            self.assertIn("title=Approved Python corrections::", captured.getvalue())

    def test_valid_scan_survives_missing_wrong_or_expired_approval_evidence(self):
        for failure in ("missing", "hash", "elementtree_hash", "expired",
                        "absent_findings", "duplicate_finding", "absent_and_hash"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                paths = [Path(directory) / f"{i}.json" for i in range(3)]
                values = inputs()
                if failure in ("hash", "elementtree_hash", "absent_and_hash"):
                    module = "_elementtree" if failure == "elementtree_hash" else "pyexpat"
                    values[1]["xml_native_evidence"]["modules"][module]["sha256"] = "never-print\n::error::injected"
                if failure in ("absent_findings", "absent_and_hash"):
                    values[0]["matches"] = values[0]["matches"][-1:]
                if failure == "duplicate_finding":
                    values[0]["matches"].append(copy.deepcopy(values[0]["matches"][0]))
                for path, value in zip(paths, values):
                    path.write_text(json.dumps(value), encoding="utf-8")
                if failure == "missing":
                    paths[1].unlink()
                real_evaluate = policy.evaluate
                def with_date(*args, **kwargs):
                    return real_evaluate(*args, **kwargs, today=date(2026, 10, 15) if failure == "expired" else date(2026, 9, 15))
                with patch.object(policy, "evaluate", side_effect=with_date), redirect_stdout(io.StringIO()) as captured:
                    code = policy.main([str(paths[0]), "--backports", str(paths[1]), "--trace", str(paths[2]),
                                        "--image-id", IMAGE, "--commit", COMMIT, "--run-id", "123",
                                        "--github-annotation"])
                self.assertEqual(code, 2)
                self.assertIn("title=Image vulnerability audit::", captured.getvalue())
                self.assertIn("CVE-unresolved", captured.getvalue())
                self.assertNotIn("title=Approved Python corrections::", captured.getvalue())
                expected_reason = ("reviewed_python_module_hash_mismatch"
                                   if failure in ("hash", "elementtree_hash")
                                   else "invalid_missing_or_expired_evidence")
                if failure in ("absent_findings", "duplicate_finding", "absent_and_hash"):
                    expected_reason = "reviewed_python_finding_set_mismatch"
                self.assertIn(f'"reason": "{expected_reason}"', captured.getvalue())
                self.assertIn('"deployment_approved": false', captured.getvalue())
                self.assertNotIn("never-print", captured.getvalue())
                self.assertNotIn("::error::injected", captured.getvalue())
                if failure == "absent_and_hash":
                    self.assertIn('"changed_or_missing_modules": ["pyexpat"]', captured.getvalue())
                    self.assertIn('"missing_reviewed_findings": ["CVE-2026-3644", "CVE-2026-4224", "CVE-2026-7210"]', captured.getvalue())


class PolicyWorkflowTests(unittest.TestCase):
    def test_workflow_preserves_evidence_and_never_ignores_policy_exit(self):
        import yaml
        path = ROOT / ".github/workflows/backend-linux-candidate.yml"
        if not path.exists():
            self.skipTest("Workflow is repository-only, not mounted in runtime unit tests")
        config = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
        steps = config["jobs"]["image-and-unit-tests"]["steps"]
        preserve = next(s for s in steps if s["name"] == "Preserve Python correction evidence without credentials")
        self.assertEqual(preserve["with"]["if-no-files-found"], "error")
        self.assertEqual(preserve["with"]["path"], "${{ runner.temp }}/python-backport-evidence/report.json")
        backport = next(s for s in steps if s["name"].startswith("Verify bounded Python"))["run"]
        self.assertIn("title=Python backport checks", backport)
        self.assertIn('--entrypoint python "$image_id"', backport)
        scan = next(s for s in steps if s["name"].startswith("Scan OS"))
        self.assertNotIn("continue-on-error", scan)
        self.assertIn("set -euo pipefail", scan["run"])
        self.assertIn("scripts/evaluate-image-policy.py", scan["run"])
        self.assertNotIn("|| true", scan["run"])


if __name__ == "__main__":
    unittest.main()
