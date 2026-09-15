"""Check runtime code ownership, effective access and symlink destinations."""

import os
from pathlib import Path
import stat


ROOTS = (Path("/app"), Path("/opt/muvv-venv"), Path("/usr"), Path("/etc/ssl"))


def validate_metadata(metadata, writable):
    if metadata.st_uid != 0 or writable:
        raise ValueError("Unprotected code ownership or access")
    if not stat.S_ISLNK(metadata.st_mode) and metadata.st_mode & 0o6022:
        raise ValueError("Unsafe code permissions")


def check_entry(path, roots):
    metadata = path.lstat()
    validate_metadata(metadata, os.access(path, os.W_OK))
    if stat.S_ISLNK(metadata.st_mode):
        # No broken links, cycles, or unchecked external directory trees.
        direct = path.readlink()
        if ".." in direct.parts:
            raise ValueError("Parent traversal in protected symlink requires review")
        if not direct.is_absolute():
            direct = path.parent / direct
        direct = Path(os.path.abspath(direct))
        if not any(direct.is_relative_to(root) for root in roots):
            raise ValueError("Symlink traverses an unprotected root")
        target = path.resolve(strict=True)
        if not any(target.is_relative_to(root) for root in roots):
            raise ValueError("Symlink escapes protected roots")
        validate_metadata(target.stat(), os.access(target, os.W_OK))


def verify(roots=ROOTS):
    if os.geteuid() == 0:
        raise ValueError("Run checks as the application user")
    def walk_error(error):
        raise error
    inspected = 0
    for root in roots:
        if not root.is_dir():
            raise ValueError("Missing protected root")
        for parent in root.parents:
            validate_metadata(parent.stat(), os.access(parent, os.W_OK))
        for directory, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
            for path in [Path(directory), *(Path(directory) / name for name in dirs + files)]:
                check_entry(path, roots)
                inspected += 1
    return inspected


def main():
    try:
        inspected = verify()
    except (OSError, ValueError, RuntimeError):
        print("Protected code verification incomplete or unsafe; not approved.")
        return 1
    print("Protected entries checked:", inspected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
