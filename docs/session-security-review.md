# Seguridad de sesiones y chat

Fecha: 2026-09-15. Candidata de seguridad, NO desplegada ni aprobacion de produccion.

## Hallazgos priorizados

| Prioridad | Hallazgo comprobado | Correccion |
| --- | --- | --- |
| Alta | Recuperar la contrasena no revocaba los JWT anteriores de cliente, conductor ni administrador. | Generacion de sesion persistida por cuenta y comprobada en HTTP, analitica autenticada y WebSocket. La recuperacion incrementa la generacion en la misma transaccion que cambia la contrasena. |
| Alta | Un chat abierto retenia acceso despues de suspender al usuario, vencer el token o cambiar al conductor asignado. | Revalidacion con una transaccion nueva antes de cada entrega, al recibir eventos y cada 30 segundos de inactividad; cierre al perder acceso. |
| Media | Dos solicitudes concurrentes podian comprobar el mismo enlace de recuperacion antes de marcarlo usado. | Bloqueo por cuenta, recarga y segunda comprobacion del enlace; se invalidan todos los enlaces pendientes de esa cuenta al completar el cambio. |
| Media | El limitador retenia identificadores vencidos indefinidamente y no serializaba el conteo entre hilos. | Estado acotado, limpieza por vencimiento y seccion critica protegida; no se expulsan cuotas activas. |

## Segunda revision independiente

Un segundo agente reviso el bloque de sesiones y chat, sin permisos de escritura,
despliegue o acceso a datos reales. Detecto tres problemas adicionales:

- Alta: lectura de objetos ORM expirados despues de commit retenia una conexion
  mientras el broadcast solicitaba otra para comprobar permisos. Ahora se prepara
  respuesta, evento y datos de notificacion antes de commit y no se recarga el ORM
  al enviar. Prueba real con pool de una conexion: dos textos concurrentes, foto
  y confirmacion de lectura conservan la entrega y liberan el pool.
- Media: registro normal/Google capturaba la generacion despues del primer commit.
  Ahora ejecuta flush y captura el JWT antes de confirmar; no devuelve el token
  si falla el registro. Prueba determinista introduce revocacion entre commit y
  refresh y comprueba que la respuesta no herede la generacion nueva.
- Media: la migracion carecia de timeout propio. Ahora fija `SET LOCAL lock_timeout`
  de cinco segundos; se prueba separadamente, anulando el timeout heredado del
  ejecutor, con contencion real de PostgreSQL.

La segunda pasada no encontro hallazgos altos o medios pendientes en estas tres
correcciones. Fue una revision de codigo; el segundo agente no repitio las pruebas
ni reviso el limitador. No equivale a una auditoria profesional ni aprueba produccion.

Las pruebas iniciales reprodujeron cinco fallos: tres roles conservaban su
sesion, un suspendido recibia pong y el conductor retirado recibia mensajes.
La prueba concurrente verifica que exactamente una solicitud tenga exito.
No se han identificado nuevos hallazgos criticos en este alcance acotado;
esto NO certifica la ausencia de otros problemas en todo el proyecto.

## Medidas y compatibilidad

- JWT nuevos incluyen `session_version`; valores de tipo incorrecto o negativos
  se rechazan. Los JWT anteriores equivalen a generacion cero: siguen funcionando
  solo mientras no se haya recuperado la contrasena de esa cuenta.
- Login por contrasena, Google, registros y cambio de modo emiten la generacion
  de la cuenta. Se captura antes de commit para no renovar accidentalmente una
  sesion revocada durante la emision. Los roles siguen comprobados en la DB.
- Recuperacion fallida no cierra sesiones. Recuperacion correcta no inicia una
  sesion automaticamente; la persona debe volver a identificarse.
- El chat vuelve a comprobar identidad activa, JWT y participacion real. Un
  administrador no recibe acceso al canal privado por tener ese rol: conserva
  la ruta de revision justificada y auditada existente.
- Consultas de revalidacion fuera del event loop, sesiones DB cortas, sin cache
  de permisos. Si no se puede verificar el acceso, no se entrega el mensaje.
- Limite de 120 eventos entrantes/minuto/cuenta antes de consultar DB en el chat,
  usando el limitador existente. El limite es por proceso, no distribuido.
- El limitador conserva como maximo 4096 claves, con identificadores SHA-256 de
  tamano fijo. Limpia cuotas completamente vencidas cada 30 segundos y protege
  la comprobacion/insercion con Lock. No elimina una cuota activa para dejar
  entrar otra: al llenarse rechaza identificadores nuevos con 503 y Retry-After.
  Los usuarios ya contabilizados mantienen sus cuotas; un ataque de saturacion
  todavia puede perjudicar disponibilidad, pero no crece el mapa indefinidamente.
  Politicas internas acotadas a 1000 intentos y 86400 segundos; no son nuevos
  permisos para endpoints. Se conservan sus limites actuales y se comprueba
  primero el limite por IP en login. Nueve pruebas incluyen 24 hilos: ocho
  solicitudes admitidas y dieciseis rechazadas para una cuota de ocho.
- Logs genericos, sin publicar JWT, claves de recuperacion ni contenido del chat.
- No cambia Flutter, splash, precios, estados financieros, documentos ni diseno.

## Verificacion

Pruebas sobre PostgreSQL desechable local, con cuentas y fletes sinteticos;
el ejecutor impide usar una DB existente o integraciones externas. La migracion
se comprueba desde historia Alembic vacia y desde un esquema previo simulado.

- 291 pruebas unitarias aprobadas; una prueba de descriptores se omite en Windows
  porque requiere Linux (292 seleccionadas).
- 51 pruebas HTTP/WebSocket aprobadas, sin sustituir la autenticacion de Muvv.
  La identidad externa de Google se simula; no se prueba su consola real.
- Diez pruebas de migracion aprobadas en cada uno de los dos escenarios
  (20 ejecuciones): conservan datos existentes, estados financieros y controles
  RLS; incluyen backfill cero, preservacion de generacion siete y contencion real
  de bloqueo con timeout propio de cinco segundos.
- Nueve pruebas de permisos PostgreSQL/RLS aprobadas.
- Recuperacion simultanea: una respuesta 200, una 400, una sola revocacion y
  un solo evento de auditoria. Login nuevo conserva permisos segun el rol.

Comando del ejecutor aislado (desde la raiz):

```powershell
.\.local-tools\dependency-audit\venv\Scripts\python.exe -B scripts/test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --http --migrations --migration-start models
```

Para el escenario de historia vacia, omitir `--migration-start models`.
No ejecutar las pruebas apuntando DATABASE_URL a Railway o Supabase.

Nueva auditoria `pip-audit` del entorno aislado: 87 dependencias, cero avisos
conocidos el 2026-09-15. Reporte local no versionado:
`.local-tools/dependency-audit/recheck-20260915.json`. No es un escaneo Linux,
del sistema operativo ni de la imagen que esta ejecutandose en Railway.

## Candidata Linux comprobada

Commit de seguridad: `e55defc8644f5ad15d4d0e28dad4fe20a70a4268`, subido con
autorizacion a `codex/mvp-supabase-rls-review`, sin deploy.
[Ejecucion 34932432750](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34932432750).

- Construccion, dependencias, unitarias, descriptores, backports, permisos,
  arranque sin privilegios, rechazo de root y evidencia nativa/XML: aprobados.
- La etapa final Grype termino con reporte valido y bloqueo por vulnerabilidades,
  no por error de construccion o formato del reporte.
- Imagen exacta: `sha256:4a07fa0598a82fb4be5ba6eeb23c0b3e0450b4367c44d314a35b3f441116f08e`.
- Grype 0.118.0; Debian 13.7; escaneo `2026-09-15T05:24:17.064117449Z`.
- Coincidencias: critica 0, alta 45, media 49, baja 9, negligible 44,
  desconocida 8; 155 conservadas en anotaciones, cero alertas de paquete/EOL.
  Las 45 altas corresponden a 13 avisos diferentes, no a 45 ataques demostrados.
- Sin excepciones nuevas, filtros solo-corregibles ni cambios de politica.
  Gitleaks del contenido preparado: 43.16 KB revisados, sin secretos detectados.

Esta candidata NO esta aprobada para produccion. Las correcciones locales no
estan instaladas en Railway; la autorizacion de esta ronda excluye desplegar.

## Archivos

- `backend/app/core/security.py`, `rate_limit.py`, `backend/app/models/user.py`.
- `backend/app/routers/auth.py`, `analytics.py`, `chat.py`.
- `backend/app/services/chat_connections.py`.
- `backend/alembic/versions/a7d2e9c1f630_add_session_revocation.py`.
- `backend/tests/test_jwt_compatibility.py`, `test_chat_connections.py`, `test_rate_limit.py`.
- `backend/integration_tests/test_http_permissions.py`, `test_migration_chain.py`.

## Antes de publicar

1. Conservar la segunda revision y la evidencia de esta candidata. Cualquier
   cambio posterior de codigo o imagen requiere nuevas pruebas Linux.
2. Resolver la politica de vulnerabilidades Docker sin borrar hallazgos ni
   aprobar excepciones implicitamente. La ultima corrida documentada sigue
   bloqueada tambien en la nueva candidata Linux documentada arriba.
3. En entorno aislado, aplicar primero la migracion `a7d2e9c1f630`, despues el
   backend. No ejecutar estos comandos en produccion desde esta revision.
4. Terminar todos los procesos antiguos, incluidos sockets: una instancia del
   backend anterior no comprueba la generacion y anula la garantia de revocacion.
   No hacer rollback a codigo que ignore este campo. El downgrade de la migracion
   se rechaza para no borrar el historial de revocacion.
5. Probar desde dispositivos: recuperar cuenta, rechazo del acceso anterior,
   nuevo login normal/Google, cambio de modo, reconexion y envio de fotos.
6. Medir carga, latencia y fallos de DB; verificar proxy/TLS y limites globales.

No se pueden retirar mensajes ya recibidos o en transmision. El cierre de
sockets ociosos depende del intervalo de 30 segundos y la disponibilidad del
servidor; antes de enviar contenido siempre se vuelve a comprobar el acceso.
Enlaces firmados de imagen ya emitidos conservan su vencimiento propio; no se
convierten en enlaces revocables por cuenta en esta ronda. Logout global,
revocacion inmediata de esos enlaces y limitacion distribuida siguen pendientes.
La confianza en `X-Forwarded-For` depende de que el proxy final lo reconstruya
correctamente y no permita acceso directo al backend; este contrato con Railway
todavia debe comprobarse. No se considera resuelto por acotar el limitador local.

Reconsulta de proveedores: Debian todavia marca trixie vulnerable para
[ACL](https://security-tracker.debian.org/tracker/CVE-2026-54369) y
[zlib](https://security-tracker.debian.org/tracker/CVE-2026-85091).
No se instalaron bibliotecas de sid ni se altero el filtro de Grype.

Referencias de criterio:
[OWASP recuperacion](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html),
[OWASP WebSocket](https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html).
