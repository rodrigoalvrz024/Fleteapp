# Evaluacion aislada de Python 3.14 en Linux

2026-09-21. Estado: construida y probada en Linux, bloqueada por avisos del SO.
No modifica `backend/Dockerfile`, `app.server`, Railway, datos o pagos reales.

## Resultado de la ejecucion autorizada

Commit `78ba41a6b8cfddbaf662d149095a26dcb0249d6e`, solo rama de pruebas.
Main permanece en `590e8fec432f094619355dad89dcb068c4bd649f`.

| Ejecucion | Funcionalidad y protecciones | Critical | High | Medium | Duracion |
| --- | --- | --- | --- | --- | --- |
| [Python 3.14](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35633803365) | Pasaron todos los pasos anteriores al escaneo | 0 | 44 | 51 | 2m06s |
| [Clasico Python 3.11](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35633803150) | Pasaron todos los pasos anteriores al escaneo | 0 | 45 | 55 | 2m48s |

Ambas ejecuciones terminaron en failure por el control de seguridad, no por
fallos de funcionamiento. Duracion total de jobs: 4m54s; no es una consulta
de facturacion ni de cuota mensual.

Python 3.14: imagen
`sha256:cbc61c60ab243abd2af777ebf583671c226837973a4177bfe7341e510bfcb3f6`,
Grype 0.118.0, Debian 13.7, `2026-09-21T17:45:24.560274457Z`.
146 coincidencias completas: 0 Critical, 44 High, 51 Medium, 7 Low,
43 Negligible, 1 Unknown. Sin excepciones, filtros ni descuentos.

Clasico: imagen
`sha256:0413a1612e5cdadcb184be43076d5f02babbae711f74d44af92171be751f93c4`,
Grype 0.118.0, Debian 13.7, `2026-09-21T17:46:05.619533797Z`.
152 coincidencias: 0 Critical, 45 High, 55 Medium, 7 Low, 44 Negligible,
1 Unknown. Mantiene el rechazo `reviewed_python_finding_set_mismatch`.

Comparando severidad/CVE/paquete desaparecen seis coincidencias de Python:
High CVE-2026-82049; Medium CVE-2025-12781, CVE-2025-15366, CVE-2026-3446,
CVE-2026-6019; Negligible CVE-2026-3479. No aparecen coincidencias nuevas
en esa comparacion. Esto no prueba ausencia de vulnerabilidades desconocidas.

Los 44 High de Python 3.14 corresponden a 11 CVE del SO: util-linux y sus
paquetes relacionados (32 coincidencias), ncurses (4), glibc (4), libacl (2),
zlib (1) y perl-base (1). La actualizacion de Python no las resuelve.
Python 3.14 tambien conserva cinco avisos Medium y uno Low propios.

Pendiente: evaluar esos componentes en una base mantenida mas reducida o sus
correcciones oficiales, sin ignorar hallazgos ni mezclar paquetes inestables.
Este resultado prueba compatibilidad del candidato, NO aprueba produccion.

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
No hay Docker disponible en este PC; construir/arrancar/escanear se comprobo
despues en GitHub Actions, con los resultados y limites descritos arriba.

La revision independiente detecto un trigger incompleto; se corrigio para
`backend/**` y `scripts/**`. Los cambios futuros en esas rutas volveran a ejecutar
este trial en la rama de pruebas. El push inicial tambien dispara el candidato
clasico. No hay nueva suscripcion: se usan runners existentes de GitHub con
limites de 15 minutos (trial) y 20 minutos (clasico); el consumo real depende
de la duracion y del plan de la cuenta. No se afirma una cuota actual.

El propietario autorizo commit/push y las dos ejecuciones de GitHub Actions
el 2026-09-21. No autoriza despliegue ni cambios de produccion.
Las dos ejecuciones finalizaron y se revisaron sin autorizar despliegue.
El candidato clasico conserva 45 High; la alternativa Python 3.14 tiene 44 High.
