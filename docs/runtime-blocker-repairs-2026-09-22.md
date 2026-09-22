# Runtime blocker repairs, 2026-09-22

Scope: testing branch only. No production, Railway, main, payment or APK changes.
The owner authorized commit/push and Linux CI after local tests and review.

## Starting evidence

Commit `7fd2ae72683a3efa6e2f222f671a9d9e1bb1d994`:

- [Classic Linux](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35684430275):
  449 tests, 6 skips, no failures. Image scan: 0 Critical, 45 High, 55 Medium,
  7 Low, 44 Negligible, 1 Unknown. Additional policy error:
  `reviewed_python_finding_set_mismatch`.
- [Python 3.14](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35684430323):
  466 tests, 3 skips, no failures. Image scan: 0 Critical, 44 High, 51 Medium,
  7 Low, 43 Negligible, 1 Unknown. Disposable PostgreSQL job passed.
- Previous [DHI trial](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35680307413):
  filesystem check blocked by two missing symlink destinations; startup and root
  rejection steps not executed. Scan blocked with 30 High matches (12 CVEs).

Counts differ across suites because repository-only configuration files are not
all mounted in each runtime test container. Skips are not passes. Scanner counts
are package matches, not distinct vulnerabilities or demonstrated attacks.

## Corrections prepared

1. The classic policy uses the unchanged full scan when none of the three
   previously reviewed Python findings is present. It does not apply an expired
   or obsolete approval, subtract any findings, renew hashes or approve release.
   Any nonempty partial set still requires the exact previous evidence and fails
   closed on mismatches. Mandatory runtime regression steps remain unchanged.
2. DHI build completes missing `/etc/localtime` from the image's own
   `/usr/share/zoneinfo/Etc/UTC`, after validating permissions, regular-file type,
   size and UTC offsets. Existing differing configurations are not overwritten.
3. DHI build can restore the missing `base-files/README` from the same package's
   `README.gz`, only if FAQ points exactly to README. Decompression is bounded;
   invalid gzip, non-UTF-8 data, unsafe ancestors or unexpected links stop build.
   Both inputs validate before either file is created. If both README and its
   compressed copy are truly absent, remove only the root-owned dangling
   FAQ -> README documentation alias instead. No libraries, licenses, package
   database records or scanner exemptions are removed or changed.

The FAQ rule is supported by the [Debian base-files link definition](https://sources.debian.org/src/base-files/13.8%2Bdeb13u7/debian/base-files.links).
It is a conditional repair, NOT a claim that the DHI image has this exact link
and compressed source: Linux must verify those preconditions. The
[DHI image definition](https://github.com/docker-hardened-images/catalog/blob/main/image/python/debian-13/3.11.yaml)
includes tzdata. No runtime data is downloaded from another distribution.

## Local verification

- Full backend suite: 496 tests, 493 passed, 3 pre-existing skips.
  Follow-up suite after orphan-alias handling: 498 tests, 495 passed, 3 skips.
- Policy suite: 19 tests passed, including raw/clean/High/Critical/EOL, expired
  historical approval, invalid identity, partial findings and duplicates.
- Runtime-data suite: initially 6 tests, then 8 passed with bounded gzip and synthetic TZif files.
  Ownership metadata is simulated for Windows/non-root portability. These tests
  do not replace validation of real inode ownership or symlinks in Linux.
- DHI configuration suite: 13 tests passed. New build helper and configuration
  files are mounted read-only in DHI tests and included in workflow triggers.
- Independent review found no remaining P1/P2 in the conditional repair. An
  unexpected FAQ layout must still stop CI; no precondition was relaxed.
- Linux results remain required before claiming the DHI files are repaired.

## First Linux attempt

Commit `6365d87f2de824d3bb073427b8f2818227d71341` was published with authorization.
[DHI build 35685698395](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35685698395)
stopped inside the configuration helper before creating an image; no runtime
checks or scan passed for that candidate. The fixed generic error did not expose
the missing path, so this is not evidence that README.gz was specifically absent.

Follow-up handles a fully stripped document only under the exact preconditions
above, and reports fixed diagnostic codes for known missing source paths. It
does not silently accept corrupt data or redirect an unknown link. Linux must
confirm the actual layout and outcome; this is not a vulnerability fix.

## Completed Linux validation of 55e3a60

Code commit: `55e3a601b7defe0259c07dc8359e91ffe204abd1`.

- [DHI 35686100377](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35686100377):
  image `sha256:e146c08d57b2f8fc61e9b99c11bc88b8955b0ef3e50590743b9f0f7a3c574ccd`.
  Filesystem gate PASS: zero violations, 252 symlinks checked, UID/GID 65532,
  zero process capabilities, no_new_privileges=1. Actual CMD/PID1 startup, six
  unauthenticated-route checks, clean SIGTERM shutdown and refusal of UID 0 PASS.
  The previously broken-link gate no longer prevents these checks from running.
  Full scan remains BLOCKED: 0 Critical, 30 High, 36 Medium, 2 Low,
  20 Negligible, 0 Unknown. These 30 High matches group 12 distinct CVEs and
  15 CVE/package/version combinations. No findings waived.
- [Classic 35686100407](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35686100407):
  image `sha256:2d9c9f689ce527e9b2f2e7e9311ba799a8f22ab25b2f75ee72fb9c91dd61a10f`.
  Policy now reports `not_applicable`, no approval and zero recognized corrections.
  Original/remaining High both 45. No obsolete finding-set error; the scan
  legitimately remains BLOCKED with 0 Critical, 45 High, 55 Medium, 7 Low,
  44 Negligible and 1 Unknown.
- [Python 3.14 35686100388](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35686100388):
  image `sha256:63af8a8f745b891d086cc573db7241ceab4944c203ef754e678584e9d285b92e`.
  PostgreSQL integration succeeded. Scan remains BLOCKED: 0 Critical, 44 High,
  51 Medium, 7 Low, 43 Negligible and 1 Unknown.

No deployment or APK installation performed. Main stayed at
`590e8fec432f094619355dad89dcb068c4bd649f`. No paid service purchased; CI uses the
existing GitHub Actions quota. Do not rebuild identical candidates to try to
clear the remaining findings: require changed maintained packages or a reviewed,
explicitly authorized per-advisory disposition first.

## Remaining release blockers

No High/Critical vulnerability is waived by this lot. On the source consultation
date, Debian still lists stable trixie glibc as vulnerable to
[CVE-2026-19499](https://security-tracker.debian.org/tracker/CVE-2026-19499), and
stable Expat as vulnerable to
[CVE-2026-93990](https://security-tracker.debian.org/tracker/CVE-2026-93990).
The [Chainguard Python advisory page](https://images.chainguard.dev/directory/image/python/vulnerabilities)
also still reports a High glibc finding. Switching vendors is not a proven fix.

Do not mix unstable Debian packages into this stable image or claim that passing
functional tests makes a vulnerable library safe. Release needs maintained
patched packages or an explicitly approved, independent, per-advisory exposure
assessment tied to the actual image and hosting conditions. Neither is supplied
by these configuration repairs. No paid product or service has been ordered.
