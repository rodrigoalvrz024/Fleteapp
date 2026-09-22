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

    def test_removed_storage_provider_is_not_installed_or_built(self):
        build, runtime = self.dockerfile.split("FROM ${PYTHON_RUNTIME_IMAGE} AS trial", 1)
        self.assertNotIn("cloudinary", (ROOT / "backend/requirements.txt").read_text().lower())
        self.assertNotIn("cloudinary", self.dockerfile.lower())
        self.assertNotIn("pip wheel", build)
        self.assertIn("--only-binary=:all: -r requirements.txt", build)
        self.assertNotIn("/wheels", runtime)
        self.assertNotIn("pip install", runtime)
        self.assertNotIn("--no-binary=:all:", self.dockerfile)

    def test_trial_removes_infocmp_without_erasing_package_catalog(self):
        runtime = self.dockerfile.split("FROM ${PYTHON_RUNTIME_IMAGE} AS trial", 1)[1]
        self.assertIn("'/usr/bin/infocmp', '/bin/infocmp'", runtime)
        self.assertIn("unlink(missing_ok=True)", runtime)
        self.assertIn("os.chown('/app', 0, 0)", runtime)
        self.assertIn("os.chmod('/app', 0o755)", runtime)
        self.assertLess(runtime.index("unlink"), runtime.index("USER 65532:65532"))
        self.assertNotIn("/var/lib/dpkg", runtime)

    def test_dhi_lifecycle_uses_real_cmd_and_no_production_network(self):
        steps = {step["name"]: step for step in self.config["jobs"]["evaluate"]["steps"]}
        startup = steps["Verify real DHI startup and shutdown without hosting privilege flags"]["run"]
        for required in ("--network none", "RUN_STARTUP_MIGRATIONS=false", "/users/me", "/drivers/me", "/admin/users",
                         "error.code == 401", "NoNewPrivs", "CapAmb", "docker stop --time 10", "Application shutdown complete."):
            self.assertIn(required, startup)
        self.assertNotIn("--entrypoint", startup)
        self.assertNotIn("--security-opt", startup)
        self.assertNotIn("--cap-drop", startup)
        self.assertIn("trap 'docker rm --force", startup)
        embedded = startup.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        compile(embedded, "dhi-startup-probe", "exec")
        reject = steps["Verify DHI startup refuses a root hosting configuration"]["run"]
        self.assertIn("--user 0:0", reject)
        self.assertIn('test "$code" -eq 1', reject)

    def test_permissions_are_not_masked_and_native_export_not_published(self):
        steps = {step["name"]: step for step in self.config["jobs"]["evaluate"]["steps"]}
        permissions = steps["Verify DHI filesystem permissions without read-only masking"]["run"]
        self.assertIn("--profile dhi", permissions)
        self.assertNotIn("--read-only", permissions)
        exported = steps["Preserve DHI native metadata only"]["with"]
        self.assertTrue(exported["path"].endswith("/report.json"))
        self.assertEqual(exported["retention-days"], "14")

    def test_readonly_evidence_continues_after_a_failed_gate_not_after_failed_build(self):
        steps = self.config['jobs']['evaluate']['steps']
        build = next(step for step in steps if step['name'].startswith('Pull and build'))
        self.assertEqual(build['id'], 'build')
        for prefix in ('Inspect complete DHI', 'Scan full trial'):
            step = next(step for step in steps if step['name'].startswith(prefix))
            self.assertEqual(step['if'], "${{ always() && steps.build.outcome == 'success' && !cancelled() }}")
            self.assertNotIn('continue-on-error', step)
        for prefix in ('Verify DHI filesystem', 'Verify real DHI startup', 'Verify DHI startup refuses'):
            step = next(step for step in steps if step['name'].startswith(prefix))
            self.assertNotIn('if', step)
            self.assertNotIn('continue-on-error', step)

    def test_scan_failure_is_not_hidden_by_the_diagnostic_probe(self):
        steps = self.config['jobs']['evaluate']['steps']
        scan = next(step for step in steps if step.get('id') == 'scan')
        diagnosis = next(step for step in steps if step['name'].startswith('Diagnose DHI'))
        self.assertLess(steps.index(scan), steps.index(diagnosis))
        self.assertIn('scripts/report-image-audit.py', scan['run'])
        self.assertNotIn('inspect-hardened-findings.py', scan['run'])
        self.assertNotIn('docker run', scan['run'])
        self.assertNotIn('||', scan['run'])
        self.assertNotIn('continue-on-error', scan)
        self.assertIn("steps.scan.outputs.report != ''", diagnosis['if'])
        self.assertIn("steps.build.outcome == 'success'", diagnosis['if'])
        self.assertIn('!cancelled()', diagnosis['if'])
        self.assertEqual(diagnosis['env'], {
            'AUDIT_REPORT': '${{ steps.scan.outputs.report }}',
            'AUDIT_IMAGE': '${{ steps.scan.outputs.image_id }}'})
        for required in ('--user 65532:65532', '--network none', '--read-only', '--cap-drop ALL',
                         '--security-opt no-new-privileges', '--entrypoint python "$AUDIT_IMAGE"'):
            self.assertIn(required, diagnosis['run'])
        self.assertNotIn('${{ steps.', diagnosis['run'])
        self.assertNotIn('secrets.', str(diagnosis))

    def test_native_metadata_is_bounded_and_only_uploaded_after_success(self):
        steps = self.config['jobs']['evaluate']['steps']
        native = next(step for step in steps if step.get('id') == 'native')
        upload = next(step for step in steps if step['name'] == 'Preserve DHI native metadata only')
        self.assertEqual(upload['if'], "${{ always() && steps.native.outcome == 'success' && !cancelled() }}")
        for required in ('umask 077', '^sha256:[0-9a-f]{64}$', 'docker create --network none',
                         'timeout --signal=TERM --kill-after=5s 60s docker export'):
            self.assertIn(required, native['run'])
        for forbidden in ('docker run', 'docker start', 'extractall', 'tar --extract'):
            self.assertNotIn(forbidden, native['run'])
        self.assertNotIn('rootfs.tar', str(upload))


if __name__ == "__main__":
    unittest.main()
