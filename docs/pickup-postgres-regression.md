# Pickup acceptance: isolated PostgreSQL regression

Review date: 2026-09-15. Local verification only; no release approval.
Base commit: `41df869`; changes are limited to integration tests and this report.

## Scope

Four new HTTP integration tests exercise the existing pickup/home-office rule:

- Require an actual boolean confirmation, reject missing/false confirmation,
  and persist the actor, notice version, assigned vehicle and accepted status.
  Replaying acceptance cannot create a second acceptance audit entry.
- Confirmation cannot override pending vehicle approval, insufficient weight
  or volume capacity, or the vehicle's approved list of services.
- An account with an approved driver profile and its own compatible pickup
  still cannot accept while its active role is client or admin. A different
  approved driver cannot select that pickup either.
- An older client without the confirmation field selects an eligible enclosed
  vehicle when available, without inventing consent. Both successful paths
  require accepted status, matching assignment timestamps and one history row.

The negative cases check that the freight remains unassigned and pending,
that its price/payment authorization are preserved and no acceptance audit
entry is committed. No changes to production authorization or matching rules.

## Environment and results

PostgreSQL 18.3 on Windows, bound to loopback, using disposable randomly named
databases, synthetic users and application roles without superuser/BYPASSRLS.
The existing runner guards database identity, omits real integration credentials,
limits queries and stops/removes each temporary cluster when finished.

- Baseline run: 9 RLS + 10 empty-database migration + 52 HTTP tests passed.
- Expanded run: 9 RLS + 10 legacy-schema migration + 56 HTTP tests passed.
- Independent review identified two weak assertions (role rejection could be
  caused by a missing driver; success did not require accepted status). Both
  were strengthened and the second static review found no remaining P1/P2.
- Final rerun of the strengthened assertions: 9 RLS + 56 HTTP tests passed;
  the runner confirmed the temporary cluster was stopped and removed.
- General unit suite: 347 tests, 346 passed and one Linux-only skip.

The migration suite passed in both empty and legacy-schema modes. Counts from
repeated runs are not added together as if they were distinct tests: the final
integration coverage is 9 RLS, 10 migration and 56 HTTP checks (75 total).

These are local tests, not testing against the deployed Supabase PostgreSQL
version, PgBouncer/TLS, actual storage or payment providers, phones or Railway.
They do not replace a load test or prove correctness of every concurrent path.
The main GitHub unit-test workflow does not run this disposable Windows runner.

## Release blockers remain

The last image scan still has 44 remaining High matches; see
[storage cleanup results](storage-dependency-cleanup.md). No exceptions, image
changes, deployment, financial operation or real-data migration were made.

Read-only provider recheck: [Debian glibc](https://security-tracker.debian.org/tracker/CVE-2026-19499)
still lists the installed stable version as vulnerable. The
[Chainguard Python vulnerability page](https://images.chainguard.dev/directory/image/python/vulnerabilities)
still lists zlib 1.3.2-r7; the [upstream query](https://github.com/madler/zlib/issues/1310)
remains open. These checks provide no basis for waiving those findings.
