# Muvv - Regresion local de permisos HTTP

Actualizado: 2026-09-11. Resultado: 39/39 pruebas HTTP/WebSocket, 9/9 pruebas RLS
y 148/148 pruebas unitarias aprobadas con las dependencias candidatas.
No es una aprobacion de produccion. La corrida previa del 2026-09-09 fue
24/24 HTTP, 9/9 RLS y 118/118 unitarias.

## Entorno y aislamiento

- PostgreSQL 18.3 temporal, escucha solo en 127.0.0.1, puerto libre y SCRAM.
- Base nueva con nombre aleatorio y 20 tablas creadas recorriendo la historia
  Alembic completa hasta `f6b8c0d2e411`, mas la tabla de version de Alembic.
- Rol propietario de aplicacion sin superusuario, BYPASSRLS ni permiso para
  crear roles o bases. Las peticiones no usan el superusuario del cluster.
- La historia incluye RLS de `f2a4b6c8d010` y la revision aditiva que completa
  tablas/columnas antes ausentes. El verificador confirma 20 tablas y cero
  permisos efectivos de tabla/columna para anon/authenticated.
- FastAPI real, rutas, middleware, serializacion, JWT y consultas SQL reales.
  TestClient en proceso y una prueba adicional con Uvicorn real en loopback.
  Sin servidor publicado externamente ni sustitucion de get_current_user,
  require_role o get_db.
- Usuarios, mensajes, vehiculos, coordenadas y pagos son fixtures sinteticos.
  El proceso hijo recibe un entorno limpio, sin .env ni credenciales externas.
- HTTP saliente bloqueado en los transportes; intentos Python de conexion
  fuera de loopback abortan la prueba. Storage y push se sustituyen unicamente
  en sus fronteras externas. Ningun archivo ni mensaje se envio a un proveedor.
- Cluster apagado y directorio temporal eliminado. La carpeta de ejecuciones
  quedo vacia. No se leyeron ni modificaron datos de produccion.

## Cobertura comprobada

| Area | Resultado observado |
| --- | --- |
| JWT | Sin token, invalido, expirado o audiencia incorrecta: 401. Usuario suspendido con token valido: 401. Declarar admin en el JWT no cambia el rol de la base. |
| Login | Contrasena hasheada funciona; el noveno intento fallido para un correo devuelve 429. |
| Fletes | Cliente propietario y conductor asignado acceden; otros usuarios no acceden cambiando el ID. Listados excluyen el flete ajeno. |
| Asignacion | Requiere pago autorizado, conductor aprobado y vehiculo propio aprobado/compatible. Otra aceptacion no reemplaza al conductor ya asignado. |
| Compatibilidad | Una pickup no recibe la solicitud de van; la mudanza requiere camion compatible. Retirar aprobacion al vehiculo impide operar. |
| Rechazos | La solicitud rechazada sale de disponibles y ese conductor no puede aceptarla. |
| Datos criticos | Precio, propietario, conductor y estado inyectados al crear el flete se rechazan antes de cotizar. Campos criticos extra en cambio de estado: 422. |
| Fotos de carga | Solo propietario, asignado o admin obtiene enlaces. Token manipulado o referencia reemplazada: 404 y sin lectura de Storage. |
| Chat | Participantes envian, leen y marcan lectura. Ajenos y admin no pueden participar. Chat completado queda solo lectura. |
| Revision administrativa | Requiere admin y motivo valido; queda auditoria con actor y razon. No marca mensajes leidos ni los modifica. |
| Imagenes de chat | Acceso se comprueba antes de llamar al almacenamiento. La respuesta no revela attachment_ref. |
| WebSocket | Cliente y conductor reciben ready/pong. Ajenos/admin: cierre 4403; token invalido: 4401. |
| Evaluacion | Solo participantes despues de completar, preguntas segun rol y rechazo de duplicados. Se guardan ambas evaluaciones. |
| Ubicacion | Solo asignado escribe; ajenos no leen. Se oculta antes de la ventana y despues de completar. |
| Perfil | Cambio de nombre persiste. No acepta cambiar ID, correo, rol ni account_roles mediante el perfil. Otro usuario queda intacto. |
| Administracion | Listado de usuarios y emision de enlace de licencia restringidos a admin. |
| CORS y cabeceras | Origen autorizado permitido, origen ajeno rechazado; respuestas sensibles incluyen no-store y nosniff. |
| Limites de formularios | Callback rechaza mas de 1000 campos y campos mayores a 1 MiB; chat rechaza campo multipart excesivo antes de Storage. |
| Uvicorn real | HTTP en 127.0.0.1: salud, 20 rechazos sin token, login, perfil, admin e ID ajeno denegados; WebSocket autenticado ready/pong. Servidor cerrado al terminar. |
| Recursos | Se cierran clientes y se fuerza GC; cualquier ResourceWarning hace fallar la prueba. Sin esos avisos en la candidata. |
| Webpay REST | Roles y propietario requeridos; precio inyectado rechazado y monto tomado del backend. Callback valida monto/orden/resultado; repeticion autorizada no vuelve a contactar al proveedor. Timeout deja pago pendiente, sin reintento. Respuestas externas sinteticas. |
| Retornos de checkout | Orden sin token no lee ni modifica pagos. Token/orden cruzados y entradas ambiguas se rechazan. Cancelacion/error registra intento sin cambiar estado financiero; aprobados, fallidos y reembolsados no se alteran. Confirmacion posterior valida resuelve el pendiente. |

## Hallazgo corregido el 2026-09-11

Alta, solo en candidata local: se reprodujo que un callback de cancelacion
sin token, con una orden conocida, cambiaba un pago autorizado a fallido.
Siete regresiones nuevas, seis inicialmente fallidas; despues del cambio
39/39 HTTP pasan. Las pruebas no modifican cuentas ni pagos reales.

El callback valida campos y duplicados antes de consultar, exige token y orden
coincidentes para el detalle, conserva estados terminales y bloquea la fila
durante el procesamiento. El retorno sin token va al listado sin consultar
por numero de orden. Un aviso de abandono/error del navegador solo se audita;
no demuestra el resultado financiero ni cambia el pago pendiente. No se llama
a commit para cancelar. Queda conciliacion automatica y prueba de concurrencia.

## Repetir

Desde PowerShell en la raiz del proyecto, con las dependencias del backend
y PostgreSQL instalados. La ultima corrida uso el entorno aislado actualizado:

```powershell
& .\.local-tools\dependency-audit\venv\Scripts\python.exe -B .\scripts\test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --http
```

El ejecutor crea su propia base y credenciales efimeras. No pasar DATABASE_URL
de Railway/Supabase. No ejecutar el modulo de integracion por separado: rechaza
un entorno no preparado y cualquier esquema preexistente.

## Limites y seguimiento

- No se uso el respaldo real. La ultima corrida SI recorre la historia Alembic
  completa; corridas anteriores usaban modelos y solo la migracion RLS.
  Ocho comprobaciones adicionales pasan en cada uno de dos escenarios locales
  (base vacia/esquema previo simulado). Evidencia: `docs/backend-release-candidate.md`.
  No sustituye repetir con una restauracion representativa del esquema real.
- No certifica proxy/TLS de Railway, latencia, reconexion movil, concurrencia,
  carga sostenida o carreras de aceptacion simultanea: la segunda aceptacion
  de esta suite es secuencial. No se probaron todos los endpoints existentes.
- No certifica cobro, retencion o liquidacion real: los pagos autorizados son
  filas ficticias. No se activaron mapas, correo, Google/Apple OAuth ni push.
- Subidas/descargas de Storage estan simuladas: queda verificar proveedor,
  MIME/tamano/contenido y URLs reales con la release candidata. Los enlaces
  firmados son temporales de portador: quien tenga uno puede usarlo mientras
  sea valido; no son enlaces publicos permanentes.
- Los ResourceWarning previos con FastAPI 0.111.0, Starlette 0.37.2 y AnyIO
  4.13.0 ya no se reproducen con la candidata. Se agrego una comprobacion de
  cierre de recursos, ademas de Uvicorn local. Falta medir bajo carga sostenida;
  no se establecio una fuga en el servidor desplegado. Persiste un aviso de
  deprecacion de TestClient/httpx, distinto de una fuga de recursos.
  Versiones, JWT y retiro del SDK/Marshmallow: `docs/backend-dependency-audit.md`.
- Los fallos iniciales fueron del montaje: reutilizacion de una conexion
  read-only del verificador en el pool, nombre de ruta de licencia y expectativa
  403 en vez del 404 deliberado para tokens de imagen. Corregidos en las pruebas,
  sin reducir las comprobaciones de acceso. La pasada de dependencias posterior
  cambia la biblioteca JWT y exige claims, manteniendo el contrato de permisos.
- La pasada REST conserva el contrato de pagos con respuestas externas falsas.
  Se permite exactamente un evento de error auditado en la prueba deliberada
  de timeout 503; las demas pruebas siguen exigiendo cero errores del backend.
- No hubo commit, push, deploy, cambio visual, APK ni modificaciones del Splash.
- Por indicacion de Rodrigo, la recuperacion desde otro computador queda para
  el cierre final; sigue pendiente, no aprobada por esta suite.
