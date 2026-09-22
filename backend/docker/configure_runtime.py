"""Complete known DHI runtime data during the isolated image build, never startup."""

from datetime import datetime, timedelta
import gzip
import io
import os
from pathlib import Path
import stat
import sys
from zoneinfo import ZoneInfo


MAX_DATA = 128 * 1024


class RuntimeDataError(ValueError):
    """Only fixed diagnostic messages, never data or arbitrary link targets."""


def validate_metadata(metadata, *, directory=False):
    kind = stat.S_ISDIR if directory else stat.S_ISREG
    if (not kind(metadata.st_mode) or metadata.st_uid != 0
            or metadata.st_mode & 0o7022):
        raise RuntimeDataError("Untrusted runtime data permissions or file type")


def check_directories(root, relative):
    current = root
    validate_metadata(current.lstat(), directory=True)
    for part in relative.split("/"):
        current /= part
        validate_metadata(current.lstat(), directory=True)


def read_regular(path):
    metadata = path.lstat()
    validate_metadata(metadata)
    if not 0 < metadata.st_size <= MAX_DATA:
        raise RuntimeDataError("Unexpected runtime data size")
    # Ancestors are root-owned and not writable by the app. Do not follow a
    # substituted final symlink even during this single-process build step.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        validate_metadata(os.fstat(stream.fileno()))
        data = stream.read(MAX_DATA + 1)
    if not 0 < len(data) <= MAX_DATA:
        raise RuntimeDataError("Unexpected runtime data size")
    return data


def validate_utc(data):
    zone = ZoneInfo.from_file(io.BytesIO(data), key="Etc/UTC")
    for year in (1970, 2000, 2026, 2050, 2100):
        for month in (1, 7):
            if datetime(year, month, 1, tzinfo=zone).utcoffset() != timedelta(0):
                raise RuntimeDataError("Runtime timezone is not UTC")


def missing_regular(path, expected):
    try:
        actual = read_regular(path)
    except FileNotFoundError:
        # lstat/open without following links must not classify a dangling link
        # as an absent file that can be replaced.
        if os.path.lexists(path):
            raise RuntimeDataError("Unexpected existing runtime data link") from None
        return True
    if actual != expected:
        raise RuntimeDataError("Existing runtime data differs; manual review required")
    return False


def configure(root=Path("/")):
    for directory in ("etc", "usr/share/zoneinfo/Etc", "usr/share/doc/base-files"):
        check_directories(root, directory)
    utc = read_regular(root / "usr/share/zoneinfo/Etc/UTC")
    validate_utc(utc)
    writes = []
    localtime = root / "etc/localtime"
    # No package files or symlinks are removed, retargeted or overwritten.
    if missing_regular(localtime, utc):
        writes.append((localtime, utc))

    docs = root / "usr/share/doc/base-files"
    faq = docs / "FAQ"
    faq_metadata = faq.lstat()
    if faq_metadata.st_uid != 0 or not stat.S_ISLNK(faq_metadata.st_mode) or os.readlink(faq) not in (
            "README", "/usr/share/doc/base-files/README"):
        raise RuntimeDataError("Unexpected base-files FAQ link; no repair attempted")
    readme = docs / "README"
    try:
        read_regular(readme)
    except FileNotFoundError:
        if os.path.lexists(readme):
            raise RuntimeDataError("Unexpected README link") from None
        compressed = read_regular(docs / "README.gz")
        with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
            content = stream.read(MAX_DATA + 1)
        if not 0 < len(content) <= MAX_DATA:
            raise RuntimeDataError("Unexpected decompressed README size")
        content.decode("utf-8")
        writes.append((readme, content))

    # All inputs must validate before creating either missing file. O_EXCL
    # refuses replacement; a failed build is discarded rather than published.
    for path, content in writes:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444)
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            os.fchmod(stream.fileno(), 0o444)
    return {"created": [path.relative_to(root).as_posix() for path, _ in writes],
            "package_files_removed": False, "security_findings_waived": False}


if __name__ == "__main__":
    import json
    try:
        if sys.platform != "linux" or os.geteuid() != 0:
            raise RuntimeDataError("Linux build root required")
        print(json.dumps(configure(), sort_keys=True))
    except RuntimeDataError as error:
        raise SystemExit("Runtime data configuration failed: " + str(error)) from None
    except (OSError, ValueError, EOFError):
        raise SystemExit("Runtime data configuration failed; image not ready") from None
