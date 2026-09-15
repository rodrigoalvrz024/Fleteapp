# Recuperacion segura del chat movil

Fecha: 2026-09-15. Cambio candidato en Flutter, sin instalar APK ni desplegar.
Continua la proteccion del transporte en [chat-delivery-resilience.md](chat-delivery-resilience.md).

## Resultado

Al recibir ready de una conexion nueva, el cliente consulta el resumen y el
historial persistido. Recorre paginas de hasta 80 mensajes usando before_id,
hasta enlazar con el mensaje mas antiguo mostrado o agotar el historial.
Asi recupera huecos mayores que una pagina sin cambiar endpoints ni backend.
Deduplica por ID, conserva el orden y tambien recupera los metadatos de fotos.
No se reenvian mensajes o fotos automaticamente ni se crean cargos.

## Protecciones

- Cada conexion/recarga tiene una generacion. Respuestas y callbacks de una
  generacion anterior se descartan; dispose invalida callbacks y temporizadores.
- ready duplicado no inicia consultas adicionales para esa conexion.
- Los fallos transitorios reintentan con esperas de 1, 2, 4, 8 y hasta 15 segundos.
  La frontera de recuperacion se conserva durante los reintentos.
- 401/403 en recuperacion o recarga manual borra estado privado, impide nuevos
  envios, detiene reintentos e invalida respuestas pendientes. Un envio anterior
  que termine despues no restaura datos en esa instancia denegada.
- El proveedor observa la identidad de la cuenta: otra cuenta recibe una
  instancia nueva, sin historial ni respuestas pendientes de la anterior.
- El cierre/cancelacion del transporte antiguo no bloquea la conexion nueva.
  Se manejan errores tardios y se limita la espera de cleanup a dos segundos;
  eso no garantiza terminar la operacion subyacente en ese plazo.
- El estado recibido en vivo no se sobrescribe con un resumen REST mas antiguo.
- Un evento read solicita reconciliacion REST; si llega durante una consulta,
  se repiten las paginas afectadas. No se deduce lectura por fecha ni se aplica
  una marca de lectura a mensajes que el servidor todavia no ha confirmado.
- El marcado tras recuperacion se consume antes de enviar la solicitud. Un
  recibo puede actualizar REST, pero no dispara otro marcado por si mismo.

## Revision y pruebas

Segunda revision estatica independiente realizada. Identifico carreras de
recarga/respuestas tardias, riesgo de inferir lecturas por fechas y un caso de
denegacion en refresh; se corrigieron y cubrieron con pruebas. No encontro
P1/P2 remanentes en estas correcciones. El revisor no ejecuto Flutter; no es
una auditoria profesional de toda la app ni aprobacion de produccion.

Verificacion local final:

- 52 pruebas Flutter aprobadas, dos omitidas porque son capturas opcionales sin
  directorio de salida configurado. Incluye regresiones existentes de splash,
  login/roles, navegacion de pagos, carga/vehiculos y texto ampliado.
- 18 pruebas del chat: 3 previas y 15 nuevas. Transporte y repositorio ficticios,
  sin JWT reales, documentos, pagos, Firebase, Railway ni Supabase de produccion.
- Recuperacion de 170 mensajes por varias paginas, fotos, ready duplicado,
  reintento, mensaje en vivo durante REST, read antes de la pagina, insercion
  creada antes del recibo pero confirmada despues (permanece no leida), cambio
  de cuenta, dispose, refresh obsoleto, 403 y envio tardio.
- Dos pruebas hacen que markRead emita un read: con/sin mensaje durante
  recuperacion. Ambas se estabilizan en dos marcados y tres consultas de
  historial, sin nuevas llamadas al avanzar 30 segundos el reloj de pruebas.
- flutter analyze de los dos archivos modificados: sin observaciones.

Comandos desde mobile:

```powershell
flutter test --no-pub
flutter analyze --no-pub lib/providers/chat_provider.dart test/chat_provider_test.dart
```

## Pendiente antes de instalar/publicar

No hay prueba nueva en telefonos ni compilacion release en esta ronda. Las
pruebas no demuestran entrega push real, visualizacion de fotos descargadas,
comportamiento con red movil real o reanudacion del proceso tras suspension.
Falta probar con ambos telefonos: desconectar receptor, enviar texto/foto,
reconectar, comprobar ausencia de duplicados/lecturas falsas y cambio de cuenta.
La paginacion es secuencial y no tiene presupuesto total de paginas por sesion;
medir conversaciones largas y volumen de reintentos antes de abrir el piloto.

No cambia diseno, splash, contratos API, precios, configuracion de infraestructura
ni dependencias. No se han contratado servicios ni actualizado produccion.
Los 44 hallazgos altos pendientes de la ultima candidata Docker siguen
bloqueando el despliegue; este cambio movil no los corrige ni los exceptua.

Archivos: mobile/lib/providers/chat_provider.dart,
mobile/test/chat_provider_test.dart y este informe.
