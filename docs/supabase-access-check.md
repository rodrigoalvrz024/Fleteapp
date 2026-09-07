# Supabase - verificacion de acceso del MVP

Fecha: 2026-09-07.

## Alcance y resultado

Consultas exclusivamente de metadatos, en transaccion de solo lectura y con
timeout, usando la conexion local configurada en `backend/.env`. No se leyeron
mensajes, documentos ni datos de usuarios. Esto no acredita que las variables
del contenedor Railway sean identicas: debe confirmarse antes del despliegue.

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

- 90 pruebas unitarias de backend aprobadas; 14 nuevas para esta correccion.
- La lista del verificador debe coincidir con todas las tablas de SQLAlchemy.
- Se comprueban tablas ausentes, RLS desactivado, privilegios efectivos de tabla
  y columna, roles API ausentes/privilegiados y errores sin exponer credenciales.
- Conexion del verificador limitada a solo lectura, TLS y tiempos acotados.
- Alembic genera el SQL del tramo `e1f0a2b3c4d5:head` correctamente sin conexion.
- 8 pruebas de integracion aprobadas en PostgreSQL 18.3 local, usando un cluster
  nuevo con autenticacion SCRAM, escucha exclusiva en 127.0.0.1 y datos sinteticos.
- Migracion ejecutada con rol propietario NOSUPERUSER y NOBYPASSRLS. Conserva
  lectura/escritura del backend y las filas anteriores; revoca permisos de tablas
  y secuencias a PUBLIC, anon y authenticated. Ambos roles reciben denegacion real.
- Si reaparecen permisos de tabla, RLS sigue ocultando filas e impidiendo INSERT,
  UPDATE y DELETE. La repeticion y downgrade conservan la proteccion. Una tabla
  ajena permanece intacta. El verificador detecta permisos PUBLIC y por columna.
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

## Aplicacion y comprobacion pendientes

1. Commit/push autorizado el 2026-09-07 exclusivamente a la rama de revision
   `codex/mvp-supabase-rls-review`, separado de cambios mobile, web y marketing.
   No autoriza fusionar a `main`, crear un entorno preview ni desplegar.
2. Prueba aislada de la migracion completada (8/8). Antes del piloto, repetir
   la regresion del esquema completo y los endpoints del servicio candidato.
3. Confirmar respaldo recuperable y conexion/usuario del servicio Railway.
4. Desplegar con el pre-deploy existente `alembic upgrade head`. Mantener
   `RUN_STARTUP_MIGRATIONS=false`; no ejecutar migraciones simultaneas manuales.
5. En el contenedor actualizado, comparar `alembic current` y `alembic heads`:
   ambos deben informar `f2a4b6c8d010`.
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
