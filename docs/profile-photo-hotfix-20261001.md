# Profile photo persistence hotfix

Approved by the user on 2026-10-01: publish the profile-photo correction to
Railway and install the corresponding Android APK. Based on production commit
ae81adf81e11414907bdd86d62893c95a0e74649, not the local security/design branch.

## Scope

- Authenticated POST/GET /users/me/avatar; no caller-selected user ID or path.
- Persist the private object reference in the existing users.avatar_url column.
- Retain existing name, phone, roles and driver verification documents.
- Allow JPG/PNG/WEBP signatures, strip metadata with the existing storage helper,
  enforce 5 MB file limit and generate a random per-owner object name.
- Before multipart parsing: scoped 6 MB request-body limit, receive timeout and
  eight concurrent buffered requests per worker. Other routes are unchanged.
- Ten uploads per hour per authenticated account using the existing limiter.
- Recheck active/deleted state and password under a bounded row lock after upload;
  also recheck session_version when present in the newer development schema.
- Private downloads only; never follow an external avatar URL or a supplied path.
- No image URLs or image contents in avatar audit events.
- No migration, dependency update, Docker image change, payment or pricing change.

## Verification

- New hotfix tests: 12 avatar tests and 12 request-body-limit tests passed.
- Full production-source suite: 117 executed, 114 passed, 3 failures.
- Unmodified ae81adf baseline: 93 executed, 90 passed, the same 3 failures.
- All 3 failures are existing pricing-history assertions expecting v2 while the
  existing pricing engine emits v3. No assertions were removed or weakened.
- Development-source checks: 20 passed (avatar, profile mutations, storage import
  boundary). SQLite checks do not replace production PostgreSQL concurrency tests.
- Mobile: 188 passed, 6 optional captures skipped; 25 existing analyzer notices,
  no new notices/errors. Five focused photo tests cover persistence state,
  failed upload, late responses after logout, concurrent name edit, refresh and
  refusing external/other-owner references.
- Splash and loader hashes unchanged. Android release 1.0.29 (30) built.

## Limits

This is a pilot bug fix, not clearance of the outstanding runtime security findings
or approval for public launch/real payments. Storage tests use mocked transport;
real end-to-end photo upload must be checked after deployment with a user-selected
photo. The app's former preview was never stored and must be selected again.

Replaced private photos are deleted best-effort. Failed cleanup or an ambiguous
storage/database write may leave a private orphan; durable reconciliation remains
pending. No potentially attached object is deleted on an ambiguous commit failure.
Image checks reuse existing signature/metadata validation, not full image decoding.
No paid plan was purchased and no new service or bucket is required.
