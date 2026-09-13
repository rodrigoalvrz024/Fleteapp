# Linux candidate image vulnerability audit

Updated 2026-09-13. Scope: `codex/mvp-supabase-rls-review` only, no deployment.
The earlier run 34618327432 built and tested the image but did not scan CVEs.

## Latest result

[Run 34767762044](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34767762044)
tested `87aea1930eed0f4b359d2e2de8ab0323a63a447a`. The report is valid; CI
remains blocked by 45 High matches, not by a parser failure. There are zero
Critical matches in this scan. Counts are 155 total: High 45, Medium 49, Low 9,
Negligible 44, Unknown 8; no package/EOL alerts and no exclusions.
Image: `sha256:aa9c46cfd3d768eea3ffcfc4d6de9292e771f81c56797ec4136e10965575acad`.
Scan time: `2026-09-13T16:11:54.923744933Z`. All findings fit in the annotations.

The 45 High matches represent 13 CVEs: three Python records with previously
documented backport evidence, plus the ten open Debian records below, across
42 package matches. The 20 Debian High/Critical matches whose installed fixes
were documented in the earlier triage no longer appear. Overall, 28 earlier
matches are absent relative to run 34733438698. The new report has no changed
matches relative to run 34763412239 in the normalized comparison.
This is not attributed to chmod: the image is rebuilt and advisory data is
refreshed on each run. No blanket exception or risk acceptance was added.

Build, dependency consistency, all 197 unit tests, runtime permissions and real
startup/shutdown passed. Bounded cookie and XML recursion regressions also
verified the installed behavior for CVE-2026-3644 and CVE-2026-4224. They do not
measure XML hash entropy or automatically waive findings. The full 13-CVE
review matrix and sources are in `residual-image-review.md`.
`infocmp` and `nsenter` are root-only, with no effective
read/execute access for the app user. Perl's normal include paths have no
readable `Archive/Tar.pm`. These are scoped runtime observations, not proof of
global CVE absence or of Railway's runtime configuration. See
`runtime-image-hardening.md` for the complete evidence and limits.

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
The job summary includes up to 200 matches. Annotations are split into at most
nine detail fragments plus metadata, each below 3000 bytes to avoid GitHub's
message truncation; metadata states the total and the number actually included.
Distribution, advisory namespace and matcher names are included for triage;
raw match metadata and image environment/configuration are not copied.
No raw backup, user data, real payment or private document is involved.

## Initial validation

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

Run 34705538623 at `78fde6b` confirmed the exact rejection via a safe annotation:
`Invalid field: vulnerability.fix.state`. The official image fixture also has
an empty fix state. Empty strings are now normalized to `unknown`; unknown
types or unrecognized states still fail. Severity and advisory identity remain
mandatory, so the match is retained and a high/critical finding still blocks CI.

Nine added regressions cover empty optional URLs/fix state, mandatory fields,
invalid types, safe CLI diagnostics and high-severity exit status. The official
`TestJsonImgsPresenter.golden` fixture was exercised with only synthetic scanner
version/database/timestamp metadata supplied: both matches were retained
(one Critical, one Low) and the gate remained blocked as expected.
Run 34705763025 at `b126de4` successfully validated the real image report and
exited 1 because the security gate correctly blocked actual scanner findings.
Image: `sha256:599ba38e76e4e717b40f875cb73ea955e7e8ab0aa2f8304ea739b33212896df9`.
Scan time 2026-09-12T16:38:14Z. Matches: Critical 7, High 64, Medium 56,
Low 12, Negligible 45, Unknown 8; 192 total, not 192 unique vulnerabilities.
No package/EOL alerts. The original single annotation was truncated by GitHub;
the reporter now produces bounded JSON fragments and preserves the full log.

## Candidate image remediation

Official Debian records confirm fixes for glibc CVE-2026-5450 in
`2.41-12+deb13u4` and Perl CVE-2026-12087 in `5.40.1-6+deb13u1`.
The scanned image still contained `2.41-12+deb13u3` and `5.40.1-6`.
The scan's `wont-fix` label is not proof that Debian has no patch; preserve
scanner results and compare vendor records and the installed versions.

The Dockerfile now stays on Python 3.11 / Debian trixie explicitly and applies
available Debian updates during the build before dropping privileges. It also
pins pip 26.2.1, setuptools 84.0.0 and wheel 0.48.0, matching the tested local
toolchain. This replaces the old vendored jaraco.context 5.3.0 reported in the
image; GHSA-58pv-8j8x-9vj2 affects versions 5.2.0 through 6.0.x and has a fix
in 6.1.0. No application endpoints, data, roles or payment behavior changed.

Run 34706140887 at `0e2520bf37e5bc0022fbecec9ab6defb6e096c21` rebuilt the image
and passed non-root, pip consistency and all 171 unit tests. The valid scan
still blocked approval (exit 1): Critical 7, High 62, Medium 55, Low 12,
Negligible 45, Unknown 8; 189 matches, no package/EOL alerts. All 189 normalized
findings were recovered from public annotations without authentication.
Image: `sha256:f2c0b3af346aec9a28fd52ad03841d6253b0b04dd9129e92c31a73114425ad99`.
Scan time: 2026-09-12T16:46:00.151128984Z.

The report confirms glibc `2.41-12+deb13u4`, Perl `5.40.1-6+deb13u1` and
Python `3.11.16` are installed. There are 172 Debian-package matches and 17
binary matches, with no Python-package matches in this particular scan.
The previous jaraco.context high-severity match is absent; this does not
establish that all packages are safe or resolve the remaining image gate.

## Residual finding triage

Vendor records checked on 2026-09-12 disagreed with several scanner findings.
This section preserves the earlier triage; the latest result above identifies
which matches are no longer reported.

| Installed package | Scanner finding | Vendor evidence |
| --- | --- | --- |
| libc6 / libc-bin `2.41-12+deb13u4` | CVE-2026-5450, two Critical matches | [Debian marks this trixie version fixed](https://security-tracker.debian.org/tracker/CVE-2026-5450) |
| perl-base `5.40.1-6+deb13u1` | CVE-2026-12087 | [Debian: fixed](https://security-tracker.debian.org/tracker/CVE-2026-12087) |
| perl-base `5.40.1-6+deb13u1` | CVE-2026-13221 | [Debian: fixed](https://security-tracker.debian.org/tracker/CVE-2026-13221) |
| perl-base `5.40.1-6+deb13u1` | CVE-2026-42496 | [Debian: fixed](https://security-tracker.debian.org/tracker/CVE-2026-42496) |
| perl-base `5.40.1-6+deb13u1` | CVE-2026-57433 | [Debian: fixed](https://security-tracker.debian.org/tracker/CVE-2026-57433) |
| perl-base `5.40.1-6+deb13u1` | CVE-2026-8376 | [Debian: fixed](https://security-tracker.debian.org/tracker/CVE-2026-8376) |
| Python `3.11.16` | CVE-2026-3644 / CVE-2026-4224, High | [Python 3.11.16 release notes explicitly include both fixes](https://www.python.org/downloads/release/python-31116/) |
| Python `3.11.16` | CVE-2026-7210, High | Release notes include the Python fix; the diagnostic run confirmed linked Expat `2.8.3`, satisfying the vendor's >= 2.8.0 requirement |

The seven Critical matches above are six distinct CVEs, not seven confirmed
exploitable application flaws. They remain visible and blocking until the
scanner/vendor discrepancy has a reviewed resolution. The official
[Python advisory](https://github.com/psf/advisory-database/blob/main/advisories/python/PSF-2026-23.json)
requires both the interpreter patch and an adequate Expat version; the Python
version number alone is not enough to close CVE-2026-7210.

The official Debian JSON registry was also checked for every Debian High/Critical
CVE, using the trixie release and the corresponding source package. Eighteen
CVE records (20 matches) have a vendor fixed version exactly equal to the
installed package version. In addition to the Critical rows above, these are
glibc CVE-2026-5928, gzip CVE-2026-41992, PCRE2 CVE-2026-86145/89161,
SQLite CVE-2026-11822/11824 and Perl CVE-2026-42497/48959/48961/48962/57432/7017.
Registry: https://security-tracker.debian.org/tracker/data/json

Ten Debian CVEs (46 High matches) remain open in that registry:

| Source package | Open CVEs | Review still needed |
| --- | --- | --- |
| glibc | [CVE-2026-5435](https://security-tracker.debian.org/tracker/CVE-2026-5435) | Deprecated DNS formatting functions; no trixie fix recorded |
| perl | [CVE-2026-9538](https://security-tracker.debian.org/tracker/CVE-2026-9538) | Archive::Tar memory exhaustion; verify module presence and any reachable extraction |
| util-linux | [CVE-2026-76642](https://security-tracker.debian.org/tracker/CVE-2026-76642), [CVE-2026-78408](https://security-tracker.debian.org/tracker/CVE-2026-78408), [CVE-2026-78409](https://security-tracker.debian.org/tracker/CVE-2026-78409), [CVE-2026-78410](https://security-tracker.debian.org/tracker/CVE-2026-78410) | Privileged mount/namespace operations; inspect installed tools, SUID/SGID, capabilities and deployment configuration |
| acl | [CVE-2026-54369](https://security-tracker.debian.org/tracker/CVE-2026-54369), [CVE-2026-54370](https://security-tracker.debian.org/tracker/CVE-2026-54370) | Privileged ACL operations and attacker-controlled paths; trixie update pending |
| ncurses | [CVE-2025-69720](https://security-tracker.debian.org/tracker/CVE-2025-69720) | infocmp CLI; verify installed component and input reachability |
| zlib | [CVE-2026-85091](https://security-tracker.debian.org/tracker/CVE-2026-85091) | Tracker marks trixie vulnerable while description starts at upstream 1.3.1.2; installed runtime is 1.3.1. Reconcile with upstream before any disposition |

These are not 46 independent flaws. Debian labels nine of these records as
minor or postponed for a point release, but that does not automatically waive
Muvv's review or establish non-exploitability. No direct references to the
listed command-line tools, native APIs, subprocess calls or XML/archive APIs
were found in `backend/app` during a source search; transitive dependencies,
runtime tools and hosting behavior still need review. CI uses no-new-privileges
and drops capabilities, but this has not been verified for Railway production.
Do not add unstable Debian repositories or upgrade Python's major/minor series
merely to remove scanner matches.

## Diagnostic run result

[Run 34720388243](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34720388243)
tested `6ab5df3b55c303a2671ab8a564517caf605d1c4e`. Build, non-root, pip check,
all 174 unit tests and runtime metadata collection passed. The scanner report
is valid and still blocks approval with the same 189 matches (exit 1).
Image: `sha256:2018fa6a2529d8cce6109dc9721c36abda4662ab9c808defab33662a97499865`.
Scan time: 2026-09-12T21:37:21.253212764Z.

- Runtime: Python `3.11.16`, Expat `2.8.3`, zlib `1.3.1`.
- Detected distro: Debian `13.7`; 172 matches use
  `debian:distro:debian:13` / `dpkg-matcher`.
- The 17 Python binary matches use `nvd:cpe` / `stock-matcher`.
- All 189 findings fit in the bounded public annotations, including provenance.
- Among 69 High/Critical matches (31 CVEs), 20 Debian matches and three Python
  matches have installed-patch evidence. The other 46 matches represent the ten
  Debian CVEs above. All remain in the scanner gate, with no automatic waiver.

The Python matches are consistent with overly broad NVD CPE ranges when
compared with the release's documented backports. The Debian matching uses the
expected release namespace, but the scanner's fixed-state data differs from
the current vendor registry for the 18 resolved records. This is a data/triage
discrepancy, not evidence that replacing the parser or weakening its checks
would make the image ready. A future resolution needs exact image/package/CVE
evidence and review; remaining components require remediation or an explicitly
approved, scoped and expiring risk disposition before release.

No ignore rule or severity threshold was relaxed. Production, database,
mobile app and Splash remain unchanged.

Fixture reference:
https://github.com/anchore/grype/blob/v0.118.0/grype/presenter/json/testdata/snapshot/TestJsonImgsPresenter.golden

## Limitations

A scoped runtime-hardening candidate removes the unused mount package, clears
SUID/SGID bits and protects installed code. Its separate verification and
limitations are documented in `runtime-image-hardening.md`; those controls do
not suppress or resolve package CVEs by themselves.

The hardening was verified in run 34733438698 at `fa4b683`: all 183 unit tests,
image permissions, real startup and shutdown passed. Removing `mount` reduced
matches from 189 to 183 (Critical 7, High 58, Medium 54, Low 12, Negligible 44,
Unknown 8). The scan remains valid and blocked, with no exclusions. The ten
open Debian CVEs still map to 42 matches, down from 46; this does not close those
CVEs. See the linked hardening guide for the exact image ID and runtime evidence.

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
- [Debian glibc advisory](https://security-tracker.debian.org/tracker/CVE-2026-5450)
- [Debian Perl advisory](https://security-tracker.debian.org/tracker/CVE-2026-12087)
- [jaraco.context advisory](https://github.com/advisories/GHSA-58pv-8j8x-9vj2)
