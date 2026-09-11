# Linux candidate image vulnerability audit

Prepared 2026-09-11. Scope: `codex/mvp-supabase-rls-review` only, no deployment.
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
- Real Linux scan result: pending the next candidate workflow run.

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
