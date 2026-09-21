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
