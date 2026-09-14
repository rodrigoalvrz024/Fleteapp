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
