# Candidate runtime image hardening

Updated 2026-09-12. Security branch only; no merge, Railway deployment, mobile
build or production data access is part of this change.

## Changes

- Remove the non-essential Debian `mount` package through apt, without automatic
  dependency removal or permission to remove essential packages. Muvv does not
  invoke mount, umount, swapon, swapoff or losetup. Container volume setup remains
  the responsibility of the host/runtime, not the unprivileged API process.
- Clear SUID/SGID bits on regular files in the built image. The API does not
  require OS user switching or privileged system administration commands.
- Keep application code, Alembic migrations and configuration owned by root,
  instead of the application user. Remove group/world write permission from
  `/app` and `/usr/local`. Application uploads use the external private storage
  service; no writable application source directory is required.
- Use `exec` in the existing shell startup command so Python becomes PID 1 and
  receives termination signals directly. PORT expansion is preserved.

Shared system libraries, the shell, certificate store, PostgreSQL driver and
Alembic remain available. No application endpoints, roles, financial state
logic or dependency pins are changed by this hardening pass.

Debian marks [util-linux](https://packages.debian.org/trixie/amd64/util-linux)
and [ncurses-bin](https://packages.debian.org/trixie/amd64/ncurses-bin) essential.
They are not forcibly purged. The separate
[mount package](https://packages.debian.org/trixie/amd64/mount) is not marked
essential. No package database records are deleted to hide scanner findings.

## Verification

`scripts/verify-runtime-image.py` runs as the image's normal user and inspects
`/usr` and `/app` without reading file contents. It rejects root identity,
effective/permitted process capabilities, privilege elevation permission,
remaining mount commands, SUID/SGID files, file capabilities, and writable or
non-root-owned application/runtime code. Missing metadata or inspection errors
fail the check. It exports counts and runtime identity, never environment
variables, credentials or process command lines.

The permission check deliberately does NOT use Docker's `--read-only` flag,
so a writable root filesystem cannot mask bad file ownership/mode settings.
The startup and unit-test containers do use a read-only root filesystem and
a bounded writable `/tmp`. CI drops capabilities and enables
no-new-privileges; these hosting flags are not encoded by the Dockerfile and
have not yet been verified on Railway production.

The startup check uses the real image CMD with a synthetic environment and no
external network. It checks the root endpoint, Python as PID 1, rejection of
missing/invalid credentials on client/driver/admin routes, Alembic head access,
and graceful shutdown. It does not claim database health, successful login or
payment processing without a real isolated database.

Nine local policy regressions were added; all 183 unit tests pass locally.
The isolated PostgreSQL rehearsal also passed 9 RLS checks, 8 migration checks
and 39 HTTP/WebSocket checks, including authenticated role boundaries, private
photos/chat, vehicle matching, backend-owned pricing and payment callbacks.
It used temporary local data and synthetic provider responses, not production.
The disposable cluster was stopped and removed. A TestClient/httpx deprecation
warning remains, without test failures; a future test-tooling update is separate
from the image permission changes.
## Linux results

The follow-up dated 2026-09-13 makes `/usr/bin/infocmp` and `/usr/bin/nsenter`
root-only (0700). Both belong to retained essential packages but are unnecessary
for the API. Read access is removed as well as execution, so the application
user cannot bypass the restriction by copying the executable elsewhere.
Verification rejects a non-root owner, symlink, group/other access, or effective
read/execute access. This does not restrict the application's business roles;
the container user is distinct from client, driver and administrator accounts.

The verifier also queries Perl's configured include paths for a readable
`Archive/Tar.pm` without loading the module. It uses a fixed command and a clean
environment, accepts only explicit present/absent output, and treats failures
as incomplete inspection. Absence concerns the normal interpreter include path,
not every arbitrary file in the image or every possible future configuration.
This is evidence for triage, not an automatic CVE waiver.

Sources: [infocmp advisory](https://security-tracker.debian.org/tracker/CVE-2025-69720),
[nsenter advisory](https://security-tracker.debian.org/tracker/CVE-2026-78408),
[Archive::Tar advisory](https://security-tracker.debian.org/tracker/CVE-2026-9538).
The follow-up requires a new Linux verification; the result below predates it.

[Run 34733438698](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34733438698)
tested commit `fa4b68397bb6fc82c6e2c52fa64da7286942ed90`. Build, non-root/pip
checks, all 183 unit tests, permission verification and startup/shutdown passed.
The checker inspected 15,511 entries as UID 100 / GID 101 with zero violations,
zero effective/permitted capabilities and no-new-privileges enabled. The real
startup command ran Python as PID 1, all six missing/invalid-token checks
returned 401, and Alembic heads was readable. Uvicorn completed its shutdown
sequence on SIGTERM; exit 143 is allowed because Uvicorn re-raises the captured
signal after graceful shutdown, while exit 137 or missing shutdown completion
fails the check.

The scan at 2026-09-13T02:37:55.605023824Z used image
`sha256:fc098922f01c5b5d3964fec5dc9a3194445dd4be3b57c19bb13d0e1964c0a06a`.
Grype produced a valid report with 183 matches: Critical 7, High 58, Medium 54,
Low 12, Negligible 44, Unknown 8. No package/EOL alerts; all matches were retained
in public annotations. Six matches against the removed `mount` package are
gone (four High, one Medium, one Negligible), not six globally resolved CVEs.
The job ends with exit 1 because the vulnerability gate remains blocked.

Python `3.11.16`, Expat `2.8.3` and zlib `1.3.1` remain unchanged. The earlier
vendor analysis still applies: 23 High/Critical matches have installed-patch
evidence, while the ten Debian CVEs marked open still have 42 matches across
remaining packages. Runtime mitigation is not a blanket CVE exception.

## Remaining gates

Removing privileged helpers and protecting code reduces attack paths; it does
not patch every library advisory. The Grype high/critical gate is unchanged,
with no ignored matches or automatic risk acceptance. Review the exact rebuilt
image and the vendor discrepancies in `linux-image-security-audit.md`.
PostgreSQL migration/role tests, Railway runtime settings and representative
mobile/payment end-to-end tests remain separate release gates.
