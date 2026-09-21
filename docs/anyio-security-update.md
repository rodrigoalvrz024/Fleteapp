# AnyIO security update - 2026-09-21

Status: committed and pushed as 04591c3 to `codex/mvp-supabase-rls-review` with
owner authorization. Linux verification completed: the Critical finding is gone,
but the image remains blocked by separate findings and approval-evidence checks.
No production deployment was authorized or performed.

## Findings and scoped change

The application images built from 180b11b report Critical
[GHSA-82r6-8w77-94w6 / CVE-2026-63374](https://github.com/advisories/GHSA-82r6-8w77-94w6).
AnyIO before 4.14.2 can normalize a Unicode hostname using IDNA 2003 in a way
that permits certificate validation against the wrong hostname when traffic is
redirected. This is not evidence of an attack against Muvv.

`backend/requirements.txt` changes only AnyIO 4.13.0 to 4.14.2.
The [upstream release](https://github.com/agronholm/anyio/releases/tag/4.14.2)
also fixes Medium [GHSA-5p39-cfhj-2xmp](https://github.com/advisories/GHSA-5p39-cfhj-2xmp),
a worker-process stderr draining issue. No local reproduction is claimed for
that separate Medium advisory.

No API contracts, permissions, UI, credentials, payment settings, image
exceptions or production configuration changed.

## Regression evidence

`backend/tests/test_anyio_tls_security.py` exercises AnyIO's TLS wrapping with
the real Python SSLContext and SSLObject, bypassing only the handshake.
It checks IDNA 2008 normalization of a reserved Unicode example hostname with
native and wrapped contexts, plus preservation of ASCII and IP hostnames.
No DNS resolution, socket connection or real service is used.

- Before upgrade, both Unicode assertions failed: IDNA 2003 produced
  `fass.example.invalid` instead of `xn--fa-hia.example.invalid`.
- After upgrade, all three tests passed. The ASCII/IP control also passed
  before the upgrade.
- Full local unit suite: 373 total, 371 passed and 2 Linux-only skips.
- `pip check`: no broken requirements.
- Disposable PostgreSQL 18.3 with `--tls --http --migrations`: 83 passed
  (9 RLS, 5 TLS, 11 migrations, 58 HTTP). Coverage includes role boundaries,
  session revocation, chat access, private images, pricing tampering, vehicle
  ownership and synthetic payment callbacks. External providers remain mocked;
  this is not a real payment or mobile-device test.
- The disposable cluster stopped and was removed. No external database was used.
- Independent static review found no P1/P2 issue or false-positive mechanism.
  The reviewer did not execute tests; this test checks hostname normalization,
  not a real server handshake or certificate authentication.

## Dependency audit

pip-audit 2.10.1, in a separate local tool environment, queried the pinned list:

```powershell
& '.local-tools\anyio-audit\venv\Scripts\python.exe' -m pip_audit --disable-pip --no-deps -r backend/requirements.txt --progress-spinner off --format json --output .local-tools/anyio-audit/report-20260921.json
```

Result: exit 0, 83 dependencies, 0 known findings, 0 skipped dependencies;
AnyIO 4.14.2 was included. The report remains local and ignored by git.
This checks the explicit pins against the service's current advisory database;
it does not resolve omitted dependencies or scan an installed Linux image.
The tool recommends fully hashed dependencies. No vulnerabilities were ignored.

## Remaining gates

- [Linux run 35624670986](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35624670986)
  built the candidate and passed 355 unit tests with 3 skips (358 total).
  Image `sha256:e248ce9101e7a64ec6eba5749b87efb60fe9fc7ff858abc64ca12df8dbe132f3`
  has 0 Critical, 45 High and 55 Medium findings. No finding was waived.
- Retain the separate container OS findings and the Python evidence mismatch
  documented in [current image status](image-security-current-status.md).
- Do not treat clean Python pins or passing functionality as approval of the
  container, hosted TLS configuration, payment readiness or production release.
