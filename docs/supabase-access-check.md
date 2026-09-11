# Supabase - verificacion de acceso del MVP

Fecha: 2026-09-07. Respaldo actualizado: 2026-09-08.

## Alcance y resultado

Consultas exclusivamente de metadatos usando la conexion local configurada en
`backend/.env`, posteriormente cotejada con el contenedor Railway activo. No se
leyeron mensajes, documentos ni datos de usuarios. La comprobacion final exige
confirmar una transaccion de solo lectura y limita tiempos dentro de ella.

- Revision consultada: `e1f0a2b3c4d5`, coincidente con la cabeza local anterior.
- 20 tablas de modelos revisadas; ninguna ausente.
- Sin RLS: `freight_cargo_photos`, `freight_chat_messages`,
  `freight_driver_declines`, `trip_feedback`. Propietario: `postgres`.
- Permisos efectivos de `anon` y `authenticated` sobre tablas: 0.
- Permisos efectivos exclusivos de columnas para esos roles: 0.
- Ambos roles existen y ninguno tiene superusuario o BYPASSRLS.
- Bucket `muvv-private`: privado, limite 8 MiB, sin lista MIME en el bucket.
- No se encontraron politicas en `storage.objects` en la consulta realizada.

**Hallazgo medio: falta de defensa en profundidad RLS en cuatro tablas nuevas.**
No se confirmo exposicion publica: los roles API no tienen permisos efectivos.
El analisis no cubre funciones RPC, vistas, todos los roles, claves robadas ni
autorizacion HTTP de FastAPI. Un bucket privado tampoco certifica por si solo
la autorizacion y caducidad de cada descarga.

## Correccion preparada, no aplicada

Migracion: `f2a4b6c8d010`, posterior a `e1f0a2b3c4d5`.

- Activa RLS en las cuatro tablas, sin crear politicas permisivas.
- Revoca permisos de tabla y secuencia asociada de PUBLIC, anon y authenticated.
- No modifica registros, precios, roles de usuarios ni archivos de Storage.
- No usa FORCE RLS: mantiene el acceso del propietario usado por FastAPI.
- El downgrade no desactiva RLS ni vuelve a otorgar permisos. La recuperacion
  de la version anterior de la aplicacion conserva esta proteccion.

Antes de aplicar, confirmar que el usuario de conexion del backend sigue siendo
propietario o tiene el acceso directo previsto. Si se cambia a un rol de menor
privilegio, hay que disenar y probar sus permisos antes, no desactivar RLS para
resolver errores de acceso.

## Evidencia local

- 118 pruebas unitarias de backend aprobadas nuevamente el 2026-09-09;
  16 de la correccion RLS,
  11 del respaldo y diagnostico de claves, y 15 de recuperacion portable.
- La lista del verificador debe coincidir con todas las tablas de SQLAlchemy.
- Se comprueban tablas ausentes, RLS desactivado, privilegios efectivos de tabla
  y columna, roles API ausentes/privilegiados y errores sin exponer credenciales.
- Conexion del verificador limitada a solo lectura, TLS y tiempos acotados.
- Alembic genera el SQL del tramo `e1f0a2b3c4d5:head` correctamente sin conexion.
- 9 pruebas de integracion aprobadas en PostgreSQL 18.3 local, usando un cluster
  nuevo con autenticacion SCRAM, escucha exclusiva en 127.0.0.1 y datos sinteticos.
- Migracion ejecutada con rol propietario NOSUPERUSER y NOBYPASSRLS. Conserva
  lectura/escritura del backend y las filas anteriores; revoca permisos de tablas
  y secuencias a PUBLIC, anon y authenticated. Ambos roles reciben denegacion real.
- Si reaparecen permisos de tabla, RLS sigue ocultando filas e impidiendo INSERT,
  UPDATE y DELETE. La repeticion y downgrade conservan la proteccion. Una tabla
  ajena permanece intacta. El verificador detecta permisos PUBLIC y por columna.
- Una prueba adicional confirma la transaccion de solo lectura y los limites
  de tiempo sin depender de opciones de arranque. PostgreSQL rechaza UPDATE.
- El cluster fue apagado y eliminado al finalizar. No se conecto a Supabase.
  Las cuatro tablas temporales reproducen id/secuencia y filas representativas;
  esto no sustituye probar el esquema completo, HTTP, Storage o una restauracion
  de respaldo, ni certifica compatibilidad de todos los flujos de produccion.

Prueba reproducible en Windows, con PostgreSQL instalado (no usa DATABASE_URL):

```powershell
& .\backend\venv\Scripts\python.exe .\scripts\test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin'
```

El ejecutor genera credenciales efimeras, acota tiempos de consulta/arranque y
limpia solo su directorio generado dentro de `.local-tools/rls-tests`.

El verificador devuelve 1 en la base actual por las cuatro tablas sin RLS.
No debe interpretarse como fallo de conexion ni marcarse como resuelto antes
de aplicar y repetir la comprobacion.

## Comprobacion del entorno desplegado

El 2026-09-07 se consultaron Settings, el despliegue activo y metadatos desde la
consola del servicio `muvv-api`, proyecto `muvv-app`, entorno `production`:

- Commit activo: `590e8fec432f094619355dad89dcb068c4bd649f`.
- Origen GitHub `main`, despliegue automatico habilitado, raiz `backend`.
- Pre-deploy: `alembic upgrade head`. Healthcheck: `/health`. Reinicio: Always.
- Una replica US West; no se modificaron recursos ni configuraciones.
- `/health`: HTTP 200, `healthy`, `pilot_mode=true` (consulta puntual, no SLA).
- Conexion al proyecto Supabase `vlyolrdjtkxabtcbrulg`, base `postgres`, rol
  `postgres`, propietario de las cuatro tablas. Revision: `e1f0a2b3c4d5`.
- `APP_ENV=production`, `PILOT_MODE=true`, `RUN_STARTUP_MIGRATIONS=false`.
- Storage apunta al mismo proyecto y al bucket `muvv-private`.
- No se mostraron claves, DSN completos, contrasenas ni datos de usuarios.

La primera consulta informo `transaction_read_only=off`: el pooler no aplico
la opcion de arranque enviada. Todas las sentencias fueron SELECT de metadatos;
no hubo cambios. Se repitio usando `set_session(readonly=True, autocommit=False)`
y SET LOCAL para tiempos, y se comprobo `transaction_read_only=on` antes de
continuar. El verificador local ahora hace lo mismo y aborta si no lo confirma.
Su repeticion reviso 20 tablas: solo permanecen las cuatro sin RLS, sin permisos
efectivos de tabla o columna de los roles API (salida 1 esperada).

## Respaldo y restauracion local

El panel Supabase de FletGo, Database > Backups, informa que el plan Free no
incluye respaldos del proyecto. No se encontro un respaldo recuperable en ese
panel; esto no descarta copias externas que Rodrigo pudiera conservar.

Tras autorizacion expresa, se creo el respaldo `20260908T025031Z-bcdc953a` y
se verifico su restauracion el 2026-09-08 a las 03:01 UTC. Incluye volcado logico
completo PostgreSQL y los 13 objetos privados de Storage (5.337.010 bytes),
en un paquete cifrado de 7.775.736 bytes fuera del repositorio.

- SHA-256 cifrado: `a251d6f49eaf793328dad69f834d958eec7611c1361cc0d963be4f5ed0e6d6a3`.
- Restauracion local: 21 tablas public (20 de aplicacion y Alembic), recuentos,
  huellas de datos, propietarios, RLS y revision `e1f0a2b3c4d5` coincidentes.
- Los 13 archivos se recuperaron del paquete y sus bytes coinciden por SHA-256.
- Se igualo `extra_float_digits=0`, configuracion verificada del origen al crear
  la primera huella. Nuevos respaldos usan explicitamente 3 en ambos extremos.
- Instancia SCRAM nueva, solo 127.0.0.1, sin iniciar backend, notificaciones ni
  cobros. Se apago y elimino junto con los temporales descifrados al terminar.
- Clave de respaldo protegida con DPAPI del usuario Windows, en carpeta separada.
  La copia temporal de la credencial Storage y la clave RSA de transporte se eliminaron.
- No hubo cambios en Supabase/Railway, contratacion de planes, commit ni deploy.

Exportacion portable con contrasena personal creada y comprobada; el mecanismo
ya permite descifrar sin DPAPI. Segunda copia en Google Drive privado verificada
el 2026-09-09: ZIP con acceso Restringido, solo propietario, y descarga identica
byte por byte y por SHA-256 al original. No se extrajeron datos privados.
Falta ensayar otro computador y recuperar la contrasena sin el PC original.
Los esquemas gestionados de Supabase estan
en el volcado, pero no se ensayaron como plataforma completa: tampoco se subieron
los archivos a otro proyecto Supabase ni se validaron URLs de descarga tras esa
migracion. Ver procedimiento y limites en `docs/private-backup-recovery.md`.

Referencia: [Supabase Database Backups](https://supabase.com/docs/guides/platform/backups).

## Aplicacion y comprobacion pendientes

Regresion del 2026-09-09: 24/24 pruebas HTTP/WebSocket aprobadas sobre una base
desechable con las 20 tablas de modelos y la migracion candidata; sin cobros,
notificaciones ni llamadas a Storage/Maps productivos. Comprueba participantes,
IDs ajenos, compatibilidad/aprobacion de vehiculos, JWT, fotos, chat auditado,
perfil, evaluaciones y ubicacion. Autenticacion y SQL reales; integraciones
externas simuladas. Ver `docs/http-permissions-regression.md` para alcance,
reproduccion, avisos de AnyIO y pruebas aun pendientes sobre la candidata real.

1. Commit/push autorizado el 2026-09-07 exclusivamente a la rama de revision
   `codex/mvp-supabase-rls-review`, separado de cambios mobile, web y marketing.
   No autoriza fusionar a `main`, crear un entorno preview ni desplegar.
2. Prueba aislada de la migracion/verificador (9/9) y HTTP sobre modelos reales
   (24/24) completadas. Antes del piloto, revisar compatibilidad de la candidata
   con el esquema desplegado y repetir sobre el servicio candidato.
3. Conexion/usuario Railway y recuperacion local del respaldo confirmados.
   Clave portable exportada y copia externa/descarga verificadas; falta ensayo
   en otro equipo y acceso independiente a la contrasena, diferidos al cierre
   por Rodrigo el 2026-09-09.
   Commit/push de los ajustes posteriores a `87e8248` y validacion Linux
   autorizados el 2026-09-11 en la misma rama; no se autoriza fusion ni despliegue.
4. Desplegar con el pre-deploy existente `alembic upgrade head`. Mantener
   `RUN_STARTUP_MIGRATIONS=false`; no ejecutar migraciones simultaneas manuales.
5. En el contenedor actualizado, comparar `alembic current` y `alembic heads`:
   ambos deben informar `f6b8c0d2e411`, revision aditiva posterior a
   `f2a4b6c8d010`. Ver `docs/backend-release-candidate.md` antes de desplegar.
6. Con DATABASE_URL del entorno correcto ya configurada de forma privada,
   ejecutar desde la raiz del repositorio en PowerShell:

```powershell
& .\backend\venv\Scripts\python.exe .\scripts\verify-supabase-rls.py
```

Resultado esperado: 20 tablas; RLS desactivado, tablas/roles ausentes y roles
API con bypass: ninguno; permisos efectivos de tabla/columna: 0; salida 0.
Salida 1 indica un hallazgo; salida 2 indica que no se pudo verificar.
No usar el script legado que obtiene secretos del proyecto GCP eliminado.

7. Repetir HTTP y dos telefonos: cliente adjunta foto y ve su flete; conductor
   apto ve detalles, chat y fotos; conductor/cliente ajenos no acceden cambiando
   IDs; admin conserva solo el acceso previsto y auditado. Completar evaluacion
   bilateral y verificar el retorno de pantallas sin errores de permisos.
8. Registrar evidencia depurada y actualizar MVP-02, MVP-03 y MVP-04 del plan.
   No incorporar claves ni capturas de documentos en Notion.
