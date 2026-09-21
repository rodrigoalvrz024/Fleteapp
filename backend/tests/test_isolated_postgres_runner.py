import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "isolated_postgres_runner", ROOT / "scripts/test-supabase-rls-isolated.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class IsolatedPostgresRunnerTests(unittest.TestCase):
    def test_native_binaries_on_windows_and_posix(self):
        for platform, suffix in (("nt", ".exe"), ("posix", "")):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                for name in ("initdb", "pg_ctl"):
                    (base / (name + suffix)).touch()
                found = runner.postgres_executables(base, platform)
                self.assertEqual(set(found), {"initdb", "pg_ctl"})
                for name, path in found.items():
                    self.assertEqual(path, base.resolve() / (name + suffix))
                    self.assertTrue(path.is_absolute())

    def test_missing_binary_fails_before_creating_a_cluster(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "initdb").touch()
            with self.assertRaises(ValueError):
                runner.postgres_executables(base, "posix")
            self.assertEqual({item.name for item in base.iterdir()}, {"initdb"})

    def test_executable_must_be_a_file(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "initdb").touch()
            (base / "pg_ctl").mkdir()
            with self.assertRaises(ValueError):
                runner.postgres_executables(base, "posix")

    def test_unknown_platform_fails_closed(self):
        with self.assertRaises(ValueError):
            runner.postgres_executables(ROOT, "unknown")

    def test_no_inherited_application_credentials_or_postgres_settings(self):
        original = {key: "private" for key in (
            "DATABASE_URL", "SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY", "PGHOST",
            "pgport", "PGSERVICEFILE", "PGPASSFILE", "HOME", "PYTHONPATH",
            "LD_PRELOAD", "GOOGLE_APPLICATION_CREDENTIALS", "APP_ENV")}
        original.update(PATH="system-tools", SystemRoot="windows", TMP="scratch")
        before = dict(original)
        self.assertEqual(runner.isolated_environment(original), {
            "PATH": "system-tools", "SystemRoot": "windows", "TMP": "scratch"})
        self.assertEqual(original, before)

    def test_parent_environment_isolated_and_restored_even_on_failure(self):
        poison = {key: "synthetic-must-not-be-used" for key in (
            "PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE", "PGOPTIONS", "PGSSLMODE",
            "PGPASSFILE", "DATABASE_URL", "SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY")}
        poison["PATH"] = "synthetic-tools"
        for fails in (False, True):
            with self.subTest(fails=fails), patch.dict(os.environ, poison, clear=True):
                def fake_run():
                    self.assertEqual(dict(os.environ), {"PATH": "synthetic-tools"})
                    if fails:
                        raise RuntimeError("Synthetic test failure")
                    return 7
                with patch.object(runner, "run_disposable_tests", side_effect=fake_run):
                    if fails:
                        with self.assertRaisesRegex(RuntimeError, "Synthetic test failure"):
                            runner.main()
                    else:
                        self.assertEqual(runner.main(), 7)
                self.assertEqual(dict(os.environ), poison)

    def test_linux_library_path_is_derived_not_inherited(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lib = root / "lib"
            lib.mkdir()
            (lib / "libpython-test.so").touch()
            config = {"Py_ENABLE_SHARED": 1, "LIBDIR": str(lib), "LDLIBRARY": "libpython-test.so"}
            with patch.object(runner.sys, "platform", "linux"), \
                 patch.object(runner.sys, "base_prefix", str(root)), \
                 patch.object(runner.sysconfig, "get_config_var", side_effect=config.get):
                result = runner.python_worker_environment({"LD_LIBRARY_PATH": "untrusted",
                                                          "LD_PRELOAD": "untrusted", "PGHOSTADDR": "untrusted"})
                self.assertEqual(result, {"LD_LIBRARY_PATH": str(lib.resolve())})
                for name in ("../libpython-test.so", str(root / "outside.so")):
                    config["LDLIBRARY"] = name
                    with self.assertRaises(RuntimeError):
                        runner.python_worker_environment({})
                config["LDLIBRARY"] = "libpython-test.so"
                with patch.object(runner.sys, "base_prefix", str(lib)):
                    config["LIBDIR"] = str(root)
                    (root / "libpython-test.so").touch()
                    with self.assertRaises(RuntimeError):
                        runner.python_worker_environment({})

    def test_preflight_failure_is_sanitized_and_precedes_cluster_creation(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(runner, "ROOT", Path(directory)), \
             patch.object(runner.sys, "argv", ["runner", "--pg-bin", directory]), \
             patch.object(runner.os, "geteuid", return_value=1000, create=True), \
             patch.object(runner, "python_worker_environment", return_value={}), \
             patch.object(runner.subprocess, "run", return_value=SimpleNamespace(
                 returncode=1, stdout=b"never-print-private-path")) as execute:
            with self.assertRaisesRegex(RuntimeError, "preflight failed") as caught:
                runner.main()
            self.assertNotIn("never-print", str(caught.exception))
            self.assertEqual(list(Path(directory).iterdir()), [])
            self.assertIn("-I", execute.call_args.args[0])
            self.assertEqual(execute.call_args.kwargs["env"], {})
            self.assertEqual(execute.call_args.kwargs["timeout"], 30)

    def test_config_binds_only_loopback_and_disables_shared_sockets(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = base / "postgresql.conf"
            config.write_text("# initdb defaults\n", encoding="ascii")
            runner.configure_loopback(base, 15432)
            self.assertEqual(config.read_text(encoding="ascii"),
                             "# initdb defaults\n\nlisten_addresses = '127.0.0.1'\n"
                             "port = 15432\nunix_socket_directories = ''\n")

    def test_invalid_port_never_writes_config(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for port in (0, 65536, -1, True, "5432\nlisten_addresses='*'"):
                with self.subTest(port=port), self.assertRaises(ValueError):
                    runner.configure_loopback(base, port)
            self.assertFalse((base / "postgresql.conf").exists())

    def test_failed_start_cleans_up_only_after_confirmed_stop(self):
        for failure in ("initdb", "start", "stop"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                calls = []

                def fake_pg(command, **kwargs):
                    name = Path(command[0]).name
                    data = Path(command[command.index("-D") + 1])
                    operation = "initdb" if name == "initdb" else command[-1]
                    calls.append(operation)
                    if operation == "initdb":
                        data.mkdir()
                        if failure == "initdb":
                            raise subprocess.TimeoutExpired("synthetic-initdb", 60)
                        return SimpleNamespace(returncode=0)
                    if operation == "start":
                        (data / "postmaster.pid").write_text("synthetic", encoding="ascii")
                        raise subprocess.TimeoutExpired("synthetic-start", 60)
                    self.assertEqual(operation, "stop")
                    if failure == "stop":
                        return SimpleNamespace(returncode=1)
                    (data / "postmaster.pid").unlink()
                    return SimpleNamespace(returncode=0)

                with patch.object(runner, "ROOT", root), \
                     patch.object(runner, "verify_worker_python"), \
                     patch.object(runner.sys, "argv", ["runner", "--pg-bin", str(root)]), \
                     patch.object(runner.os, "geteuid", return_value=1000, create=True), \
                     patch.object(runner, "postgres_executables", return_value={
                         "initdb": root / "initdb", "pg_ctl": root / "pg_ctl"}), \
                     patch.object(runner.socket, "socket") as mocked_socket, \
                     patch.object(runner.subprocess, "run", side_effect=fake_pg):
                    mocked_socket.return_value.__enter__.return_value.getsockname.return_value = ("127.0.0.1", 15432)
                    error = RuntimeError if failure == "stop" else subprocess.TimeoutExpired
                    with self.assertRaises(error):
                        runner.main()
                remaining = list((root / ".local-tools/rls-tests").iterdir())
                if failure == "stop":
                    self.assertEqual(len(remaining), 1)
                    self.assertTrue((remaining[0] / "data/postmaster.pid").exists())
                else:
                    self.assertEqual(remaining, [])
                self.assertEqual(calls, ["initdb"] if failure == "initdb"
                                 else ["initdb", "start", "stop"])

    @unittest.skipIf(os.name == "nt", "POSIX filesystem permissions required")
    def test_disposable_tls_private_key_is_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runner.prepare_tls_fixture(base)
            self.assertEqual((base / "server.key").stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
