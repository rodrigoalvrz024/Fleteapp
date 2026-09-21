# PostgreSQL aislado: portabilidad y seguridad

Fecha: 2026-09-21. La primera validacion fue local, sin commit/push ni CI.
El propietario autorizo despues subir la preparacion a la rama de pruebas
y ejecutar la comprobacion Linux descrita al final. No autoriza despliegue.
No se modifico el backend de produccion, Flutter ni los datos reales.

## Hallazgo y correccion

La segunda revision encontro un P2 en el ejecutor de pruebas: el filtrado de
variables solo protegia subprocesses. El proceso padre conservaba PGHOSTADDR,
PGSERVICE y otras opciones que libpq puede leer aunque el codigo indique un
host local. Era una brecha preexistente del aislamiento, no evidencia de que
se haya conectado a una base externa.

Se corrigio aislando tambien el entorno del padre durante toda la ejecucion,
incluidos el apagado y la limpieza. Se restaura el entorno al salir, tambien
si hay excepciones. Las conexiones directas de psycopg2 y SQLAlchemy fijan
ademas `hostaddr=127.0.0.1`. No se conserva configuracion PG*, credenciales de
la aplicacion, HOME ni rutas de carga dinamica heredadas.

Otros cambios acotados:

- Seleccion de `initdb.exe`/`pg_ctl.exe` en Windows y `initdb`/`pg_ctl` en POSIX.
- Comprobacion de ambos ejecutables antes de crear el cluster.
- Rechazo de ejecucion como root en POSIX.
- Configuracion del servidor limitada a TCP `127.0.0.1`, puerto temporal y
  sin sockets Unix compartidos. Autenticacion SCRAM existente conservada.
- Archivo de contrasena temporal con modo 0600 (efectivo en POSIX; no equivale
  a auditar las ACL de Windows). La clave TLS ya tenia ese modo.
- Reutilizacion de la misma lista de variables permitidas en los tres workers.

La revision independiente de la correccion no identifico otros P1/P2 en este
diff. Fue estatica, no una auditoria completa ni aprobacion de produccion.

## Pruebas realizadas

Todas las ejecuciones reales de esta pasada fueron en Windows con PostgreSQL
18.3 local, no en Linux ni Supabase.

| Verificacion | Resultado |
| --- | --- |
| Suite unitaria completa, Python 3.11, codigo final | 403 casos: 400 aprobados y 3 omitidos por plataforma |
| Ejecutador aislado, Python 3.11 | 10 casos: 9 aprobados y 1 omitido (permisos POSIX) |
| Ejecutador aislado, Python 3.14.7 | 10 casos: 9 aprobados y 1 omitido (permisos POSIX) |
| Integracion Python 3.11, antes del ultimo ajuste del entorno padre | 109 aprobados: 9 RLS + 5 TLS + 11 migraciones + 84 HTTP/WebSocket |
| Integracion Python 3.14.7, con el aislamiento del padre corregido | 109 aprobados: 9 RLS + 5 TLS + 11 migraciones + 84 HTTP/WebSocket |

Los tests nuevos inyectan variables ficticias y verifican aislamiento y
restauracion normal/excepcional sin abrir conexiones. Simulan timeouts de
initdb/arranque y fallo de apagado: solo se elimina el directorio tras parar
el servidor o cuando no llego a arrancar. Si falla la parada, se conserva el
directorio. Ningun proceso PostgreSQL real se crea en esos tests unitarios.

Las integraciones reales comprobaron roles, IDs ajenos, chat, documentos,
pagos concurrentes, conciliacion y certificados, con integraciones externas
simuladas. Ambos clusters se apagaron y eliminaron; el directorio de clusters
temporales quedo vacio. No se hicieron cobros, transferencias ni subidas reales.

La primera invocacion manual de la suite general no definia HOME/USERPROFILE
en su entorno limpio y fallo al importar dos modulos de respaldo. Se repitio
con un directorio de usuario temporal, sin usar respaldos personales: resultado
final de la tabla. No se cambio codigo de respaldos para ocultar ese error.

## Siguiente comprobacion Linux

Este PC no tiene Docker ni WSL operativo. Los tests unitarios comprueban la
seleccion de rutas POSIX, pero NO sustituyen arrancar PostgreSQL en Linux.
No se instalo WSL ni se disparo GitHub Actions. La integracion Linux sigue
pendiente al terminar la primera validacion local; el job agregado despues
se describe al final de este documento.

En un entorno Linux desechable con Python/dependencias y PostgreSQL instalados,
usar usuario no root y una ruta comprobada a los binarios del servidor:

```bash
python -B scripts/test-supabase-rls-isolated.py \
  --pg-bin "$(pg_config --bindir)" --http --tls --migrations
```

Registrar versiones, commit y resultados; repetir con `--migration-start models`
para cubrir tambien el esquema legado. Una prueba de este ejecutor no acredita
automaticamente la imagen final de la app: esa debe comprobarse por separado.
No ejecutar contra una URL proporcionada por el operador: el ejecutor crea
sus propias bases y credenciales temporales, y no admite DATABASE_URL externa.

## Proveedores y bloqueo de imagen

La [consulta Docker #596](https://github.com/orgs/docker-hardened-images/discussions/596)
se consulto por HTTP 200 y seguia Unanswered, con cero comentarios.
La [tabla publica de Chainguard Python](https://images.chainguard.dev/directory/image/python/vulnerabilities)
sigue mostrando CVE-2026-19499 High en glibc-2.44 2.44-r6. Es informacion de
su imagen publicada, no un escaneo nuevo de la aplicacion Muvv completa.

No se repitieron construcciones identicas ni se omitieron avisos. La imagen
de Muvv sigue bloqueada segun el [informe de imagen](image-security-review-2026-09-21.md).
No hubo nueva cuota de Actions consumida por ejecuciones iniciadas en esta
pasada, ni contratacion de servicios.

## Preparacion autorizada de GitHub Actions

Se agrega `postgres-integration` al workflow de compatibilidad Python 3.14,
independiente del resultado del analisis de imagen. Usa Ubuntu 24.04,
Python 3.14.7 fijado y PostgreSQL 16 preinstalado, cuyo major se comprueba antes
de iniciar. La [documentacion del runner](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
lista PostgreSQL 16; las versiones efectivas se registran en el resumen de CI.
Esta combinacion NO es identica a PostgreSQL 18.3 local ni a Supabase real.

- Solo permisos `contents: read`, checkout sin credenciales persistentes y
  acciones fijadas por hash de commit verificado en sus repositorios oficiales.
- Entorno virtual nuevo con los requisitos fijados del backend; sin secretos,
  sudo, servicios de produccion, publicacion de imagen ni pasos de despliegue.
- Prueba aislamiento y permisos POSIX, luego el bloque completo HTTP/TLS/RLS y
  migraciones desde vacio. Otro cluster verifica la migracion del esquema legado.
- Tiempos maximos por comando y 15 minutos por job. La comprobacion final de
  limpieza corre tambien si falla un paso y no borra una base que siga activa.
- Cuatro regresiones de configuracion nuevas verifican esos limites. Los cinco
  bloques Bash nuevos pasaron `bash -n` localmente (sin ejecutar los comandos).

La subida de los cambios de seguridad activa las dos corridas de imagen ya
existentes; esta tarea adicional pertenece a una de ellas. Puede consumir
minutos de Actions. No se disparan corridas manuales duplicadas. Los resultados
Linux se registraran con el commit y las URLs, sin confundirlos con aprobacion
de los avisos de Docker o de produccion.

La segunda revision senalo la posible dependencia del Python de setup-python
de una ruta de bibliotecas. Se agrega un preflight real del interprete y sus
dependencias con el entorno limpio ANTES de crear un cluster. Solo los workers
Python en Linux reciben una ruta derivada de sysconfig, validada dentro del
runtime actual y con su biblioteca real presente. No se hereda LD_LIBRARY_PATH
ni LD_PRELOAD y PostgreSQL no recibe esta ruta. Las pruebas cubren rutas ajenas,
traversal y fallo del preflight sin crear archivos ni exponer su salida.

Los timeouts o cancelaciones forzadas del job pueden impedir ejecutar el finally
del interprete. La comprobacion always detecta restos pero no garantiza apagar
un proceso ante esas senales; el runner hospedado es desechable. No usar este
workflow como procedimiento de limpieza garantizada de un servidor persistente.

## Resultado Linux autorizado

Commit subido: `1efdd8a23c2e33ada9b76c910cdafc4a8558bda0`, solo a
`codex/mvp-supabase-rls-review`. `main` se mantuvo en
`590e8fec432f094619355dad89dcb068c4bd649f`. Los otros cambios locales quedaron
fuera del commit. No hubo despliegue ni operaciones sobre datos reales.

[Job PostgreSQL 106499399990](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35649892597/job/106499399990):
**SUCCESS**, en Ubuntu 24.04, Python 3.14.7 y PostgreSQL major 16 verificado.
Pasaron preparacion, aislamiento/permisos POSIX, integracion HTTP/WebSocket,
pagos y TLS, migracion desde vacio, migracion desde modelos legados y el control
final de ausencia de clusters temporales. La confirmacion registrada procede
del estado de cada paso de la API de GitHub, no de inferir la compatibilidad
desde las pruebas Windows. No se equipara este host con la imagen final.

Las dos corridas de imagen terminaron bloqueadas por el escaneo; sus pasos de
aplicacion y arranque pasaron. No se ocultaron avisos:

| Corrida | Critical | High | Medium | Resultado |
| --- | ---: | ---: | ---: | --- |
| [3.11 / 35649892723](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35649892723) | 0 | 45 | 55 | Bloqueada |
| [3.14 / 35649892597](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35649892597) | 0 | 44 | 51 | Imagen bloqueada; job PostgreSQL aprobado |

Imagen 3.11: `sha256:82531228b41dbc80101986d8c17a9dcbc5dc08a271a3e95dac6383767f5885c0`.
Imagen 3.14: `sha256:84fa4f1d876eb325421c712cf1b28afaa9c4d7479aaa7763ab4430dc52a59844`.
Grype 0.118.0, escaneos UTC del 2026-09-21 a las 20:17:45 y 20:17:11.
El diagnostico nuevo 3.11 confirmo en CI tres avisos revisados ausentes y
`pyexpat` cambiado; no se reconocio ninguna excepcion nueva.

Antes del push, la suite local final tuvo 409 casos: 406 aprobados y tres
omitidos por plataforma; preflight real Python 3.14 Windows aprobado. Revision
independiente estatica sin P1/P2 pendientes en el diff acotado. No es una
auditoria global ni garantia de ausencia de otros riesgos.

Quedan pendientes la imagen de produccion, la validacion del hosting real y
el resto de condiciones del piloto. Este resultado cierra la primera ejecucion
de estas pruebas PostgreSQL en Linux; no cierra el bloqueo de vulnerabilidades.

## Seguimiento local: errores del preflight

El preflight descarta stdout/stderr del worker y convierte TimeoutExpired y
OSError en errores acotados, sin encadenar detalles del comando o rutas. No
cambia permisos de usuarios, logica de pagos, migraciones ni configuracion de
produccion. Es endurecimiento de la herramienta de pruebas, no una correccion
de los avisos High de la imagen.

Se agrego una regresion con errores sinteticos que comprueba el traceback
mostrado y la ausencia de directorios de cluster. Los mocks no prueban un
timeout real en todas las plataformas.

Resultados locales posteriores al cambio, 2026-09-21:

- Suite Python 3.11: 410 casos, 407 aprobados, 3 omitidos por plataforma.
- Suite especifica del runner: 13 casos, 12 aprobados, 1 omitido por POSIX.
- PostgreSQL temporal con Python 3.14 en Windows: 9 RLS, 5 TLS,
  11 migraciones desde vacio y 84 HTTP/WebSocket: 109 aprobados.
- El primer intento en el sandbox no pudo iniciar initdb por el token
  restringido de Windows. La ejecucion local autorizada fuera del sandbox
  paso; no se desactivaron las protecciones PostgreSQL para lograrlo.
- Cluster detenido y eliminado; directorio temporal comprobado vacio.
- Segunda revision estatica: sin P1/P2 en el diff acotado. No ejecutada por el
  revisor ni equivalente a una auditoria global.

No se repitio la migracion desde modelos legados en esta ejecucion. Los
resultados Linux anteriores corresponden al commit 1efdd8a; este ajuste local
no se ha subido ni ejecutado en Actions. No hubo acceso a bases externas,
cobros reales, cambios de APK ni despliegue.
