# Unused storage dependency cleanup

Status: verified locally and in fresh candidate/DHI Linux builds; release
remains blocked by image vulnerability policy.

## Scope

- Remove `cloudinary==1.40.0` from backend requirements.
- Remove the Cloudinary source-wheel build from the DHI and Wolfi trials.
- Preserve binary-only dependency installation, runtime permissions, image
  selection and all vulnerability gates.
- No changes to API behavior, storage credentials, buckets, mobile UI or payments.

The current storage service uses Supabase through `httpx`. Repository searches
found no Cloudinary SDK consumers in `backend/app`. An independent review of
87 installed distributions found no declared reverse dependency on Cloudinary.
Other dependency pins are intentionally unchanged.

## Local verification

- Focused storage boundary and Docker configuration checks: 16 passed.
- Complete backend suite: 347 tests, 346 passed and one Linux-only skip.
- A child interpreter blocks all Cloudinary imports, imports the API with
  startup migrations disabled, and runs freight flow, chat access and freight
  access suites. Socket `connect` calls are blocked during these checks.
- The child uses a temporary working directory, a restricted environment and
  a dummy database URL, avoiding the repository's local `.env` file.
- The existing local environment still contains Cloudinary. The import-blocked
  test verifies behavior without access to it; it does not replace installing
  requirements and testing a fresh Linux image.

## Release limitations

This cleanup does not claim to resolve any of the 44 remaining High findings
in the last candidate scan. No suppression, new exception or release approval
is introduced. Historical trial reports describing Cloudinary wheel builds
remain records of those earlier images, not the updated build procedure.

## Authorized CI results

Commit `171c757fe5d5b841c552d5f188562f6612bb7217` was pushed only to
`codex/mvp-supabase-rls-review`. The staged secret scan found no leaks.

- [Candidate run 35047310399](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35047310399):
  fresh build and offline tests passed. The runner reported 332 tests and
  `OK (skipped=3)`; repository-only configuration checks are not mounted in
  this runtime suite. The isolated removed-provider test is included.
  Image `sha256:e8a7f80a4f9485349b84c05df47845a782de098d1289e3c9b2362fcef0fd7c55`.
  Scan UTC `2026-09-16T02:18:22.846191799Z`: 0 Critical, 47 High, 51 Medium,
  9 Low, 44 Negligible, 4 Unknown. Three existing verified Python corrections
  recognized; 44 High remain. BLOCKED.
- [DHI run 35047310403](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35047310403):
  build and pre-scan checks completed; vulnerability gate blocked the run.
  Image `sha256:0fbc8d3a93211f8bd82850fdbfe024b157e95fd53d8954bcad64d4f3861a3dce`.
  Scan UTC `2026-09-16T02:18:05.807587629Z`: 0 Critical, 28 High, 32 Medium,
  2 Low, 20 Negligible, 4 Unknown. No candidate-only corrections transferred.
- [Wolfi run 35047310387](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35047310387):
  base scan blocked before building Muvv. Base image
  `sha256:45818b585e19f3eb0cfb22a621476ee8b73af060c0f590fdf252de7a71586070`.
  Scan UTC `2026-09-16T02:17:24.748522073Z`: 0 Critical, 1 High, 2 Medium,
  1 Low, 0 Negligible, 1 Unknown. The High remains CVE-2026-85091 in
  zlib 1.3.2-r7. This is not a successful application build or migration.

No image was deployed, no gate was relaxed, and no real user data was changed.
The cleanup is verified but did not reduce the remaining High counts. Further
progress requires a maintained fix or a reviewed, explicit per-advisory
disposition, not repeated identical builds or implicit risk acceptance.
