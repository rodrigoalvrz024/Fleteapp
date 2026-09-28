# DHI: disposition of the 12 remaining High advisories

Status: investigation, NOT release approval. Reviewed 2026-09-22.
No scanner suppression, policy exception, dependency replacement or deployment.

## Exact candidate and evidence

- Code: `55e3a601b7defe0259c07dc8359e91ffe204abd1`.
- [Completed CI run](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35686100377).
- Derived image: `sha256:e146c08d57b2f8fc61e9b99c11bc88b8955b0ef3e50590743b9f0f7a3c574ccd`.
- Build base: `dhi.io/python@sha256:a7bb712353136de87ec96d2c2d15de48852031aeda75be9196f2ca1825a27766`.
- Runtime base: `dhi.io/python@sha256:6258618887b43ee67c5fd867a2d7dc76f21655aef417a4e23115902c5ba05a1e`.
- Grype 0.118.0: 30 High matches, 12 distinct CVEs, 15 CVE/package/version
  groups. All matches remain blocking. Duplicate catalog records are retained.
- Provider declarations: [immutable Docker VEX revision](https://raw.githubusercontent.com/docker-hardened-images/advisories/d57e443dad6ffba03a0effd80974995cc778552c/vex/python/dhi-python.vex.json),
  document version 664. UTF-8 response SHA-256:
  `844d47f05ebaae1510fcfdfb7e4edffe13c5e044a1795c8f799ad94c5e74c2c6`.
  This pins what was read, not publisher authenticity or package provenance.

Package/version identities below were read from this run's scanner annotations,
not copied from the older image. The source-package names in VEX differ from
the binary-package names reported by Grype: version agreement is a lead, not
proof of the source-to-binary mapping or proof that every bundled copy is fixed.

## Three explicit patch claims: verify, do not suppress

| CVE | Binary packages in candidate | Exact version | High matches | Provider claim |
| --- | --- | --- | ---: | --- |
| CVE-2026-19499 | libc6 | 2.41-12+deb13u4+dhi0 | 2 | glibc rebuild backports the strfmon right-padding fix. Statement ecdbed59-22b7-422e-9b22-ae7f68349640. |
| CVE-2026-85091 | zlib1g | 1:1.3.dfsg+really1.3.1-1+dhi4 | 2 | zlib rebuild applies the upstream failed-write pointer reset. Statement 2f135020-089f-4366-b0c0-9e349fab1b63. |
| CVE-2025-69720 | libncursesw6, libtinfo6, ncurses-base, ncurses-bin | 6.5+20250216-2+dhi4 | 8 | ncurses rebuild includes the 20251213 infocmp/tic correction. Statement cbbb37c0-641d-4131-9633-04a23515c025. |

These are stronger leads than the older generic `no-dsa` statements. They do
NOT yet establish three verified fixes. `no-dsa` itself is not a patch or an
application-specific exposure assessment. Do not reuse the earlier approval
for three unrelated CPython CVEs.

Required before proposing recognition of any of these three:

1. Verify publisher identity/signatures and attestations for the exact base
   digests, with the provider's documented trust policy.
2. Tie each binary package to its exact source revision, applied backport and
   build provenance. Check all relevant copies, including wheel-bundled code.
3. Compare upstream fix and regression coverage with the claimed backport;
   run bounded regression checks against the actual derived Linux image.
4. Obtain independent review and explicit approval for any gate change,
   preserving the raw scanner report and all other findings. No approval now.

The [zlib upstream fix](https://github.com/madler/zlib/commit/df84af25dc1942490e1d1c899a07619152a46148)
is available. The vendor's glibc mailing-list link could not be read in this
review; that is an evidence gap, not evidence that the patch is missing.
The ncurses patch reference is
https://invisible-island.net/archives/ncurses/6.5/ncurses-6.5-20251213.patch.gz.

## Four Expat advisories: maintained fixes still needed

Candidate: `libexpat1 2.8.3-1~deb13u1+dhi3`; Python reports `expat_2.8.3`.

| CVE | High matches | Primary source and closure requirement |
| --- | ---: | --- |
| CVE-2026-66046 | 2 | [Debian](https://security-tracker.debian.org/tracker/CVE-2026-66046): attribute-processing complexity; upstream 2.8.4 fixes include a required follow-up to avoid CVE-2026-76641. |
| CVE-2026-76956 | 2 | [Debian](https://security-tracker.debian.org/tracker/CVE-2026-76956): getentropy return handling; fixed in upstream 2.8.4. Existing salt-call traces alone are insufficient. |
| CVE-2026-76957 | 2 | [Debian](https://security-tracker.debian.org/tracker/CVE-2026-76957): custom-encoding callback lifetime; upstream 2.8.4 fixes. |
| CVE-2026-93990 | 2 | [Debian](https://security-tracker.debian.org/tracker/CVE-2026-93990): malformed UTF-16 handling; 2.8.4 remains affected. Require the subsequent fix or maintained backport. |

Docker's consulted VEX gives generic `no-dsa` reasons for the first three;
no statement for CVE-2026-93990 was found. Do not treat upgrading to 2.8.4 as
closing all four. A shared-library update alone may not repair Python's bundled
Expat. No direct XML calls found in app code is not proof against indirect calls.

The candidate's bounded native probe reported these module hashes:

- pyexpat: `43ea74e8b24b049ff48ed17a37acb1d5b792d3862cf74f32261e0374898be1d0`.
- _elementtree: `c764dff2e70d5a20c76eb91da981bc95507925b4e48639896ae7d001cb6ec72e`.

No separate libexpat mapping appeared during that probe; this does not establish
global absence or full linkage. Updated provider question is in
`docs/dhi-expat-provider-question.md`, still unsent.

## Five exposure assessments, not automatic exemptions

| CVE | Candidate binary/version | High matches | Required distinction |
| --- | --- | ---: | --- |
| CVE-2026-5435 | libc6 2.41-12+deb13u4+dhi0 | 2 | [Deprecated DNS diagnostic helpers](https://security-tracker.debian.org/tracker/CVE-2026-5435), not ordinary DNS resolution. Establish actual callers and dynamic loading before an exposure decision. |
| CVE-2026-76642 | libuuid1 2.41.5-0+deb13u1+dhi3 | 2 | [Privileged mount post-hooks](https://security-tracker.debian.org/tracker/CVE-2026-76642). Prove which util-linux binary components are actually present and the hosting privilege boundary. |
| CVE-2026-78408 | libuuid1 2.41.5-0+deb13u1+dhi3 | 2 | [nsenter cgroup descriptor](https://security-tracker.debian.org/tracker/CVE-2026-78408). Container evidence does not cover privileged host operators. |
| CVE-2026-78409 | libuuid1 2.41.5-0+deb13u1+dhi3 | 2 | [Mount subdirectory resolution](https://security-tracker.debian.org/tracker/CVE-2026-78409). Source-package match alone does not identify vulnerable code in libuuid. |
| CVE-2026-78410 | libuuid1 2.41.5-0+deb13u1+dhi3 | 2 | [Restricted bind-mount race](https://security-tracker.debian.org/tracker/CVE-2026-78410). Need package/build evidence and actual hosting conditions, not only absent tool paths. |

Latest candidate probe found none of the named admin tools in its checked
paths and verified UID 65532. Those are useful mitigations, not proofs against
renamed tools, indirect calls or host vulnerabilities. Older full ELF inventories
cannot approve this newer image. No `not_affected` decision is recorded here.

## Next action, costs and limits

Prioritize obtaining exact provider patch/provenance evidence for the three
matching rebuilds and a maintained solution for all four Expat issues. Do not
repeat unchanged CI or purchase another base image on the assumption that it
has no CVEs. No paid plan is required by this investigation.

No external support request has been sent. Publishing a technical question
requires approval and must omit repository source, credentials, customer data
and private CI links. Public base digests and package versions are sufficient.

The raw release gate is unchanged: 30 High matches remain unresolved by our
policy. This investigation groups the next actions; it does not subtract 12
matches for the three provider patch claims, or the 10 exposure-review matches.

## Follow-up 2026-09-28: actual patches located

Independent review located all three patch files and recipes in immutable DHI
catalog revision `6d3708a74a958944f0ba8f60a17e854a3787646b`. The main review
also read the three recipes and the glibc patch directly. Each recipe names
the exact candidate package version and applies its corresponding patch:

- [glibc patch](https://github.com/docker-hardened-images/catalog/blob/6d3708a74a958944f0ba8f60a17e854a3787646b/package/deb/main/glibc/patch/CVE-2026-19499.patch)
  and [recipe](https://github.com/docker-hardened-images/catalog/blob/6d3708a74a958944f0ba8f60a17e854a3787646b/package/deb/main/glibc/debian-13/2.yaml).
  The patch includes a regression test, but the recipe specifies `nocheck`:
  test inclusion is not evidence of test execution. Independent HTTP retrieval
  returned 404 for the claimed upstream mailing-list reference.
- [zlib patch](https://github.com/docker-hardened-images/catalog/blob/6d3708a74a958944f0ba8f60a17e854a3787646b/package/deb/main/zlib/patch/dhi-cve-2026-85091-reset-gzwrite-input-state.patch)
  and [recipe](https://github.com/docker-hardened-images/catalog/blob/6d3708a74a958944f0ba8f60a17e854a3787646b/package/deb/main/zlib/debian-13/1.yaml).
- [ncurses patch](https://github.com/docker-hardened-images/catalog/blob/6d3708a74a958944f0ba8f60a17e854a3787646b/package/deb/main/ncurses/patch/CVE-2025-69720.patch)
  and [recipe](https://github.com/docker-hardened-images/catalog/blob/6d3708a74a958944f0ba8f60a17e854a3787646b/package/deb/main/ncurses/debian-13/6.yaml).

This advances source review, NOT source-to-shipped-binary verification.
The user authorized a separate read-only GitHub Actions verification of the
two existing base digests, with no deployment, APK or CVE exception.
`.github/workflows/backend-dhi-provenance.yml` uses Scout 1.24.0, an archive
SHA-256 from its official GitHub release, and a pinned Docker public key hash.
No checkout, build, image execution or upload to a registry is needed.

The workflow uses Docker's documented `--verify --skip-tlog` mode: verifies
against the pinned Docker key but DOES NOT verify Rekor transparency-log
inclusion. Missing/bad signatures, tool/key hash mismatches and unexpected
provenance formats fail. Authentication files are temporary and removed;
private logs and credentials are not artifacts. Only successfully retrieved,
signature-verified public provenance documents with the expected basic shape
can be preserved for 14 days.

Even success is evidence collection only: actual subject/platform binding,
package-level attestations, backport/source links and regressions must still
be reviewed. It cannot approve a release or waive findings. See Docker's
[verification instructions](https://docs.docker.com/dhi/how-to/verify/) and
[package evidence instructions](https://docs.docker.com/dhi/how-to/hardened-packages/#package-attestations).

### First provenance-only run

- Commit `3ebf75581769ef84ecce59bc18bd35b5d4ee4a90`,
  [run 36449736627](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/36449736627),
  failed (11 seconds total displayed by GitHub).
- Tool/key hash checks and registry logins completed. Both Scout invocations
  returned failure; neither document reached the shape validator. No artifacts
  or verified signatures resulted. The private tool logs were deliberately not
  published, so the first run alone does not identify the underlying cause.
- Follow-up emits only fixed diagnostic categories and the exit status, never
  raw tool output, URLs or credentials. Tests include secret-bearing synthetic
  errors and annotation injection. Verification requirements are unchanged.
- Diagnostic [run 36450556241](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/36450556241)
  at `102d38b` failed in 13 seconds. Both invocations returned exit 1 and the
  fixed category `authentication`; no signed documents were obtained.
- Add the missing Docker Hub login to the same temporary credential store.
  Docker [documents this prerequisite for Scout](https://docs.docker.com/scout/integrations/ci/azure/).
  Reuses the existing read-only PAT through stdin; no new permissions or
  subscription. Successful registry authentication alone does not validate
  provenance. This change must still pass the actual attestation retrieval.

### Signed provenance retrieved successfully

- Commit `a9801f137e0b458a7576c3c156ed07c6e8c3a559`,
  [run 36450823162](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/36450823162),
  passed (38 seconds total; job 32 seconds). Both Scout signature checks and
  both basic document-shape checks passed after adding Docker Hub login.
- Artifact `dhi-base-provenance-evidence`, ID `10983067835`, ZIP size 89,715 bytes.
  Downloaded and independently hashed locally: SHA-256
  `29f071eb6559f1c044c138b0fa542d6912c8cda80f4209dcdd0a0e3ee514965e`,
  matching the GitHub artifact digest. Contains only the two provenance JSONs.
- Both documents declare `linux/amd64`. Build lists 263 materials; runtime 104.
  Their first subjects are respectively
  `pkg:docker/dhi/python@3.11.16-debian13-dev?platform=linux%2Famd64` and
  `pkg:docker/dhi/python@3.11.16-debian13?platform=linux%2Famd64`.
- Subject SHA-256 values are respectively
  `3b3f52951a5496cd953be80a9b0dff8132190a5d6459b4ac089fa2d7d34d27e9` and
  `96542a5780b7c12083b208b09dff449bc2ed32e5c90907f5c903a46294f3b796`.
  These are NOT the input index digests. An explicit registry index-to-platform
  manifest comparison is still required; do not equate these values or treat
  a declared platform as independent proof of that mapping.

Both documents list these identical package material hashes (SHA-256):

| Package | Version | Material hash |
| --- | --- | --- |
| libc6 | 2.41-12+deb13u4+dhi0 | `4a8baee075cce76aa3c04e30727fb3a095b4ab48b666a30a7b00b410fddd0f43` |
| zlib1g | 1:1.3.dfsg+really1.3.1-1+dhi4 | `e4775cc88b8fc53843e43452a1e535ed49676d31e77bab9511e3a6555e7eccba` |
| libncursesw6 | 6.5+20250216-2+dhi4 | `6a11ea46b9100f07449caaa6de558dc3994f2daf1ce343d5212da101455a9102` |
| libtinfo6 | 6.5+20250216-2+dhi4 | `e3e3f9b84ee68f482eaa6ea6a1c33bc18e8863a4e5d28c0c8610fb7cec6b0380` |
| ncurses-base | 6.5+20250216-2+dhi4 | `578958b3f8fdbec5ba4a79396191459434df763167be3c9d43318a2ddda92463` |
| ncurses-bin | 6.5+20250216-2+dhi4 | `54821f5e17572f0badc7059efefb54fb54d9e8a28449274f478735314f22474d` |
| libexpat1 | 2.8.3-1~deb13u1+dhi3 | `a8a537936675dc242a3ae4c25fad31bb1c1b52458e6bb00e36922cdc3c7b90c7` |

These are signed material declarations, not independently downloaded/tested
packages. Next: bind the platform manifests, retrieve package attestations,
compare patch sources, and execute relevant regressions. No scanner findings
were waived. The previous 30 High matches remain unresolved, not newly scanned.
No deployment, APK, image rebuild or subscription change occurred.
