"""Read-only preflight for the pinned backend environment; never installs packages."""

from importlib import metadata
from pathlib import Path

from packaging.requirements import Requirement


ROOT = Path(__file__).resolve().parents[1]


def check_requirements(lines, installed_version=metadata.version):
    checked = 0
    mismatches = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        requirement = Requirement(line)
        pins = list(requirement.specifier)
        if (requirement.url or len(pins) != 1 or pins[0].operator != "=="
                or "*" in pins[0].version):
            raise ValueError("Every backend dependency must have one exact version pin")
        if requirement.marker is not None and not requirement.marker.evaluate():
            continue
        checked += 1
        try:
            actual = installed_version(requirement.name)
        except metadata.PackageNotFoundError:
            actual = None
        if actual is None or not requirement.specifier.contains(actual, prereleases=True):
            mismatches.append((requirement.name, pins[0].version, actual))
    if not checked:
        raise ValueError("No applicable pinned dependencies found")
    return checked, mismatches


def main():
    try:
        lines = (ROOT / "backend/requirements.txt").read_text(encoding="utf-8-sig").splitlines()
        checked, mismatches = check_requirements(lines)
    except (OSError, ValueError):
        print("Dependency preflight invalid; tests are not approved.")
        return 2
    print(f"Pinned dependencies checked: {checked}")
    for name, expected, actual in mismatches:
        print(f"MISMATCH {name}: expected {expected}, installed {actual or 'missing'}")
    if mismatches:
        print("Use an environment matching backend/requirements.txt before interpreting test results.")
        return 1
    print("All dependency pins match. This is not a vulnerability scan or deployment approval.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
