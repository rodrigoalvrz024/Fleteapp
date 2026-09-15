# Disponibilidad del chat ante conexiones lentas

Fecha: 2026-09-15. Candidata de seguridad; no desplegada.

## Hallazgos y alcance

- Media: el broadcast esperaba send_json sin plazo. Un transporte detenido
  podia bloquear los destinatarios siguientes y la respuesta HTTP de un mensaje
  ya confirmado en la base de datos. Reproducido antes del arreglo con una
  coroutine suspendida; no es una prueba de ataque de red contra produccion.
- Baja: una copia de la lista de conexiones podia seguir intentando entregar a
  una conexion retirada por otro envio. Se comprueba identidad de la conexion
  antes y despues de autorizar. La autorizacion por cuenta y flete permanece.

## Medidas

El envio tiene un plazo de tres segundos. Un error o timeout retira inmediatamente
el socket del registro y solicita cierre 1013. Si no queda otra pestana activa,
la ruta HTTP puede programar la notificacion existente. El mensaje persistido no
se elimina ni se vuelve a insertar. No se cambia formato, API, permisos o Flutter.

El cierre se conserva en una tarea supervisada por socket, con recoleccion de
excepciones y liberacion de referencias al terminar. El broadcast espera como
maximo 0.5 segundos por esa tarea, sin cancelarla. La cancelacion del broadcast
se propaga, sin reutilizar un transporte con un envio posiblemente parcial.

La primera implementacion usaba wait_for(close). La segunda revision encontro
que el transporte puede absorber la cancelacion durante la limpieza TCP: ese
timeout no limitaba realmente la espera del broadcast. Se sustituyo por wait
sobre una tarea supervisada. Pruebas incluyen cierre que absorbe cancelacion y
cancelacion del broadcast mientras esa limpieza sigue pendiente.

Referencia del comportamiento de cancelacion y espera:
[asyncio de Python 3.11](https://docs.python.org/3.11/library/asyncio-task.html#asyncio.wait).

## Verificacion local

- Diez pruebas unitarias del administrador de conexiones: envio bloqueado,
  cierre bloqueado, excepciones de cierre, retiro de snapshot y durante
  autorizacion, cancelacion y conservacion de otras pestanas/permisos.
- Suite completa: 326 seleccionadas, 325 aprobadas y una omitida por Linux.
- PostgreSQL desechable: nueve pruebas RLS y 52 HTTP/WebSocket aprobadas.
- Nueva prueba HTTP mantiene autenticacion real y base sintetica. Sustituye
  solamente el envio del socket para forzar el bloqueo y el proveedor push para
  no contactar servicios externos. Comprueba 201, cierre 1013, mensaje guardado,
  programacion de notificacion al destinatario, GET autorizado, 403 a otro
  conductor y reconexion con ready/pong.
- La suite tambien verifica chat de texto/foto/lectura con pool de una conexion,
  revocacion de sesiones, suspension, reasignacion del conductor, revision admin
  justificada/auditada, precios y estados financieros controlados por backend.
- El ejecutor apaga y elimina su cluster temporal. No usa Railway, Supabase,
  documentos ni pagos reales. No se ejecutaron migraciones sobre una DB existente.
- Segunda revision: sin P1/P2 remanentes en el arreglo acotado. El revisor
  ejecuto las diez unitarias y una sonda con Uvicorn real en loopback y transporte
  frenado: el peer sano recibio, la cancelacion se propago y el cierre supervisado
  termino/libero su referencia al liberar el transporte. No cargo la app ni DB
  en esa sonda, ni repitio la suite PostgreSQL; no es aprobacion de produccion.

## Limites pendientes

- El plazo no es un SLA de toda la peticion: los destinatarios se procesan en
  serie y la consulta de autorizacion conserva sus propios limites de DB.
- El envio depende de cancelacion cooperativa de ASGI; la limpieza TCP puede
  durar mas de 0.5 segundos. Su terminacion depende del timeout del transporte,
  no de ese plazo de espera del broadcast. Faltan pruebas de carga con red lenta
  real, limites globales de conexiones y cantidad de cierres pendientes.
- Un socket retirado no puede recibir nuevos broadcasts del registro, pero no
  se pueden retirar datos que ya estaban en transmision.
- Flutter tiene reconexion con espera creciente. Su evento ready no recarga
  automaticamente todo el historial perdido: el REST conserva el mensaje, pero
  falta mejorar/probar la recuperacion automatica en el dispositivo. Reabrir el
  chat carga el historial. No se declara solucionada la entrega exactamente una vez.
- No demuestra entrega push real: el proveedor esta sustituido en las pruebas.
- No corrige ni exceptua los 42 avisos altos pendientes de la imagen actual.
  Tampoco aprueba la base Wolfi ni modifica Docker, la politica de CI o produccion.

## Archivos

- backend/app/services/chat_connections.py
- backend/tests/test_chat_connections.py
- backend/integration_tests/test_http_permissions.py
- docs/chat-delivery-resilience.md

La revision Linux de esta nueva candidata debe documentarse despues del push;
los resultados locales no sustituyen esa corrida ni las pruebas del hosting.
