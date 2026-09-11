# Muvv - Auditoria de dependencias del backend

Fecha: 2026-09-10. Estado: candidata local probada, NO desplegada.

## Resultado

- Auditoria inicial de las 85 versiones del manifiesto: 14 paquetes afectados.
  El reporte contiene 36 pares paquete/identificador distintos, con aliases y
  duplicados; no interpretar ese numero como 36 vulnerabilidades explotables.
- Los 14 paquetes iniciales quedaron actualizados o retirados de la candidata.
- Auditoria intermedia: 89 paquetes, un aviso en Marshmallow 3.26.1. Se conservo
  ese reporte con su codigo de salida 1, sin excepciones ni avisos ocultos.
- Segunda pasada: SDK Transbank y Marshmallow retirados; adaptador REST oficial
  implementado. Auditoria final del entorno completo: 87 paquetes, cero avisos
  conocidos y cero paquetes omitidos. Codigo de salida 0, sin `--ignore-vuln`.
- `pip check`: sin incompatibilidades. 148 pruebas unitarias, 9 de RLS y
  39 HTTP/WebSocket aprobadas (regresion del 2026-09-11). Incluye Uvicorn real solo en loopback.
- Los ResourceWarning de streams de AnyIO observados con la combinacion
  anterior ya no se reprodujeron. La suite ahora falla si quedan recursos
  sin cerrar despues de limpiar clientes y ejecutar el recolector.

Los alcances de los dos escaneos difieren: el primero uso `--no-deps` sobre
requirements; el segundo inspecciono todas las distribuciones instaladas.
El hallazgo transitivo de Marshmallow no aparecia en el manifiesto inicial.
Esto no certifica ausencia de otras vulnerabilidades ni es una auditoria del
contenedor Linux, del SO, de Flutter o del servicio desplegado.

## Priorizacion

1. Alta: procesamiento de formularios y archivos en Starlette y
   python-multipart. Hay rutas reales que reciben archivos y un callback que
   procesa formularios. Se actualizaron y se agregaron pruebas de rechazo de
   mas de 1000 campos y de campos mayores a 1 MiB, sin llamar al proveedor.
2. Alta preventiva: retirar python-jose 3.3.0 y su dependencia ecdsa. El aviso
   de confusion de algoritmo de python-jose esta clasificado como critico por
   el proveedor, pero no se demostro explotacion aqui: Muvv fija HS256 y no usa
   claves OpenSSH ni JWE. El ataque de ecdsa tampoco corresponde a la firma HMAC
   actual. Se elimina igualmente esa superficie usando PyJWT ya presente.
3. Media / dependiente del uso: restantes avisos de bibliotecas de criptografia,
   parsing, serializacion y herramientas. Se aplicaron versiones corregidas;
   no se afirma que todos tuvieran una ruta explotable desde Muvv.
4. Media resuelta en candidata: Marshmallow, CVE-2025-68480 / GHSA-428g-f7cq-pgp5.
   Se elimino junto con el SDK que lo requeria; ver solucion REST mas abajo.
5. Baja operativa: deprecacion de TestClient con httpx. No es el ResourceWarning
   anterior ni un fallo de permisos; planificar actualizacion del cliente de
   pruebas sin cambiar los transportes salientes de la app innecesariamente.

## Versiones

| Paquete | Antes | Candidata |
| --- | --- | --- |
| click | 8.3.1 | 8.3.3 |
| cryptography | 46.0.6 | 50.0.1 |
| ecdsa | 0.19.2 | Retirado |
| httplib2 | 0.31.2 | 0.32.0 |
| idna | 3.11 | 3.15 |
| Mako | 1.3.10 | 1.3.12 |
| msgpack | 1.1.2 | 1.2.1 |
| pyasn1 | 0.6.3 | 0.6.4 |
| PyJWT | 2.12.1 | 2.13.0 |
| python-jose | 3.3.0 | Retirado |
| python-multipart | 0.0.27 | 0.0.31 |
| Starlette | 0.37.2 | 1.6.0 |
| ujson | 5.12.0 | 5.13.0 |
| urllib3 | 2.6.3 | 2.7.0 |

Compatibilidad necesaria del framework: FastAPI 0.141.1, Pydantic 2.13.5,
pydantic-core 2.46.5 y typing-inspection 0.4.4. Se fijo la transitiva
google-cloud-storage 3.14.1. Marshmallow, fijado en la pasada intermedia, ya
no esta en el manifiesto ni en el entorno candidato, igual que transbank-sdk.
No se modifico `backend/venv`: las instalaciones se hicieron en
`.local-tools/dependency-audit/venv`. Sus herramientas locales quedaron en
pip 26.2.1, setuptools 84.0.0 y wheel 0.48.0; esto NO actualiza la imagen Docker.

## JWT y enlaces privados

- Misma clave configurada, HS256, emisor, audiencia, identidad y tipos de token.
  El rol efectivo sigue viniendo de la base, no de una declaracion del JWT.
- Se exigen exp, iat, iss, aud y sub para acceso; exp para enlaces privados.
  Tokens incompletos o invalidos devuelven 401; enlaces invalidos devuelven 404.
- No se cambia la derivacion de claves por proposito para documentos, fotos
  de carga, evidencias o imagenes de chat; no se vuelven enlaces publicos.
- Fixtures sinteticos generados con python-jose 3.3.0 verifican compatibilidad
  de un token de acceso y un enlace de documento. Los cuatro propositos tienen
  pruebas de expiracion, uso cruzado y prohibicion de autenticar como usuario.
  Los fixtures no contienen secretos reales y no prueban sesiones de produccion.

## Solucion del aviso de Transbank

La ultima version publicada consultada, transbank-sdk 6.1.0, declara
`marshmallow<=3.26.1,>3`. El parche del aviso esta en 3.26.2 / 4.1.2: forzarlo
romperia el contrato de dependencias declarado. No se uso `--no-deps`, un fork
ni un parche global de terceros para simular que el aviso esta resuelto.

El aviso afecta `Schema.load(..., many=True)`. En la pasada anterior se verifico
que el adaptador no llamaba a esa funcion, pero eso no eliminaba el paquete.
Ahora se retiraron ambos paquetes y sus imports. Las funciones publicas
`create_webpay_transaction` y `commit_webpay_transaction` conservan sus entradas
y resultados; internamente usan httpx contra la API REST oficial de Webpay Plus.
No se reemplazo Transbank como proveedor ni se cambio la modalidad de cobro.

Protecciones del adaptador nuevo:

- Hosts oficiales fijos por ambiente; produccion requiere las dos variables
  existentes y no usa valores de prueba como fallback. Un ambiente desconocido
  se rechaza. Los valores predeterminados de integracion son los publicos de
  la documentacion, nunca credenciales de un comercio real.
- TLS verificado por httpx, sin redirects ni proxy heredado del entorno.
  Timeout de conexion 5 s y lectura 30 s; respuesta limitada a 64 KiB.
- Sin reintentos automaticos. Un timeout del callback deja el pago pendiente;
  no se supone aprobado ni se inventa una confirmacion.
- Datos de entrada y respuesta validados; CLP entero positivo al crear,
  montos no finitos/fraccionarios rechazados al confirmar. No se envia precio
  ingresado directamente por el frontend.
- URL de pago devuelta limitada al host del ambiente; tokens validados antes
  de incluirlos en una ruta. Errores externos genericos sin cuerpos/credenciales.
- Logs INFO de httpx hacia Webpay depurados porque la URL de commit incluye
  el token. Esto no certifica todos los logs del proxy ni los de otros modulos.

Pruebas: 16 contratos unitarios del adaptador con MockTransport y cuatro pruebas
HTTP de pagos sobre PostgreSQL sintetico. Se comprobo precio del backend,
permisos, monto/orden incorrectos, rechazo, callback repetido y timeout pendiente.
Estas pruebas usan respuestas sinteticas. El ensayo externo del 2026-09-11
completo creacion, checkout manual, retorno y commit reales contra el ambiente
de integracion: AUTHORIZED, codigo 0, monto/orden coincidentes, un commit.
Rechazo tambien verificado (FAILED, codigo -1, un commit) y cancelacion con
cero commits. No hubo dinero real ni base de datos de Muvv.
Ver `docs/webpay-integration-check.md`.
No se hizo
reserva, captura, reembolso ni liquidacion real, ni se agregaron esas funciones.

## Evidencia y repeticion

Reportes locales excluidos de Git: `.local-tools/dependency-audit/before.json`,
`after.json` (intermedio), `after-webpay-rest.json` (final, cero avisos),
`install.json` (instalacion intermedia). Auditor: pip-audit 2.10.1;
Python 3.11.9 en Windows. El entorno inicial del usuario sigue sin modificarse.

Desde la raiz, usando el entorno aislado ya preparado:

```powershell
& .\.local-tools\dependency-audit\venv\Scripts\python.exe -m pip check
& .\backend\venv\Scripts\python.exe -B -m pip_audit --path .local-tools/dependency-audit/venv/Lib/site-packages --progress-spinner off --format json --output .local-tools/dependency-audit/after-webpay-rest.json
& .\.local-tools\dependency-audit\venv\Scripts\python.exe -B .\scripts\test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --http
```

El ultimo comando crea y elimina PostgreSQL temporal con usuarios sinteticos,
sin .env ni credenciales de produccion. No ejecutar las pruebas contra Supabase.
El reporte HTTP detalla permisos, aislamiento y limitaciones adicionales.

## Archivos de esta correccion

- backend/requirements.txt
- backend/app/core/security.py
- backend/app/services/storage_service.py
- backend/app/services/transbank_service.py
- backend/app/routers/payments.py (callback endurecido en la pasada del 2026-09-11)
- backend/tests/test_security_hardening.py
- backend/tests/test_jwt_compatibility.py
- backend/tests/test_transbank_rest.py
- backend/integration_tests/test_http_permissions.py
- docs/backend-dependency-audit.md
- docs/http-permissions-regression.md
- docs/mvp-deployment-plan.md

## Antes de publicar

Actualizacion del 2026-09-11: las 39 pruebas HTTP tambien pasaron usando toda la
historia Alembic. Se detectaron seis tablas y 36 columnas omitidas por esa historia
y se preparo `f6b8c0d2e411`, sin DML financiero. Ocho pruebas por cada escenario
(vacio/previo simulado) aprobadas. Esto no cambia el reporte de dependencias;
alcance y orden de publicacion: `docs/backend-release-candidate.md`.

- Revisar diff y secretos del conjunto de commits; no incluir cambios mobile,
  web, marketing ni archivos privados junto con esta candidata de backend.
- Construir y auditar la imagen Linux final y sus paquetes del SO; comprobar
  migraciones y compatibilidad con el esquema real en un entorno separado.
- Repetir pruebas funcionales en Railway y dispositivos, incluyendo OAuth,
  Storage, notificaciones, reconexion y el ciclo completo del flete.
- Medir latencia, memoria y concurrencia bajo carga: la prueba local de
  Uvicorn es breve, no demuestra estabilidad prolongada ni proxy/TLS correcto.
- Repetir desde Flutter y el backend candidato desplegado. Aprobacion,
  rechazo y cancelacion pasaron en integracion externa el 2026-09-11; esto
  no prueba persistencia en DB ni toda la operacion de pagos.
- Publicar y revalidar la correccion adicional del callback: el numero de
  orden ya no permite cambiar el estado financiero sin token. Cancelacion y
  error del navegador se registran sin modificar el pago; estados terminales
  preservados y entradas ambiguas rechazadas. Siete regresiones HTTP nuevas
  aprobadas; el hallazgo alto solo esta corregido localmente.
- No hubo commit, push, deploy, cambio de datos reales, APK ni cambio de Splash.
  La recuperacion en otro computador sigue para el cierre final por solicitud.

## Fuentes oficiales consultadas

- [Starlette: limites de formularios](https://github.com/Kludex/starlette/security/advisories/GHSA-82w8-qh3p-5jfq)
- [Starlette: historial, incluido cierre de streams](https://www.starlette.io/release-notes/)
- [python-jose: confusion de algoritmo](https://github.com/advisories/GHSA-6c5p-j8vq-pqhj)
- [PyJWT: correcciones de 2.13.0](https://pyjwt.readthedocs.io/en/stable/changelog.html)
- [Cryptography: correcciones y versiones](https://cryptography.io/en/latest/changelog/)
- [Marshmallow: aviso y versiones corregidas](https://github.com/marshmallow-code/marshmallow/security/advisories/GHSA-428g-f7cq-pgp5)
- [Transbank: metadatos de la version publicada](https://pypi.org/pypi/transbank-sdk/6.1.0/json)
- [Webpay Plus: contrato REST oficial](https://www.transbankdevelopers.cl/referencia/webpay)
