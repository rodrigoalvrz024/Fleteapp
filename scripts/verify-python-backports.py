"""Collect bounded CPython backport evidence; never waive scanner findings."""

import argparse
import _elementtree
import ctypes
import hashlib
from http import cookies
import json
import operator
from pathlib import Path
import pyexpat
import sys


COOKIE_CASES = (
    "update", "merge", "state_key", "state_value", "state_coded_value",
    "js_key", "js_coded_value",
)
CONTROL_CHARACTERS = tuple(map(chr, (*range(32), 127)))
MAX_NATIVE_MODULE_BYTES = 64 * 1024 * 1024
EXPAT_CAPSULE_NAME = b"pyexpat.expat_CAPI"
EXPAT_CAPI_MAGIC = b"pyexpat.expat_CAPI 1.1\0"


class ExpatCapiHeader(ctypes.Structure):
    _fields_ = [("magic", ctypes.c_void_p), ("size", ctypes.c_int),
                ("major", ctypes.c_int), ("minor", ctypes.c_int), ("micro", ctypes.c_int)]


# Append-only layout reviewed against CPython v3.11.16 Include/pyexpat.h.
CAPI_FUNCTIONS = (
    "ErrorString", "GetErrorCode", "GetErrorColumnNumber", "GetErrorLineNumber",
    "Parse", "ParserCreate_MM", "ParserFree", "SetCharacterDataHandler",
    "SetCommentHandler", "SetDefaultHandlerExpand", "SetElementHandler",
    "SetNamespaceDeclHandler", "SetProcessingInstructionHandler", "SetUnknownEncodingHandler",
    "SetUserData", "SetStartDoctypeDeclHandler", "SetEncoding", "DefaultUnknownEncodingHandler",
    "SetHashSalt", "SetReparseDeferralEnabled", "SetAllocTrackerActivationThreshold",
    "SetAllocTrackerMaximumAmplification", "SetBillionLaughsAttackProtectionActivationThreshold",
    "SetBillionLaughsAttackProtectionMaximumAmplification", "SetHashSalt16Bytes",
)


class ExpatCapi(ctypes.Structure):
    _fields_ = ExpatCapiHeader._fields_ + [(name, ctypes.c_void_p) for name in CAPI_FUNCTIONS]


def capi_snapshot(address):
    # Only called with a validated capsule owned by this interpreter, never external addresses.
    if not address:
        raise ValueError("Missing Expat C API")
    header = ExpatCapiHeader.from_buffer_copy(ctypes.string_at(address, ctypes.sizeof(ExpatCapiHeader)))
    if header.size != ctypes.sizeof(ExpatCapi) or not header.magic:
        raise ValueError("Unreviewed Expat C API layout")
    if ctypes.string_at(header.magic, len(EXPAT_CAPI_MAGIC)) != EXPAT_CAPI_MAGIC:
        raise ValueError("Unreviewed Expat C API signature")
    return ExpatCapi.from_buffer_copy(ctypes.string_at(address, header.size))


def validated_expat_capi_address():
    if (sys.platform != "linux" or sys.implementation.name != "cpython"
            or sys.version_info[:3] != (3, 11, 16) or sys.version_info.releaselevel != "final"
            or ctypes.sizeof(ctypes.c_void_p) != 8):
        raise RuntimeError("Expat C API probe requires reviewed Linux CPython 3.11.16 ABI")
    valid = ctypes.pythonapi.PyCapsule_IsValid
    valid.argtypes = [ctypes.py_object, ctypes.c_char_p]
    valid.restype = ctypes.c_int
    capsule = pyexpat.expat_CAPI
    if valid(capsule, EXPAT_CAPSULE_NAME) != 1:
        raise ValueError("Invalid Expat capsule")
    pointer = ctypes.pythonapi.PyCapsule_GetPointer
    pointer.argtypes = [ctypes.py_object, ctypes.c_char_p]
    pointer.restype = ctypes.c_void_p
    address = pointer(capsule, EXPAT_CAPSULE_NAME)
    capi_snapshot(address)
    return address


def expat_capi_evidence():
    api = capi_snapshot(validated_expat_capi_address())
    return {
        "compiled_expat_version": [api.major, api.minor, api.micro],
        "reviewed_layout_size": api.size,
        "salt_16_bytes_available": bool(api.SetHashSalt16Bytes),
        "legacy_salt_available": bool(api.SetHashSalt),
        "ready": (api.major, api.minor, api.micro) >= (2, 8, 0) and bool(api.SetHashSalt16Bytes),
        "method": "read_only_validated_capi_metadata",
        "hash_salt_call_path_proven": False,
    }


def module_identity(module):
    path = Path(module.__file__).resolve(strict=True)
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_NATIVE_MODULE_BYTES:
                raise ValueError("Native module exceeds evidence limit")
            digest.update(chunk)
    if not size:
        raise ValueError("Empty native module")
    return {"path": str(path), "sha256": digest.hexdigest(), "size": size}


def xml_native_evidence():
    # Exercise both native parsers with fixed input, without external entities or secret values.
    data = b'<root status="synthetic"><item>ok</item></root>'
    elements = []
    parser = pyexpat.ParserCreate()
    parser.StartElementHandler = lambda name, attrs: elements.append(name)
    parser.Parse(data, True)
    tree_parser = _elementtree.XMLParser()
    tree_parser.feed(data)
    root = tree_parser.close()
    return {
        "modules": {module.__name__: module_identity(module)
                    for module in (pyexpat, _elementtree)},
        "parse_checks": {
            "pyexpat": elements == ["root", "item"],
            "_elementtree": (root.tag == "root" and root.get("status") == "synthetic"
                             and len(root) == 1 and root[0].tag == "item" and root[0].text == "ok"),
        },
        "hash_salt_call_path_proven": False,
    }


def cookie_rejects(case, character):
    morsel = cookies.Morsel()
    morsel.set("session", "synthetic", "synthetic")
    try:
        if case == "update":
            morsel.update({"path": character})
        elif case == "merge":
            operator.ior(morsel, {"path": character})
        elif case.startswith("state_"):
            state = {"key": "session", "value": "synthetic", "coded_value": "synthetic"}
            state[case.removeprefix("state_")] = character
            morsel.__setstate__(state)
        elif case in ("js_key", "js_coded_value"):
            # Simulate legacy object state, not untrusted pickle deserialization.
            setattr(morsel, "_" + case.removeprefix("js_"), character)
            jar = cookies.SimpleCookie()
            jar["session"] = morsel
            jar.js_output()
        else:
            raise ValueError("Unknown cookie probe")
    except cookies.CookieError:
        return True
    return False


def cookie_checks():
    results = {case: all(cookie_rejects(case, char) for char in CONTROL_CHARACTERS)
               for case in COOKIE_CASES}
    valid = cookies.Morsel()
    valid.set("session", "synthetic", "synthetic")
    valid.update({"path": "/"})
    operator.ior(valid, {"httponly": True})
    valid.__setstate__({"key": "session", "value": "synthetic", "coded_value": "synthetic"})
    jar = cookies.SimpleCookie()
    jar["session"] = valid
    results["valid_cookie_preserved"] = (
        valid["path"] == "/" and valid["httponly"] is True
        and "session=synthetic" in jar.output()
        and "session=synthetic" in jar.js_output()
    )
    return results


def xml_recursion_is_bounded():
    # Exercise the fixed C recursion guard with < 1 KB, not the large upstream stress case.
    depth = 128
    data = b"<!DOCTYPE root [<!ELEMENT root " + b"(a," * depth + b"a" + b")" * depth + b">]><root/>"
    parser = pyexpat.ParserCreate()
    parser.ElementDeclHandler = lambda name, model: None
    original_limit = sys.getrecursionlimit()
    try:
        sys.setrecursionlimit(64)
        try:
            parser.Parse(data, True)
        except RecursionError:
            return True
        return False
    finally:
        sys.setrecursionlimit(original_limit)


def version_requirements(implementation, version, releaselevel, expat_version):
    return {
        "reviewed_cpython_311_patch_baseline": (
            implementation == "cpython" and version[:2] == (3, 11)
            and version >= (3, 11, 16) and releaselevel == "final"
        ),
        "expat_at_least_280": expat_version >= (2, 8, 0),
    }


def collect_evidence():
    cookie_results = cookie_checks()
    xml_result = xml_recursion_is_bounded()
    native_xml = xml_native_evidence()
    capi = expat_capi_evidence()
    requirements = version_requirements(
        sys.implementation.name, sys.version_info[:3], sys.version_info.releaselevel,
        pyexpat.version_info,
    )
    return {
        "python": ".".join(map(str, sys.version_info[:3])),
        "expat": ".".join(map(str, pyexpat.version_info)),
        "cookie_controls_tested": len(CONTROL_CHARACTERS),
        "cookie_checks": cookie_results,
        "xml_recursion_guard": xml_result,
        "xml_native_evidence": native_xml,
        "xml_capi_evidence": capi,
        "version_requirements": requirements,
        # Version evidence is not a dynamic entropy test for CVE-2026-7210.
        "xml_hash_entropy_behavior_tested": False,
        "scanner_findings_waived": False,
        "blocked": not (all(value is True for value in cookie_results.values())
                        and xml_result is True and all(requirements.values())
                        and all(value is True for value in native_xml["parse_checks"].values())
                        and capi["ready"] is True),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-annotation", action="store_true")
    parser.add_argument("--image-id")
    parser.add_argument("--commit")
    parser.add_argument("--run-id")
    args = parser.parse_args(argv)
    try:
        result = collect_evidence()
        if args.image_id or args.commit or args.run_id:
            if not all((args.image_id, args.commit, args.run_id)):
                raise ValueError("Incomplete CI identity")
            result["ci_identity"] = {"image_id": args.image_id,
                                     "commit": args.commit, "run_id": args.run_id}
    except Exception as error:
        # The runner must fail closed without printing input or exception payloads.
        print(f"Python backport verification incomplete: {type(error).__name__}")
        return 2
    encoded = json.dumps(result, sort_keys=True)
    print(encoded)
    if args.github_annotation:
        level = "error" if result["blocked"] else "notice"
        print(f"::{level} title=Python backport checks::{encoded}")
    return 1 if result["blocked"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
