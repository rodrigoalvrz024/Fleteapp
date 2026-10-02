# Trip location privacy hotfix - 2026-10-01

User requested live driver location be visible only after trip start and
authorized isolated commit/push, Railway deployment and APK installation.

## Server policy

- Only an assigned freight with status in_progress can expose or accept live
  driver coordinates. Accepted, pending, completed and cancelled are hidden.
- Scheduled time and urgency never open an early-access window. Existing
  available_from response field remains for compatibility but returns null.
- Hidden responses redact latitude, longitude, accuracy, heading and timestamp,
  including data stored by older app versions before this hotfix.
- Legacy clients receive 409 when sending positions before start or after close.
- Starting a trip clears any pre-start cached position. The next driver GPS
  update supplies the first live point. Completion/cancellation still clear it.
- Existing owner/assigned-driver/admin access checks remain unchanged. This
  policy does not expose historical location to administrators.

## Verification and boundaries

- 20 focused backend access/flow tests pass on the production-based worktree.
- Full production-based suite: 126 passed, 3 existing pricing-history failures
  (v2 expected versus v3 actual), out of 129 tests. These are the same failures
  documented for release 44dae5a; none were suppressed or edited.
- No pricing, payment, schema/migration, environment, dependency or image change.
- Only this backend hotfix is committed here; mobile UI/privacy changes remain
  in the development workspace with the ongoing design work, as in prior fixes.
- Existing global security/release blockers remain; this is not approval for
  public launch or real payments.

## Companion mobile changes

- GPS sharing starts only for server-confirmed in_progress, never acceptance.
- Client rechecks status and hides late/cached location after closure; it never
  renders a driver's live marker on accepted trips, including old API responses.
- Driver sees a privacy notice before starting rather than an active claim.
- Home start/complete actions open the detail flow to enforce pickup evidence
  and delivery PIN. GPS for driver's own map/availability stays independent.
- No splash modifications and no live freight transition used for validation.
