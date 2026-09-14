import copy
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch


path = Path(__file__).resolve().parents[2] / "scripts" / "trace-xml-calls.py"
spec = importlib.util.spec_from_file_location("xml_call_trace", path)
tracer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tracer)


def evidence():
    modules = {name: {"path": f"/usr/local/lib/python3.11/lib-dynload/{name}.cpython-311-x86_64-linux-gnu.so",
                      "sha256": "a" * 64, "size": 100} for name in tracer.PARSERS}
    handoff = {"parser": "pyexpat", "modules": modules, "salt16": 8192, "legacy": 16384}
    parsed = {"parser": "pyexpat", "modules": copy.deepcopy(modules), "parse_successes": 3}
    trace = {"hardware_breakpoints": True, "exit_code": 0, "salt16_hits": 3, "legacy_hits": 0}
    return handoff, parsed, trace


class XmlCallTraceTests(unittest.TestCase):
    def test_valid_trace_preserves_binary_identity_without_leaking_control_data(self):
        handoff, parsed, trace = evidence()
        tracer.validate_handoff(handoff, "pyexpat")
        trace["private_detail"] = "must-not-be-published"
        result = tracer.validate_result(handoff, parsed, trace)
        self.assertEqual(result["modules"], handoff["modules"])
        self.assertNotIn("salt16", result)
        self.assertNotIn("private_detail", result)
        self.assertFalse(result["salt_values_read"])

    def test_handoff_rejects_wrong_parser_addresses_and_module_paths(self):
        for key, value in (("parser", "unexpected"), ("salt16", True), ("salt16", -1),
                           ("salt16", 2**63), ("salt16", 16384), ("modules", {})):
            handoff, _, _ = evidence()
            handoff[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                tracer.validate_handoff(handoff, "pyexpat")
        for key, value in (("path", "/etc/passwd"), ("sha256", "short")):
            handoff, _, _ = evidence()
            handoff["modules"]["pyexpat"][key] = value
            with self.assertRaises(ValueError):
                tracer.validate_handoff(handoff, "pyexpat")

    def test_missing_calls_legacy_calls_software_breakpoints_or_failed_exit_cannot_pass(self):
        for key, value in (("salt16_hits", 0), ("salt16_hits", 2), ("salt16_hits", 4),
                           ("legacy_hits", 1), ("hardware_breakpoints", False), ("exit_code", None),
                           ("exit_code", 1)):
            handoff, parsed, trace = evidence()
            trace[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                tracer.validate_result(handoff, parsed, trace)

    def test_parser_failure_or_changed_binary_cannot_pass(self):
        for key, value in (("parser", "_elementtree"), ("parse_successes", 2), ("modules", {})):
            handoff, parsed, trace = evidence()
            parsed[key] = value
            with self.assertRaises(ValueError):
                tracer.validate_result(handoff, parsed, trace)

    def test_cli_failure_redacts_internal_data(self):
        with patch.object(tracer, "child", side_effect=RuntimeError("private-address")), \
                patch.object(tracer.sys, "stderr", new_callable=io.StringIO) as output:
            self.assertEqual(tracer.main(["--child", "pyexpat"]), 2)
        self.assertNotIn("private-address", output.getvalue())

    def test_container_is_removed_when_handoff_is_invalid(self):
        container = "a" * 64
        with patch.object(tracer, "run", side_effect=[container, '{}', '']) as run:
            with self.assertRaises(ValueError):
                tracer.trace_parser("sha256:" + "b" * 64, "pyexpat", Path("unused"))
        self.assertEqual(run.call_args.args[0], ["docker", "rm", "--force", container])
        arguments = run.call_args_list[0].args[0]
        self.assertIn("--read-only", arguments)
        self.assertEqual(arguments[arguments.index("--network") + 1], "none")
        self.assertEqual(arguments[arguments.index("--cap-drop") + 1], "ALL")
