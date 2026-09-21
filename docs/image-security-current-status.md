# Estado actual de seguridad de la imagen

## Resultado vigente 2026-09-21 (7d9a4a4)

Commit autorizado y subido solo a `codex/mvp-supabase-rls-review`.
[Linux #35](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35629859122)
finalizo en 2m23s con bloqueo de seguridad. Main sigue en 590e8fec.
No hubo despliegue, nueva suscripcion ni ejecucion Hardened/Wolfi para este lote.

- Construccion, consistencia de dependencias, suite de aplicacion y controles
  Linux de descriptores, permisos, arranque no privilegiado y rechazo de root:
  aprobados. Las anotaciones confirman cierre limpio por SIGTERM y comprobaciones
  de seis rutas sin autenticacion. No inferir una prueba completa de produccion.
- Imagen: `sha256:7c7151a4b7e4391ed89ac5e87dc5a0fa1276510da99ad0ce8d5ff13cf339fea4`.
- Grype 0.118.0, Debian 13.7, `2026-09-21T17:08:42.644706036Z`:
  0 Critical, 45 High, 55 Medium, 7 Low, 44 Negligible, 1 Unknown.
  Las cantidades no cambiaron respecto de #34. Ningun aviso fue descontado.
- El nuevo diagnostico funciona: exit 2 con
  `reviewed_python_finding_set_mismatch`, sin declarar aprobacion ni imprimir
  evidencia arbitraria. Las tres CVE de la excepcion anterior siguen ausentes;
  no se debe modificar la autorizacion para forzar un resultado verde.

Los 45 High son coincidencias en paquetes, agrupadas en 12 CVE:

| Grupo | CVE | Coincidencias |
| --- | --- | --- |
| util-linux y paquetes relacionados | 2026-76642, 2026-78408, 2026-78409, 2026-78410 | 32 |
| ncurses | 2025-69720 | 4 |
| glibc | 2026-19499, 2026-5435 | 4 |
| libacl | 2026-54369, 2026-54370 | 2 |
| Python | 2026-82049 | 1 |
| zlib | 2026-85091 | 1 |
| perl-base | 2026-9538 | 1 |

El escaner marca Python como fixed en otra version, zlib como not-fixed y
los restantes como wont-fix para esta fuente/distribucion. Estas etiquetas
no son excepciones ni prueban explotabilidad o ausencia de riesgo en Muvv.
La siguiente evaluacion debe centrarse en una imagen Linux mantenida y minima
con Python actualizado, conservando las protecciones y el escaneo completo.
Las pruebas Windows de Python 3.14 no sustituyen esa evaluacion.

## Avance local de compatibilidad 2026-09-21 (sin nueva imagen)

Se preparo SQLAlchemy 2.0.54 y se corrigio un falso negativo del verificador
de cookies. Python 3.11 y 3.14.7 aprobaron, cada uno, 373 tests unitarios
(2 omitidos por requerir Linux) y 83 de integracion PostgreSQL aislada.
pip-audit reviso 83 dependencias: cero avisos conocidos y cero omitidas.
Ver [evidencia y limites](python314-compatibility.md).

El propietario autorizo commit/push de este lote a la rama de pruebas.
Se completo como 7d9a4a4 y ejecuto #35, descrito arriba. No aprueba Python 3.14
para produccion y no amplia excepciones. Se probo el candidato Linux actual
(Python 3.11), no una imagen 3.14. No autoriza despliegue.

## Resultado anterior 2026-09-21 (04591c3)

[Linux #34](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35624670986)
termino con bloqueo de seguridad, no con fallo de las pruebas de aplicacion.
Imagen: `sha256:e248ce9101e7a64ec6eba5749b87efb60fe9fc7ff858abc64ca12df8dbe132f3`.
Escaneo Grype 0.118.0: `2026-09-21T16:20:07.776096996Z`, Debian 13.7.

- 0 Critical, 45 High, 55 Medium, 7 Low, 44 Negligible, 1 Unknown.
- 358 tests en Linux: 355 aprobados y 3 skips. Incluye las tres nuevas pruebas
  de regresion AnyIO. Desaparecieron un Critical y un Medium respecto de #33.
- No se aplico ninguna excepcion ni descuento de hallazgos.
- Solo corrio Linux: los filtros de rutas de Hardened y Wolfi no incluyen
  requirements.txt. Sus resultados anteriores NO validan este nuevo commit.

La tabla contiene 44 coincidencias High del sistema operativo y una de Python,
CVE-2026-82049. Las tres CVE de la autorizacion anterior (3644, 4224 y 7210 de
2026) ya no figuran. Por tanto, el primer rechazo en la politica actual es que
no existe el conjunto exacto autorizado; ocurre ANTES de comprobar los hashes.
El hash distinto de pyexpat sigue siendo otra incompatibilidad independiente
con aquella evidencia, pero no debe presentarse como el primer fallo de #34.
No restar tres a 45: no hay tres hallazgos reconocidos en este escaneo.

El [aviso oficial Python del 14 de septiembre](https://mail.python.org/archives/list/security-announce@python.org/thread/EFJWGAZJA56AKSBR2WHMHQZO7RRLZPRH/)
describe CVE-2026-82049 como un bypass de los filtros TAR mediante enlaces.
La busqueda local de tarfile, unpack_archive, extractall y .extract( no encontro
llamadas en backend/app ni en los Dockerfiles revisados. Esto no cubre codigo
de dependencias ni rutas dinamicas, y NO permite descartar la vulnerabilidad.
El arreglo publicado para otra rama de Python no acredita un arreglo en 3.11.16.

Se preparo localmente un diagnostico mas claro del control: codigos fijos para
conjunto de hallazgos distinto y hash distinto; el resto conserva el error
generico. No imprime evidencia no confiable, mantiene exit 2 y todos los avisos
originales, sin reconocer correcciones ni cambiar hashes, fechas o condiciones.
Pruebas de politica y revision: 21 aprobadas. Suite completa local: 371 aprobadas,
2 skips (373 total). Incluye controles de hashes maliciosos, avisos ausentes o
duplicados y aprobacion vencida. Este diagnostico forma parte del lote
autorizado para commit/push descrito arriba.

Siguiente: evaluar una base mantenida con Python corregido y las bibliotecas
del sistema pendientes, antes de proponer otra construccion. No relanzar sin
cambios, no retocar la lista autorizada para obtener verde y no desplegar.

## Nuevas corridas de CI 2026-09-21 (180b11b)

Estado: BLOQUEADA. Las tres corridas terminaron; no se desplego en Railway.
Estos resultados reemplazan el estado vigente del seguimiento anterior, que
se conserva debajo como historial.

| Candidato | Resultado original del escaner | Alcance |
| --- | --- | --- |
| [Linux #33](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35622327545) | 1 Critical, 45 High, 56 Medium, 7 Low, 44 Negligible, 1 Unknown | Imagen de la aplicacion. |
| [Hardened #9](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35622327577) | 1 Critical, 30 High, 37 Medium, 2 Low, 20 Negligible | Imagen de la aplicacion; puede haber coincidencias duplicadas entre fuentes. |
| [Wolfi #3](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35622327688) | 0 Critical, 1 High, 5 Medium, 1 Low | Solo imagen base: bloqueo antes de construir Muvv. |

Las cantidades son coincidencias, no vulnerabilidades distintas ni ataques
demostrados. Linux y Hardened ejecutaron 355 tests, con resultado OK y 3 skips.
Los 15 tests de configuracion de workflows/Dockerfiles del repositorio no se
ejecutan dentro de la imagen: dos clases se omiten al no montar esos archivos.
No confundir este resultado con el total de pruebas locales.

Linux: `sha256:b8aa026aedb9cec075e9c2ae1dc6117b876b085472f0f7825b8f667abbd17bae`,
escaneo `2026-09-21T15:58:55.21420749Z`. La politica termino con exit 2:
`Image policy evidence invalid, missing or expired; not approved.`
El hash de pyexpat observado fue
`09cda70b60a3ffd5f17efbafbf65bc26d6e32c264a78eaebdf154b9b4845d749`,
distinto del aprobado
`27e28ee2600c7d6347130227616e4fd5ae1c59800ad01fa12e1f23c6f41f34e3`.
La revision estatica independiente confirma que esa diferencia basta para
bloquear; no prueba que sea el unico motivo ni que el binario sea vulnerable.
No se descuentan las tres correcciones Python de los 45 High y no se cambia
la evidencia autorizada para hacer pasar el control.

Wolfi verifico firmas y escaneo la base runtime
`cgr.dev/chainguard/python@sha256:1206ffee8644e6338b3fc8b6e5dc384b03d91ad1df1d6b74fa4255544ac51ad2`.
El High es CVE-2026-19499 en `glibc-2.44 2.44-r6`. La desaparicion del aviso
anterior de zlib no aprueba esta base ni demuestra compatibilidad con Muvv.

El Critical nuevo de las imagenes de aplicacion corresponde a AnyIO. Se preparo
una [correccion local y pruebas de regresion](anyio-security-update.md), aun
sin una nueva imagen Linux verificada. Produccion sigue sin cambios.

## Seguimiento previo 2026-09-21

Consulta de fuentes oficiales, no un nuevo escaneo. El ultimo resultado de CI
registrado corresponde a `171c757`, imagen
`sha256:e8a7f80a4f9485349b84c05df47845a782de098d1289e3c9b2362fcef0fd7c55`,
con 44 coincidencias High pendientes despues de las tres correcciones Python
ya autorizadas. Ver [resultado exacto](storage-dependency-cleanup.md).
Los resultados historicos que siguen se conservan sin reescribirlos.

Hay una novedad concreta en zlib: upstream publico el
[arreglo df84af2](https://github.com/madler/zlib/commit/df84af25dc1942490e1d1c899a07619152a46148)
para CVE-2026-85091 y la consulta #1310 ahora figura cerrada. La
[receta Wolfi](https://github.com/wolfi-dev/os/blob/main/zlib.yaml) consultada
usa `1.3.2.1_rc20260601-r0` con un parche para el mismo manejo del buffer.
Esto reemplaza la observacion anterior de que no habia evidencia de arreglo;
NO acredita que la imagen Muvv anterior contenga ese cambio.

La [pagina actual de Python de Chainguard](https://images.chainguard.dev/directory/image/python/vulnerabilities)
ya no muestra zlib en su tabla, pero si muestra CVE-2026-19499 como High en
`glibc-2.44 2.44-r6`, ademas de cinco Medium y un Low. No se obtuvo un nuevo
digest ni se verifico firma/SBOM: es informacion del proveedor, no resultado
de nuestro escaner. No equivale a una base aprobada ni a compatibilidad de Muvv.

En Debian trixie siguen figurando vulnerables las versiones estables de
[glibc monetario](https://security-tracker.debian.org/tracker/CVE-2026-19499),
[glibc DNS](https://security-tracker.debian.org/tracker/CVE-2026-5435),
[util-linux](https://security-tracker.debian.org/tracker/CVE-2026-76642) y
[ACL](https://security-tracker.debian.org/tracker/CVE-2026-54369).
Debian ahora enlaza el arreglo upstream de
[zlib](https://security-tracker.debian.org/tracker/CVE-2026-85091), pero mantiene
sus paquetes listados como vulnerables. No mezclar paquetes sid con trixie.

Decision: mantener bloqueo, sin cambiar excepciones, versiones de dependencias
ni imagen de Railway. Antes de repetir la comparacion Wolfi, revisar una
actualizacion mantenida de glibc o solicitar al proveedor evidencia especifica
de ese aviso. La consulta anterior centrada en zlib ya no debe enviarse sin
actualizarla. No se envio ninguna consulta ni se contrato ningun servicio.

En paralelo, las [pruebas TLS](database-tls-preflight.md) locales y una conexion
real autorizada desde este PC al pooler Supabase pasaron con `verify-full` y
modo de solo lectura, sin consultas a tablas. El operador descargo el certificado
tras el bloqueo inicial de Chrome; no se desactivaron protecciones. La
configuracion efectiva y conectividad desde Railway siguen pendientes. Este
resultado no elimina avisos del contenedor ni autoriza desplegar.

## Revision anterior

Fecha de revision: 2026-09-15 (America/Santiago).
Estado: BLOQUEADA. No modifica autorizaciones, excepciones ni produccion.

## Evidencia exacta

- Commit: `7d4e9a6caed754ac54e487794da962f1e51cbb4b`.
- [Corrida 35045218540](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35045218540).
- Imagen: `sha256:b49572f8674087c85d41b5adeb14353ba14b966bb99bfd959852006b51cb5f04`.
- Escaneo UTC: `2026-09-16T01:46:21.555150705Z`.
- Originales: 0 Critical, 47 High, 51 Medium, 9 Low, 44 Negligible, 4 Unknown.
- Tres correcciones Python reconocidas segun la autorizacion existente.
- Pendientes High: 44 coincidencias de paquetes, correspondientes a 11 CVE.

Los 44 registros no son 44 vulnerabilidades independientes ni 44 ataques
demostrados. Tampoco es correcto descartarlos porque las pruebas funcionales
pasen. Los 11 CVE siguen abiertos y el control conserva las filas originales.

## Matriz de trabajo

| Familia | CVE distintos | Coincidencias High pendientes | Siguiente accion |
| --- | ---: | ---: | --- |
| util-linux | 4 | 32 | Version estable corregida o revision acotada de componentes y privilegios del hosting; no confundir controles no-root con parche. |
| glibc | 2 | 4 | Revisar llamadas nativas DNS y formato monetario; esperar actualizacion estable o evidencia revisada por aviso. |
| ncurses | 1 | 4 | La herramienta infocmp fue retirada, pero siguen registros y bibliotecas. Revisar alcance completo antes de proponer disposicion. |
| ACL | 2 | 2 | Esperar paquete mantenido compatible; cambios de ABI desaconsejan parches individuales improvisados. |
| Perl | 1 | 1 | Conservar evidencia de ausencia del modulo afectado y revisar uso operativo. |
| zlib | 1 | 1 | Resolver discrepancia entre rango publicado y version instalada con el proveedor; no declarar falso positivo. |
| Total | 11 | 44 | Sin excepciones nuevas ni autorizacion de despliegue. |

## Cambio del contador de 42 a 44

El aviso adicional es [CVE-2026-19499](https://security-tracker.debian.org/tracker/CVE-2026-19499),
registrado para `libc-bin` y `libc6`, ambos `2.41-12+deb13u4`.
El proveedor describe escritura fuera del buffer en `strfmon`/`strfmon_l`
al aplicar determinado relleno de ancho. No es un fallo demostrado en la
logica de precios de Muvv. La descripcion no acredita que sea inalcanzable.

No se encontraron llamadas directas a `strfmon`, `setlocale` ni
`locale.currency` en `backend/app`. Hay uso de ctypes en el guard de arranque
para prctl y close_range; no es una llamada al formateador monetario. Esta
busqueda no cubre todas las dependencias ni las llamadas dinamicas.

Se amplia el inventario ELF existente con `monetary_format`, incluyendo
simbolos publicos, internos conocidos y nombres versionados. Se distinguen
imports de exports: que libc exporte la funcion no demuestra que Muvv la llame.
No se ejecutan payloads contra el servidor ni se leen documentos o dinero real.
Los informes previos NO recopilaron ese grupo: no equivalen a cero llamadas.
El nuevo inventario aun debe ejecutarse en Linux sobre una imagen concreta.

## Disponibilidad reconsultada

Consultas de solo lectura del 15 de septiembre, sin instalaciones:

- [glibc: formato monetario](https://security-tracker.debian.org/tracker/CVE-2026-19499)
  y [DNS](https://security-tracker.debian.org/tracker/CVE-2026-5435): trixie sigue
  marcado vulnerable; el arreglo listado no esta en la version estable usada.
- [util-linux](https://security-tracker.debian.org/tracker/CVE-2026-76642): arreglo
  listado en sid, no justifica mezclar esa distribucion con trixie.
- [ACL](https://security-tracker.debian.org/tracker/CVE-2026-54369): Debian indica
  esperar actualizacion del paquete; no hacer backports individuales a ciegas.
- [zlib](https://security-tracker.debian.org/tracker/CVE-2026-85091): estable aun
  marcado vulnerable; la [consulta upstream](https://github.com/madler/zlib/issues/1310)
  sigue abierta sin una resolucion verificable en la pagina consultada.

## Plan para desbloquear, sin repetir builds identicos

1. Ejecutar el inventario ampliado y revisar el nuevo aviso de glibc en la
   imagen exacta. Conservar las limitaciones de busqueda estatica/dinamica.
2. Continuar consultas concretas a proveedores ya preparadas para DHI y Wolfi;
   no contratar servicios ni enviar datos/consultas en nombre del propietario
   sin autorizacion. Las comparaciones anteriores tambien quedaron bloqueadas.
3. Elegir una actualizacion mantenida que resuelva los avisos, o encargar una
   evaluacion independiente por CVE con alcance, pruebas, vencimiento y
   condiciones de invalidacion. No aceptar riesgos implicitamente.
4. Solo tras resolver el control de imagen, verificar PostgreSQL/TLS y hosting
   aislado, luego desplegar backend compatible y actualizar la APK con permiso.

No requiere cambiar el plan de Railway ni pagar por Docker para preparar
estas pruebas. No se inicia un servicio nuevo. Una eventual ejecucion de CI
utilizara la cuota existente de GitHub Actions; servicios externos se cotizan
y autorizan por separado. No hay promesa de cero costo por consumos del plan.

## Verificacion de esta ampliacion

Suite local: 346 pruebas ejecutadas, 345 aprobadas y una omitida por requerir
Linux. Dos regresiones nuevas comprueban simbolos monetarios versionados,
separacion entre imports/exports, identidad de imagen y limites del informe.
Segunda revision estatica: sin hallazgos P1/P2 en este diff acotado; no ejecuto
inventarios ni verifico de forma independiente fuentes externas o escaneos.

El propietario autorizo commit/push de estos tres archivos a la rama de pruebas
y ejecucion en GitHub, sin despliegue. El resultado Linux se registrara tras
la corrida; las pruebas locales no demuestran cuantos callers tiene la imagen
ni resuelven alguno de los 44 registros pendientes.
