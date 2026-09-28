# Consulta preparada para Docker: Expat en Python 3.11

Estado: borrador tecnico, NO publicado ni enviado. Sin secretos ni datos de usuarios.

## Suggested title

Python 3.11 Debian 13: maintained fixes for all bundled Expat copies, including CVE-2026-93990

## Suggested body

We are evaluating the Community images `dhi.io/python:3.11-debian13` and
`dhi.io/python:3.11-debian13-dev` in an isolated Linux/amd64 CI environment.
Our downstream image reports Python 3.11.16 and Expat 2.8.3 via pyexpat.
The application dependency versions are pinned; we do not replace Python
extensions or Expat in the downstream build.

During bounded valid XML parses, `/proc/self/maps` shows the pyexpat and
ElementTree extensions under `/usr/lib/python3.11/lib-dynload/`, but no
separate libexpat mapping. This is consistent with a bundled implementation,
but we are not treating it as a full linkage proof.

Grype 0.118.0 identifies these Debian advisories for libexpat1
2.8.3-1~deb13u1+dhi3:

- CVE-2026-66046
- CVE-2026-76956
- CVE-2026-76957
- CVE-2026-93990

Debian's tracker lists upstream 2.8.4 fixes for the first three, but also marks
2.8.4 affected by CVE-2026-93990. We see an official DHI Expat 2.8.4 package
definition, but do not regard that alone as sufficient. We do not assume that
updating a shared library would fix a separately bundled copy in Python.

The exact Linux/amd64 evaluation bases resolved on 2026-09-22 are:

- Build: `dhi.io/python@sha256:a7bb712353136de87ec96d2c2d15de48852031aeda75be9196f2ca1825a27766`.
- Runtime: `dhi.io/python@sha256:6258618887b43ee67c5fd867a2d7dc76f21655aef417a4e23115902c5ba05a1e`.

Could you clarify:

1. Which maintained Python 3.11 Debian 13 image/package revision incorporates
   all four fixes in every Expat copy, including the Python extensions and the
   follow-up for CVE-2026-66046 that avoids introducing CVE-2026-76641?
2. Is a release containing those fixes already available in Community?
3. Which source/provenance or package-level patch evidence should downstream
   users verify, if version strings remain 2.8.3 due to backports?
4. Is there a maintained release/backport for the UTF-16 correction tracked as
   CVE-2026-93990, rather than only the update to 2.8.4?

No CVEs have been suppressed in our evaluation. We are seeking a maintained
update or precise patch evidence, rather than a general VEX exemption.

## References

- https://github.com/docker-hardened-images/catalog/blob/0ee2e85afed637f186419f211ca6434b1c8ce690/package/expat/debian-13/2.yaml
- https://github.com/docker-hardened-images/catalog/blob/0ee2e85afed637f186419f211ca6434b1c8ce690/image/python/debian-13/3.11.yaml
- https://github.com/libexpat/libexpat/releases/tag/R_2_8_4
- https://security-tracker.debian.org/tracker/CVE-2026-66046
- https://security-tracker.debian.org/tracker/CVE-2026-76956
- https://security-tracker.debian.org/tracker/CVE-2026-76957
- https://security-tracker.debian.org/tracker/CVE-2026-93990

## Decision local

No se compilan ni reemplazan bibliotecas criticas en produccion por esta
consulta. Los digests anteriores se verificaron en el resumen de la corrida
35686100377, sin publicar su enlace privado en el texto sugerido. El ID Docker
de la imagen derivada no sustituye el digest del proveedor. Borrador actualizado
el 2026-09-22; no se ha publicado ni enviado.
