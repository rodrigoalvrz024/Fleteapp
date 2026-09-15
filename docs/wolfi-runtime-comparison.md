# Comparacion aislada de runtime Wolfi

Fecha: 2026-09-15. Experimental: NO sustituye el Dockerfile actual, no autoriza
produccion ni aplica las disposiciones Python a una imagen nueva.

## Motivo y alcance

La candidata actual conserva 45 coincidencias altas originales, de las cuales
tres tienen correccion verificada autorizada y 42 siguen pendientes. La prueba
DHI anterior tambien mantiene avisos propios. En lugar de recompilar la misma
base, se evalua una familia mantenida diferente con menos componentes.

Se usa la opcion publica Starter de Chainguard para Python, basada en Wolfi.
El proveedor documenta `cgr.dev/chainguard/python:latest` y `latest-dev` como
variantes publicas. La etiqueta gratuita sigue Python reciente: eso puede
requerir cambios de compatibilidad y no garantiza una version fija disponible
gratuitamente a futuro. No se cambia Python en produccion por esta comparacion.

Fuentes primarias:
[imagen y variantes](https://images.chainguard.dev/directory/image/python/overview),
[identidad de firma de la opcion gratuita](https://images.chainguard.dev/directory/image/python/provenance).

## Barreras

- Workflow solo para archivos de esta comparacion en la rama de pruebas,
  permisos GitHub de lectura, sin secretos de repositorio ni token de escritura.
- Cosign 3.1.3 y Grype 0.118.0 fijados por version y SHA-256. La huella Cosign
  se obtuvo del asset oficial de GitHub; esto confia en GitHub/TLS para el
  bootstrap de la herramienta, no es una atestacion independiente de Cosign.
- Descarga las dos bases, resuelve sus digests y verifica firma keyless con
  issuer e identidad exactos publicados para Free. No omite transparency log,
  validacion de certificados ni errores. No ejecuta las bases antes de verificar.
- Usa esos mismos digests para el build; no vuelve a resolver `latest` dentro
  del Dockerfile. Dev y runtime deben ser compatibles para que funcione el venv.
- Primer escaneo: base sin modificar, con catalogo APK presente y deteccion
  explicita Wolfi. Un informe sin deteccion esperada o un High/Critical detiene
  el trabajo antes de instalar Muvv; no se contabiliza como base limpia.
- Build multietapa: mismos requirements, wheel de Cloudinary con hash revisado,
  resto solo wheels, sin copiar `.env`, secretos ni todo el repositorio. Si no
  existe un wheel compatible se detiene: no actualiza pins automaticamente.
- Runtime UID/GID 65532, mismo guard de privilegios, no shell agregado, codigo
  root-owned sin escritura por app. Pruebas sin red y con datos sinteticos.
- Comprobar unitarias, permisos, CMD real, HTTP protegido, Alembic heads y
  apagado SIGTERM. Leer heads no aplica una migracion.
- Ultimo escaneo: imagen completa de Muvv con el escaner original, sin reconocer
  los tres arreglos de otra imagen. Cero cambios en ignores, umbrales o VEX.

El escaneo de una base vacia NO equivale al de Muvv con todas sus dependencias.
Las firmas prueban procedencia bajo esa identidad, no ausencia de vulnerabilidades.
Los controles de permisos de esta comparacion tampoco sustituyen inventario ELF,
revision de capacidades de archivos, base de datos real, TLS o pruebas del hosting.

## Costos y decisiones pendientes

No se contratan planes, servicios ni cuentas. La ejecucion utiliza minutos y
artefactos de la cuota existente de GitHub Actions. Firmas conservadas 14 dias.
Si el acceso publico requiere autenticacion o pago, se detiene; no se contrata
ni se sustituye por una imagen no verificada. Una version especifica de Python
puede requerir oferta comercial del proveedor: pedir condiciones antes de adoptar.

Antes de adopcion: probar roles y migraciones con PostgreSQL bajo el interprete
nuevo, chat/imagenes, notificaciones, proveedor de pagos en pruebas, SSL de las
conexiones y runtime en hosting aislado. Actualizar la matriz de compatibilidad,
resolver todos los avisos y definir actualizaciones/reproducibilidad. No hay
aprobacion de despliegue aunque la comparacion termine verde.

## Archivos y verificacion

- `backend/Dockerfile.wolfi`: alternativa multietapa, no usada por Railway.
- `.github/workflows/backend-wolfi-trial.yml`: comparacion aislada.
- `backend/tests/test_wolfi_trial_config.py`: seis controles de configuracion.
- `scripts/verify-protected-code.py` y nueve pruebas: enlaces/destinos y saltos
  externos, ownership, escritura efectiva y fallos cerrados. Incluye `/etc/ssl`
  entre las raices recorridas para verificar tambien certificados enlazados.
- Destinos de enlaces que contienen `..` se rechazan conservadoramente antes de
  normalizar. Puede detenerse ante un enlace legitimo: exige revisar ese recorrido,
  no significa por si solo que la imagen tenga una vulnerabilidad.
- Suite local final: 318 seleccionadas, 317 aprobadas y una omitida por Linux.
  Segunda revision detecto y comprobo correcciones de enlaces y `..`; nueve
  pruebas dedicadas aprobadas, sin P1/P2 remanentes en ese arreglo acotado.
- Nueve bloques Bash pasan comprobacion sintactica local. Resultado de ejecucion
  Linux y pruebas completas se agrega cuando exista; no se presume exito.
