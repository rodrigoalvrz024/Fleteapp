"""Review three vendor-fixed Python findings without changing the scan gate."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re


REVIEWED_CVES = ("CVE-2026-3644", "CVE-2026-4224", "CVE-2026-7210")
COOKIE_CHECKS = {"update", "merge", "state_key", "state_value", "state_coded_value",
                 "js_key", "js_coded_value", "valid_cookie_preserved"}
MODULE_HASHES = {
    "pyexpat": "27e28ee2600c7d6347130227616e4fd5ae1c59800ad01fa12e1f23c6f41f34e3",
    "_elementtree": "03bb0f3a57760a0afe252ffbb41acd6492552a2115ada2e42a277075ce7f49c5",
}
COLUMNS = ["severity", "id", "package", "version", "type", "fix_state",
           "fix_versions", "namespace", "matchers"]
SEVERITIES = ("Critical", "High", "Medium", "Low", "Negligible", "Unknown")


def require(condition):
    if not condition:
        raise ValueError("Evidence does not meet the reviewed conditions")


def review(evidence):
    require(evidence["schema"] == 1)
    run = evidence["run"]
    require(re.fullmatch(r"[0-9a-f]{40}", run["head_sha"]) is not None)
    require(type(run["id"]) is int and run["id"] > 0)
    require(run["status"] == "completed")
    require(run["html_url"] == f"https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/{run['id']}")
    annotations = {}
    for entry in evidence["annotations"]:
        title = entry["title"]
        require(title not in annotations)
        annotations[title] = json.loads(entry["message"])
    audit = annotations["Image vulnerability audit"]
    image_id = audit["image_id"]
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", image_id) is not None)
    require(audit["scanner"] == "0.118.0" and audit["blocked"] is True)
    rows = []
    for title, batch in annotations.items():
        if title.startswith("Image vulnerability details "):
            require(batch["columns"] == COLUMNS)
            for values in batch["rows"]:
                require(len(values) == len(COLUMNS))
                rows.append(dict(zip(COLUMNS, values)))
    require(len(rows) == audit["total_findings"] == audit["annotated_findings"])
    counts = Counter(row["severity"] for row in rows)
    require(set(counts) <= set(SEVERITIES))
    require({name: counts[name] for name in SEVERITIES} == audit["counts"])
    validate_python_evidence(rows, annotations["Python backport checks"],
                             annotations["XML execution trace (not approval)"], image_id)
    return {
        "run_url": run["html_url"], "commit": run["head_sha"], "image_id": image_id,
        "status": "vendor_fixed_candidates_pending_approval",
        "candidate_cves": list(REVIEWED_CVES),
        "original_counts": audit["counts"],
        "high_matches_after_separate_approval": counts["High"] - len(REVIEWED_CVES),
        "remaining_high_cves": sorted({row["id"] for row in rows
                                       if row["severity"] == "High" and row["id"] not in REVIEWED_CVES}),
        "scanner_gate_changed": False, "deployment_approved": False,
        "vendor_release": "https://www.python.org/downloads/release/python-31116/",
        "limitations": "Same-run CI evidence, not independent attestation; no entropy-quality claim or general Python exemption.",
    }


def validate_python_evidence(rows, backport, trace, image_id):
    """Validate exact findings and runtime evidence; confer no approval by itself."""
    for cve in REVIEWED_CVES:
        matches = [row for row in rows if row["id"] == cve]
        require(len(matches) == 1)
        row = matches[0]
        require((row["severity"], row["package"], row["version"], row["type"], row["namespace"])
                == ("High", "python", "3.11.16", "binary", "nvd:cpe"))
        require(row["matchers"] == ["stock-matcher"])

    require(backport["blocked"] is False and backport["scanner_findings_waived"] is False)
    require((backport["python"], backport["expat"]) == ("3.11.16", "2.8.3"))
    require(backport["cookie_controls_tested"] == 33)
    require(set(backport["cookie_checks"]) == COOKIE_CHECKS)
    require(all(value is True for value in backport["cookie_checks"].values()))
    require(backport["xml_recursion_guard"] is True)
    capi = backport["xml_capi_evidence"]
    require(capi["ready"] is True and capi["salt_16_bytes_available"] is True)
    require(capi["compiled_expat_version"] == [2, 8, 3] and capi["reviewed_layout_size"] == 224)
    native = backport["xml_native_evidence"]
    require(native["parse_checks"] == {"pyexpat": True, "_elementtree": True})
    require(set(native["modules"]) == set(MODULE_HASHES))
    for name, digest in MODULE_HASHES.items():
        require(native["modules"][name]["sha256"] == digest)

    require(trace["image_id"] == image_id and trace["scanner_findings_waived"] is False)
    require(trace["status"] == "synthetic_call_path_observed_not_security_approval")
    require(len(trace["checks"]) == 2)
    require({check["parser"] for check in trace["checks"]} == set(MODULE_HASHES))
    for check in trace["checks"]:
        require(check["hardware_breakpoints"] is True and check["salt_values_read"] is False)
        require((check["salt16_hits"], check["legacy_hits"], check["parse_successes"], check["exit_code"])
                == (3, 0, 3, 0))
        require(check["modules"] == native["modules"])

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        require(args.evidence.stat().st_size <= 1024 * 1024)
        result = review(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
        encoded = json.dumps(result, indent=2) + "\n"
        if args.output:
            args.output.write_text(encoded, encoding="utf-8")
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        print("Python finding review incomplete; no gate changed.")
        return 2
    print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
