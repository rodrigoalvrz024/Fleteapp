from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class WolfiTrialConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / ".github/workflows/backend-wolfi-trial.yml"
        if not path.exists():
            raise unittest.SkipTest("Repository-only comparison configuration")
        cls.raw = path.read_text(encoding="utf-8")
        cls.config = yaml.load(cls.raw, Loader=yaml.BaseLoader)
        cls.steps = cls.config["jobs"]["compare"]["steps"]
        cls.dockerfile = (ROOT / "backend/Dockerfile.wolfi").read_text(encoding="utf-8")

    def step(self, prefix):
        return next(s for s in self.steps if s["name"].startswith(prefix))

    def test_isolated_branch_no_credentials_or_deployment(self):
        self.assertEqual(self.config["on"]["push"]["branches"], ["codex/mvp-supabase-rls-review"])
        self.assertEqual(self.config["permissions"], {"contents": "read"})
        self.assertEqual(self.steps[0]["with"]["persist-credentials"], "false")
        for value in ("${{ secrets.", "railway up", "docker push", "id-token:", "continue-on-error", "evaluate-image-policy.py"):
            self.assertNotIn(value, self.raw)

    def test_signature_check_exact_identity_before_execution_or_build(self):
        verify = self.step("Verify both")
        command = verify["run"]
        self.assertIn("cosign\" verify", command)
        self.assertIn("--certificate-oidc-issuer=https://token.actions.githubusercontent.com", command)
        self.assertIn("--certificate-identity=https://github.com/chainguard-images/images/.github/workflows/release.yaml@refs/heads/main", command)
        for forbidden in ("insecure", "ignore-tlog", "identity-regexp", "|| true"):
            self.assertNotIn(forbidden, command)
        self.assertLess(self.steps.index(verify), self.steps.index(self.step("Scan the unmodified")))
        self.assertLess(self.steps.index(verify), self.steps.index(self.step("Build isolated")))
        self.assertIn('"$digest" >', command)
        self.assertIn('^cgr\\.dev/chainguard/python@sha256:[0-9a-f]{64}$', command)

    def test_downloads_pinned_and_checked_before_execution(self):
        command = self.step("Obtain pinned")["run"]
        self.assertEqual(command.count("sha256sum --check --strict"), 2)
        self.assertIn("v3.1.3/cosign-linux-amd64", command)
        self.assertIn("v0.118.0/grype_0.118.0_linux_amd64.tar.gz", command)
        self.assertIn("--proto '=https' --proto-redir '=https'", command)
        self.assertLess(command.index("4629c757"), command.index("chmod 0755"))

    def test_same_verified_digests_used_for_multistage_build(self):
        command = self.step("Build isolated")["run"]
        self.assertIn('"PYTHON_BUILD_IMAGE=$WOLFI_BUILD_IMAGE"', command)
        self.assertIn('"PYTHON_RUNTIME_IMAGE=$WOLFI_RUNTIME_IMAGE"', command)
        self.assertIn("COPY requirements.txt .", self.dockerfile)
        self.assertIn("--only-binary=:all:", self.dockerfile)
        self.assertNotIn("cloudinary", self.dockerfile.lower())
        self.assertNotIn("pip wheel", self.dockerfile)
        self.assertTrue(self.dockerfile.rstrip().endswith('CMD ["/opt/muvv-venv/bin/python", "-m", "app.server"]'))
        self.assertIn("USER 65532:65532", self.dockerfile)
        self.assertNotIn("apk add", self.dockerfile)
        self.assertNotIn("COPY . .", self.dockerfile)

    def test_base_and_application_scans_fail_closed_without_dispositions(self):
        for name in ("Scan the unmodified", "Scan the complete"):
            command = self.step(name)["run"]
            self.assertIn("set -euo pipefail", command)
            self.assertIn("scripts/grype-candidate.yaml", command)
            self.assertIn("scripts/report-image-audit.py", command)
            self.assertIn('r["distro"]["name"]=="wolfi"', command)
            self.assertNotIn("|| true", command)
            self.assertNotIn("--only-fixed", command)

    def test_runtime_tests_remain_offline_and_use_synthetic_credentials(self):
        command = self.step("Run application security")["run"]
        self.assertIn("--network none", command)
        self.assertIn("--memory 512m", command)
        self.assertIn("127.0.0.1:1/muvv_test", command)
        self.assertIn("secrets.token_urlsafe(48)", command)
        self.assertIn("-B -m unittest discover -s tests", command)
        lifecycle = self.step("Check actual HTTP")["run"]
        self.assertIn("Application shutdown complete.", lifecycle)
        self.assertIn("/admin/users", lifecycle)
        self.assertIn("error.code==401", lifecycle)


if __name__ == "__main__":
    unittest.main()
