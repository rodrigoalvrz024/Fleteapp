# Camionetas para cargas pequenas de hogar u oficina

## Regla autorizada

Se admite `pickup` para `home_office` cuando el vehiculo esta aprobado,
no eliminado, tiene capacidad suficiente de peso/volumen y el servicio esta
habilitado para ese vehiculo. No cambia la tarifa ni los pedidos existentes.
Una mudanza sigue requiriendo como minimo `truck_medium`.

Las listas explicitas de `supported_service_types` existentes se respetan.
Los nuevos registros obtienen `home_office` en los servicios por defecto de
camioneta. No se migra ni amplia automaticamente una lista restringida antigua.
Antes del piloto, revisar con administracion los servicios del vehiculo concreto;
no concluir que el flete #109 sera visible solo por desplegar esta regla.

## Aviso al conductor

El detalle de hogar/oficina muestra un aviso para revisar capacidad, sujecion y
proteccion contra lluvia, polvo y golpes cuando se use una caja abierta.
Las tres rutas de aceptacion de la app muestran la misma confirmacion antes de
enviar la solicitud. Cerrar el aviso o pulsar Volver no acepta el flete.

La confirmacion no sustituye la inspeccion fisica, no modifica capacidades
declaradas y no implica que una carga fragil o incompatible deba transportarse.

## Contrato del backend

`PUT /freights/{id}/accept` admite el booleano estricto opcional
`cargo_safety_acknowledged` (false por defecto).

Despues de validar conductor, pago y compatibilidad, el backend selecciona el
vehiculo real. Si es pickup para hogar/oficina exige la confirmacion; sin ella
responde 409 antes de asignar o confirmar cambios. No basta con alterar el ID
del vehiculo ni con enviar el booleano para saltar los controles anteriores.

El evento de auditoria existente `freight.accepted` registra el booleano y la
version `pickup_home_office_v1` cuando corresponde. Esto registra la confirmacion
del cliente software, no demuestra que una persona haya leido el texto.

## Despliegue y limites

1. Revisar/aprobar los cambios y los controles de seguridad pendientes.
2. Desplegar el backend compatible antes de distribuir la nueva APK.
3. Actualizar las apps del piloto y verificar el aviso en ambos caminos activos
   (solicitud entrante y detalle).
4. Revisar servicios/capacidades/aprobacion del vehiculo de prueba; no modificar
   datos reales ni permisos para forzar una coincidencia.
5. Repetir la aceptacion controlada del flete QA, las fotos y el chat, sin iniciar
   un viaje ni repetir el pago.

Las apps anteriores quedan bloqueadas para el nuevo caso pickup/hogar por falta
de confirmacion si solo hay camioneta apta o se solicita esa camioneta expresamente.
Si no se especifica vehiculo y tambien existe un furgon/camion compatible, la
seleccion automatica sin confirmacion prefiere ese vehiculo. Los otros casos
mantienen compatibilidad sin cuerpo de solicitud.
La APK nueva envia un campo que el backend antiguo rechaza: no instalarla antes
del despliegue compatible. No se alteraron el splash, la reserva ni el pago #109.

Esta implementacion local no implica un despliegue, publicacion de APK o
aprobacion general de seguridad. La APK 1.0.14 ya instalada no contiene este aviso.

## Pruebas

Verificacion local del 15 de septiembre de 2026: 26 pruebas enfocadas del backend
aprobadas y suite Flutter completa con 63 aprobadas y 2 capturas opcionales
omitidas. Analisis focalizado de Flutter: sin errores nuevos; persisten cinco
sugerencias `const` en el componente previo de ubicacion y una advertencia por
el dialogo legado `_showIncomingFreight` sin uso, comprobados contra HEAD.

- Backend: cotizacion contra matching para todas las opciones ofrecidas;
  limites de capacidad, aprobacion, servicios explicitos y mudanza;
  confirmacion estricta; rechazo sin escritura cuando falta el aviso;
  aceptacion confirmada con auditoria; pago/vehiculo invalidos; compatibilidad
  de los casos anteriores. Las pruebas de endpoint usan una base simulada.
- Flutter: aviso antes de enviar; cancelar/cerrar sin aceptar; confirmacion
  explicita en el body; sin confirmacion por defecto; pantalla 320x640 y texto 2x.

## Revision adicional antes del push

La revision independiente no encontro un bypass nuevo de permisos. Confirmo que
las pickups antiguas con listas persistidas no se habilitan por este cambio:
la procedencia de una lista automatica antigua no se puede distinguir de una
restriccion deliberada. Se requiere habilitacion administrativa explicita antes
de probar con uno de esos vehiculos. No se modificaron registros existentes.

Se corrigio la seleccion con pickup y furgon simultaneos para conservar el flujo
de apps antiguas sin omitir el aviso del nuevo caso. Se agregaron pruebas para
vehiculo ajeno, pickup explicita sin confirmar y fallback a furgon compatible.
Las pruebas HTTP comprueban 401 sin sesion, 403 para cliente/administrador
(aunque la cuenta tenga ambos modos), booleano estricto y rechazo de campos
criticos adicionales. Usan autenticacion sustituida salvo el caso anonimo y
base simulada; no sustituyen pruebas con PostgreSQL ni dispositivos reales.

Suite backend ampliada: 344 pruebas ejecutadas, 343 aprobadas y una omitida
por requerir Linux. Persiste un aviso de deprecacion de TestClient/httpx; no
se cambiaron dependencias en esta entrega. Queda pendiente validar las rutas
reales de home y detalle en el telefono despues del despliegue compatible.
