# Docker case 00236676: follow-up draft

STATUS UPDATE 2026-09-28: the user has now supplied the human support response.
The drafts below are retained as history, NOT the current request to send.
Support closed duplicate 00237588, clarified dhi3 versus dhi4, supplied a new
Python 3.11 runtime index, and reports that pyexpat appears to use bundled
Expat. It cannot supply further package-level provenance or test results.
See `docs/dhi-advisory-disposition-2026-09-22.md`, human follow-up section.
Do not resend these questions unchanged or purchase support automatically.
No further email has been sent by the agent.

Prepared 2026-09-28. NOT sent. Reply in the existing support email thread.
No purchase, subscription, security exception or deployment is requested.

## Suggested reply

Hello,

Thank you for confirming the DHI-specific glibc backport and that the corrected
Python 3.14 image is available in Community without a paid DHI subscription.
Please keep case 00236676 open while we complete verification.

We have also evaluated Python 3.11.16 Debian 13 to avoid an unnecessary Python
upgrade. Our pinned runtime base is:

`dhi.io/python@sha256:6258618887b43ee67c5fd867a2d7dc76f21655aef417a4e23115902c5ba05a1e`

Docker Scout verified the signature of the SLSA document retrieved for that
reference with the published DHI key (using the documented skip-tlog mode).
Independent index-to-platform binding remains pending. The document lists libc6
`2.41-12+deb13u4+dhi0`, with package material SHA-256:

`4a8baee075cce76aa3c04e30727fb3a095b4ab48b666a30a7b00b410fddd0f43`

Could you confirm the backport for this exact package material and point us to
its signed package-level provenance and regression-test evidence? We found
the public glibc patch and recipe, but the recipe uses `nocheck`; we therefore
cannot infer that the included regression test was executed. A maintained
upstream reference for the fix would also help.

Separately, our evaluated image reports Expat 2.8.3 via pyexpat and libexpat1
`2.8.3-1~deb13u1+dhi3`. We still need a maintained fix or precise backport
evidence for CVE-2026-66046, CVE-2026-76956, CVE-2026-76957 and CVE-2026-93990,
covering both the shared library and any copy bundled in Python extensions.
Could you direct us to the corrected Python 3.11 Community image digest, or
route this part to a separate case if appropriate?

We have not suppressed findings or approved deployment. This is an evidence
request only, not a request to purchase or activate any paid service.

Thank you.

## Local notes (not part of the reply)

- Do not include repository/CI links, app source, secrets or customer data.
- The support email's Python 3.14 catalog URL is not our Python 3.11 base pin.
- An affirmative email is useful vendor evidence, not a replacement for signed
  evidence bound to the exact image and tests against the derived runtime.
- The existing detailed Expat draft is `docs/dhi-expat-provider-question.md`.

## Follow-up after the automated Gordon response

NOT sent. This shorter clarification is for the human support team in case
00236676; it supersedes resending the full initial question unchanged.

Hello,

Thank you. Please forward this follow-up to the human support team handling
case 00236676 and keep the case open.

There appears to be a version mismatch in Gordon's answer. Our evaluated Expat
package is `2.8.3-1~deb13u1+dhi3`, but the cited recipe specifies
`2.8.3-1~deb13u1+dhi4` and lists patches for CVE-2026-66046, CVE-2026-76956 and
CVE-2026-93990:

https://github.com/docker-hardened-images/catalog/blob/4c77bc608d47ff97eba2024fc5cee0d9643ea5af/package/deb/main/expat/debian-13/2.yaml

Could you please confirm:

1. Whether these fixes require `dhi4`, rather than our evaluated `dhi3`.
2. The immutable digest of a Python 3.11 Debian 13 Community image containing
   the corrected package, and the status of CVE-2026-76957.
3. Image-specific evidence showing whether DHI Python's pyexpat and ElementTree
   extensions use the corrected shared library or another bundled Expat copy.

Our earlier request for signed package-level provenance and regression-test
evidence for the exact libc6 material also remains open. Gordon's lack of
information does not resolve or invalidate your previous confirmation of
the glibc backport.

This remains an information request only. We are not authorizing a paid
subscription or purchase.

Thank you.
