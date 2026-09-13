"""Collect bounded CPython backport evidence; never waive scanner findings."""

import argparse
from http import cookies
import json
import operator
import pyexpat
import sys


COOKIE_CASES = (
    "update", "merge", "state_key", "state_value", "state_coded_value",
    "js_key", "js_coded_value",
)
CONTROL_CHARACTERS = tuple(map(chr, (*range(32), 127)))


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
        "version_requirements": requirements,
        # Version evidence is not a dynamic entropy test for CVE-2026-7210.
        "xml_hash_entropy_behavior_tested": False,
        "scanner_findings_waived": False,
        "blocked": not (all(value is True for value in cookie_results.values())
                        and xml_result is True and all(requirements.values())),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-annotation", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = collect_evidence()
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
