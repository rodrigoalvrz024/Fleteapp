# Conciliacion protegida de Webpay

Validacion previa al commit, 2026-09-21: implementacion probada localmente, sin
deploy, cobros, consultas a Transbank real ni cambios en Flutter. Complementa la revision de
`security-payment-concurrency-2026-09-21.md`, no aprueba produccion.

## Objetivo

Recuperar el resultado de un checkout pendiente cuando se pierde el retorno del
navegador o la respuesta del commit. No crear ni confirmar otra operacion bancaria.

Transbank documenta la consulta de estado hasta siete dias desde la creacion:
[referencia oficial](https://proyecto-ejemplo-node.transbankdevelopers.cl/api-reference/webpay-plus).
La operacion usa GET sobre el token existente, como muestra el
[SDK oficial](https://github.com/TransbankDevelopers/transbank-sdk-python/blob/master/transbank/webpay/webpay_plus/transaction.py).
No interpretar un 404, un timeout o la ausencia de respuesta como rechazo bancario.

## Contrato local

`POST /payments/{payment_id}/reconcile`, autenticado, cuerpo JSON `{}`.
No acepta monto, token, orden ni estado suministrados por el cliente.

- Cliente: solo su propio pago y con rol activo client.
- Administrador: puede conciliar un pago ajeno; la session_id esperada sigue siendo
  la del propietario, no la del administrador.
- Conductor y terceros: rechazados antes de consultar al proveedor.
- Respuesta: payment_id, freight_id, status local y result. Sin tokens ni datos de tarjeta.
- Limites: 20 peticiones por usuario y seis por pago en 15 minutos. Usan el limitador
  existente en memoria por proceso, no una cuota distribuida entre replicas.
- Lectura preliminar escalar; bloqueo Freight -> Payment, espera acotada y rollback
  en todas las salidas. GET con timeout, sin redirects ni reintentos automaticos.

## Decisiones

| Situacion | Resultado | Cambio local |
| --- | --- | --- |
| Pago local authorized, failed o refunded | unchanged | Ninguno; sin llamada externa. |
| Pago simulado, sin checkout o de otro metodo | HTTP 409 | Revision manual; sin llamada externa. |
| Orden, sesion o monto no coinciden | HTTP 503 | Conservar pendiente. |
| Respuesta invalida, error HTTP o timeout | HTTP 503 | Conservar pendiente. |
| AUTHORIZED, codigo 0, autorizacion no vacia e identidad exacta | resolved | Autorizar mediante el mismo helper del callback. |
| FAILED, codigo negativo e identidad exacta | resolved | Marcar fallido; otro checkout requiere una peticion explicita posterior. |
| INITIALIZED | pending | Conservar pendiente. |
| Reversa, anulacion, captura u otro resultado no soportado | review_required | Conservar pendiente; no habilitar otro checkout. |
| Confirmacion autorizada tardia de flete cancelado | review_required | Registrar pago autorizado sin reabrir flete ni crear payout. |

La finalizacion compartida registra auditoria y snapshot. Crea una liquidacion
pendiente solo para un flete completado elegible; no transfiere dinero. La consulta
autenticada registra actor y resultado en payment.reconciled. Las repeticiones de
estados finales no duplican la transicion ni programan de nuevo el aviso.

## Validacion

Se agregaron seis pruebas de contrato REST y trece pruebas HTTP con PostgreSQL
temporal. Cubren GET sin body, validacion estricta, errores saneados, roles,
identidad, replays, callback concurrente, recuperacion de confirmacion perdida,
rechazo confirmado, estados inciertos, limites y programacion unica de avisos.

Segunda revision estatica: sin P1/P2 nuevos en el diff acotado. El revisor no
ejecuto pruebas ni verifico el contrato externo por su cuenta.

Resultado final local:

- Python 3.11 y 3.14.7: 390 pruebas por entorno, 388 aprobadas y dos omitidas por
  requerir Linux. No sumar ambas versiones como cobertura distinta.
- PostgreSQL 18.3 con TLS: 109 pruebas aprobadas (84 HTTP, nueve RLS, cinco TLS y
  once de migraciones). Cluster temporal detenido y eliminado correctamente.
- `git diff --check` sin errores. Estos resultados no incluyen GitHub Actions;
  los controles Linux del commit deben verificarse por separado.

## Antes de publicar

1. Conectar una accion de comprobacion explicita en la pantalla de pagos. No hay
   un boton nuevo ni comprobacion periodica automatica en esta entrega.
2. Comprobar casos reales en Transbank integracion con autorizacion del propietario.
   Las pruebas locales usan respuestas simuladas y no certifican liquidacion bancaria.
3. Resolver pendientes antiguos, checkout vencido y anulaciones con un procedimiento
   administrativo; no resetear token/orden ni ejecutar devoluciones automaticamente.
4. Conservar un historial de intentos y resolver durabilidad de notificaciones tras
   caidas. La programacion unica por concurrencia no garantiza entrega exactamente una vez.
5. Validar Cloud Tasks y limites distribuidos antes de multiples replicas. El test
   nuevo de avisos cubre el envio directo, no Cloud Tasks.
6. Ejecutar CI/Linux y resolver el control de seguridad Docker antes de aprobar deploy.

Archivos de este paso: routers/payments.py, schemas/payment.py,
services/transbank_service.py, tests/test_transbank_rest.py e
integration_tests/test_http_permissions.py, todos dentro de backend.
