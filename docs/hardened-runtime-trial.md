# Evaluacion de una imagen mantenida y reducida

Fecha: 2026-09-14. Estado: preparada, descarga autenticada pendiente. No es
una sustitucion del Dockerfile actual ni una aprobacion de produccion.

## Objetivo

Probar Docker Hardened Images Community con Python 3.11 y Debian 13 para
reducir varios componentes innecesarios juntos. No cambiar versiones de las
dependencias de la API, aplicar excepciones ni mezclar Debian sid.
Una imagen comercializada como endurecida no se considera libre de fallos
sin analizar el paquete exacto que contiene Muvv.

Se evaluaron tambien los metadatos publicos de los paquetes DHI para trixie:
los sufijos `dhi` no prueban por si solos que esten corregidos los CVE abiertos.
No se instalo ese repositorio ni se sustituyeron bibliotecas de produccion.

Referencias: [Python DHI](https://hub.docker.com/hardened-images/catalog/dhi/python/guides),
[inicio Community](https://docs.docker.com/dhi/get-started/),
[alcance de paquetes publicos y pagos](https://docs.docker.com/dhi/how-to/hardened-packages/).

## Preparacion realizada

- `backend/Dockerfile.hardened`: archivo alternativo; builder dev separado del
  runtime. Copia solo venv y app, conserva requirements y usa UID/GID 65532.
  Codigo root-owned sin escritura de grupo/otros y mismo guard `app.server`.
  Solo acepta wheels; no instala compiladores en el runtime.
- `.github/workflows/backend-hardened-trial.yml`: solo rama de revision,
  permisos GitHub de lectura, sin push de imagen, migracion real o deploy.
  Resuelve las dos bases Community por digest antes de construir. Mantiene
  las credenciales unicamente en una carpeta temporal durante pull/build;
  se eliminan al terminar incluso si falla. No llegan al Dockerfile ni a capas.
- La evaluacion exige el guard real, Python 3.11.16, pip check, suite offline,
  backports y escaner completo existente, sin VEX automatico ni ignores.
  Si DHI publica otra version, se detiene para revisarla.
- Pruebas locales: 119 seleccionadas, 118 aprobadas y una omitida por Linux.
  Cinco pruebas nuevas revisan configuracion y aislamiento; siete bloques
  Bash pasaron comprobacion sintactica sin ejecutar sus comandos.

Las pruebas de configuracion del workflow son locales. Se omiten dentro de
contenedores donde no se montan `.github` ni Dockerfile.hardened; no se
presentan como una compilacion del runtime nuevo. La descarga anonima de
`dhi.io/python:3.11-debian13` devolvio HTTP 401.

## Lo que debe hacer el propietario

1. Iniciar sesion o crear cuenta en [Docker Hub](https://hub.docker.com/).
   Usar Community/Personal; no contratar Select, Enterprise ni una prueba paga.
   No es necesario instalar Docker Desktop en el PC para esta evaluacion.
2. En [Docker Home](https://app.docker.com/): avatar, Account settings,
   Personal access tokens, Generate new token. Nombre `Muvv CI lectura`,
   permiso **Read** y vencimiento corto (por ejemplo, 30 dias).
   Si la cuenta no permite Read sin contratar un plan, detenerse y avisar;
   no sustituirlo silenciosamente por una clave con Write/Delete.
3. En [secretos de GitHub Actions de Fleteapp](https://github.com/rodrigoalvrz024/Fleteapp/settings/secrets/actions),
   pulsar New repository secret y crear:
   `DHI_USERNAME` con el nombre de usuario Docker (no necesariamente el correo),
   y `DHI_READ_TOKEN` con ese token de lectura.
4. No pegar claves en el chat, Railway, archivos `.env`, commits ni capturas.
   Avisar cuando esten guardados. Reejecutar la evaluacion de la rama de revision.

Guia oficial del token:
[Personal access tokens](https://docs.docker.com/security/access-tokens/personal-access-tokens/).
El workflow no puede demostrar solo por el nombre del secreto que el token
sea de lectura; ese alcance se configura y verifica en Docker.

## Costos y limites

DHI Community es gratuito segun Docker. Eso no promete cero costo total:
GitHub Actions puede consumir minutos/cuota y Railway mantiene su plan actual.
No se activo ninguna suscripcion, trial pago, servidor ni base adicional.
Funciones de parches personalizados, SLA y cumplimiento pueden pertenecer a
planes pagados; no se presupone acceso ni necesidad de contratarlos.

## Antes de adoptar la alternativa

1. Obtener la imagen y comparar numero real de paquetes, versiones y CVE con
   la candidata actual. Menos avisos sin deteccion correcta de paquetes no basta.
2. Verificar firmas/procedencia del proveedor y compatibilidad builder/runtime.
   Resolver por digest asegura identidad, pero no sustituye la firma.
3. Adaptar y ejecutar el inventario/permisos y observacion XML para las rutas
   nativas reales de DHI. No copiar las huellas de la imagen anterior ni debilitar
   las comprobaciones para que pasen con una estructura diferente.
4. Probar CMD real, HTTP, SIGTERM, migraciones en datos ficticios, TLS con
   PostgreSQL/Storage y comportamiento del hosting sin shell en el runtime.
   La sonda de guard y las unitarias iniciales no reemplazan estas pruebas.
5. Solo entonces decidir promocion por separado. La candidata anterior sigue
   bloqueada por 45 coincidencias altas; la nueva no tiene escaneo valido aun.

La aprobacion pendiente de los tres arreglos Python es independiente de esta
evaluacion. No se interpreto "sigamos" como autorizacion para excluirlos.

## Resultado del primer intento

Commit preparado: `02305a6956c764b7a93bb714c1d3d42dec945899`.
[Evaluacion DHI 34872463423](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34872463423)
bloqueada en `Require read-only registry access`: falta uno o ambos secretos.
Checkout, descargas, build, pruebas y escaner de la alternativa no se ejecutaron.
No es un fallo de la API ni evidencia de que DHI tenga cero vulnerabilidades.

La [candidata actual 34872463273](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34872463273)
paso pruebas, arranque, permisos, inventario y traza. Su escaner mantuvo 45 High,
49 Medium y 0 Critical (155 coincidencias), sin cambios de politica.
Imagen actual comprobada: `sha256:390888a331a9a12e4bd9ddd1507bc7a09e4445150b8e0c75e2b387883b7ee525`.

## Correccion de construccion: Cloudinary

El intento 3 supero el control de secretos y llego al build. Fallo porque
`cloudinary==1.40.0` solo publica un sdist, incompatible con `--only-binary=:all:`.
Se conserva esa version y se genera su wheel exclusivamente en el builder,
desde la URL oficial de PyPI y con SHA-256 fijado. Se usan las herramientas de
build ya fijadas, sin resolver dependencias adicionales durante ese paso.
La instalacion restante sigue exigiendo wheels; ni el archivo fuente ni el
directorio de wheels se copian al runtime. Esto corrige el empaquetado, no
declara resueltas vulnerabilidades ni autoriza un despliegue.

Metadatos verificados: https://pypi.org/pypi/cloudinary/1.40.0/json
SHA-256: `fe1a5309734814b481de637ab3041e8699995387df965ec0f2d8f767db7067a2`.

### Verificacion de la correccion

Commit `39aabbc96b1b81ef28f3b21fb30ada97c645e5a1`.
Construccion local del wheel universal correcta y 6 pruebas de configuracion
aprobadas. La [evaluacion 34878869225](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34878869225)
construyo la imagen y paso guard real, pip check, suite offline y regresiones
Python. El escaner completo termino y bloqueo: Critical 0, High 26, Medium 30,
Low 2, Negligible 20, Unknown 8; 86 coincidencias y 0 package alerts.
Imagen: `sha256:11b72e870ad5bfe4b97674e0370504667557ab532387c0dc70aaf1aec05d7988`.

Las 26 coincidencias altas agrupan 10 CVE diferentes. Hay filas duplicadas en
los detalles publicados; falta revisar el inventario completo para determinar
si son registros duplicados o componentes distintos. No se interpreta la
diferencia 45 -> 26 como 19 vulnerabilidades corregidas: cambia la composicion
de paquetes y aparecen avisos de libexpat1 que requieren analisis propio.
No se modifico el filtro del escaner, no hubo excepciones ni despliegue.
Siguen pendientes todas las validaciones de adopcion descritas arriba.

## Diagnostico completo sin relajar bloqueos: 2026-09-21

La [evaluacion DHI 35676690697](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35676690697)
del commit `90b854e` supero construccion, dependencias y pruebas iniciales.
El control de filesystem rechazo dos enlaces no resueltos:
`/usr/share/zoneinfo/localtime` y `/usr/share/doc/base-files/FAQ`.
Inventario nativo, escaneo y pruebas posteriores de arranque quedaron omitidos;
esto no prueba que la imagen carezca de vulnerabilidades.

El nuevo lote local permite inventario y escaneo tras construir correctamente,
incluso si falla un control anterior, pero nunca tras cancelacion o build fallido.
Los fallos siguen bloqueando el job. El reporte obligatorio del escaner se evalua
antes del diagnostico, en un paso separado, sin `continue-on-error` ni exclusiones.
La sonda usa el mismo digest, UID/GID 65532, sin red, filesystem de solo lectura,
sin capacidades y con limites de recursos. El inventario exporta sin arrancar
la imagen y tiene timeout; solo se publica metadata JSON tras exito.

Verificacion local: 465 casos en Python 3.11 y Python 3.14, con 462 aprobados y
3 omitidos por plataforma en cada version; 12 pruebas de configuracion DHI.
Revision independiente estatica sin hallazgos P1/P2. La ejecucion real en Linux
de este lote aun esta pendiente; las pruebas locales no la sustituyen.
Un timeout del job puede impedir completar el diagnostico y no debe interpretarse
como resultado limpio. Commit, push y consumo de Actions requieren autorizacion
para este lote. Sin despliegue, cambios en Railway ni APK.

### Avisos que siguen abiertos

Los ultimos escaneos completos de las candidatas clasica y Python 3.14 reportaron
45 y 44 coincidencias altas, respectivamente. No son recuentos de CVE unicas.
La diferencia incluye [CVE-2026-82049](https://security-tracker.debian.org/tracker/CVE-2026-82049),
relativa a filtros de extraccion TAR en Python hasta 3.13. No se encontraron
llamadas de extraccion TAR en `backend/app`; esto no descarta exposicion indirecta
en dependencias. El estado no afectado de una version Debian sin esos filtros
no se extrapola al Python upstream 3.11.16 de la candidata.

La consulta a fuentes primarias mantiene pendientes los avisos de
[glibc strfmon](https://security-tracker.debian.org/tracker/CVE-2026-19499),
[glibc DNS](https://security-tracker.debian.org/tracker/CVE-2026-5435),
[libacl](https://security-tracker.debian.org/tracker/CVE-2026-54369) y
[zlib](https://security-tracker.debian.org/tracker/CVE-2026-85091) para las versiones
evaluadas. Una correccion en otra distribucion o rama no prueba que estas imagenes
esten corregidas. No se cambian paquetes, hashes aprobados, politica de CVE ni
la aprobacion anterior de tres correcciones Python. Estado de promocion: NO-GO.

## Resultado Linux del lote d6f0290

Commit autorizado y publicado: `d6f029081f4e618b6bfa85de97b8aa4445e6e233`,
solo en `codex/mvp-supabase-rls-review`. `main` conserva
`590e8fec432f094619355dad89dcb068c4bd649f`. Sin despliegue ni APK.
Ejecuciones terminadas el 2026-09-22 UTC (2026-09-21 en Chile).

| Evaluacion | Critical | High | Medium | Resultado |
| --- | ---: | ---: | ---: | --- |
| [Clasica](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35678405126) | 0 | 45 | 55 | Pruebas y arranque aprobados; escaneo bloqueado |
| [Python 3.14](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35678405136) | 0 | 44 | 51 | Pruebas, arranque y PostgreSQL/TLS aprobados; escaneo bloqueado |
| [DHI](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35678405218) | 0 | 30 | 36 | Pruebas iniciales aprobadas; filesystem y escaneo bloqueados |

Identidades exactas:

- Clasica: `sha256:9d3f7bfb7080be62210253b8aced9875cea07223b4be019a330be6c98ea9e1c4`.
- Python 3.14: `sha256:b3f63180a3e0ed3ae774511d9aebc8f441c40fce8ce27e0d9bafae2a23810249`.
- DHI: `sha256:a9d5b935e5502f23cd35d6079651b1b5e3d032df36cc1eb96c26ec48e2069296`.

En DHI se confirmo el comportamiento nuevo: despues del fallo de filesystem,
inventario nativo y publicacion de metadata terminaron correctamente; el escaneo
completo reporto los hallazgos y fallo; el diagnostico separado termino bien.
El job sigue fallido. Arranque real y rechazo del CMD bajo root siguen OMITIDOS,
no aprobados. Persisten los dos enlaces sin destino ya documentados arriba.

El escaneo DHI (Grype 0.118.0, 2026-09-22T02:11:10.961136441Z) registro
88 coincidencias: 0 Critical, 30 High, 36 Medium, 2 Low, 20 Negligible y 0 Unknown;
0 package alerts. Los 30 High agrupan 12 CVE y 15 combinaciones CVE/paquete/version.
Cada combinacion figura en `/var/lib/dpkg/status` y en un registro `status.d`.
Esto explica la doble procedencia del catalogo, no prueba dos copias binarias,
no acredita un parche y no autoriza eliminar coincidencias.

| Grupo de paquete | CVE High | Filas High |
| --- | --- | ---: |
| libc6 | CVE-2026-19499, CVE-2026-5435 | 4 |
| libexpat1 | CVE-2026-66046, CVE-2026-76956, CVE-2026-76957, CVE-2026-93990 | 8 |
| libuuid1 | CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410 | 8 |
| libncursesw6, libtinfo6, ncurses-base, ncurses-bin | CVE-2025-69720 | 8 |
| zlib1g | CVE-2026-85091 | 2 |

El inventario DHI analizo 435 ELF y no encontro los nombres conocidos infocmp,
nsenter, getfacl, setfacl, chacl ni Archive/Tar.pm. Hay 16 archivos con imports
de carga dinamica. La ausencia de imports directos o nombres no demuestra
ausencia de copias renombradas, enlaces estaticos o exposicion dinamica.
Las pruebas de parseo sintetico no prueban seguridad del parser.

La candidata clasica mantiene el bloqueo `reviewed_python_finding_set_mismatch`:
los tres avisos previamente autorizados no figuran y cambio la huella pyexpat.
No se renovaron huellas ni autorizaciones. No se interpreta el menor recuento
DHI frente a las otras imagenes como vulnerabilidades corregidas.

Siguiente lote: revisar los destinos exactos de los dos enlaces DHI con metadata
acotada, sin exceptuar enlaces rotos; contrastar los cuatro avisos libexpat1 con
la procedencia del paquete mantenido; decidir correcciones antes de otra CI.
No repetir construcciones sin cambios o nueva evidencia. Estado final: NO-GO.

## Revision XML y diagnostico acotado de enlaces (local, 2026-09-21)

Este lote no modifica la imagen, no elimina enlaces ni cambia el veredicto de
seguridad. Solo clasifica destinos conocidos de los dos enlaces pendientes:
`/etc/localtime` (absoluto o relativo) y `FAQ.gz` (absoluto o relativo).
Son hipotesis de diagnostico, NO destinos observados todavia en DHI. Cualquier
otro texto se publica como `unrecognized`, sin registrar su valor ni el mensaje
de excepcion. Se mantienen las comprobaciones de cada antecesor, limites de
resolucion, permisos y errores. No hay lecturas de contenido ni enumeracion nueva.
La siguiente prueba Linux debe identificar el destino antes de decidir una
reparacion; no se borran archivos del proveedor para conseguir un check verde.

### Estado de Expat segun fuentes primarias

Consulta del 2026-09-22 UTC, correspondiente al 21 de septiembre en Chile:

| Aviso | Estado publicado | Decision para la candidata |
| --- | --- | --- |
| [CVE-2026-66046](https://security-tracker.debian.org/tracker/CVE-2026-66046) | Corregido upstream 2.8.4; el conjunto requiere un arreglo adicional para evitar CVE-2026-76641. | No copiar un parche aislado; falta paquete mantenido compatible acreditado. |
| [CVE-2026-76956](https://security-tracker.debian.org/tracker/CVE-2026-76956) | Afecta 2.8.2/2.8.3; corregido en 2.8.4. | Tener API de hash de 16 bytes no demuestra calidad de entropia ni cierre de este aviso. |
| [CVE-2026-76957](https://security-tracker.debian.org/tracker/CVE-2026-76957) | Corregido en 2.8.4; trixie 2.8.3 sigue marcado vulnerable. | Parsear XML valido no prueba seguridad de callbacks de codificacion. |
| [CVE-2026-93990](https://security-tracker.debian.org/tracker/CVE-2026-93990) | Incluye 2.8.4; Debian lista arreglos upstream pero paquetes aun vulnerables. | Actualizar solamente a 2.8.4 no cierra los cuatro avisos. |

El [feed publico de Docker](https://raw.githubusercontent.com/docker-hardened-images/advisories/main/vex/python/dhi-python.vex.json)
contiene declaraciones `not_affected` para los tres primeros avisos del paquete
`expat@2.8.3-1~deb13u1+dhi3`, justificadas por la clasificacion Debian `no-dsa`.
Esa nota no acredita por si misma un parche ni inalcanzabilidad en Muvv. No se
aplico el feed al escaner ni se verifico una atestacion firmada del digest;
los hallazgos se conservan. La documentacion de
[Docker sobre VEX](https://docs.docker.com/guides/dhi-vex-walkthrough/)
exige distinguir los motivos y productos de cada declaracion.

### Exposicion revisada y pruebas locales

Los servicios propios de documentos, evidencia, chat y fotos de carga usan
Supabase/HTTPX y bytes de imagen. Se agregaron 96 subcasos: cuatro servicios,
tres contenidos (XML, SVG, XML UTF-16) y ocho combinaciones MIME/extension.
Todos exigen HTTPException 400 y ninguna escritura en storage, incluyendo
contenido XML declarado JPG, PNG, WEBP, HEIC o PDF. Esto valida el servicio,
no un recorrido HTTP completo, ni archivos poliglotas o XML embebido.

La revision independiente no encontro llamadas directas XML explotables en
los flujos propios revisados, pero identifico consumidores XML instalados:
`google-cloud-storage==3.14.1` y `google-resumable-media==2.8.2` procesan respuestas
multipart con ElementTree. Firebase Admin los incluye transitivamente. No se
encontro que Muvv use esos flujos: usa Supabase para archivos y Firebase Messaging
para notificaciones. Esto NO prueba inalcanzabilidad global ni de la imagen DHI.
No se retiran dependencias transitivas arbitrariamente ni se descuentan CVE.

Verificacion del lote: 67 pruebas del verificador aprobadas; suite completa en
Python 3.11 y 3.14 con 472 casos, 469 aprobados y 3 omisiones por plataforma en
cada version. Revision independiente sin hallazgos P1/P2 en el diff actual.
Sin commit/push de este nuevo lote, sin nueva CI ni despliegue. Siguiente paso:
autorizar su validacion Linux; luego reparar unicamente con destinos observados
y exigir evidencia de correccion mantenida para XML. La promocion sigue NO-GO.
