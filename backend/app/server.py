"""Start the Linux container without relying on hosting privilege defaults."""

import ctypes
import os
from pathlib import Path
import sys


_PR_SET_NO_NEW_PRIVS = 38
_PR_GET_NO_NEW_PRIVS = 39
_CLOSE_RANGE_UNSHARE = 2
_CAPABILITY_FIELDS = ("CapInh", "CapPrm", "CapEff", "CapAmb")


class StartupSecurityError(RuntimeError):
    pass


def _process_status():
    return dict(
        line.split(":", 1)
        for line in Path("/proc/self/status").read_text().splitlines()
        if ":" in line
    )


def _enable_no_new_privileges():
    # prctl is variadic: explicitly use machine-word arguments, including zeros.
    prctl = ctypes.CDLL(None, use_errno=True).prctl
    prctl.argtypes = [ctypes.c_int, *([ctypes.c_ulong] * 4)]
    prctl.restype = ctypes.c_int
    if prctl(_PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
        raise StartupSecurityError("no_new_privileges_unavailable")
    if prctl(_PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0) != 1:
        raise StartupSecurityError("no_new_privileges_not_enabled")


def _close_inherited_descriptors():
    # Keep stdio; detach the descriptor table and close everything else now,
    # not just on a future exec. Uvicorn opens its own sockets after this guard.
    close_range = ctypes.CDLL(None, use_errno=True).close_range
    close_range.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_int]
    close_range.restype = ctypes.c_int
    if close_range(3, ctypes.c_uint(-1).value, _CLOSE_RANGE_UNSHARE) != 0:
        raise StartupSecurityError("inherited_descriptors_not_closed")


def enforce_runtime_security():
    if sys.platform != "linux":
        raise StartupSecurityError("linux_required")
    identities = (*os.getresuid(), *os.getresgid(), *os.getgroups())
    if 0 in identities:
        raise StartupSecurityError("root_identity")
    status = _process_status()
    if any(int(status[field].strip(), 16) != 0 for field in _CAPABILITY_FIELDS):
        raise StartupSecurityError("process_capabilities")
    # New threads inherit the flag; apply it before importing the application.
    if int(status["Threads"].strip()) != 1:
        raise StartupSecurityError("startup_already_multithreaded")
    _enable_no_new_privileges()
    if int(_process_status()["NoNewPrivs"].strip()) != 1:
        raise StartupSecurityError("no_new_privileges_not_enabled")
    _close_inherited_descriptors()


def configured_port():
    value = os.environ.get("PORT") or "8080"
    if not value.isascii() or not value.isdecimal() or len(value) > 5:
        raise StartupSecurityError("invalid_port")
    port = int(value)
    if not 1 <= port <= 65535:
        raise StartupSecurityError("invalid_port")
    return port


def websocket_options():
    # Chat sockets carry authentication and small events, never uploaded images.
    return {"ws": "websockets", "ws_max_size": 16 * 1024,
            "ws_max_queue": 4, "ws_per_message_deflate": False}


def main():
    try:
        port = configured_port()
        enforce_runtime_security()
    except (StartupSecurityError, OSError, AttributeError, KeyError, ValueError):
        # Do not expose environment values, process details, or exception payloads.
        print("[startup] Security checks failed; server not started.", file=sys.stderr)
        return 1

    print("[startup] Non-root identity verified; Linux no_new_privs enabled.", flush=True)
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=port, **websocket_options())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
