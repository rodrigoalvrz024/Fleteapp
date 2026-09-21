# Seguridad de pagos, PIN y evidencia: revision local

Fecha: 2026-09-21. Validacion local previa al commit, sin despliegue ni cobros.
No se modificaron Flutter, el splash, las credenciales ni datos reales.

## Hallazgos y correcciones

| Prioridad | Riesgo encontrado | Correccion local |
| --- | --- | --- |
| Alta | Reintentar el pago sustituia token y orden de un checkout pendiente. Dos peticiones podian crear intentos diferentes. | Bloqueo del flete incluso si no existe pago, seguido del pago; reutilizar el checkout pendiente sin llamar otra vez al proveedor. |
| Alta | Un pago reembolsado podia volver a inicializarse y perder su estado terminal. | Rechazo 409 sin alterar el registro. |
| Alta | Una respuesta con orden/monto incompatible se trataba como pago fallido, habilitando un nuevo intento sin certeza del anterior. | Conservar pendiente y devolver error de verificacion; solo un rechazo coherente permite iniciar otro checkout. |
| Media | Los montos se truncaban con int y un precio final cero usaba el estimado. | Exigir CLP enteros, positivos, finitos y dentro del limite antes de contactar al proveedor; respetar final_price cuando esta presente. |
| Media | Intentos simultaneos de PIN podian perder incrementos y superar cinco verificaciones. | Serializar generacion de PIN y transiciones del mismo flete. Prueba de ocho peticiones: cinco verificaciones efectivas, contador cinco, sin completar. |
| Media | Una foto iniciada antes del cierre podia terminar despues y sustituir la evidencia anterior. | Subir sin bloqueo; luego bloquear/refrescar y revalidar estado/conductor. Ante conflicto, conservar la evidencia original y limpiar solamente el objeto nuevo. |
| Media | Esperar un bloqueo SQL dentro de una ruta async podia bloquear el event loop. | Procesar las fases transaccionales de callback y guardado de evidencia en workers. Callback libera transaccion en finally; espera de bloqueo limitada a cinco segundos, con rollback y 409. |
| Media | Actualizaciones administrativas simultaneas podian sobrescribir un estado paid o duplicar su auditoria. | Bloquear la liquidacion antes de validar y modificar su estado. Sigue siendo exclusivo del administrador. |

Las prioridades expresan impacto potencial, no cobros duplicados observados en
produccion. No se confirmo un nuevo IDOR en la revision acotada de chat/fotos/fletes.

## Archivos de este bloque

- `backend/app/routers/payments.py`: checkout estable, montos, estados y callback.
- `backend/app/routers/freights.py`: PIN, transiciones y evidencia.
- `backend/app/routers/payouts.py`: transiciones administrativas serializadas.
- `backend/app/services/row_lock_service.py`: bloqueo transaccional acotado.
- `backend/integration_tests/test_http_permissions.py`: regresiones HTTP con PostgreSQL.
- `backend/tests/test_row_lock_service.py`: timeout, rollback y errores no relacionados.

## Verificacion

- Python 3.11 y Python 3.14.7: 384 pruebas por entorno, 382 aprobadas y dos omitidas
  porque requieren Linux. No se suman ambas ejecuciones como pruebas distintas.
- Revision estatica independiente del diff: sin P1/P2 pendientes en este bloque.
  No equivale a una auditoria independiente de toda la aplicacion.
- PostgreSQL 18.3 aislado, Python 3.11: 96 pruebas aprobadas (71 HTTP, nueve RLS,
  cinco TLS y once de migraciones). Cluster detenido y eliminado al finalizar.
- Trece pruebas HTTP y tres unitarias nuevas respecto al inicio de este bloque.
- `git diff --check` sin errores en los archivos backend modificados.
- Sin llamadas a Transbank, Supabase, Firebase o Railway; proveedor y almacenamiento
  simulados. PostgreSQL es real, temporal, loopback y con TLS verificado.
- No se consumieron minutos de GitHub Actions para estas ejecuciones locales.

## Comportamiento y limites pendientes

1. Un checkout pendiente no se reemplaza automaticamente, aunque el navegador se
   cierre o la respuesta sea incierta. Se agrego despues una conciliacion protegida
   local: consultar `payment-reconciliation.md`. Aun falta integrarla en la app y
   comprobarla con el proveedor; expiraciones y anulaciones siguen requiriendo revision.
2. Las pruebas no demuestran liquidacion bancaria, retencion/captura, devoluciones
   reales ni atomicidad entre el proveedor externo y el commit local. Se mantiene
   una fila Payment por flete; un historial independiente de intentos seria otro cambio.
3. Conflictos de estado y timeout limpian la foto nueva. Fallos generales de BD,
   commit o borrado de Storage pueden dejar objetos privados huerfanos; falta un
   procedimiento de conciliacion/limpieza que no borre referencias vigentes.
4. El timeout es por espera de bloqueo, no un plazo total de la peticion. El proveedor
   mantiene sus propios timeouts. Faltan pruebas de carga en el hosting aislado.
5. Falta ampliar intercalados: regenerar PIN durante finalizacion, reasignar/cancelar
   durante upload y operadores administrativos con referencias diferentes.
6. Las nuevas carreras se prueban con TestClient y PostgreSQL; la suite tambien tiene
   una prueba HTTP/WebSocket con Uvicorn real, pero no todas las carreras usan sockets.
7. El bloqueo de seguridad de la imagen Docker sigue separado y vigente. Consultar
   `docs/image-security-current-status.md`; este trabajo no elimina ni acepta sus CVE.
8. Antes de produccion: revision del diff, CI/Linux sobre el commit exacto, resolver
   el control de imagen, validar integraciones en entorno aislado y autorizar despliegue.

## Repeticion segura

Desde la raiz, con PostgreSQL local instalado; el runner crea y elimina su propio
cluster, no admite sustituirlo por una base existente:

```powershell
& '.local-tools/dependency-audit/venv/Scripts/python.exe' -u -B scripts/test-supabase-rls-isolated.py --pg-bin 'C:/Program Files/PostgreSQL/18/bin' --http --tls --migrations
```

En este equipo initdb necesita ejecutarse fuera del token restringido del sandbox.
Eso no autoriza conexiones externas ni el uso de una base compartida.
