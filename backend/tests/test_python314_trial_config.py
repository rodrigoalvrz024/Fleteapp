from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class Python314TrialConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / ".github/workflows/backend-python314-trial.yml"
        if not path.exists():
            raise unittest.SkipTest("Repository-only trial configuration")
        cls.raw = path.read_text(encoding="utf-8")
        cls.config = yaml.load(cls.raw, Loader=yaml.BaseLoader)
        cls.job = cls.config["jobs"]["compatibility"]
        cls.steps = cls.job["steps"]
        cls.dockerfile = (ROOT / "backend/Dockerfile.python314").read_text(encoding="utf-8")

    def step(self, prefix):
        return next(step for step in self.steps if step["name"].startswith(prefix))

    def test_isolated_bounded_and_without_credentials_or_deployment(self):
        self.assertEqual(self.config["on"]["push"]["branches"], ["codex/mvp-supabase-rls-review"])
        self.assertEqual(set(self.config["on"]["push"]["paths"]), {
            "backend/**", "scripts/**", ".github/workflows/backend-python314-trial.yml"})
        self.assertEqual(self.config["permissions"], {"contents": "read"})
        self.assertEqual(self.job["timeout-minutes"], "15")
        self.assertEqual(self.steps[0]["with"]["persist-credentials"], "false")
        for forbidden in ("${{ secrets.", "railway up", "docker push", "continue-on-error", "id-token:"):
            self.assertNotIn(forbidden, self.raw)

    def test_fixed_official_version_resolved_once_then_built_by_digest(self):
        command = self.step("Resolve official")["run"]
        self.assertIn("base='python:3.14.7-slim-trixie'", command)
        self.assertIn('^python@sha256:[0-9a-f]{64}$', command)
        self.assertIn('--build-arg "PYTHON_IMAGE=$digest"', command)
        self.assertIn("--platform linux/amd64", command)
        self.assertIn("backend/Dockerfile.python314", command)
        self.assertIn("(3,14,7)", self.step("Verify interpreter")["run"])
        self.assertIn("-m pip check", self.step("Verify interpreter")["run"])

    def test_image_keeps_production_guard_and_installation_restrictions(self):
        for required in ("--only-binary=:all:", "COPY requirements.txt .",
                         "apt-get upgrade", "--no-auto-remove mount", "--chmod=0444",
                         "chmod -R go-w /app /usr/local", "-perm /6000", "USER app"):
            self.assertIn(required, self.dockerfile)
        self.assertTrue(self.dockerfile.rstrip().endswith('CMD ["python", "-m", "app.server"]'))
        for forbidden in ("COPY . .", "--trusted-host", "--break-system-packages"):
            self.assertNotIn(forbidden, self.dockerfile)

    def test_regressions_offline_and_do_not_mask_code_permissions(self):
        command = self.step("Run all")["run"]
        for required in ("--network none", "--read-only", "--memory 768m", "--cpus 2",
                         "secrets.token_urlsafe(48)", "127.0.0.1:1/muvv_test",
                         "-B -m unittest discover -s tests", "timeout --signal=TERM"):
            self.assertIn(required, command)
        for destination in ("/workspace/backend/Dockerfile.python314,readonly",
                            "/workspace/.github/workflows/backend-python314-trial.yml,readonly"):
            self.assertIn(destination, command)
        permissions = self.step("Verify permissions")["run"]
        self.assertIn("verify-runtime-image.py", permissions)
        self.assertNotIn("--read-only", permissions)

    def test_real_startup_and_root_rejection_are_mandatory(self):
        command = self.step("Verify actual startup")["run"]
        for required in ("/proc/1/status", "NoNewPrivs", "CapInh", "CapPrm", "CapEff", "CapAmb",
                         "Uid", "Gid", "Groups", "invalid-test-token", "/admin/users",
                         "error.code == 401", "Application shutdown complete.", "-m alembic heads"):
            self.assertIn(required, command)
        self.assertNotIn("--security-opt", command)
        self.assertNotIn("--cap-drop", command)
        root = self.step("Verify root")["run"]
        self.assertIn('--user 0:0', root)
        self.assertIn('test "$code" -eq 1', root)

    def test_scan_is_exact_fail_closed_and_not_a_python311_disposition(self):
        step = self.step("Scan complete")
        self.assertEqual(step["if"], "${{ always() && steps.build.outcome == 'success' && !cancelled() }}")
        command = step["run"]
        for required in ("set -euo pipefail", "sha256sum --check --strict",
                         "scripts/grype-candidate.yaml", "scripts/report-image-audit.py",
                         '"docker:${image_id}"', 'r["distro"]["name"]=="debian"'):
            self.assertIn(required, command)
        for forbidden in ("|| true", "--only-fixed", "--exclude", "--ignore"):
            self.assertNotIn(forbidden, command)
        for forbidden in ("evaluate-image-policy.py", "review-python-findings.py", "verify-python-backports.py"):
            self.assertNotIn(forbidden, self.raw)


if __name__ == "__main__":
    unittest.main()
