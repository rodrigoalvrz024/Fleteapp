from pathlib import Path
import copy
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
        for forbidden in ("docker build ", "docker buildx build", "docker run", "docker push", "railway", "SUPABASE", "continue-on-error", "actions/checkout"):
            self.assertNotIn(forbidden, self.raw)

    def test_fixed_tool_key_and_both_evaluated_bases(self):
        for value in (
            "f4e2814bd61040365153d5b964b144cb2dc6ee536a68b5bac4cadf00fc0ec34b",
            "1d02bbccf149283ae6288d96264dcad3fb23ee1911d90324a48eab28e4cb8a5f",
            "a7bb712353136de87ec96d2c2d15de48852031aeda75be9196f2ca1825a27766",
            "9a9fd7ffe996f9042cca4a2c0d167076a55b650cbd45a8bc535d9ab7d8ca2217",
            "--platform linux/amd64", "--verify --skip-tlog --key", "registry://dhi.io/python@sha256:",
        ):
            self.assertIn(value, self.shell)
        self.assertEqual(self.shell.count("sha256sum --check --strict"), 2)
        self.assertIn("Rekor transparency log not verified", self.shell)

    def test_credentials_do_not_reach_tools_or_artifact(self):
        self.assertIn("for registry in docker.io dhi.io registry.scout.docker.com; do", self.shell)
        for value in ("umask 077", "--password-stdin", "unset DHI_TOKEN DHI_USERNAME", "trap 'rm -rf -- \"$DOCKER_CONFIG\"' EXIT"):
            self.assertIn(value, self.shell)
        self.assertLess(self.shell.index("unset DHI_TOKEN"), self.shell.index('"$work/tool/docker-scout" attest'))
        self.assertNotIn("set -x", self.shell)
        self.assertNotIn("--password ", self.shell)
        upload = self.steps[1]
        paths = upload["with"]["path"].splitlines()
        self.assertEqual(paths, ["${{ steps.evidence.outputs.directory }}/*-provenance.json",
                                 "${{ steps.evidence.outputs.directory }}/*-index.json"])
        self.assertEqual(upload["with"]["retention-days"], "14")
        self.assertNotIn("secrets.", str(upload))
        self.assertIn("always()", upload["if"])

    def test_both_failures_block_and_no_predicate_only_output(self):
        self.assertEqual(self.shell.count("failed=1"), 3)
        self.assertIn('exit "$failed"', self.shell)
        self.assertNotIn("--predicate ", self.shell)
        self.assertIn("--kill-after=5s 120s", self.shell)
        self.assertIn("per-role subject/platform binding results", self.shell)
        self.assertIn("docker buildx imagetools inspect", self.shell)
        embedded = self.shell.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        compile(embedded, "provenance-shape-check", "exec")

    def test_embedded_shape_check_rejects_empty_wrong_type_and_missing_materials(self):
        embedded = self.shell.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        valid = {"_type": "https://in-toto.io/Statement/v1",
                 "predicateType": "https://slsa.dev/provenance/v0.2",
                 "subject": [{"name": "synthetic-only", "digest": {"sha256": "b" * 64}}],
                 "predicate": {"materials": [{"uri": "synthetic-only"}]}}
        index = {"schemaVersion": 2, "mediaType": "application/vnd.oci.image.index.v1+json",
                 "digest": "sha256:" + "a" * 64, "manifests": [{
                     "mediaType": "application/vnd.oci.image.manifest.v1+json",
                     "digest": "sha256:" + "b" * 64,
                     "platform": {"os": "linux", "architecture": "amd64"}}]}
        cases = [(valid, 0), ({}, 1), ([], 1), (None, 1),
                 ({**valid, "subject": []}, 1),
                 ({**valid, "subject": [dict(s, name="alias-" + str(i))
                                         for i in range(6) for s in valid["subject"]]}, 0),
                 ({**valid, "subject": valid["subject"] * 65}, 1),
                 ({**valid, "subject": valid["subject"] + [{"name": "wrong", "digest": {"sha256": "c" * 64}}]}, 1),
                 ({**valid, "subject": [{"digest": {"sha256": "a" * 64}}]}, 1),
                 ({**valid, "subject": [{"digest": {"sha256": "c" * 64}}]}, 1),
                 ({**valid, "_type": "wrong"}, 1),
                 ({**valid, "predicateType": "wrong"}, 1),
                 ({**valid, "predicate": {}}, 1),
                 ({**valid, "predicate": {"materials": []}}, 1)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.json"
            index_path = Path(directory) / "index.json"
            index_path.write_text(json.dumps(index), encoding="utf-8")
            args = [sys.executable, "-c", embedded, str(path), str(index_path), "a" * 64]
            for value, expected in cases:
                with self.subTest(value=value):
                    path.write_text(json.dumps(value), encoding="utf-8")
                    result = subprocess.run(args,
                                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, expected)
            path.write_text("not-json", encoding="utf-8")
            result = subprocess.run(args,
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            path.write_text(json.dumps(valid), encoding="utf-8")
            bad_indexes = [None, [], {}, {**index, "digest": "sha256:" + "c" * 64},
                           {**index, "mediaType": "wrong"}, {**index, "manifests": []},
                           {**index, "manifests": index["manifests"] * 2}]
            for field, value in (("digest", "sha256:bad"), ("mediaType", "wrong"),
                                 ("platform", {"os": "linux", "architecture": "arm64"}),
                                 ("platform", {"os": "linux", "architecture": "amd64", "variant": "v3"}),
                                 ("annotations", {"vnd.docker.reference.type": "attestation-manifest"})):
                mutated = copy.deepcopy(index)
                mutated["manifests"][0][field] = value
                bad_indexes.append(mutated)
            for bad in bad_indexes:
                with self.subTest(index=bad):
                    index_path.write_text(json.dumps(bad), encoding="utf-8")
                    result = subprocess.run(args, capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, b"")
                    self.assertEqual(result.stderr, b"")
            index_path.write_text('{"digest":"x","digest":"y"}', encoding="utf-8")
            self.assertEqual(subprocess.run(args, capture_output=True, timeout=5).returncode, 1)

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
