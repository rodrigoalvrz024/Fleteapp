"""Read-only checks of the candidate image, run as its normal application user."""
import argparse
from collections import Counter
import errno
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys


REMOVED_COMMANDS = ("mount", "umount", "swapon", "swapoff", "losetup")
PROTECTED_ROOTS = (Path("/app"), Path("/usr/local"))
SCAN_ROOTS = (Path("/usr"), Path("/app"))
REMOVED_TOOL_PATHS = (Path("/usr/bin/infocmp"), Path("/usr/bin/nsenter"))


def runtime_paths(profile):
    if profile == "classic":
        return PROTECTED_ROOTS, SCAN_ROOTS
    if profile == "dhi":
        return (Path("/app"), Path("/usr"), Path("/opt/muvv-venv")), (Path("/usr"), Path("/app"), Path("/opt"))
    raise ValueError("Unknown runtime profile")


def is_legacy_openssl_library(name):
    stem, separator, version = name.partition(".so.")
    return bool(separator and version in ("1.0.0", "1.0.2", "1.1")
                and (stem in ("libssl", "libcrypto") or stem.startswith(("libssl-", "libcrypto-"))))


def file_violations(metadata, *, protected, writable, capability):
    reasons = []
    if stat.S_ISREG(metadata.st_mode) and metadata.st_mode & (stat.S_ISUID | stat.S_ISGID):
        reasons.append("setid_file")
    if capability:
        reasons.append("file_capability")
    if protected:
        if metadata.st_uid != 0:
            reasons.append("code_not_root_owned")
        if not stat.S_ISLNK(metadata.st_mode) and metadata.st_mode & 0o022:
            reasons.append("code_group_or_world_writable")
        if writable:
            reasons.append("code_writable_by_app")
    return reasons


def has_file_capability(path):
    try:
        return bool(os.getxattr(path, "security.capability", follow_symlinks=False))
    except OSError as error:
        if error.errno in (errno.ENODATA, errno.ENOTSUP):
            return False
        raise


def process_security(status):
    fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
    return {"effective_capabilities": int(fields["CapEff"].strip(), 16),
            "permitted_capabilities": int(fields["CapPrm"].strip(), 16),
            "no_new_privileges": int(fields["NoNewPrivs"].strip())}


def inspect_removed_tool(path):
    try:
        path.lstat()
    except FileNotFoundError:
        return {"present": False, "blocked": False}
    return {"present": True, "blocked": True}


def perl_archive_tar_readable():
    # Query the minimal interpreter's configured include paths without loading the module.
    result = subprocess.run(
        ["/usr/bin/perl", "-e", 'for my $d (@INC) { if (-r "$d/Archive/Tar.pm") '
         '{ print "present\\n"; exit 0; } } print "absent\\n";'],
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        check=True, capture_output=True, text=True, timeout=10,
    )
    answer = result.stdout.strip()
    if answer not in ("present", "absent"):
        raise RuntimeError("Invalid component probe output")
    return answer == "present"


def inspect_runtime(profile="classic"):
    protected_roots, scan_roots = runtime_paths(profile)
    if sys.platform != "linux":
        raise RuntimeError("Runtime verification requires the Linux candidate container")
    process = process_security(Path("/proc/self/status").read_text())
    violations = []
    if os.geteuid() == 0 or os.getegid() == 0 or 0 in os.getgroups():
        violations.append({"reason": "root_identity"})
    if process["effective_capabilities"] or process["permitted_capabilities"]:
        violations.append({"reason": "process_capabilities"})
    if process["no_new_privileges"] != 1:
        violations.append({"reason": "new_privileges_allowed"})
    for command in REMOVED_COMMANDS:
        if shutil.which(command):
            violations.append({"reason": "unneeded_mount_command", "path": command})
    removed_tools = {path.name: inspect_removed_tool(path) for path in REMOVED_TOOL_PATHS}
    for command, evidence in removed_tools.items():
        if evidence["blocked"]:
            violations.append({"reason": "removed_system_tool_present", "path": command})
    # DHI may omit Perl entirely. Unknown include paths are recorded as null,
    # not a successful Perl probe; the filesystem walk still checks module names.
    archive_tar_readable = (None if profile == "dhi" and not os.path.lexists("/usr/bin/perl")
                            else perl_archive_tar_readable())
    if archive_tar_readable:
        violations.append({"reason": "perl_archive_tar_readable"})

    inspected = 0

    def walk_error(error):
        raise error

    for root in scan_roots:
        if not root.is_dir():
            raise RuntimeError("Missing runtime directory")
        for directory, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
            for path in [Path(directory), *(Path(directory) / name for name in dirs + files)]:
                metadata = path.lstat()
                protected = any(path.is_relative_to(base) for base in protected_roots)
                capability = stat.S_ISREG(metadata.st_mode) and has_file_capability(path)
                reasons = file_violations(metadata, protected=protected,
                                          writable=protected and os.access(path, os.W_OK),
                                          capability=capability)
                if (stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)) and is_legacy_openssl_library(path.name):
                    reasons.append("legacy_openssl_library")
                if profile == "dhi" and path.as_posix().endswith("/Archive/Tar.pm"):
                    reasons.append("perl_archive_tar_named_file")
                violations.extend({"reason": reason, "path": str(path)} for reason in reasons)
                inspected += 1
    return {"profile": profile, "uid": os.geteuid(), "gid": os.getegid(), **process,
            "removed_tools": removed_tools,
            "perl_archive_tar_readable": archive_tar_readable,
            "inspected_entries": inspected, "blocked": bool(violations),
            "violation_counts": dict(Counter(item["reason"] for item in violations)),
            "violations": violations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-annotation", action="store_true")
    parser.add_argument("--profile", choices=("classic", "dhi"), default="classic")
    args = parser.parse_args()
    try:
        result = inspect_runtime(args.profile)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        # Never print exception payloads or process/environment contents.
        print(f"Runtime image verification incomplete: {type(error).__name__}")
        return 2
    print(json.dumps(result, indent=2))
    if args.github_annotation:
        summary = {key: value for key, value in result.items() if key != "violations"}
        if result.get("profile") == "dhi":
            summary["violation_examples"] = [
                {"reason": row["reason"], "path": row.get("path", "")[:200]}
                for row in result["violations"][:8]]
        level = "error" if result["blocked"] else "notice"
        print(f"::{level} title=Runtime image security::{json.dumps(summary)}")
    return 1 if result["blocked"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
