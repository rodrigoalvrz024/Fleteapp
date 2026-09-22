"""Read-only checks of the candidate image, run as its normal application user."""
import argparse
from collections import Counter, deque
import errno
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys


REMOVED_COMMANDS = ("mount", "umount", "swapon", "swapoff", "losetup")
PROTECTED_ROOTS = (Path("/app"), Path("/usr"))
SCAN_ROOTS = (Path("/usr"), Path("/app"))
REMOVED_TOOL_PATHS = (Path("/usr/bin/infocmp"), Path("/usr/bin/nsenter"))
CAPABILITY_FIELDS = {
    "inheritable_capabilities": "CapInh",
    "permitted_capabilities": "CapPrm",
    "effective_capabilities": "CapEff",
    "ambient_capabilities": "CapAmb",
}
MAX_LINK_HOPS = 40
MAX_LINK_STEPS = 256
MAX_LINK_PATH = 4096
MAX_RUNTIME_ENTRIES = 200_000
VIRTUAL_LINK_ROOTS = tuple(PurePosixPath(name) for name in ("/proc", "/sys", "/dev", "/run"))
LINK_ERROR_KINDS = {
    errno.ENOENT: "missing", errno.EACCES: "denied", errno.EPERM: "denied",
    errno.ENOTDIR: "not_directory", errno.ELOOP: "loop",
}


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


def inspect_symlink(path, protected_roots, scan_roots, *, diagnostic=None):
    """Check every traversed component; never read contents or walk external trees."""
    original = PurePosixPath(path.as_posix())
    if not original.is_absolute() or len(str(original)) > MAX_LINK_PATH:
        return ["symlink_invalid_path"]
    protected = tuple(PurePosixPath(root.as_posix()) for root in protected_roots)
    scanned = tuple(PurePosixPath(root.as_posix()) for root in scan_roots)
    pending = deque(original.parts[1:])
    current = PurePosixPath("/")
    hops = 0
    try:
        # The parent of /usr or /app must not permit replacing the whole tree.
        root = Path("/")
        reasons = file_violations(root.lstat(), protected=True,
                                  writable=os.access(root, os.W_OK), capability=False)
        if reasons:
            return ["symlink_target_" + reason for reason in reasons]
        for _ in range(MAX_LINK_STEPS):
            if not pending:
                # Only directories are skipped by the normal non-following walk.
                final_metadata = Path(str(current)).lstat()
                if stat.S_ISDIR(final_metadata.st_mode):
                    if not (any(current.is_relative_to(base) for base in protected)
                            and any(current.is_relative_to(base) for base in scanned)):
                        if diagnostic is not None:
                            # Categorize only known OS paths; never log arbitrary link values.
                            diagnostic.update({
                                "target_class": {
                                    "/etc/ssl/certs": "ssl_certificates",
                                    "/etc/ssl/private": "ssl_private",
                                }.get(str(current), "other_external_directory"),
                                "target_uid": final_metadata.st_uid,
                                "target_mode": format(stat.S_IMODE(final_metadata.st_mode), "04o"),
                            })
                        return ["symlink_external_directory_unreviewed"]
                return []
            part = pending.popleft()
            if part == "..":
                current = current.parent
                continue
            candidate = current / part
            if len(str(candidate)) > MAX_LINK_PATH:
                return ["symlink_resolution_limit"]
            if any(candidate.is_relative_to(base) for base in VIRTUAL_LINK_ROOTS):
                return ["symlink_virtual_target"]
            entry = Path(str(candidate))
            metadata = entry.lstat()
            is_link = stat.S_ISLNK(metadata.st_mode)
            regular = stat.S_ISREG(metadata.st_mode)
            if not (is_link or regular or stat.S_ISDIR(metadata.st_mode)):
                return ["symlink_special_target"]
            reasons = file_violations(metadata, protected=True,
                                      writable=not is_link and os.access(entry, os.W_OK),
                                      capability=regular and has_file_capability(entry))
            if reasons:
                return ["symlink_target_" + reason for reason in reasons]
            if is_link:
                hops += 1
                if hops > MAX_LINK_HOPS:
                    return ["symlink_resolution_limit"]
                target = os.readlink(entry)
                if not target or len(target) > MAX_LINK_PATH or any(ord(c) < 32 for c in target):
                    return ["symlink_invalid_target"]
                if target.startswith("//"):
                    return ["symlink_invalid_target"]
                if target.startswith("/"):
                    current = PurePosixPath("/")
                # Keep dot components: file/. and file/.. are not valid file targets.
                parts = [part for part in target.split("/") if part]
                if target.endswith("/"):
                    parts.append(".")
                pending.extendleft(reversed(parts))
                continue
            if pending and not stat.S_ISDIR(metadata.st_mode):
                if diagnostic is not None:
                    diagnostic["resolution_issue"] = "not_directory"
                return ["symlink_unresolved"]
            if regular and is_legacy_openssl_library(candidate.name):
                return ["legacy_openssl_library"]
            if candidate.as_posix().endswith("/Archive/Tar.pm"):
                return ["perl_archive_tar_named_file"]
            current = candidate
        return ["symlink_resolution_limit"]
    except OSError as error:
        # Missing/denied targets are not evidence of absence. Do not log link contents.
        if diagnostic is not None:
            diagnostic["resolution_issue"] = LINK_ERROR_KINDS.get(error.errno, "io_error")
        return ["symlink_unresolved"]


def process_security(status):
    fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
    return {**{name: int(fields[field].strip(), 16) for name, field in CAPABILITY_FIELDS.items()},
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
    # Saved identities and inheritable/ambient capabilities must also agree
    # with the application startup guard; effective identity alone is not enough.
    if 0 in (*os.getresuid(), *os.getresgid(), *os.getgroups()):
        violations.append({"reason": "root_identity"})
    if any(process[name] for name in CAPABILITY_FIELDS):
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
    inspected_links = 0
    link_diagnostics = []

    for root in scan_roots:
        try:
            root_metadata = root.lstat()
        except FileNotFoundError:
            raise RuntimeError("Missing runtime directory") from None
        if not stat.S_ISDIR(root_metadata.st_mode):
            raise RuntimeError("Missing runtime directory")
        pending = [root]
        while pending:
            if inspected >= MAX_RUNTIME_ENTRIES:
                raise RuntimeError("Runtime entry limit exceeded")
            path = pending.pop()
            metadata = path.lstat()
            protected = any(path.is_relative_to(base) or base.is_relative_to(path)
                            for base in protected_roots)
            capability = stat.S_ISREG(metadata.st_mode) and has_file_capability(path)
            is_link = stat.S_ISLNK(metadata.st_mode)
            reasons = file_violations(metadata, protected=protected,
                                      writable=protected and not is_link and os.access(path, os.W_OK),
                                      capability=capability)
            if is_link:
                diagnostic = {}
                reasons.extend(inspect_symlink(path, protected_roots, scan_roots,
                                               diagnostic=diagnostic))
                if diagnostic and len(link_diagnostics) < 8:
                    link_diagnostics.append({"path": str(path)[:200], **diagnostic})
                inspected_links += 1
            if (stat.S_ISREG(metadata.st_mode) or is_link) and is_legacy_openssl_library(path.name):
                reasons.append("legacy_openssl_library")
            if path.as_posix().endswith("/Archive/Tar.pm"):
                reasons.append("perl_archive_tar_named_file")
            violations.extend({"reason": reason, "path": str(path)} for reason in reasons)
            inspected += 1
            if stat.S_ISDIR(metadata.st_mode) and not reasons:
                # os.walk classifies symlink destinations even with followlinks=False.
                # Enumerate names only, then lstat each entry before deciding to descend.
                with os.scandir(path) as entries:
                    for entry in entries:
                        if inspected + len(pending) >= MAX_RUNTIME_ENTRIES:
                            raise RuntimeError("Runtime entry limit exceeded")
                        pending.append(Path(entry.path))
    return {"profile": profile, "uid": os.geteuid(), "gid": os.getegid(), **process,
            "removed_tools": removed_tools,
            "perl_archive_tar_readable": archive_tar_readable,
            "inspected_symlinks": inspected_links,
            "symlink_diagnostics": link_diagnostics,
            "symlink_policy": "bounded_metadata_no_external_directory_walk",
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
        summary["violation_examples"] = [
            {"reason": row["reason"], "path": row.get("path", "")[:200]}
            for row in result["violations"][:8]]
        level = "error" if result["blocked"] else "notice"
        print(f"::{level} title=Runtime image security::{json.dumps(summary)}")
    return 1 if result["blocked"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
