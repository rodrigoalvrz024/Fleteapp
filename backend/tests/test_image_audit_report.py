import copy
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


path = Path(__file__).resolve().parents[2] / "scripts" / "report-image-audit.py"
spec = importlib.util.spec_from_file_location("image_audit_report", path)
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)
IMAGE = "sha256:" + "a" * 64


def report():
    return {"descriptor": {"name": "grype", "version": "0.118.0", "db": {"status": "valid"},
                           "timestamp": "2026-09-11T00:00:00Z"},
            "source": {"type": "image", "target": {"imageID": IMAGE}}, "matches": []}


def match(severity="High", fixed=False):
    return {"vulnerability": {"id": "CVE-test", "severity": severity,
                              "dataSource": "https://example.invalid/advisory",
                              "fix": {"state": "fixed" if fixed else "not-fixed",
                                      "versions": ["2.0"] if fixed else []}},
            "artifact": {"name": "test-package", "version": "1.0", "type": "deb"}}


class ImageAuditReportTests(unittest.TestCase):
    def test_valid_clean_report_is_not_blocked(self):
        result = reporter.inspect_report(report(), IMAGE)
        self.assertFalse(result["blocked"])
        self.assertEqual(sum(result["counts"].values()), 0)

    def test_high_and_critical_block_even_without_fix(self):
        for severity in ("High", "Critical"):
            for fixed in (False, True):
                data = report()
                data["matches"] = [match(severity, fixed)]
                self.assertTrue(reporter.inspect_report(data, IMAGE)["blocked"])

    def test_lower_severities_are_retained(self):
        data = report()
        data["matches"] = [match(severity) for severity in reporter.SEVERITIES[2:]]
        result = reporter.inspect_report(data, IMAGE)
        self.assertFalse(result["blocked"])
        self.assertEqual(len(result["findings"]), 4)
        self.assertIn("Medium=1", reporter.markdown(result))

    def test_wrong_image_is_rejected(self):
        with self.assertRaises(ValueError):
            reporter.inspect_report(report(), "sha256:" + "b" * 64)

    def test_mutable_tag_is_rejected(self):
        with self.assertRaises(ValueError):
            reporter.inspect_report(report(), "muvv-backend:candidate")

    def test_partial_report_cannot_look_clean(self):
        for field in ("matches", "descriptor", "source"):
            data = report()
            del data[field]
            with self.assertRaises((ValueError, KeyError)):
                reporter.inspect_report(data, IMAGE)
        data = report()
        data["matches"] = None
        with self.assertRaises(ValueError):
            reporter.inspect_report(data, IMAGE)

    def test_scanner_and_database_metadata_are_required(self):
        for field, value in (("name", "other"), ("version", "0.0.0"), ("db", None), ("timestamp", "")):
            data = report()
            data["descriptor"][field] = value
            with self.assertRaises(ValueError):
                reporter.inspect_report(data, IMAGE)

    def test_ignored_results_are_not_silent(self):
        data = report()
        data["ignoredMatches"] = [match()]
        with self.assertRaises(ValueError):
            reporter.inspect_report(data, IMAGE)

    def test_eol_alert_blocks_review(self):
        data = report()
        data["alertsByPackage"] = [{"alerts": [{"type": "distro-eol"}]}]
        self.assertTrue(reporter.inspect_report(data, IMAGE)["blocked"])

    def test_malformed_severity_or_fix_is_rejected(self):
        for key, value in (("severity", "urgent"), ("fix", {"state": "unknown", "versions": None})):
            item = match()
            item["vulnerability"][key] = value
            data = report()
            data["matches"] = [item]
            with self.assertRaises(ValueError):
                reporter.inspect_report(data, IMAGE)

    def test_does_not_publish_image_environment(self):
        data = report()
        data["source"]["target"]["imageConfig"] = {"env": ["PRIVATE=do-not-print"]}
        data["descriptor"]["configuration"] = {"credential": "do-not-print"}
        result = reporter.inspect_report(data, IMAGE)
        self.assertNotIn("do-not-print", str(result))

    def test_summary_escapes_package_markup(self):
        data = report()
        item = copy.deepcopy(match("Medium"))
        item["artifact"]["name"] = "<script>|`name`\n::error::bad"
        data["matches"] = [item]
        output = reporter.markdown(reporter.inspect_report(data, IMAGE))
        self.assertNotIn("<script>", output)
        self.assertNotIn("\n::error::", output)
        self.assertIn("&#124;", output)

    def test_match_provenance_preserved_without_raw_metadata(self):
        data = report()
        data["distro"] = {"name": "debian", "version": "13", "extra": "do-not-print"}
        item = match()
        item["vulnerability"]["namespace"] = "debian:distro:debian:13"
        item["matchDetails"] = [{"matcher": "dpkg-matcher", "searchedBy": {"extra": "do-not-print"}}]
        data["matches"] = [item]
        result = reporter.inspect_report(data, IMAGE)
        self.assertEqual(result["distro"], {"name": "debian", "version": "13"})
        self.assertEqual(result["findings"][0]["namespace"], "debian:distro:debian:13")
        self.assertEqual(result["findings"][0]["matchers"], ["dpkg-matcher"])
        self.assertTrue(result["blocked"])
        self.assertNotIn("do-not-print", json.dumps(reporter.annotation_payloads(result)))

    def test_missing_optional_provenance_does_not_drop_match(self):
        data = report()
        data["matches"] = [match()]
        result = reporter.inspect_report(data, IMAGE)
        self.assertEqual(result["findings"][0]["namespace"], "")
        self.assertEqual(result["findings"][0]["matchers"], [])
        self.assertTrue(result["blocked"])

    def test_malformed_provenance_is_rejected(self):
        for field, value in (("distro", "debian"), ("matchDetails", "dpkg-matcher"),
                             ("namespace", {"unexpected": "value"})):
            data = report()
            data["matches"] = [match()]
            if field == "distro":
                data[field] = value
            elif field == "namespace":
                data["matches"][0]["vulnerability"][field] = value
            else:
                data["matches"][0][field] = value
            with self.assertRaises(reporter.ReportValidationError):
                reporter.inspect_report(data, IMAGE)

    def test_empty_reference_url_preserves_official_match_shape_and_gate(self):
        for severity in ("High", "Medium"):
            data = report()
            item = match(severity)
            item["vulnerability"]["dataSource"] = ""
            data["matches"] = [item]
            result = reporter.inspect_report(data, IMAGE)
            self.assertEqual(result["counts"][severity], 1)
            self.assertEqual(result["blocked"], severity == "High")
            self.assertEqual(result["findings"][0]["source"], "")

    def test_empty_required_fields_still_fail(self):
        for section, field in (("vulnerability", "id"), ("artifact", "name"),
                               ("artifact", "version"), ("artifact", "type")):
            data = report()
            item = match()
            item[section][field] = " "
            data["matches"] = [item]
            with self.assertRaises(reporter.ReportValidationError):
                reporter.inspect_report(data, IMAGE)

    def test_non_string_url_is_not_accepted(self):
        data = report()
        data["matches"] = [match()]
        data["matches"][0]["vulnerability"]["dataSource"] = None
        with self.assertRaisesRegex(reporter.ReportValidationError, "vulnerability.dataSource"):
            reporter.inspect_report(data, IMAGE)

    def test_empty_fix_state_is_unknown_without_dropping_high_finding(self):
        data = report()
        data["matches"] = [match("High")]
        data["matches"][0]["vulnerability"]["fix"]["state"] = ""
        result = reporter.inspect_report(data, IMAGE)
        self.assertEqual(result["findings"][0]["fix_state"], "unknown")
        self.assertEqual(result["counts"]["High"], 1)
        self.assertTrue(result["blocked"])

    def test_invalid_fix_state_is_rejected(self):
        for state in (None, "safe", 0):
            data = report()
            data["matches"] = [match()]
            data["matches"][0]["vulnerability"]["fix"]["state"] = state
            with self.assertRaises(reporter.ReportValidationError):
                reporter.inspect_report(data, IMAGE)

    def invoke_cli(self, contents):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "report.json"
            file.write_text(contents, encoding="utf-8")
            output = io.StringIO()
            with patch("sys.argv", ["report-image-audit.py", str(file), "--image-id", IMAGE,
                                    "--github-annotation"]), redirect_stdout(output):
                code = reporter.main()
        return code, output.getvalue()

    def test_cli_invalid_json_fails_without_printing_content(self):
        code, output = self.invoke_cli('{"private": "do-not-print"')
        self.assertEqual(code, 2)
        self.assertIn("Reason: JSONDecodeError", output)
        self.assertIn("::error title=Image audit validation::", output)
        self.assertNotIn("do-not-print", output)

    def test_cli_reports_static_reason_without_scanner_value(self):
        data = report()
        data["descriptor"]["version"] = "do-not-print"
        code, output = self.invoke_cli(json.dumps(data))
        self.assertEqual(code, 2)
        self.assertIn("Reason: Unexpected scanner version", output)
        self.assertNotIn("do-not-print", output)

    def test_cli_missing_field_is_not_a_clean_report(self):
        code, output = self.invoke_cli('{"private": "do-not-print"}')
        self.assertEqual(code, 2)
        self.assertIn("Reason: KeyError", output)
        self.assertNotIn("do-not-print", output)

    def test_cli_high_without_reference_still_returns_one(self):
        data = report()
        data["matches"] = [match("High")]
        data["matches"][0]["vulnerability"]["dataSource"] = ""
        code, output = self.invoke_cli(json.dumps(data))
        self.assertEqual(code, 1)
        self.assertIn('"blocked": true', output)

    def test_annotations_remain_valid_json_within_github_message_limit(self):
        data = report()
        data["matches"] = [match("High") for _ in range(192)]
        result = reporter.inspect_report(data, IMAGE)
        payloads = reporter.annotation_payloads(result)
        self.assertLessEqual(len(payloads), 10)
        for payload in payloads:
            encoded = json.dumps(payload, ensure_ascii=True)
            self.assertLessEqual(len(encoded.encode("ascii")), 3000)
            self.assertEqual(json.loads(encoded), json.loads(json.dumps(payload)))
        published = sum(len(payload["rows"]) for payload in payloads[1:])
        self.assertEqual(payloads[0]["annotated_findings"], published)
        self.assertEqual(payloads[0]["total_findings"], 192)
        self.assertEqual(len(result["findings"]), 192)

    def test_annotation_limits_do_not_modify_full_report(self):
        data = report()
        data["matches"] = [match("Medium") for _ in range(500)]
        result = reporter.inspect_report(data, IMAGE)
        payloads = reporter.annotation_payloads(result)
        self.assertLess(payloads[0]["annotated_findings"], 500)
        self.assertEqual(payloads[0]["total_findings"], 500)
        self.assertEqual(len(result["findings"]), 500)


if __name__ == "__main__":
    unittest.main()
