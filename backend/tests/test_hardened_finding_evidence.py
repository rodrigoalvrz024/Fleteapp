import copy
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("hardened_evidence", ROOT / "scripts/inspect-hardened-findings.py")
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)
IMAGE = "sha256:" + "a" * 64


def report():
    return {"descriptor": {"name": "grype", "version": "0.118.0", "db": {"status": "valid"},
                           "timestamp": "2026-09-14T00:00:00Z"},
            "source": {"type": "image", "target": {"imageID": IMAGE}}, "matches": []}


def match(artifact_id, location):
    return {"vulnerability": {"id": "CVE-2026-5435", "severity": "High",
            "dataSource": "https://example.invalid/advisory",
            "fix": {"state": "not-fixed", "versions": []}},
            "artifact": {"id": artifact_id, "name": "libc6", "version": "2.41", "type": "deb",
                         "purl": "pkg:deb/debian/libc6@2.41", "locations": [{"path": location}]}}


class HardenedFindingEvidenceTests(unittest.TestCase):
    def test_repeated_rows_preserve_identities_and_gate(self):
        data = report()
        data["matches"] = [match("a", "/var/lib/dpkg/status"), match("b", "/usr/share/dpkg/status")]
        original = copy.deepcopy(data)
        result = evidence.inspect_findings(data, IMAGE)
        self.assertEqual(data, original)
        self.assertEqual(result["counts_unchanged"]["High"], 2)
        self.assertEqual(result["unique_high_critical_cves"], 1)
        self.assertEqual(result["cve_package_version_groups"], 1)
        self.assertEqual([row["artifact_id"] for row in result["matches"]], ["a", "b"])
        self.assertTrue(result["gate_blocked"])
        self.assertFalse(result["findings_waived"])

    def test_same_artifact_repeated_is_not_deleted(self):
        data = report()
        data["matches"] = [match("a", "/status")] * 2
        self.assertEqual(len(evidence.inspect_findings(data, IMAGE)["matches"]), 2)

    def test_wrong_image_or_missing_matches_rejected(self):
        with self.assertRaises(ValueError):
            evidence.inspect_findings(report(), "sha256:" + "b" * 64)
        data = report()
        del data["matches"]
        with self.assertRaises(KeyError):
            evidence.inspect_findings(data, IMAGE)

    def test_ignored_findings_rejected(self):
        data = report()
        data["ignoredMatches"] = [match("a", "/status")]
        with self.assertRaises(ValueError):
            evidence.inspect_findings(data, IMAGE)

    def test_missing_identity_or_invalid_locations_rejected(self):
        for field, value in (("id", ""), ("locations", "invalid")):
            data = report()
            item = match("a", "/status")
            item["artifact"][field] = value
            data["matches"] = [item]
            with self.assertRaises(ValueError):
                evidence.inspect_findings(data, IMAGE)

    def test_medium_retained_in_totals(self):
        data = report()
        item = match("a", "/status")
        item["vulnerability"]["severity"] = "Medium"
        data["matches"] = [item]
        result = evidence.inspect_findings(data, IMAGE)
        self.assertEqual(result["counts_unchanged"]["Medium"], 1)
        self.assertEqual(result["matches"], [])


if __name__ == "__main__":
    unittest.main()
