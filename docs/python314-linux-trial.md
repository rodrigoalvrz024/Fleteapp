# Evaluacion aislada de Python 3.14 en Linux

2026-09-21. Estado: preparada localmente, sin imagen construida ni despliegue.
No modifica `backend/Dockerfile`, `app.server`, Railway, datos o pagos reales.

## Decision y limites

- El catalogo oficial publica `python:3.14.7-slim-trixie` para amd64:
  https://github.com/docker-library/official-images/blob/master/library/python
- Se conserva Debian para separar el cambio de interprete del cambio de
  distribucion. NO se espera que esto resuelva los avisos del sistema operativo.
  El escaneo determinara si cambia el aviso Python CVE-2026-82049.
- Alpine no supero la resolucion local `--only-binary=:all:` para Python 3.14:
  falta una wheel compatible de google-crc32c 1.8.0. No se quitaron dependencias
  ni se habilito compilacion arbitraria como alternativa.
- El catalogo Chainguard consultado aun muestra CVE-2026-19499 High en glibc:
  https://images.chainguard.dev/directory/image/python/vulnerabilities
  No se relanzo esa imagen sin cambios ni se compro una suscripcion.
- La resolucion manylinux de los 83 pins actuales termino correctamente.
  Reporte local: `.local-tools/anyio-audit/python314-linux-sql254-resolution.json`.
  Se ejecuto pip en Windows con plataforma destino: no prueba imports Linux,
  todos los marcadores de entorno Linux ni la instalacion real. CI es obligatorio.

## Archivos y controles

- `backend/Dockerfile.python314`: receta separada con permisos, usuario y
  arranque equivalentes al candidato clasico; instala solo wheels.
- `.github/workflows/backend-python314-trial.yml`: solo rama de pruebas,
  permisos GitHub de lectura, sin credenciales de servicios ni despliegue.
- `backend/tests/test_python314_trial_config.py`: seis tests del contrato.

La base oficial se resuelve a digest antes de construir y se registra junto
al commit y al ID de imagen. Ese digest garantiza identidad dentro de la
corrida; no es una verificacion de firma ni congela el tag entre corridas.
Las actualizaciones apt son registradas por el escaneo de la imagen resultante.

Se comprueba Python 3.14.7 final, pip check, suite completa sin red, permisos
sin que read-only oculte escrituras, arranque real sin flags de privilegios del
hosting, rechazo de root, seis accesos anonimos/token invalido, Alembic heads
y apagado SIGTERM. No se migra una base externa ni se invocan pagos reales.
Los dos archivos de configuracion nuevos se montan individualmente readonly
para ejecutar tambien sus seis tests; no se monta el repositorio completo.

Grype analiza la imagen completa incluso si un test anterior falla, siempre
que la construccion haya terminado. No se ocultan fallos previos. Cancelacion
o timeout pueden impedir el escaneo, sin aprobar el candidato. Se conservan
todos los avisos y el bloqueo High/Critical. No se ejecutan ni reutilizan las
excepciones o el acceso C API reservado a Python 3.11.

## Verificacion y coste

La suite local con los seis tests nuevos: 379 aprobados y dos omitidos en cada
uno de Python 3.11 y 3.14.7 (381 total por interprete). Los omitidos necesitan
Linux. La sintaxis Bash de los siete pasos se verifico localmente.
No hay Docker disponible en este PC: construir/arrancar/escanear siguen pendientes.

La revision independiente detecto un trigger incompleto; se corrigio para
`backend/**` y `scripts/**`. Los cambios futuros en esas rutas volveran a ejecutar
este trial en la rama de pruebas. El push inicial tambien dispara el candidato
clasico. No hay nueva suscripcion: se usan runners existentes de GitHub con
limites de 15 minutos (trial) y 20 minutos (clasico); el consumo real depende
de la duracion y del plan de la cuenta. No se afirma una cuota actual.

El propietario autorizo commit/push y las dos ejecuciones de GitHub Actions
el 2026-09-21. No autoriza despliegue ni cambios de produccion.
Pendiente: ejecucion Linux y revision de sus resultados. Esta preparacion
no cambia los 45 High de la ultima imagen #35.
