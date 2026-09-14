import contextlib
import ctypes
import io
import os
import unittest
from unittest.mock import Mock, patch

from app import server


def process_status(**changes):
    result = {field: "0000000000000000" for field in server._CAPABILITY_FIELDS}
    result.update(Threads="1", NoNewPrivs="1")
    result.update(changes)
    return result


class RuntimeSecurityTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(server.sys, "platform", "linux"))
        self.uid = self.stack.enter_context(
            patch.object(server.os, "getresuid", return_value=(100, 100, 100), create=True)
        )
        self.gid = self.stack.enter_context(
            patch.object(server.os, "getresgid", return_value=(101, 101, 101), create=True)
        )
        self.groups = self.stack.enter_context(
            patch.object(server.os, "getgroups", return_value=[101], create=True)
        )
        self.status = self.stack.enter_context(
            patch.object(server, "_process_status", return_value=process_status())
        )
        self.enable = self.stack.enter_context(patch.object(server, "_enable_no_new_privileges"))

    def test_enables_protection_when_host_does_not_set_it(self):
        self.status.side_effect = [process_status(NoNewPrivs="0"), process_status()]
        server.enforce_runtime_security()
        self.enable.assert_called_once_with()
        self.assertEqual(self.status.call_count, 2)

    def test_keeps_protection_when_host_already_sets_it(self):
        server.enforce_runtime_security()
        self.enable.assert_called_once_with()

    def test_rejects_root_real_effective_saved_uid_and_gid(self):
        for identity in (self.uid, self.gid):
            for position in range(3):
                with self.subTest(identity=identity, position=position):
                    value = [100, 100, 100]
                    value[position] = 0
                    identity.return_value = tuple(value)
                    with self.assertRaisesRegex(server.StartupSecurityError, "root_identity"):
                        server.enforce_runtime_security()
                    identity.return_value = (100, 100, 100)
        self.enable.assert_not_called()

    def test_rejects_root_supplementary_group(self):
        self.groups.return_value = [101, 0]
        with self.assertRaisesRegex(server.StartupSecurityError, "root_identity"):
            server.enforce_runtime_security()
        self.enable.assert_not_called()

    def test_rejects_each_capability_set(self):
        for field in server._CAPABILITY_FIELDS:
            with self.subTest(field=field):
                self.status.return_value = process_status(**{field: "0000000000000001"})
                with self.assertRaisesRegex(server.StartupSecurityError, "process_capabilities"):
                    server.enforce_runtime_security()
        self.enable.assert_not_called()

    def test_rejects_existing_threads_before_setting_per_thread_flag(self):
        self.status.return_value = process_status(Threads="2")
        with self.assertRaisesRegex(server.StartupSecurityError, "startup_already_multithreaded"):
            server.enforce_runtime_security()
        self.enable.assert_not_called()

    def test_rejects_host_failure_to_apply_flag(self):
        self.status.return_value = process_status(NoNewPrivs="0")
        with self.assertRaisesRegex(server.StartupSecurityError, "no_new_privileges_not_enabled"):
            server.enforce_runtime_security()

    def test_rejects_other_platforms_without_using_linux_calls(self):
        with patch.object(server.sys, "platform", "win32"):
            with self.assertRaisesRegex(server.StartupSecurityError, "linux_required"):
                server.enforce_runtime_security()
        self.uid.assert_not_called()


class PrctlTests(unittest.TestCase):
    def test_sets_and_reads_flag_with_explicit_native_argument_types(self):
        function = Mock(side_effect=[0, 1])
        with patch.object(server.ctypes, "CDLL", return_value=Mock(prctl=function)) as load:
            server._enable_no_new_privileges()
        load.assert_called_once_with(None, use_errno=True)
        self.assertEqual(function.argtypes, [ctypes.c_int, *([ctypes.c_ulong] * 4)])
        self.assertEqual(function.restype, ctypes.c_int)
        self.assertEqual(function.call_args_list[0].args, (38, 1, 0, 0, 0))
        self.assertEqual(function.call_args_list[1].args, (39, 0, 0, 0, 0))

    def test_rejects_failed_set_or_readback(self):
        for results in ([-1], [0, 0], [0, -1]):
            with self.subTest(results=results):
                with patch.object(server.ctypes, "CDLL", return_value=Mock(prctl=Mock(side_effect=results))):
                    with self.assertRaises(server.StartupSecurityError):
                        server._enable_no_new_privileges()


class ServerStartupTests(unittest.TestCase):
    def test_port_default_empty_and_custom_values(self):
        for value, expected in ((None, 8080), ("", 8080), ("18080", 18080), ("65535", 65535)):
            with self.subTest(value=value):
                with patch.dict(os.environ, {} if value is None else {"PORT": value}, clear=True):
                    self.assertEqual(server.configured_port(), expected)

    def test_rejects_invalid_ports(self):
        for value in ("0", "65536", "-1", " 8080 ", "1;echo", "secret-test-value", "\u0661"):
            with self.subTest(value=value), patch.dict(os.environ, {"PORT": value}):
                with self.assertRaises(server.StartupSecurityError):
                    server.configured_port()

    def test_hardens_before_importing_uvicorn_and_preserves_server_options(self):
        events = []
        uvicorn = Mock()
        original_import = __import__

        def import_module(name, *args, **kwargs):
            if name == "uvicorn":
                events.append("uvicorn")
                return uvicorn
            return original_import(name, *args, **kwargs)

        with patch.dict(os.environ, {"PORT": "18080"}), contextlib.redirect_stdout(io.StringIO()):
            with patch.object(server, "enforce_runtime_security", side_effect=lambda: events.append("guard")):
                with patch("builtins.__import__", side_effect=import_module):
                    self.assertEqual(server.main(), 0)
        self.assertEqual(events, ["guard", "uvicorn"])
        uvicorn.run.assert_called_once_with("app.main:app", host="0.0.0.0", port=18080)

    def test_failures_do_not_start_server_or_log_sensitive_values(self):
        failures = (server.StartupSecurityError, OSError, AttributeError, KeyError, ValueError)
        for failure in failures:
            with self.subTest(failure=failure), patch.dict(os.environ, {"PORT": "8080"}):
                errors = io.StringIO()
                with patch.object(server, "enforce_runtime_security", side_effect=failure("secret-test-value")):
                    with patch("builtins.__import__") as imported, contextlib.redirect_stderr(errors):
                        self.assertEqual(server.main(), 1)
                imported.assert_not_called()
                self.assertEqual(errors.getvalue(), "[startup] Security checks failed; server not started.\n")


if __name__ == "__main__":
    unittest.main()
