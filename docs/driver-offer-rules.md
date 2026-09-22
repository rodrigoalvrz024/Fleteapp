# Driver offer rules

Local implementation review: 2026-09-22. Not deployed or installed on phones.
This work does not approve the pending runtime security findings.

## Eligibility

- A freight must be pending, unassigned, not deleted and have authorized payment.
- Push recipients must be available, operationally approved, have valid mandatory
  documents, an approved compatible vehicle and an active, non-deleted user account.
- Declined offers and conflicting bookings are excluded from pushes, available
  lists, pending-offer details and acceptance.
- Manual browsing/acceptance keeps the existing behavior: it does not require
  the push availability toggle. All operational and matching checks still apply.
- Recheck queued notifications immediately before each send. This narrows, but
  cannot eliminate, the race with acceptance/cancellation after the check.
- Push sending uses deterministic driver-ID order, not proximity priority or an
  exclusive reservation. Delivery order is not guaranteed by the push provider.
- No zone restriction, price change or alteration to customer/admin ownership.

## Schedule protection

The user approved these conservative initial margins:

- Normal freight: backend route duration plus 60 minutes.
- Moving: backend route duration plus 180 minutes.
- Compare UTC instants, including timezone-aware schedules from mobile clients.
- Adjacent non-overlapping future reservations are allowed.
- Missing/invalid route duration prevents a second booking, not a first booking.
- An in-progress, urgent accepted, overdue or unscheduled accepted service blocks
  additional bookings until completed/cancelled. Its actual end is uncertain.
- Completed/cancelled services do not block the agenda.
- Acceptance locks the driver before the freight, with the existing bounded
  PostgreSQL lock timeout, then checks the agenda inside that transaction.
- The conditional pending/unassigned update remains as an additional safeguard.

These margins are not an ETA between jobs and cannot guarantee actual travel or
loading times. Future dispatch needs recent waiting-driver positions and an
explicit policy for late-running trips, rescheduling and staged offers.

## Mobile behavior

- Home offer polling changes from 15 to 5 seconds while online.
- A missing offer clears the incoming state and closes only its own dialog route.
- Back/dismiss hides the local dialog without recording a server-side rejection.
- Available list refreshes every 5 seconds while visible, on foreground resume
  and after returning from details. Background polling stops on that screen.
- Pending details revalidate every 5 seconds while visible. Invalid offers lose
  the accept action. Transient errors allow recovery; authorization/not-found/
  schedule denials stop automatic retries but retain explicit refresh.
- Disposed, offline and superseded responses cannot restore stale offer state.
- This is bounded polling, not instantaneous push invalidation. Network delay
  adds to the refresh interval. Already-delivered OS notifications are not revoked.
- No automatic freight cancellation, payment refund or time-based expiry added.

## Verification

- Backend unit suite using `.local-tools/dependency-audit/venv`: 484 tests,
  481 passed and 3 pre-existing skips. Includes 12 new dispatch tests with synthetic
  SQLite data; SQLite is not used to establish PostgreSQL locking guarantees.
- The older `backend/venv` failed two existing AnyIO TLS tests because its installed
  dependency is stale. It was not updated or used as release evidence. The isolated
  dependency-audit environment matches the pinned AnyIO 4.14.2 and passes them.
- Flutter full suite: 73 passed, 2 pre-existing skips. Includes 10 new offer tests.
- Static analysis of changed mobile files: no errors; 1 existing unused legacy
  dialog warning and 5 existing const suggestions remain. No new warning suppressed.
- Disposable PostgreSQL 18 with verified TLS: initial run passed 9 RLS, 5 TLS,
  11 migration and 86 HTTP/permission tests, including two concurrent accept tests.
- Independent read-only review identified two detail-refresh defects; both were
  fixed and covered by regression tests. Re-review found no remaining P1/P2.
- Final stronger PostgreSQL verification: PASS (9 RLS, 5 TLS, 11 migration,
  86 HTTP tests). The two accept tests identify the first connection PID and
  observe it in `pg_blocking_pids` for the waiting transaction before releasing
  the first. One winner is persisted in both scenarios; the cluster is removed.
- An intermediate test-harness attempt failed to observe contention using a SQL
  text filter. It was replaced by PID-based blocking evidence, not an exemption
  or removal of the concurrency assertion. Final HTTP run: 102.346 seconds.
- Final focused mobile rerun: all 10 offer tests pass, including an obsolete
  403 response arriving after cancelling the safety confirmation.

## Before rollout

- Run Linux CI on the testing branch after authorization to commit/push.
- Validate real push delivery, loss of connectivity and two-driver contention on
  installed release builds against a controlled test backend.
- Document scheduled-offer expiry and customer rescheduling/refunds before adding
  an automatic timeout. Existing pending paid freights are not cancelled here.
- Implement trustworthy recent available-driver location before ranking by ETA;
  do not describe the current broadcast as nearest-driver dispatch.
- Existing runtime-image security release blockers remain separate and unchanged.
