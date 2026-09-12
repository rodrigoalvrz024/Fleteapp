"""Validate and summarize a local Grype image report without suppressing findings."""
import argparse
from collections import Counter
import html
import json
from pathlib import Path
import re


SEVERITIES = ("Critical", "High", "Medium", "Low", "Negligible", "Unknown")


class ReportValidationError(ValueError):
    """Messages contain static field names only, never values from a report."""


def text(value, field="text", allow_empty=False):
    if not isinstance(value, str) or (not value.strip() and not allow_empty) or len(value) > 1000:
        raise ReportValidationError(f"Invalid field: {field}")
    return " ".join(value.split())


def inspect_report(report, image_id):
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        raise ReportValidationError("Expected an immutable Docker image ID")
    descriptor = report["descriptor"]
    if descriptor["name"] != "grype" or descriptor["version"] != "0.118.0":
        raise ReportValidationError("Unexpected scanner version")
    if not descriptor.get("db") or not descriptor.get("timestamp"):
        raise ReportValidationError("Missing database or scan metadata")
    source = report["source"]
    if source["type"] != "image" or source["target"]["imageID"] != image_id:
        raise ReportValidationError("Report does not match the tested image")
    matches = report["matches"]
    if not isinstance(matches, list):
        raise ReportValidationError("Missing complete matches array")
    if report.get("ignoredMatches"):
        raise ReportValidationError("Ignored matches require explicit review; scan not approved")
    findings = []
    for match in matches:
        vulnerability, package = match["vulnerability"], match["artifact"]
        severity = vulnerability["severity"]
        if severity not in SEVERITIES:
            raise ReportValidationError("Unknown severity schema")
        fix = vulnerability["fix"]
        if not isinstance(fix["versions"], list):
            raise ReportValidationError("Missing fix versions")
        findings.append({
            "severity": severity,
            "id": text(vulnerability["id"], "vulnerability.id"),
            "package": text(package["name"], "artifact.name"),
            "version": text(package["version"], "artifact.version"),
            "type": text(package["type"], "artifact.type"),
            "fix_state": text(fix["state"], "vulnerability.fix.state"),
            "fix_versions": [text(version, "vulnerability.fix.versions") for version in fix["versions"]],
            # Grype's official JSON fixtures allow an empty reference URL.
            "source": text(vulnerability["dataSource"], "vulnerability.dataSource", allow_empty=True),
        })
    findings.sort(key=lambda row: (SEVERITIES.index(row["severity"]), row["package"], row["id"]))
    counts = Counter(row["severity"] for row in findings)
    return {
        "image_id": image_id,
        "scanner": descriptor["version"],
        "scan_time": text(descriptor["timestamp"], "descriptor.timestamp"),
        "counts": {severity: counts[severity] for severity in SEVERITIES},
        "blocked": bool(counts["Critical"] or counts["High"] or report.get("alertsByPackage")),
        "package_alerts": len(report.get("alertsByPackage") or []),
        "findings": findings,
    }


def markdown(result):
    def cell(value):
        return html.escape(str(value)).replace("|", "&#124;").replace("`", "&#96;")

    lines = ["## Image vulnerability audit", "", f"Image: `{result['image_id']}`",
             f"Grype: {result['scanner']}; scan time: {result['scan_time']}", "",
             "Matches (not unique CVEs): " + ", ".join(f"{key}={value}" for key, value in result["counts"].items()),
             f"Package/EOL alerts: {result['package_alerts']}",
             "Gate: " + ("BLOCKED" if result["blocked"] else "No high/critical matches"), "",
             "No ignored findings or only-fixed filter. Medium/low findings still require review.", "",
             "| Severity | Advisory | Package | Installed | Fix state | Fixed versions |",
             "| --- | --- | --- | --- | --- | --- |"]
    for row in result["findings"][:200]:
        lines.append("| " + " | ".join(cell(value) for value in (
            row["severity"], row["id"], row["package"], row["version"],
            row["fix_state"], ", ".join(row["fix_versions"]) or "not available")) + " |")
    if len(result["findings"]) > 200:
        lines.append("Additional matches are preserved in the complete JSON in the step log.")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--image-id", required=True)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--github-annotation", action="store_true")
    args = parser.parse_args()
    try:
        result = inspect_report(json.loads(args.report.read_text(encoding="utf-8")), args.image_id)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        reason = str(error) if isinstance(error, ReportValidationError) else type(error).__name__
        message = f"Image audit incomplete or invalid; not approved. Reason: {reason}"
        print(message)
        if args.github_annotation:
            print(f"::error title=Image audit validation::{message}")
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=True))
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as output:
            output.write(markdown(result))
    if args.github_annotation:
        # Only package/advisory metadata is published, never the image config/env.
        compact = {**result, "findings": result["findings"][:40]}
        message = json.dumps(compact, ensure_ascii=True).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        level = "error" if result["blocked"] else "notice"
        print(f"::{level} title=Image vulnerability audit::{message}")
    return 1 if result["blocked"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
