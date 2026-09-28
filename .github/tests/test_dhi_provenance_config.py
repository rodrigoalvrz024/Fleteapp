from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

import yaml


class DhiProvenanceConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[2] / ".github/workflows/backend-dhi-provenance.yml"
        if not path.exists():
            raise unittest.SkipTest("Standalone evidence workflow not mounted")
        cls.raw = path.read_text(encoding="utf-8")
        cls.config = yaml.load(cls.raw, Loader=yaml.BaseLoader)
        cls.steps = cls.config["jobs"]["verify"]["steps"]
        cls.shell = cls.steps[0]["run"]

    def test_only_testing_branch_and_read_only_permissions(self):
        self.assertEqual(self.config["on"]["push"]["branches"], ["codex/mvp-supabase-rls-review"])
        self.assertEqual(self.config["permissions"], {"contents": "read"})
        self.assertEqual(self.config["jobs"]["verify"]["timeout-minutes"], "10")
        for forbidden in ("docker build", "docker run", "docker push", "railway", "SUPABASE", "continue-on-error", "actions/checkout"):
            self.assertNotIn(forbidden, self.raw)

    def test_fixed_tool_key_and_both_evaluated_bases(self):
        for value in (
            "f4e2814bd61040365153d5b964b144cb2dc6ee536a68b5bac4cadf00fc0ec34b",
            "1d02bbccf149283ae6288d96264dcad3fb23ee1911d90324a48eab28e4cb8a5f",
            "a7bb712353136de87ec96d2c2d15de48852031aeda75be9196f2ca1825a27766",
            "6258618887b43ee67c5fd867a2d7dc76f21655aef417a4e23115902c5ba05a1e",
            "--platform linux/amd64", "--verify --skip-tlog --key", "registry://dhi.io/python@sha256:",
        ):
            self.assertIn(value, self.shell)
        self.assertEqual(self.shell.count("sha256sum --check --strict"), 2)
        self.assertIn("Rekor transparency log not verified", self.shell)

    def test_credentials_do_not_reach_tools_or_artifact(self):
        for value in ("umask 077", "--password-stdin", "unset DHI_TOKEN DHI_USERNAME", "trap 'rm -rf -- \"$DOCKER_CONFIG\"' EXIT"):
            self.assertIn(value, self.shell)
        self.assertLess(self.shell.index("unset DHI_TOKEN"), self.shell.index('"$work/tool/docker-scout" attest'))
        self.assertNotIn("set -x", self.shell)
        self.assertNotIn("--password ", self.shell)
        upload = self.steps[1]
        self.assertTrue(upload["with"]["path"].endswith("/*-provenance.json"))
        self.assertEqual(upload["with"]["retention-days"], "14")
        self.assertNotIn("secrets.", str(upload))
        self.assertIn("always()", upload["if"])

    def test_both_failures_block_and_no_predicate_only_output(self):
        self.assertEqual(self.shell.count("failed=1"), 2)
        self.assertIn('exit "$failed"', self.shell)
        self.assertNotIn("--predicate ", self.shell)
        self.assertIn("--kill-after=5s 120s", self.shell)
        self.assertIn("subject/platform review", self.shell)
        embedded = self.shell.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        compile(embedded, "provenance-shape-check", "exec")

    def test_embedded_shape_check_rejects_empty_wrong_type_and_missing_materials(self):
        embedded = self.shell.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        valid = {"predicateType": "https://slsa.dev/provenance/v0.2",
                 "subject": [{"name": "synthetic-only"}],
                 "predicate": {"materials": [{"uri": "synthetic-only"}]}}
        cases = [(valid, 0), ({}, 1), ([], 1), (None, 1),
                 ({**valid, "subject": []}, 1),
                 ({**valid, "predicateType": "wrong"}, 1),
                 ({**valid, "predicate": {}}, 1),
                 ({**valid, "predicate": {"materials": []}}, 1)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.json"
            for value, expected in cases:
                with self.subTest(value=value):
                    path.write_text(json.dumps(value), encoding="utf-8")
                    result = subprocess.run([sys.executable, "-c", embedded, str(path)],
                                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, expected)
            path.write_text("not-json", encoding="utf-8")
            result = subprocess.run([sys.executable, "-c", embedded, str(path)],
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 1)

    def test_failure_diagnostic_outputs_only_fixed_categories(self):
        embedded = self.shell.split("<<'DIAGNOSTIC'\n", 1)[1].split("\nDIAGNOSTIC\n", 1)[0]
        cases = [("unauthorized token=SECRET https://user:SECRET@example.test", "1", "authentication"),
                 ("unknown flag: --SECRET\n::error::SECRET", "1", "cli_usage"),
                 ("SECRET", "124", "process_timeout"),
                 ("SECRET", "1", "unclassified")]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private.log"
            for message, status, category in cases:
                path.write_text(message, encoding="utf-8")
                result = subprocess.run([sys.executable, "-c", embedded, str(path), status],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, "")
                self.assertEqual(result.stdout.strip(),
                                 f"Verifier diagnostic: exit={status}; categories={category}; raw output withheld.")
                self.assertNotIn("SECRET", result.stdout)


if __name__ == "__main__":
    unittest.main()
