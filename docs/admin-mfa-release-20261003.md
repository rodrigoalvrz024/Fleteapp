# Admin MFA release candidate - 2026-10-03

## Scope

Based on deployed commit 932e69ee1a2972d8efb0f56e4eacb340963721da, not the
main local working tree. Railway was still running deployment
dd0566e2-23f5-43ca-b4ab-fb0c70ed76b6 when this candidate was prepared.

The initial MFA commit f0fe4de did not change payment logic, dependency pins,
vehicle catalog, mobile design, splash, Dockerfile or Railway startup configuration.
The dependency follow-up below changes pins and the JWT implementation only;
payment logic, mobile UI and production configuration remain unchanged.

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

## Initial local evidence (f0fe4de)

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

## Dependency follow-up (2026-10-03, not deployment approval)

A fresh audit of the original pinned manifest reported affected versions in
15 packages (81 entries, including repeated advisory identifiers). This was
not an exploit demonstration and was not a complete transitive-environment audit.

- Updated affected packages and compatible FastAPI/Pydantic pins. Replaced
  python-jose with PyJWT 2.15.1, removing the vulnerable ecdsa dependency.
- Access tokens require expiration, issuance, issuer, audience and subject.
  Private image tokens require expiration and retain existing signing keys and
  purpose separation. Existing synthetic python-jose access/document fixtures
  remain valid; malformed/expired/cross-purpose tokens are rejected.
- Built a separate local environment instead of modifying either existing venv.
  pip check passes and all 85 application pins match. google-cloud-storage is
  now explicitly pinned to the tested resolver result, 3.16.0.
- Pinned build tools separately: pip 26.2.1, setuptools 84.0.0, wheel 0.48.0.
  CI installs these before application dependencies. Railway's actual build
  tools/runtime still need independent inspection; this does not change them.
- 171 unit/route tests pass. Real disposable PostgreSQL migration, RLS,
  concurrent OTP reuse, persistent lockout and migration repeatability pass.
- Full installed-environment audit, including transitive packages and build
  tools, still fails: marshmallow 3.26.1 / PYSEC-2026-1605 (two duplicate
  entries, one unique identifier). transbank-sdk 6.1.0 requires <=3.26.1;
  forcing a newer incompatible version is not an acceptable fix.

Raw audit reports remain in the main workspace under
`.local-tools/dependency-audit/`: `admin-release-before-20261003.json`,
`admin-release-installed-20261003.json`, `admin-release-after-20261003.json`.
No advisory is ignored. No clean-scan or runtime-image approval is claimed.
An explicit user decision is pending for a separate, payment-compatible
Transbank REST adapter backport. No real payment was made or modified.

The compatibility workflow's success must not be interpreted as a security
release gate: the dependency finding above and all publication gates remain.
