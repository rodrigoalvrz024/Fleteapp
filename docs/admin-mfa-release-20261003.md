# Admin MFA release candidate - 2026-10-03

## Scope

Based on deployed commit 932e69ee1a2972d8efb0f56e4eacb340963721da, not the
main local working tree. Railway was still running deployment
dd0566e2-23f5-43ca-b4ab-fb0c70ed76b6 when this candidate was prepared.

No payment logic, dependency pins, vehicle catalog, mobile design, splash,
Dockerfile or Railway startup configuration changed.

## Controls

- Password plus TOTP for admin access, encrypted factors, serialized one-time
  counters and persistent lockout after five incorrect codes.
- Old/password-only/Google admin tokens cannot authenticate. The common
  authentication helper also protects analytics and initial chat authentication.
- Admin review remains through the existing audited HTTP review endpoint.
  Admin chat sockets are denied: they would otherwise outlive MFA expiration
  or logout. Native client/driver chat access is preserved.
- Admin tokens last 29 minutes. Logout and authenticator enrollment/reset
  increment the session version. Suspension/reactivation increments atomically.
  A keyed credential stamp also invalidates tokens after password changes.
- Invalid admin form responses do not reflect passwords or authenticator codes.
- Explicit consent uses the published admin document versions without changing
  the legal version requirements of the mobile customer/driver app.
- Enrollment is operator-only in a private interactive console. Never run
  app.admin_mfa_setup in logged agent tools or share its output in a chat.

## Migration

New revision f30c6a8b210d follows deployed head b2e4f6a81047. It adds only
users.session_version and admin_second_factors. The latter has RLS enabled,
with PUBLIC/anon/authenticated permissions revoked. Lock wait is bounded.

This is distinct from the unpublished local e7b9c1d43280 revision. Before
merging the other local migration history, reconcile its session-version and
factor-table changes. Do not apply both histories blindly, alter an already
deployed migration, or downgrade away enrolled authenticators.

## Local evidence

- All 85 deployed requirements match the selected test environment exactly.
- 164 unit/route tests pass, with no omissions. Includes real OTP generation,
  bad/expired/replayed codes, legal consent, wrong encryption keys, owner
  binding, logout, password change, suspension/reactivation, analytics and chat.
- Real disposable PostgreSQL: upgrade from the deployed head, sentinel
  preservation, private permissions, non-superuser backend, concurrent same-code
  use (one success/one rejection), concurrent failure persistence/lockout, and
  repeated migration preserving the factor all pass.
- PostgreSQL cluster stopped and deleted; no real account or remote DB used.
- Existing support/avatar tests now use post-MFA admin fixtures rather than
  obsolete password-only admin tokens. Actual MFA is tested independently.
- Three pricing tests incorrectly expected v2 although unchanged production
  pricing emits v3. Expectations now use PRICING_VERSION. Price code unchanged.

Reproduce against this checkout, using an environment matching its requirements:

```text
python scripts/check-backend-dependencies.py
python -m pip check
cd backend
python -W ignore::ResourceWarning -m unittest discover -s tests
cd ..
python scripts/test-admin-mfa-isolated.py --pg-bin <postgres-bin-directory>
```

The GitHub workflow is compatibility-only, restricted to codex/admin-mfa-release,
read-only repository permission, pinned actions, synthetic credentials and no
deployment step. It does not certify the runtime image or resolve open CVEs.

## Publication gates still open

1. Obtain Linux results and review the security status of the actual runtime.
   Existing image/dependency security findings are not waived by this backport.
2. Recheck deployed commit/schema before release; do not stamp a real DB blindly.
3. Configure an independent backed-up ADMIN_MFA_ENCRYPTION_KEY privately.
4. Add exactly https://admin.muvv.cl to existing CORS configuration, preserving
   other origins; test allowed and rejected origins.
5. Deploy only the reviewed candidate, migrate, privately enroll the first
   administrator and verify real login/logout without sharing secrets.
6. Verify HTTPS and frontend/API compatibility, then publish only hosting:admin
   with firebase.admin.json. The mobile app and public site are out of scope.

No production deployment or live MFA enrollment was performed for this evidence.
