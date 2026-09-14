"""Read-only diagnostic evidence; never changes the release gate or findings."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys


def inspect_findings(report, image_id):
    validator = runpy.run_path(str(Path(__file__).with_name("report-image-audit.py")))
    validated = validator["inspect_report"](report, image_id)
    rows = []
    for match in report["matches"]:
        vuln, artifact = match["vulnerability"], match["artifact"]
        if vuln["severity"] not in ("High", "Critical"):
            continue
        # Keep package identity and discovery locations: equal CVE rows may
        # refer to distinct catalog entries, not separate vulnerable files.
        locations = artifact.get("locations", [])
        if not isinstance(locations, list):
            raise ValueError("Invalid artifact locations")
        rows.append({
            "cve": validator["text"](vuln["id"]),
            "package": validator["text"](artifact["name"]),
            "version": validator["text"](artifact["version"]),
            "artifact_id": validator["text"](artifact["id"]),
            "purl": validator["text"](artifact.get("purl", ""), allow_empty=True),
            "locations": sorted({validator["text"](item["path"]) for item in locations}),
        })
    groups = Counter((row["cve"], row["package"], row["version"]) for row in rows)
    return {
        "image_id": image_id,
        "counts_unchanged": validated["counts"],
        "gate_blocked": validated["blocked"],
        "unique_high_critical_cves": len({row["cve"] for row in rows}),
        "cve_package_version_groups": len(groups),
        "matches": rows,
        "limitations": "Catalog locations do not prove runtime reachability or vulnerability fixes.",
        "findings_waived": False,
    }


def runtime_evidence(image_id):
    if sys.platform != "linux":
        raise ValueError("Linux required")
    import pyexpat
    import _elementtree

    # Force bounded valid parses, without contacting external services.
    pyexpat.ParserCreate().Parse(b"<muvv/>", True)
    parser = _elementtree.XMLParser()
    parser.feed(b"<muvv/>")
    parser.close()
    paths = set()
    for line in Path("/proc/self/maps").read_text().splitlines():
        parts = line.split(maxsplit=5)
        if len(parts) == 6 and parts[5].startswith("/"):
            path = Path(parts[5])
            if path.name.startswith(("libexpat", "libc.so", "pyexpat.", "_elementtree.")):
                paths.add(path)
    files = []
    if not paths:
        raise ValueError("Missing native mappings")
    for path in sorted(paths):
        if path.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("Unexpected native file size")
        files.append({"path": str(path), "size": path.stat().st_size,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    tools = ("infocmp", "mount", "umount", "nsenter", "getfacl", "setfacl", "chacl")
    return {"image_id": image_id, "python": sys.version.split()[0],
            "expat": pyexpat.EXPAT_VERSION, "uid": os.geteuid(),
            "mapped_native_files": files,
            "known_tool_paths_present": [str(Path(root) / tool)
                for root in ("/usr/bin", "/bin", "/usr/sbin", "/sbin") for tool in tools
                if os.path.lexists(Path(root) / tool)],
            "limitations": "Known paths only; loaded libraries do not prove vulnerable code execution.",
            "findings_waived": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", nargs="?", type=Path)
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--image-id", required=True)
    args = parser.parse_args()
    try:
        import re
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", args.image_id):
            raise ValueError("Invalid image identity")
        if args.runtime:
            result = runtime_evidence(args.image_id)
            title = "Hardened native evidence"
        else:
            if args.report is None or args.report.stat().st_size > 64 * 1024 * 1024:
                raise ValueError("Invalid report")
            result = inspect_findings(json.loads(args.report.read_text()), args.image_id)
            title = "Hardened finding identities"
        payload = json.dumps(result, sort_keys=True)
        if len(payload.encode()) > 50000:
            raise ValueError("Evidence exceeds annotation limit")
        escaped = payload.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::notice title={title}::{escaped}")
        return 0
    except (ValueError, KeyError, TypeError, OSError):
        print("Hardened diagnostic evidence incomplete; no approval.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
