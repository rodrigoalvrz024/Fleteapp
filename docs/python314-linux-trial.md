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

## Inventario nativo: preparacion y ejecucion

El 2026-09-21 se preparo un paso adicional para obtener evidencia de la misma
imagen Python 3.14 construida y escaneada. No se puede usar el inventario de
DHI/Python 3.11 para afirmar ausencia de componentes en esta candidata.

Se reutiliza `scripts/report-native-symbols.py`, sin cambiar su analisis:

- Docker crea un contenedor sin red y no lo inicia. Se exporta su filesystem
  efectivo a un TAR temporal; el analizador lee archivos ELF sin ejecutarlos
  ni extraer el archivo sobre el filesystem del runner.
- Herramienta en virtualenv separado, dependencia fijada con hash y sin deps
  adicionales. No se instala en la aplicacion ni modifica la candidata.
- Exportacion limitada a 60 segundos y analisis a 180; job conserva 15 minutos.
- Se registran ID de imagen, hashes, imports, exports y componentes por nombre.
  El informe conserva sus limites: enlaces no resueltos, posibles copias
  renombradas, llamadas dinamicas y enlaces estaticos impiden inferir
  inalcanzabilidad solo a partir de imports ausentes.
- Se publica SOLO `python314-native-symbol-evidence/report.json` durante
  14 dias. No se publica el TAR, virtualenv, codigo ni datos de usuarios.
  Ese plazo solo aplica al artefacto; las anotaciones y el resumen tambien
  contienen metadatos y siguen la retencion de la corrida de GitHub.
  El contenedor temporal se elimina al salir del paso; los archivos de trabajo
  quedan en RUNNER_TEMP del runner hospedado desechable.
- La subida del informe precede al escaneo. El escaneo conserva su condicion
  always tras build exitoso, incluso si el inventario o su subida fallan.
  No hay `continue-on-error`, excepcion nueva ni aprobacion de despliegue.

Verificacion local: 12 pruebas de configuracion y 20 del analizador aprobadas;
sintaxis Bash del paso nuevo validada. Suite completa: 412 casos, 409 aprobados
y 3 omitidos por plataforma. La configuracion aun no se ha ejecutado en Linux.
No hubo push ni nueva corrida de Actions en esta preparacion.
Segunda revision estatica sin P1/P2 en el diff acotado. Las pruebas de
configuracion no demuestran tiempos reales, ejecucion Docker ni limpieza
efectiva en Linux; esos resultados siguen pendientes.

La proxima corrida tendria una finalidad distinta de repetir un contador:
obtener este inventario faltante, ligado al ID de imagen de esa corrida, para
revisar exposicion por CVE. No se espera que agregar diagnostico repare los
44 registros High. Un inventario vacio o fallido no es evidencia de ausencia.
Antes de publicar la preparacion, separar los cambios propios de web/mobile y
confirmar autorizacion de commit/push a pruebas y consumo de Actions.

### Resultado autorizado del 2026-09-21

La preparacion anterior se publico como commit
`c1d9cca521b70ba362720a61cb4b62b08ad70d09`, exclusivamente en
`codex/mvp-supabase-rls-review`. Los resultados siguientes sustituyen el estado
pendiente de ejecucion descrito en el registro de preparacion. No hubo deploy.

- Python 3.14: https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35669571540
  (compatibility, job 106562776187). Build, dependencias, tests offline,
  privilegios, inventario y preservacion de metadatos: success. Solo el
  escaneo de seguridad falla y mantiene el bloqueo.
- Imagen examinada y escaneada:
  `sha256:91440550843b1f025bc2eebae8f3abc001d553acb2ee44a45ee7ffb5f6b931d3`.
  Grype 0.118.0, Debian 13.7: 0 Critical, 44 High, 51 Medium, 7 Low,
  43 Negligible, 1 Unknown (146 registros). No se exime ninguno.
- PostgreSQL independiente, job 106562776342 de esa misma corrida: todos los
  pasos success, incluidos permisos HTTP, pagos de prueba, TLS, migraciones
  desde esquema vacio y legado, y comprobacion de limpieza de clusters.
  Estos tests del runner no sustituyen la aprobacion de la imagen.
- Clasico: https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35669571548
  (job 106562769618). Solo falla el escaneo. Imagen
  `sha256:c9d6e5b5f1f618bf2a2427323251cb581f314e60f922148bc8da8914c7bce904`:
  0 Critical, 45 High, 55 Medium, 7 Low, 44 Negligible, 1 Unknown.
  Sigue bloqueado tambien por `reviewed_python_finding_set_mismatch`.

Inventario Python 3.14: 784 archivos ELF inspeccionados; cero importadores
directos encontrados en los grupos legacy_dns, monetary_format y xml_hash.
ACL tiene cinco (cp, install, mv, sed, tar); gzip_write tiene dos (dpkg-deb y
libapt-pkg). Hay 33 archivos con imports de carga dinamica. Las anotaciones
de carga dinamica muestran 12 y omiten 21; no se afirma haber inspeccionado
manualmente el artefacto JSON completo.

Por nombres conocidos, infocmp, getfacl, setfacl, chacl y perl_archive_tar no
aparecen. La coincidencia nsenter es un archivo de autocompletado Bash, no
el ejecutable. Esto no descarta copias renombradas, enlaces estaticos ni
llamadas dinamicas. No equivale a demostrar inalcanzabilidad por CVE.

Siguiente revision: cruzar los componentes/importadores reales con las
funciones y condiciones afectadas de cada aviso, priorizando bibliotecas
presentes y carga dinamica. No borrar archivos de bibliotecas ni aprobar
excepciones a partir de este inventario. La decision sigue siendo NO-GO.
