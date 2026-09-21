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

    def test_native_inventory_uses_candidate_without_running_or_extracting_it(self):
        step = self.step("Inspect complete Python 3.14")
        self.assertNotIn("continue-on-error", step)
        command = step["run"]
        for required in ("set -euo pipefail", "umask 077", "--require-hashes",
                         "--only-binary=:all: --no-deps", "scripts/native-audit-requirements.txt",
                         "docker image inspect muvv-backend:python314-trial",
                         '^sha256:[0-9a-f]{64}$', 'docker create --network none "$image_id"',
                         'docker export --output "$audit_dir/rootfs.tar" "$container"',
                         'scripts/report-native-symbols.py "$audit_dir/rootfs.tar" --image-id "$image_id"',
                         "timeout --signal=TERM --kill-after=5s 60s",
                         "timeout --signal=TERM --kill-after=5s 180s",
                         'trap \'docker rm "$container"',
                         "not a CVE exemption or deployment approval"):
            self.assertIn(required, command)
        for forbidden in ("docker start", "docker run", "docker exec", "tar --extract",
                          "extractall", "--privileged", "docker.sock", "sudo "):
            self.assertNotIn(forbidden, command)

    def test_only_metadata_is_preserved_before_unmodified_scan_gate(self):
        native = self.step("Inspect complete Python 3.14")
        upload = self.step("Preserve Python 3.14")
        scan = self.step("Scan complete")
        self.assertEqual(upload["uses"],
                         "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a")
        self.assertEqual(upload["with"], {
            "name": "python314-native-symbol-evidence",
            "path": "${{ runner.temp }}/python314-native-symbol-evidence/report.json",
            "if-no-files-found": "error", "retention-days": "14"})
        self.assertLess(self.steps.index(native), self.steps.index(upload))
        self.assertLess(self.steps.index(upload), self.steps.index(scan))
        self.assertEqual(scan["if"], "${{ always() && steps.build.outcome == 'success' && !cancelled() }}")


class PostgresIntegrationConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ROOT / ".github/workflows/backend-python314-trial.yml"
        if not path.exists():
            raise unittest.SkipTest("Repository-only integration configuration")
        cls.raw = path.read_text(encoding="utf-8")
        cls.config = yaml.load(cls.raw, Loader=yaml.BaseLoader)
        cls.job = cls.config["jobs"]["postgres-integration"]
        cls.steps = cls.job["steps"]

    def step(self, prefix):
        return next(step for step in self.steps if step["name"].startswith(prefix))

    def test_runs_independently_of_blocked_image_with_readonly_permissions(self):
        self.assertNotIn("needs", self.job)
        self.assertEqual(self.job["runs-on"], "ubuntu-24.04")
        self.assertEqual(self.job["timeout-minutes"], "15")
        self.assertEqual(self.config["permissions"], {"contents": "read"})
        self.assertEqual(self.steps[0]["with"]["persist-credentials"], "false")
        for forbidden in ("${{ secrets.", "railway", "docker push", "continue-on-error", "sudo "):
            self.assertNotIn(forbidden, yaml.dump(self.job))

    def test_python_action_is_pinned_and_dependencies_are_isolated(self):
        step = self.step("Set up pinned")
        self.assertEqual(step["uses"], "actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1")
        self.assertEqual(step["with"]["python-version"], "3.14.7")
        command = self.step("Prepare isolated")["run"]
        for required in ('test "$(id -u)" -ne 0', "python -m venv .local-tools/linux-pg-venv",
                         "--only-binary=:all:", "-r backend/requirements.txt", "-m pip check",
                         "pg_bin=/usr/lib/postgresql/16/bin", "Host-runner tests, not approval"):
            self.assertIn(required, command)

    def test_both_migration_paths_use_disposable_verified_tls(self):
        command = self.step("Test HTTP permissions")["run"]
        self.assertIn("--http --tls --migrations", command)
        legacy = self.step("Test legacy-schema")["run"]
        self.assertIn("--tls --migrations --migration-start models", legacy)
        for command in (command, legacy):
            self.assertIn("scripts/test-supabase-rls-isolated.py", command)
            self.assertIn("--pg-bin /usr/lib/postgresql/16/bin", command)
            self.assertIn("timeout --signal=TERM --kill-after=10s", command)
            self.assertNotIn("DATABASE_URL", command)
            self.assertNotIn("|| true", command)

    def test_cleanup_is_checked_even_after_failures(self):
        step = self.step("Check disposable")
        self.assertEqual(step["if"], "${{ always() }}")
        self.assertIn('test -z "$(find .local-tools/rls-tests', step["run"])
        self.assertNotIn("rm ", step["run"])


if __name__ == "__main__":
    unittest.main()
