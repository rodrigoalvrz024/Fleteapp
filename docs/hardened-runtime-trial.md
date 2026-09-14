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
