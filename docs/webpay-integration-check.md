# Webpay REST: prueba externa de integracion

Actualizado: 2026-09-11. Casos aprobado, rechazado y cancelado verificados en integracion.
No certifica pagos productivos.

## Verificado

- El adaptador real `backend/app/services/transbank_service.py` creo una
  transaccion en `https://webpay3gint.transbank.cl` mediante la API REST oficial.
- Se uso el comercio publico de integracion Webpay Plus y CLP 1.000 ficticios.
  No se usaron credenciales de un comercio real, usuarios ni base de datos.
- La URL devuelta paso las validaciones del adaptador. El formulario POST
  abrio el checkout oficial en el navegador y mostro el monto correcto.
- El 2026-09-11 Rodrigo completo manualmente el checkout con la tarjeta VISA
  publica de prueba. El navegador regreso al servidor local y el adaptador real
  confirmo la transaccion contra Transbank, sin MockTransport.
- Resultado del proveedor: `AUTHORIZED`, `response_code=0`; monto CLP 1.000
  y orden coincidentes, un intento de commit, `outcome=approved`, `passed=true`.
  Inicio 02:59:36 UTC, fin 03:04:42 UTC. La pagina mostro `Resultado: approved`.
  Informe: `.local-tools/webpay-integration/20260911T030442Z-approved-5aac27.json`.
  El servidor temporal termino correctamente y su carpeta temporal se elimino.
- Rechazo con la Mastercard publica de prueba, confirmado manualmente por
  Rodrigo: `FAILED`, `response_code=-1`, monto y orden coincidentes,
  `outcome=declined`, un commit y `passed=true`. Inicio 03:08:02 UTC, fin
  03:11:05 UTC. Pagina de retorno: `Resultado: declined`.
  Informe: `.local-tools/webpay-integration/20260911T031105Z-declined-8b3fd4.json`.
- Cancelacion manual con Anular compra y volver, sin ingresar tarjeta:
  retorno con token de cancelacion coincidente, `outcome=cancelled`, cero
  intentos de commit y `passed=true`. Inicio 03:11:44 UTC, fin 03:12:31 UTC.
  Pagina de retorno: `Resultado: cancelled`.
  Informe: `.local-tools/webpay-integration/20260911T031231Z-cancelled-e8f52b.json`.
  Ambos servidores terminaron y sus carpetas temporales fueron eliminadas.
- La primera sesion, del 2026-09-10, termino por timeout local a las 22:16:23 UTC, con cero intentos
  de commit. Resultado `expired_locally`, `passed=false`; no equivale a una
  transaccion aprobada ni rechazada por Transbank. El servidor fue cerrado.
  Informe: `.local-tools/webpay-integration/20260910T221624Z-approved-1c52bf.json`.
- Regresion local posterior (2026-09-11): 148 unitarias, 9 RLS y 39 HTTP/WebSocket aprobadas.
  Estas ultimas usan respuestas sinteticas en el limite HTTP de Transbank.

## Pendiente

- Probar el recorrido desde Flutter, el callback de la app desplegada y su
  persistencia/idempotencia; este ensayo no usa el router ni la DB de Muvv.
- Captura diferida, devoluciones, conciliacion y liquidaciones no quedan
  implementadas ni certificadas por probar create/commit de Webpay Plus.
- Validar configuracion del comercio y proceso de puesta en produccion con
  Transbank. No habilitar credenciales ni dinero real durante este ensayo.

## Correccion adicional del callback de Muvv

Alta, reproducida localmente y corregida en la candidata, NO desplegada:
el callback anterior aceptaba un numero de orden sin token para marcar un pago
como fallido, incluso si ya estaba autorizado. Tambien mezclaba parametros de
query y formulario sin comprobar duplicados. Se agregaron siete pruebas HTTP;
seis fallaron contra el codigo previo y las siete pasan con la correccion.

- Se exige token de cancelacion y orden del mismo pago para redirigir a su
  detalle. Orden/sesion sin token no consultan ni modifican pagos: retorno
  generico al listado, sin divulgar un ID de flete.
- Un retorno del navegador NO prueba un estado bancario. Cancelacion y error
  de checkout quedan auditados sin tokens y mantienen el pago pendiente de
  confirmacion/conciliacion; no provocan commit ni lo convierten en fallido.
- Los estados autorizado, fallido y reembolsado se conservan ante repeticiones.
  La consulta del callback bloquea la fila mientras comprueba su estado.
- Parametros duplicados, tokens contradictorios y valores fuera de limites
  se rechazan. El error oficial con ambos tokens iguales no se confirma.
- Una confirmacion posterior legitima puede resolver un checkout pendiente.
  Reembolso, conciliacion automatica y concurrencia bajo carga siguen pendientes.

Esta correccion del router se probo sobre PostgreSQL local con respuestas de
proveedor sinteticas. Los tres checkouts externos anteriores usan el adaptador
real y un servidor temporal independiente, no certifican este router desplegado.

## Repetir sin credenciales privadas

Desde la raiz del repositorio:

```powershell
& .\.local-tools\dependency-audit\venv\Scripts\python.exe -B .\scripts\test-webpay-integration.py --expect approved --timeout 600
```

Abrir la URL `CHECKOUT` que imprime la consola. El proceso acepta solo el
ambiente y credenciales PUBLICAS de integracion: descarta variables heredadas,
inicia desde una carpeta temporal sin .env y no importa la base de datos.
Usa el adaptador candidato, sin mocks para create/commit.

En el checkout, usar exclusivamente las tarjetas de integracion que publica
Transbank. La confirmacion final debe hacerla la persona que realiza la prueba.
No guardar datos de tarjeta en el navegador ni usar datos personales reales.

El ensayo termina al recibir el retorno o transcurridos 600 segundos. Un timeout
local NO equivale a rechazo del proveedor: significa resultado no comprobado.
Se puede volver a iniciar para generar una prueba nueva; no reutilizar el enlace
anterior. `--expect declined` y `--expect cancelled` permiten repetir los otros
casos; no seleccionan una respuesta ficticia del proveedor.

## Protecciones y evidencia

- Servidor temporal solo en 127.0.0.1, puerto aleatorio, ruta impredecible,
  Host comprobado, formulario limitado y tokens comparados en tiempo constante.
- Sin logs de URLs de retorno, tokens, cabeceras o respuesta cruda. Tokens
  solo en memoria; no hay almacenamiento de tarjetas ni credenciales bancarias.
- Un intento de commit como maximo por ensayo; sin reintentos tras un error.
  Monto, orden, estado y codigo de respuesta comprobados antes de aprobar.
- Resultados depurados en `.local-tools/webpay-integration/`, excluidos de Git.
  El lanzador elimina su carpeta temporal al cerrar. El timeout o interrupcion
  se informa como incompleto, nunca como exito.
- Cinco pruebas del lanzador comprueban aislamiento del entorno, validacion de
  resultado y limites de formularios. No se altero configuracion productiva.

## Fuentes oficiales

- [Ambiente, tarjetas y credenciales publicas](https://www.transbankdevelopers.cl/documentacion/como_empezar#tarjetas-de-prueba)
- [Contrato REST de Webpay](https://www.transbankdevelopers.cl/referencia/webpay)
- [Retornos normales, timeout, cancelacion y error](https://www.transbankdevelopers.cl/documentacion/webpay-plus)
