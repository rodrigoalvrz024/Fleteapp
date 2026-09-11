import copy
import importlib.util
from pathlib import Path
import unittest


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


if __name__ == "__main__":
    unittest.main()
