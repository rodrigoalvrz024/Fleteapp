# Linux candidate image vulnerability audit

Updated 2026-09-12. Scope: `codex/mvp-supabase-rls-review` only, no deployment.
The earlier run 34618327432 built and tested the image but did not scan CVEs.

## Method

The existing Linux workflow now scans the exact local Docker image ID after
the non-root, dependency-consistency and unit-test checks. It uses Grype
0.118.0, downloaded from the official immutable release and checked against
the published SHA-256:
`1d444c5e7360471815f7158f71935fcecc68a3c417d85c7344f770854300bba2`.

The scanner downloads its public vulnerability database. Update checks, hash
validation and a maximum database age of 120 hours are required. No package
inventory, source, application credentials or image is uploaded to Anchore.
External package-lookup sources are disabled. No production services are used.

`scripts/grype-candidate.yaml` has no exclusions or ignore rules and does not
hide unfixed findings. `scripts/report-image-audit.py` checks the image ID,
scanner metadata and report structure, then reports every matching advisory.
High/critical matches and package/EOL alerts block CI; medium/low/unknown
matches remain visible for review. Counts are matches, not unique CVEs.
Ignored matches, malformed output or scanner/database failure cannot pass.

The complete normalized package/advisory report is printed in the job log.
The job summary includes up to 200 matches and one annotation up to 40;
image environment/configuration is not copied into these summaries.
No raw backup, user data, real payment or private document is involved.

## Local validation

- 160 unit tests passed (148 previous and 12 new report-validation tests).
- YAML, branch/permission scope, scan policy and all Bash blocks validated.
- Linux build, non-root check, pip check and unit-test step passed in run
  34619555142 for commit `33aa6ed54b5a39fb256b40ccc19535840c0932ac`.
- The scan step failed with exit code 2. No normalized findings annotation was
  produced. This is an incomplete audit, not evidence of zero vulnerabilities
  and not enough evidence to identify a particular vulnerability.

## Initial run diagnosis

[Run 34619555142, job 103329823424](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34619555142/job/103329823424)
remains failed as of 2026-09-12. The unauthenticated logs API returns 403 and
the browser requires sign-in to view logs. An attempted authenticated lookup
through the stored Git credential helper was rejected by the approval reviewer
before the command ran; no credential was extracted or saved.

The owner supplied the log on 2026-09-12. The download checksum passed and
Grype exited successfully; the failure came from our Python report validator.
The original generic error did not identify which field it rejected.

Official Grype 0.118.0 `TestJsonImgsPresenter.golden` fixtures allow an empty
`vulnerability.dataSource`. That optional reference URL was incorrectly treated
as mandatory by our validator. It now accepts an empty string without dropping
the finding or changing severity/fix handling. Invalid types still fail.
Static validation reasons are now emitted as GitHub annotations, without raw
report contents, source config/environment or stored credentials.

Seven regressions cover empty optional URLs, mandatory fields, invalid types,
safe CLI diagnostics and high-severity exit status. This is a reproduced schema
incompatibility; a fresh CI run must confirm the original report has no other
incompatibilities. Production, database, mobile app and Splash remain unchanged.

Fixture reference:
https://github.com/anchore/grype/blob/v0.118.0/grype/presenter/json/testdata/snapshot/TestJsonImgsPresenter.golden

## Limitations

A successful scan is a dated check against known advisories, not proof that
the application is vulnerability-free or ready for production. Grype findings
need source-specific triage, including installed versions and available fixes.
Do not suppress a finding merely because no patch exists.

The image is built from a moving Python base tag; each rebuilt image must be
scanned and its ID recorded. No image is pushed to a registry by this workflow.
PostgreSQL restoration/migration rehearsals and mobile end-to-end checks remain
separate release gates. Historical Google API keys also remain under review.

## Official references

- [Grype 0.118.0 release](https://github.com/anchore/grype/releases/tag/v0.118.0)
- [Configuration](https://oss.anchore.com/docs/reference/grype/configuration/)
- [Vulnerability database](https://oss.anchore.com/docs/guides/vulnerability/database/)
- [Understanding results](https://oss.anchore.com/docs/guides/vulnerability/interpreting-results/)
