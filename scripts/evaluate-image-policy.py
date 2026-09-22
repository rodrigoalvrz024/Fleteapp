"""Apply the owner's narrow Python correction approval; retain the full scan."""

import argparse
from datetime import date, datetime, timezone
import importlib.util
import json
from pathlib import Path
import re


def sibling(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = sibling("report-image-audit")
reviewer = sibling("review-python-findings")
APPROVAL_ID = "muvv-owner-python-three-20260915"
APPROVED_FROM = date(2026, 9, 15)
EXPIRES_ON = date(2026, 10, 15)


def has_reviewed_findings(findings):
    return any(row["id"] in reviewer.REVIEWED_CVES for row in findings)


def evaluate(report, backports, trace, *, image_id, commit, run_id, today=None):
    original = audit.inspect_report(report, image_id)
    reviewer.require(isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit) is not None)
    reviewer.require(isinstance(run_id, str) and re.fullmatch(r"[1-9][0-9]{0,19}", run_id) is not None)
    remaining = dict(original["counts"])
    recognized = []
    applicable = has_reviewed_findings(original["findings"])
    if applicable:
        today = today if today is not None else datetime.now(timezone.utc).date()
        reviewer.require(APPROVED_FROM <= today < EXPIRES_ON)
        reviewer.require(backports["ci_identity"] == {"image_id": image_id, "commit": commit, "run_id": run_id})
        reviewer.validate_python_evidence(original["findings"], backports, trace, image_id)
        recognized = [dict(row, disposition="vendor_fix_verified") for row in original["findings"]
                      if row["id"] in reviewer.REVIEWED_CVES]
        remaining["High"] -= len(recognized)
    return original, {
        "mode": "approved_corrections" if applicable else "not_applicable",
        "approval_id": APPROVAL_ID if applicable else None,
        "expires_on_exclusive": EXPIRES_ON.isoformat() if applicable else None,
        "image_id": image_id, "commit": commit, "run_id": run_id,
        "original_counts": original["counts"], "remaining_counts": remaining,
        "recognized_corrections": recognized,
        "blocked": bool(remaining["Critical"] or remaining["High"] or original["package_alerts"]),
        "deployment_approved": False,
        "scope": ("Three exact Python findings only; medium and other findings remain unapproved."
                  if applicable else "No reviewed Python findings present; unchanged raw scan gate, no approval applied."),
    }


def read_json(path, max_bytes):
    if path.stat().st_size > max_bytes:
        raise ValueError("Oversized evidence")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def evidence_drift(findings, backports):
    """Explain independent mismatches without approving or echoing evidence."""
    counts = {cve: sum(row["id"] == cve for row in findings)
              for cve in reviewer.REVIEWED_CVES}
    modules = {}
    if isinstance(backports, dict):
        native = backports.get("xml_native_evidence")
        if isinstance(native, dict) and isinstance(native.get("modules"), dict):
            modules = native["modules"]
    changed_modules = [name for name, digest in reviewer.MODULE_HASHES.items()
                       if not isinstance(modules.get(name), dict)
                       or modules[name].get("sha256") != digest]
    return {
        "status": "diagnostic_only_not_approval",
        "reviewed_finding_counts": counts,
        "missing_reviewed_findings": [cve for cve, count in counts.items() if count == 0],
        "duplicate_reviewed_findings": [cve for cve, count in counts.items() if count > 1],
        "changed_or_missing_modules": changed_modules,
        "scanner_findings_waived": False,
        "deployment_approved": False,
    }


def annotation(title, value, level="notice"):
    encoded = json.dumps(value, ensure_ascii=True).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::{level} title={title}::{encoded}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--backports", type=Path, required=True)
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--image-id", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--github-annotation", action="store_true")
    args = parser.parse_args(argv)
    try:
        report = read_json(args.report, 64 * 1024 * 1024)
        original = audit.inspect_report(report, args.image_id)
        # Preserve a valid scan even when approval evidence is missing or expired.
        print(json.dumps({"original": original}, indent=2, ensure_ascii=True))
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as stream:
                stream.write(audit.markdown(original))
        if args.github_annotation:
            for index, payload in enumerate(audit.annotation_payloads(original)):
                annotation("Image vulnerability audit" if index == 0 else f"Image vulnerability details {index}", payload)
        backports = trace = None
        # Historical approval evidence is irrelevant when no correction is applied.
        # Mandatory runtime regression steps remain independent workflow gates.
        if has_reviewed_findings(original["findings"]):
            backports = read_json(args.backports, 1024 * 1024)
            drift = evidence_drift(original["findings"], backports)
            if (drift["missing_reviewed_findings"] or drift["duplicate_reviewed_findings"]
                    or drift["changed_or_missing_modules"]):
                print(json.dumps({"evidence_drift": drift}, ensure_ascii=True))
                if args.github_annotation:
                    annotation("Python approval evidence drift (not approval)", drift)
            trace = read_json(args.trace, 1024 * 1024)
        _, policy = evaluate(report, backports, trace,
                             image_id=args.image_id, commit=args.commit, run_id=args.run_id)
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as stream:
                stream.write("\n## Python correction policy\n\n")
                if policy["mode"] == "not_applicable":
                    stream.write("Mode: not_applicable. No approval applied; raw findings unchanged.\n\n")
                else:
                    stream.write(f"Approval: {APPROVAL_ID}; expires before {EXPIRES_ON}.\n\n")
                stream.write(f"Original High: {original['counts']['High']}; verified corrections: "
                             f"{len(policy['recognized_corrections'])}; "
                             f"remaining High: {policy['remaining_counts']['High']}.\n\n")
                stream.write("Policy: " + ("BLOCKED" if policy["blocked"] else "No remaining High/Critical")
                             + ". No deployment approval. Medium and other findings require review.\n")
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        # Emit only fixed reason codes; never echo untrusted evidence or paths.
        if isinstance(error, reviewer.ModuleHashMismatch):
            reason = "reviewed_python_module_hash_mismatch"
        elif isinstance(error, reviewer.ReviewedFindingSetMismatch):
            reason = "reviewed_python_finding_set_mismatch"
        else:
            reason = "invalid_missing_or_expired_evidence"
        print("Image policy evidence invalid, missing or expired; not approved.")
        print("Validation reason: " + reason)
        if args.github_annotation:
            annotation("Image policy validation", {"blocked": True, "deployment_approved": False,
                                                   "reason": reason}, "error")
        return 2
    print(json.dumps({"policy": policy}, indent=2, ensure_ascii=True))
    if args.github_annotation:
        title = "Python corrections not applicable" if policy["mode"] == "not_applicable" else "Approved Python corrections"
        annotation(title, policy, "error" if policy["blocked"] else "notice")
    return 1 if policy["blocked"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
