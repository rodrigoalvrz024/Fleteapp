"""Trace synthetic XML constructors in disposable containers; never change the image."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


PARSERS = ("pyexpat", "_elementtree")
ITERATIONS = 3
SCRIPTS = Path(__file__).resolve().parent


def run(command, *, timeout=30):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout).stdout


def child(parser_name):
    if os.getpid() <= 1:
        raise RuntimeError("Synthetic process requires a container init")
    spec = importlib.util.spec_from_file_location("backport_checks", SCRIPTS / "verify-python-backports.py")
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    if not checker.expat_capi_evidence()["ready"]:
        raise RuntimeError("Required C API missing")
    api = checker.capi_snapshot(checker.validated_expat_capi_address())
    modules = {module.__name__: checker.module_identity(module)
               for module in (checker.pyexpat, checker._elementtree)}
    # Internal handoff only: raw container logs are never printed or uploaded.
    print(json.dumps({"parser": parser_name, "modules": modules,
                      "salt16": api.SetHashSalt16Bytes, "legacy": api.SetHashSalt}), flush=True)
    os.kill(os.getpid(), signal.SIGSTOP)
    for _ in range(ITERATIONS):
        data = b'<root status="synthetic"><item>ok</item></root>'
        if parser_name == "pyexpat":
            parser = checker.pyexpat.ParserCreate()
            seen = []
            parser.StartElementHandler = lambda name, attrs: seen.append(name)
            parser.Parse(data, True)
            if seen != ["root", "item"]:
                raise RuntimeError("XML result mismatch")
        else:
            parser = checker._elementtree.XMLParser()
            parser.feed(data)
            root = parser.close()
            if root.tag != "root" or len(root) != 1 or root[0].text != "ok":
                raise RuntimeError("XML result mismatch")
    print(json.dumps({"parser": parser_name, "parse_successes": ITERATIONS,
                      "modules": {module.__name__: checker.module_identity(module)
                                  for module in (checker.pyexpat, checker._elementtree)}}), flush=True)


def validate_handoff(data, parser_name):
    if data.get("parser") != parser_name or parser_name not in PARSERS:
        raise ValueError("Wrong trace target")
    for key in ("salt16", "legacy"):
        if type(data.get(key)) is not int or not 4096 <= data[key] < 2**63:
            raise ValueError("Invalid trace address")
    if data["salt16"] == data["legacy"]:
        raise ValueError("Ambiguous trace addresses")
    if set(data.get("modules", {})) != set(PARSERS):
        raise ValueError("Missing module identity")
    for name, module in data["modules"].items():
        expected = f"/usr/local/lib/python3.11/lib-dynload/{name}.cpython-311-x86_64-linux-gnu.so"
        if module.get("path") != expected or not re.fullmatch(r"[0-9a-f]{64}", module.get("sha256", "")):
            raise ValueError("Unreviewed module identity")


def validate_result(handoff, parsed, trace):
    if (parsed.get("parser") != handoff["parser"] or parsed.get("parse_successes") != ITERATIONS
            or parsed.get("modules") != handoff["modules"]):
        raise ValueError("Trace input or module identity changed")
    if (trace.get("hardware_breakpoints") is not True or trace.get("exit_code") != 0
            or trace.get("salt16_hits") != ITERATIONS or trace.get("legacy_hits") != 0):
        raise ValueError("Required XML call path not observed")
    return {"parser": handoff["parser"], "modules": handoff["modules"],
            "hardware_breakpoints": True, "exit_code": 0,
            "salt16_hits": trace["salt16_hits"], "legacy_hits": trace["legacy_hits"],
            "parse_successes": ITERATIONS, "salt_values_read": False}


def trace_parser(image_id, parser_name, directory):
    container = run(["docker", "run", "--detach", "--init", "--network", "none", "--read-only",
                     "--cap-drop", "ALL", "--security-opt", "no-new-privileges", "--pids-limit", "32",
                     "--memory", "256m", "--cpus", "1", "--ulimit", "core=0",
                     "--mount", f"type=bind,src={SCRIPTS},dst=/audit,readonly",
                     "--entrypoint", "python", image_id, "-I", "-B", "/audit/trace-xml-calls.py",
                     "--child", parser_name]).strip()
    if not re.fullmatch(r"[0-9a-f]{64}", container):
        raise ValueError("Invalid container identity")
    try:
        for _ in range(100):
            logs = run(["docker", "logs", container])
            if len(logs) > 16384:
                raise ValueError("Unexpected trace output")
            if logs.strip():
                break
            time.sleep(0.1)
        else:
            raise TimeoutError("Trace target not ready")
        handoff = json.loads(logs)
        validate_handoff(handoff, parser_name)
        state = json.loads(run(["docker", "inspect", container]))[0]
        init_pid = state["State"]["Pid"]
        if state["Image"] != image_id or type(init_pid) is not int or init_pid <= 1:
            raise ValueError("Wrong container process")
        pids = [int(line.strip()) for line in run(["docker", "top", container, "-eo", "pid"]).splitlines()[1:]]
        children = [pid for pid in pids if pid != init_pid]
        if len(pids) != 2 or len(children) != 1 or children[0] <= 1:
            raise ValueError("Ambiguous synthetic process")
        pid = children[0]
        control = directory / "control.json"
        result = directory / "trace.json"
        control.write_text(json.dumps({**handoff, "host_pid": pid}), encoding="utf-8")
        # The debugger runs on the ephemeral CI host; no debugging privileges are added to the target.
        run(["sudo", "-n", "env", "DEBUGINFOD_URLS=", f"MUVV_TRACE_CONTROL={control}",
             f"MUVV_TRACE_RESULT={result}", "gdb", "--batch", "--nx", "--nh",
             "-iex", "set auto-load off", "-iex", "set debuginfod enabled off",
             "-ex", f"source {SCRIPTS / 'trace-xml-gdb.py'}"], timeout=45)
        if run(["docker", "wait", container], timeout=10).strip() != "0":
            raise RuntimeError("Synthetic XML process failed")
        lines = run(["docker", "logs", container]).splitlines()
        if len(lines) != 2:
            raise ValueError("Unexpected trace completion")
        return validate_result(handoff, json.loads(lines[1]), json.loads(result.read_text()))
    finally:
        run(["docker", "rm", "--force", container])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--child", choices=PARSERS)
    parser.add_argument("--image-id")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--github-annotation", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.child:
            child(args.child)
            return 0
        if sys.platform != "linux" or not re.fullmatch(r"sha256:[0-9a-f]{64}", args.image_id or "") or not args.output:
            raise ValueError("Immutable Linux image and output required")
        def interrupted(signum, frame):
            raise TimeoutError("XML trace interrupted")
        signal.signal(signal.SIGTERM, interrupted)
        checks = []
        for name in PARSERS:
            with tempfile.TemporaryDirectory(prefix="muvv-xml-trace-") as folder:
                checks.append(trace_parser(args.image_id, name, Path(folder)))
        report = {"image_id": args.image_id, "checks": checks,
                  "status": "synthetic_call_path_observed_not_security_approval",
                  "entropy_quality_tested": False, "scanner_findings_waived": False}
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        if args.github_annotation:
            print("::notice title=XML execution trace (not approval)::" + json.dumps(report))
        return 0
    except Exception:
        print("XML execution evidence incomplete; no findings waived.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
