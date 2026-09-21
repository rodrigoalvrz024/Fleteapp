# Database TLS preflight

Status: local tooling, disposable PostgreSQL TLS handshakes and an authorized
readonly connection from this PC to the project's Supabase pooler verified.
The effective Railway/API/Alembic connection configuration remains unverified.
No deployed application, Railway or Supabase setting has been changed.
The local Alembic connection handling fix below has not been deployed.
Public CA packaging and HTTP-worker TLS assertions are now prepared locally;
Linux-image validation and hosted activation remain pending.

## Finding and scope

`backend/app/database.py` forwards the configured URL without enforcing an SSL
mode. Alembic initially used `settings.DATABASE_URL` independently; the local
fix below reuses the API's normalized URL and connection arguments. Neither
path yet mandates `verify-full` in production configuration. The RLS inspection script
requires encryption but accepts `require`, which does not check the hostname.
These are configuration gaps, not evidence that Railway currently sends data
unencrypted: its effective connection was not inspected in this change.

PostgreSQL documents that `prefer` can fall back to plaintext and `require`
does not verify the server hostname. `verify-full` checks the trust chain and
hostname. See [PostgreSQL SSL modes](https://www.postgresql.org/docs/current/libpq-ssl.html).
Supabase documents downloading the server root certificate in Database settings
and configuring both `sslmode=verify-full` and `sslrootcert`:
[Supabase SSL configuration](https://supabase.com/docs/guides/database/connecting-to-postgres#ssl).

## New verifier

`scripts/verify-database-tls.py` reads only the process environment, never `.env`.
Its default mode only parses configuration and checks the syntax of the explicit
CA path; it does not access the filesystem, DNS or database. Exit zero does
NOT establish certificate validity, TLS negotiation or readiness to deploy.

It rejects weak/missing modes, duplicate or unsupported URL parameters,
implicit PG environment overrides, missing credentials, multiple/socket hosts,
unsupported drivers, unusual database names and relative/UNC/device CA paths.
File existence is checked only after the explicit connection opt-in; a mapped
drive or a symlink may still access remote storage in that authorized mode.
Conservatively unsupported configurations require review, not silent rewriting.

Only `--connect-read-only` enables a connection. That opt-in uses the configured
host and CA, `verify-full`, TLS >= 1.2, GSS encryption disabled so TLS is actually
tested, and a 10-second libpq connection timeout. It checks TLS and the effective
SSL settings, then performs only bounded local transaction settings and
`SHOW transaction_read_only`, rolls back and closes. No application tables,
schema changes, payments or user records are accessed. DNS resolution and
network behavior still require an operator-controlled overall execution limit.

Output contains fixed status codes/booleans, never URLs, hosts, CA paths,
passwords or exception text. Every result keeps `deployment_approved=false`.
With a pooler, success validates only the client-to-pooler TLS connection,
not the pooler-to-database hop, the app's connection or provider configuration.
This check does not install the CA or enforce TLS in the application.

## Verification and next steps

- Independent review found offline CA filesystem access and silent port-zero
  substitution. Three regression tests reproduced both issues before the fix.
  Offline checking is now purely syntactic and explicit port zero is rejected.
  UNC rejection also handles mixed Windows separators, before any filesystem
  check in either mode; normalization is lexical, without resolving paths.
- Fifteen isolated unit tests passed, covering the no-network default, weak modes,
  parameter overrides, cleanup, readonly enforcement and error redaction.
- General suite after the review fixes: 362 tests, 361 passed and one Linux-only skip.
- Final independent static review found no remaining P1/P2 in this limited
  verifier change. Gitleaks detected no secrets in the three new files.
- The fifteen unit tests mock network interactions. The additional real local
  handshake coverage below does not use those mocks.
- No new vulnerability exception, image scan, CI execution or deployment.

## Disposable PostgreSQL TLS regression (2026-09-16)

The existing isolated runner now accepts `--tls`. It creates a one-day test CA,
an unrelated CA and a server certificate with only `127.0.0.1` in its SAN.
Certificates and the synthetic private key stay in the fresh temporary PGDATA;
the existing guarded cleanup removes them with the cluster. No provider CA,
real password or application `.env` is used. PostgreSQL binds only loopback.

Command, from the repository root on Windows:

```powershell
& '.local-tools\dependency-audit\venv\Scripts\python.exe' -B scripts/test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --tls --http --migrations
```

Observed on PostgreSQL 18.3: all 80 integration tests passed (9 RLS, 5 TLS,
10 migrations and 56 HTTP/permissions). The temporary cluster stopped and was
removed. The general unit suite separately passed 361 tests with one Linux-only
skip, 362 total. These counts are different suites, not repeated attempts added
together.

The five TLS cases exercise real libpq connections and the actual CLI:

- Trusted CA plus correct server identity succeeds with `verify-full` and TLS
  1.2 or 1.3; the readonly inspector also succeeds.
- An unrelated CA fails specifically with certificate verification failure.
- A mismatched hostname fails specifically with an identity mismatch. The test
  uses `hostaddr=127.0.0.1` only for this direct-driver negative control, avoiding
  external DNS; the operator-facing verifier still rejects hostaddr overrides.
- CLI success reports a verified connection but never deployment approval.
- CLI failure reports a sanitized error without exposing the synthetic password.

Valid connections before and after negative cases establish that failures are
not caused by an unreachable server. There is no plaintext fallback in those
tested `verify-full` connections. Independent static review found no P1/P2 in
this extension. Failure of PostgreSQL shutdown/cleanup itself is not fault-tested.

This does NOT verify Supabase's certificate, Railway connectivity, pooler
behavior, the API/Alembic connection modes or Linux-container compatibility.
The isolated HTTP/migration tests are regressions, not evidence that those
production paths enforce `verify-full`. The existing container vulnerability
gate remains blocked; this tooling does not change its findings or exceptions.

Remaining steps after the authorized provider check below:

1. Confirm the effective Railway endpoint matches the reviewed local endpoint;
   a successful local check does not establish the hosting configuration.
2. Retain the isolated valid/invalid certificate regression above and verify
   provider-specific CA/endpoint compatibility in the intended deployment runtime.
3. Package the correct public CA and plan consistent API/Alembic settings with
   rollback, then request deployment approval after the image gate is resolved.
   Do not edit the live `DATABASE_URL` or enable SSL enforcement blindly.

This preparation neither buys a service nor requires a plan change. Real
hosting tests may consume the existing service quota and need separate approval.

## Public CA received (2026-09-21)

The operator downloaded `prod-ca-2021.crt` into Downloads after Chrome blocked
the earlier automated download. Offline inspection of the 1,367-byte file found
one PEM certificate, CA basic constraints enabled and no private key material.
Its subject and issuer are Supabase Root 2021 CA; its self-signature verifies.
Validity: 2021-04-28 10:56:53 UTC through 2031-04-26 10:56:53 UTC.
It is within that interval on the inspection date.

Certificate SHA-256 fingerprint:
`807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa`.

These are certificate properties, not proof of a successful provider handshake
or an independent authenticity check. The certificate was not installed in the
OS trust store or deployed to Railway. No connection settings were changed.
At this offline inspection stage, the current process had no DATABASE_URL and
backend/.env was not read. Authorization and the subsequent connection result
are recorded separately below.

## Authorized Supabase pooler check (2026-09-21)

The operator explicitly authorized the readonly connection test. A structured
dotenv/SQLAlchemy parser read only DATABASE_URL for use from backend/.env, with
dotenv interpolation disabled and without importing the application. No
credentials were printed, passed as command-line arguments or written to a new
file. The reviewed endpoint was the configured Supabase transaction pooler on
port 6543, for this project; no hostname, username, port or password was guessed
or replaced. The stored URL had no SSL query parameters. This observation is
about the local file, not Railway's current environment.

The wrapper checked the downloaded CA fingerprint above and added only
`sslmode=verify-full` and the absolute CA path to an in-memory test URL. It then
ran the existing verifier in a separate process with a restricted environment
and a 40-second overall timeout. The source .env was not modified.

Observed result: exit 0, `configuration_valid=true`,
`connection_verified=true`, `application_configuration_changed=false`,
`deployment_approved=false`, result `connection_verified`; stderr was empty.
The verifier enforces TLS 1.2/1.3, certificate trust and server-name checks,
confirms the effective host/SSL mode/CA path, and confirms transaction readonly.
Its only SQL was two SET LOCAL time limits and SHOW transaction_read_only;
the transaction was rolled back and the connection closed. No user, freight,
payment or other application tables were queried or modified.

This establishes a verified TLS connection from this Windows PC to the selected
Supabase pooler with this CA and credentials. It does not establish TLS on the
pooler-to-database hop, the live Railway connection, API/Alembic configuration,
all pooler transaction semantics or Linux compatibility. No negative-certificate
attempts were made against the real project; those remain isolated regression
tests. No deploy, package change, security waiver or paid service was initiated.

## Alembic connection parity fix (2026-09-21, local only)

Preparation exposed a compatibility defect: Alembic passed the raw DATABASE_URL
through ConfigParser. A URL containing percent-encoded credentials or CA paths
raised interpolation errors; `postgres://` was not normalized as in the API,
and the API's configured connection timeout was not applied to migrations.

Five focused tests were added before the fix: four failed on the above cases,
while an existing URL without TLS settings remained compatible. The local fix
imports DATABASE_URL and connect_args from app.database, escapes percent signs
only at the ConfigParser boundary, and passes the same connect_args when building
the migration engine. The decoded URL reaching SQLAlchemy remains identical to
the API's URL. NullPool, migration content and offline behavior are preserved.
No TLS settings are silently enabled or weakened, and no .env file was edited.

The disposable runner now passes explicit verify-full/CA parameters to its
migration and HTTP workers when --tls is selected. Its migration password has
synthetic percent/at-sign characters to exercise real URL decoding. An Engine
connect listener in the migration tests checks TLS 1.2/1.3, verify-full and the
expected CA on every SQLAlchemy connection before fixture or migration SQL.
An additional regression exercises a fresh Alembic connection after setup.

Verification on Windows/PostgreSQL 18.3:

- Five focused tests passed after the fix.
- General suite: 367 tests, 366 passed and one Linux-only skip.
- --tls --http --migrations: 81 passed (9 RLS, 5 TLS, 11 migrations, 56 HTTP).
- --tls --migrations --migration-start models: 25 passed on a second disposable
  cluster, including preservation of synthetic legacy rows and payment states.
  These repeat some cases above; do not add them as distinct coverage.
- Both clusters stopped and were removed. No external database was used in
  either regression run. Secret scan of the four implementation/test files
  found no leaks; tracked diff whitespace checks passed.

This is not a migration against Supabase, a Linux/container verification, a
Railway configuration change or an approval to deploy. CA packaging and the
effective hosted connection remain separate pending work.

Independent static review found no new P1/P2 issues in the Alembic parity fix.
The reviewer did not run tests or connect to any database. Coverage limitation:
the Engine listener verifies connections in the migration worker only. The HTTP
worker receives the TLS URL, but its separate raw psycopg2 RLS-inspection helper
does not forward the SSL query parameters. Thus the HTTP suite passing is not
proof that every connection in that worker, or in the disposable runner, used
verify-full. Production approval remains blocked; the verified migration-engine
coverage and the separate authorized PC-to-pooler result retain their narrower
scope described above.

## HTTP TLS coverage and CA packaging preparation (2026-09-21)

The HTTP coverage limitation above is now addressed locally. Its SQLAlchemy
Engine connect listener checks TLS 1.2/1.3, verify-full and the expected CA on
each new API, migration and auxiliary-engine connection before SQL. The raw
psycopg2 RLS-inspection helper explicitly forwards sslmode/sslrootcert and runs
the same check before inspection SQL. A real /users/me request after disposing
the pool proves that the request opens a checked connection. A negative control
connects with require to the disposable server and confirms that the observer
rejects it before any SQL. This observer is test-only, not production enforcement.
Runner bootstrap/admin connections are still outside this assertion's scope.

The reviewed public Supabase Root 2021 CA is copied into
`backend/certs/supabase-root-2021.crt`. Its source is the certificate manually
downloaded by the operator from this project's Database settings, recorded above.
Its DER SHA-256 fingerprint matches the certificate used in the authorized real
pooler check. No private key, password or service credential is included.

All three backend Dockerfiles now explicitly copy only that certificate to
`/app/certs/supabase-root-2021.crt`, owned by root with mode 0444. The experimental
multi-stage variants carry it forward with /app. It is not added to a global
trust store, downloaded during builds, or used to change DATABASE_URL by default.
New unit tests locate the installed application rather than the mounted test
directory, validate the fingerprint, sole public certificate, self-signature,
CA signing constraints and at least 90 remaining days of validity. A Linux-image
test additionally checks root ownership, non-writable directory and file modes.

Verification:

- --tls --http --migrations: 83 passed (9 RLS, 5 TLS, 11 migrations, 58 HTTP).
- Without --tls: 75 passed and 3 TLS-only skips (78 total). This is compatibility
  coverage, not additional distinct tests or a TLS claim for that run.
- Unit suite: 368 passed and 2 Linux-only skips (370 total).
- Both fresh PostgreSQL 18.3 clusters stopped and were removed. No external
  database or application table was accessed outside the disposable fixtures.
- Gitleaks found no secrets in the six changed/new implementation and test
  files scanned for this step; tracked whitespace checks passed.
- Docker is unavailable on this PC. No Linux image was built or scanned in this
  step, and the image ownership check remains unexecuted here. No GitHub Actions
  execution, commit, push, deployment or provider configuration change occurred.

Before activation, build the exact reviewed candidate in Linux, run the bundled
certificate test against that image and retain the existing image security gates.
Only after separate deployment/configuration approval should the hosted URL use
verify-full and sslrootcert=/app/certs/supabase-root-2021.crt. Keep its existing
host, credentials and other reviewed parameters; do not replace it with a local
test URL. Verify the actual API and Alembic connections from the approved image
with bounded readonly checks and without logging the URL. A CA-file copy alone
does not prove a verified production connection or approve a release.

Independent static review of the CA packaging found no new P1/P2 issues and
confirmed the certificate fingerprint, self-signature and CA properties locally.
The reviewer did not run Docker or the full suite. Linux image permissions remain
pending verification; this review is not release approval.
