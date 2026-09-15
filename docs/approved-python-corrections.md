# Reconocimiento acotado de correcciones Python

Fecha: 2026-09-15. Autorizacion expresa del propietario en esta tarea:
"Si, reconocer solo esas tres correcciones verificadas". NO autoriza despliegue,
aceptacion de los otros avisos ni una excepcion general para Python.

Identificador: `muvv-owner-python-three-20260915`.
Vigencia UTC: desde 2026-09-15 hasta antes de 2026-10-15. No se renueva sola.

## Alcance exacto

Solo CVE-2026-3644, CVE-2026-4224 y CVE-2026-7210, cada una con exactamente una
coincidencia High de `python` binario `3.11.16`, namespace `nvd:cpe`, matcher
`stock-matcher`. No alcanza a paquetes Debian, otras versiones o duplicados.
Clasificacion: `vendor_fix_verified`, no aceptacion de codigo vulnerable.

Se reutiliza el validador revisado de cookies, recursion y ejecucion XML.
Exige Expat 2.8.3, ABI C de 224 bytes, pruebas aprobadas y estos hashes:

- pyexpat: `27e28ee2600c7d6347130227616e4fd5ae1c59800ad01fa12e1f23c6f41f34e3`.
- _elementtree: `03bb0f3a57760a0afe252ffbb41acd6492552a2115ada2e42a277075ce7f49c5`.

Para cada parser: tres llamadas observadas a la funcion de 16 bytes, ninguna
heredada, tres lecturas validas, salida cero y los mismos modulos antes/despues.
No se mide calidad estadistica de entropia ni todos los usos posibles de XML.

Fuente del arreglo: [Python 3.11.16](https://www.python.org/downloads/release/python-31116/).
Evidencia previa y limites: [revision conjunta](security-batch-review.md).

## Funcionamiento del control

- Grype y su configuracion no cambian. El reporte completo se valida contra
  la identidad inmutable de la imagen, sin aceptar `ignoredMatches`.
- Los originales sanitizados se publican ANTES de revisar la autorizacion.
  Siguen visibles si falta evidencia, un hash cambia o vence el permiso.
- Las pruebas de backports se ejecutan por ID de imagen; su JSON se vincula a
  commit y corrida, se conserva 14 dias como artefacto y tambien en anotacion.
  La traza XML debe usar el mismo ID de imagen. No se publican variables de
  entorno, contenido del filesystem ni argumentos de entropia.
- El reporte conserva `original_counts`, `remaining_counts` y las tres filas
  reconocidas. Un High/Critical restante o alerta de paquete/EOL bloquea.
- Evidencia invalida, ausente, cambiada o vencida devuelve codigo 2, nunca exito.
  No hay `continue-on-error`, cambios al informe original ni excepciones DHI.
- Esto confia en el workflow y scripts revisados de la misma corrida; no es una
  atestacion firmada independiente. Proteger permisos de escritura del repositorio.
- Aunque no queden High/Critical, `deployment_approved` siempre es falso;
  los avisos medios y los demas requisitos de lanzamiento requieren revision.

## Proteccion del transporte del chat

El CMD `python -m app.server` fija backend WebSocket `websockets`, mensajes de
entrada de hasta 16 KiB, cola de cuatro y compresion per-message desactivada.
Antes dependia de los valores por defecto del servidor (mensajes/colas mayores).
Las fotos se suben por HTTP y no pasan por este limite de entrada WebSocket.

La prueba de transporte real conserva login y ping/pong, no negocia compresion,
rechaza un primer mensaje de 16385 bytes y un mensaje fragmentado que supera
16 KiB con codigo 1009. No produce errores internos al cerrar dos veces un
socket que el transporte ya rechazo. Sigue pendiente limitar conexiones totales
en el proxy/hosting: los limites por conexion no son proteccion DDoS completa.
El arranque directo mediante otro comando Uvicorn no hereda estas opciones.

## Verificacion local

- 303 unitarias seleccionadas: 302 aprobadas y una omitida por requerir Linux.
- 51 HTTP/WebSocket aprobadas sobre PostgreSQL desechable, incluidos roles,
  sesiones, pagos sinteticos, subida de fotos y transporte real; nueve RLS pasan.
- Once pruebas nuevas del control cubren identidades distintas, duplicados,
  paquete/version incorrectos, expiracion, pruebas fallidas, evidencia ausente,
  preservacion de originales y contrato del workflow. Doce bloques Bash validos.
- Segunda revision de codigo: dos problemas de conservacion de evidencia
  detectados y corregidos; segunda pasada sin P1/P2 remanentes en este alcance.

No se cambiaron la APK, splash, diseno, datos reales, servicios ni sus planes.
Solo se usa la cuota existente de GitHub Actions y un artefacto JSON pequeno.
La comprobacion Linux nueva se registra al terminar, sin anticipar aprobacion.
