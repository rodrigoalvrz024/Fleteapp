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
Linux image build, runtime checks and a new vulnerability scan are required
before this hardening is considered verified in the container.

## Remaining gates

Removing privileged helpers and protecting code reduces attack paths; it does
not patch every library advisory. The Grype high/critical gate is unchanged,
with no ignored matches or automatic risk acceptance. Review the exact rebuilt
image and the vendor discrepancies in `linux-image-security-audit.md`.
PostgreSQL migration/role tests, Railway runtime settings and representative
mobile/payment end-to-end tests remain separate release gates.
