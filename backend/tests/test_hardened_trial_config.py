from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class HardenedTrialConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow_path = ROOT / ".github/workflows/backend-hardened-trial.yml"
        cls.dockerfile_path = ROOT / "backend/Dockerfile.hardened"
        if not cls.workflow_path.exists() or not cls.dockerfile_path.exists():
            raise unittest.SkipTest("Repository-only configuration files are not mounted in runtime tests")
        cls.raw = cls.workflow_path.read_text(encoding="utf-8")
        cls.config = yaml.load(cls.raw, Loader=yaml.BaseLoader)
        cls.dockerfile = cls.dockerfile_path.read_text(encoding="utf-8")

    def test_trial_has_no_release_branch_or_write_permissions(self):
        self.assertEqual(self.config["on"]["push"]["branches"], ["codex/mvp-supabase-rls-review"])
        self.assertEqual(self.config["permissions"], {"contents": "read"})
        for forbidden in ("docker push", "railway up", "RAILWAY_TOKEN", "SUPABASE_SERVICE_ROLE_KEY"):
            self.assertNotIn(forbidden, self.raw)

    def test_missing_credentials_block_before_checkout_or_download(self):
        steps = self.config["jobs"]["evaluate"]["steps"]
        preflight = steps[0]["run"]
        self.assertIn('[[ -z "$DHI_USERNAME" || -z "$DHI_TOKEN" ]]', preflight)
        self.assertIn("exit 1", preflight)
        self.assertIn("actions/checkout@", steps[1]["uses"])
        self.assertEqual(steps[1]["with"]["persist-credentials"], "false")

    def test_token_is_stdin_only_and_removed_after_build(self):
        step = self.config["jobs"]["evaluate"]["steps"][2]["run"]
        self.assertIn("--password-stdin", step)
        self.assertIn("umask 077", step)
        self.assertIn("trap 'rm -rf -- \"$DOCKER_CONFIG\"' EXIT", step)
        self.assertIn("docker build --file backend/Dockerfile.hardened", step)
        self.assertNotIn("GITHUB_ENV", step)
        self.assertNotIn("set -x", step)
        self.assertNotIn("--password ", step)
        self.assertNotIn("DHI_TOKEN", self.dockerfile)

    def test_build_uses_resolved_digests_and_separate_runtime(self):
        step = self.config["jobs"]["evaluate"]["steps"][2]["run"]
        self.assertIn("RepoDigests", step)
        self.assertIn("^dhi\\.io/python@sha256:[0-9a-f]{64}$", step)
        self.assertIn("FROM ${PYTHON_BUILD_IMAGE} AS build", self.dockerfile)
        self.assertIn("FROM ${PYTHON_RUNTIME_IMAGE} AS trial", self.dockerfile)
        self.assertIn("USER 65532:65532", self.dockerfile)
        self.assertIn('ENTRYPOINT []', self.dockerfile)
        self.assertIn('"app.server"', self.dockerfile)
        self.assertIn("--chown=0:0", self.dockerfile)
        self.assertIn("--only-binary=:all:", self.dockerfile)

    def test_trial_keeps_full_scanner_and_synthetic_offline_tests(self):
        self.assertIn("scripts/grype-candidate.yaml", self.raw)
        self.assertIn("scripts/report-image-audit.py", self.raw)
        self.assertIn("-m unittest discover -s tests", self.raw)
        self.assertIn("--network none", self.raw)
        self.assertIn("postgresql://postgres:postgres@127.0.0.1:1/muvv_test", self.raw)
        for forbidden in ("--only-fixed", "--vex", "continue-on-error"):
            self.assertNotIn(forbidden, self.raw)

    def test_source_only_cloudinary_is_hash_pinned_and_builder_only(self):
        build, runtime = self.dockerfile.split("FROM ${PYTHON_RUNTIME_IMAGE} AS trial", 1)
        self.assertIn("cloudinary==1.40.0", (ROOT / "backend/requirements.txt").read_text())
        self.assertIn("cloudinary-1.40.0.tar.gz#sha256=fe1a5309734814b481de637ab3041e8699995387df965ec0f2d8f767db7067a2", build)
        self.assertIn("pip wheel --no-cache-dir --no-deps --no-build-isolation --wheel-dir /wheels", build)
        self.assertIn("--only-binary=:all: --find-links=/wheels -r requirements.txt", build)
        self.assertNotIn("/wheels", runtime)
        self.assertNotIn("pip install", runtime)
        self.assertNotIn("--no-binary=:all:", self.dockerfile)


if __name__ == "__main__":
    unittest.main()
