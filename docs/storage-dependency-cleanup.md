# Unused storage dependency cleanup

Status: locally verified; fresh Linux image builds and scans pending.

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

Next: after authorization, commit only this cleanup to the test branch, run
the existing CI builds and scans, and inspect their results. Do not deploy to
Railway or publish an APK as part of this change.
