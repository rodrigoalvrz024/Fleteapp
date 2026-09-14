# Revision de las coincidencias altas de DHI

Fecha: 2026-09-14. No autoriza excepciones ni despliegue.

## Evidencia y limites

La [corrida 34879840798](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34879840798)
construyo la imagen `sha256:01435c5264f8a4d89d22222d46c0125df56d7021f53eb0766608c0be46fcea9b`.
Pruebas y guard pasaron. Grype mantuvo 26 High, correspondientes a 13 grupos
CVE/paquete/version y 10 CVE diferentes. Los registros inspeccionados muestran
identidades distintas con el mismo PURL, descubiertas en `/var/lib/dpkg/status`
y `/var/lib/dpkg/status.d/`. No son prueba de dos copias vulnerables en memoria.
No se borra ningun registro ni se cambia el contador oficial.

La primera anotacion de identidades fue truncada por GitHub. Se corrigio el
diagnostico para emitir lotes menores a 3500 bytes, con numero de partes,
total de coincidencias e imagen. No se usa la anotacion truncada como prueba
completa; el resumen del escaner original sigue siendo independiente.

## Acciones por grupo

| Grupo | CVE | High | Decision |
| --- | --- | ---: | --- |
| ncurses/infocmp | CVE-2025-69720 | 8 | Se encontro infocmp en las rutas /usr/bin y /bin. Retirarlo de la candidata DHI, como en la base anterior, y comprobar ausencia; no eximir bibliotecas ni borrar metadatos. |
| util-linux/libuuid1 | CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410 | 8 | No se encontraron mount/umount/nsenter en las rutas consultadas. Esto no prueba ausencia global ni seguridad del host. Mantener controles de privilegios y revisar inventario ELF completo. |
| Expat | CVE-2026-66046, CVE-2026-76956, CVE-2026-76957 | 6 | Requieren revision propia; el proveedor Debian marca 2.8.3 vulnerable y fija arreglos en 2.8.4. No sustituir por sid ni declarar resueltos usando las pruebas anteriores de Python. |
| glibc | CVE-2026-5435 | 2 | Version estable aun marcada vulnerable. Bibliotecas cargadas no equivalen a llamadas a funciones DNS obsoletas; revisar alcance, sin exencion general. |
| zlib | CVE-2026-85091 | 2 | Persiste discrepancia entre rango descrito y version marcada. Mantener abierto hasta contrastar paquete DHI y respuesta del proveedor. |

## Expat: no confundir pruebas

El diagnostico ejecuto dos XML validos y registro Python 3.11.16 / Expat 2.8.3.
Las extensiones pyexpat y ElementTree aparecieron en `/proc/self/maps`; no
aparecio una biblioteca compartida libexpat en esa prueba. No demuestra que
Expat este ausente: las extensiones pueden incorporar codigo estatico.
Se conservan hashes y rutas para comparar la implementacion real.

Una busqueda textual en `backend/app` no encontro llamadas directas a parsers
XML; las menciones SOAP pertenecen al seguro del vehiculo. La busqueda no
descarta llamadas indirectas en dependencias, entradas externas de servicios
ni llamadas dinamicas. No se aprueban los tres avisos por ese motivo.

Las pruebas de cookies, recursion y API de salt anteriores no cubren por si
solas complejidad de atributos, retorno de getentropy ni custom encodings.
Actualizar una biblioteca compartida tampoco basta si Python usa otra copia.

## Fuentes primarias consultadas

- https://security-tracker.debian.org/tracker/CVE-2025-69720
- https://security-tracker.debian.org/tracker/CVE-2026-76642
- https://security-tracker.debian.org/tracker/CVE-2026-78408
- https://security-tracker.debian.org/tracker/CVE-2026-78409
- https://security-tracker.debian.org/tracker/CVE-2026-78410
- https://security-tracker.debian.org/tracker/CVE-2026-66046
- https://security-tracker.debian.org/tracker/CVE-2026-76956
- https://security-tracker.debian.org/tracker/CVE-2026-76957
- https://security-tracker.debian.org/tracker/CVE-2026-5435
- https://security-tracker.debian.org/tracker/CVE-2026-85091

## Cambios de esta ronda

Se agrego diagnostico de identidad del escaner y bibliotecas cargadas, sin
datos de usuarios ni secretos. Se retiro solamente infocmp en la etapa final
de construccion, mediante Python sin requerir shell, retornando a UID 65532.
Se mantuvieron catalogos de paquetes, versiones fijadas y escaneo completo.
Pruebas locales: 41 aprobadas, incluyendo integridad del reporte, lotes
completos, rechazo de evidencia invalida y ausencia de supresiones.
No se cambiaron API, roles, APK, splash ni produccion. No se contrato un plan.

## Resultado final comprobado

Commit `b245bd081f2d2b8fd2ecf67b4820ac49bc065167`.
[Corrida 34880370491](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34880370491),
imagen `sha256:67fbc5325a1c2557418c9f5a2e96b98b0d536516434a19cb1aac5ae3780509cd`.
Pasaron build, dependencias, guard real, suite offline y comprobaciones Python.
El diagnostico de runtime confirmo UID 65532 y ninguna de las rutas de
herramientas consultadas presente, incluyendo ambas rutas de infocmp.

Se recuperaron y analizaron los cuatro lotes JSON completos: 26 filas, misma
imagen, 13 grupos CVE/paquete/version/PURL, cada uno con dos registros de
catalogo (`status` y `status.d`). No se deducen copias binarias duplicadas.
Grype conserva High 26, Critical 0 y 86 coincidencias totales; bloqueo activo.
Retirar infocmp reduce superficie de ataque, no cambia la version del paquete
ncurses que el escaner identifica ni demuestra ausencia de copias renombradas.

Prioridad siguiente: resolver la procedencia y parche de Expat, comprobar el
inventario completo de la nueva imagen y su arranque HTTP/apagado. No se
reutilizan pruebas de la imagen antigua para aprobar una imagen diferente.
