# Muvv - Plan de despliegue MVP

Actualizado: 2026-09-12.

## Decision actual

**No abrir al publico ni prometer pagos automaticos todavia.**
La navegacion Android esta probada, pero no sustituye la validacion de un
servicio completo, la seguridad desplegada ni la conciliacion del dinero.

Propuesta de salida: piloto privado con invitados, primero en Android; iOS
cuando complete sus verificaciones propias. No se agrega restriccion por zona.
La lista de invitados no es una limitacion geografica.

## Como usar este plan

- P0: bloquea un flete real con cobro. P1: necesario para la plataforma o flujo
  indicado. P2: mejora posterior que no debe anunciarse como disponible.
- Estados: Pendiente, Parcial, Por verificar, Verificado, Bloqueado.
- Verificado siempre indica alcance, fecha y evidencia. Tener codigo o una
  variable configurada no equivale a tener una integracion productiva probada.
- Los responsables son propuestos; Rodrigo confirma decisiones operativas,
  comerciales y accesos. Desarrollo implementa y documenta las pruebas.
- No guardar en Notion claves, contrasenas, tokens, documentos, RUT, ubicaciones
  ni capturas que expongan datos de usuarios. Solo estado y evidencia depurada.

## Ya comprobado

- [x] Android release 1.0.7, versionCode 8, instalada en Huawei ANE-LX3;
  hash instalado igual al APK construido. Evidencia: `docs/mobile-ui-1.0.7.md`.
- [x] Pagos conserva menu inferior; Atrás de Android, flecha superior y regreso
  a Perfil comprobados fisicamente. Viajes, Ganancias y cambio de modo tambien.
- [x] Splash sin modificaciones en esta pasada de navegacion y despliegue.
- [x] Backend: 148 pruebas unitarias aprobadas el 2026-09-11. Incluyen historial
  legado, verificacion de acceso, RLS, respaldo, compatibilidad JWT y Webpay REST.
  Esto no certifica permisos a traves de HTTP ni integraciones en produccion.
- [x] Migracion RLS y verificador: 9 pruebas de integracion aprobadas en PostgreSQL 18.3 local
  con datos sinteticos. Backend conserva acceso y roles API quedan bloqueados,
  incluso con permisos de tabla reintroducidos. Cluster apagado y eliminado.
  No equivale a desplegar ni a probar todos los endpoints de la app.
- [x] 39 pruebas HTTP/WebSocket aprobadas sobre PostgreSQL local y las 20 tablas
  creadas por la historia Alembic completa hasta `f6b8c0d2e411`. Roles, IDs ajenos, chat, fotos, ubicacion,
  evaluaciones y campos criticos comprobados. Integraciones externas simuladas;
  evidencia y limites: `docs/http-permissions-regression.md`.
- [x] Historia de migraciones: 8/8 comprobaciones desde vacio y 8/8 desde
  esquema previo simulado. Corregido faltante de seis tablas y 36 columnas,
  conservando filas y estados financieros sinteticos. Total local 212 casos;
  evidencia, alcance de candidata y pendientes: `docs/backend-release-candidate.md`.
- [x] Dependencias candidatas probadas en entorno aislado: 14 paquetes iniciales
  afectados actualizados o retirados. SDK Transbank y Marshmallow retirados;
  adaptador REST probado localmente. Auditoria final: 87 paquetes, cero avisos
  conocidos y cero omitidos. No desplegado. Evidencia:
  `docs/backend-dependency-audit.md`.
- [x] Webpay externo de integracion (2026-09-11): creacion, checkout completado
  manualmente por Rodrigo, retorno del navegador y commit del adaptador REST.
  AUTHORIZED, codigo 0, CLP 1.000 ficticios y orden coincidentes; un commit.
  Rechazo FAILED/codigo -1 verificado con un commit; cancelacion con cero commits.
  No se uso DB de Muvv, Flutter, dinero real ni credenciales productivas.
  Evidencia y repeticion: `docs/webpay-integration-check.md`.
- [x] Railway: consulta de solo lectura el 2026-09-07 devuelve HTTP 200,
  `status=healthy`, `pilot_mode=true`.
- [x] HTTP sin sesion: `/users/me`, `/drivers/me`, `/admin/metrics` y `/payouts`
  responden 401. Preflight CORS de `https://muvv-dev.web.app` responde 200 con
  ese origen permitido; el de `https://untrusted.example` responde 400.
  No se probaron aqui todos los endpoints ni permisos entre usuarios autenticados.
- [x] Supabase, solo metadatos (2026-09-07): 20 tablas de modelos revisadas,
  sin permisos efectivos de tabla/columna para anon/authenticated; bucket
  `muvv-private` privado. Cuatro tablas aun requieren RLS. Ver evidencia en
  `docs/supabase-access-check.md`; no se aplico la migracion preparada.

## Pendientes de salida

### MVP-01 - Infraestructura y disponibilidad

P0 | Parcial | Desarrollo + Rodrigo

- [ ] Confirmar servicio Railway siempre disponible y configuracion real de
  recursos, reinicios, logs y limites de gasto; no darlo por hecho por usar Railway.
- [ ] Verificar `/health` desde dos redes y tras un reinicio controlado.
- [x] Registrar commit desplegado, dominio y respuesta saludable de API y DB.

Cierre: evidencia reciente del entorno real y disponibilidad tras reinicio.
La consulta de salud desde el PC paso el 2026-09-07; no demuestra continuidad
ni corrige por si misma la causa del timeout observado en la prueba anterior.
Railway activo: `590e8fec432f094619355dad89dcb068c4bd649f`, `main`, una replica
US West y reinicio Always. No se reinicio ni modifico el servicio. Conexion DB
del contenedor confirmada; ver `docs/supabase-access-check.md`.

### MVP-02 - Migraciones, respaldo y recuperacion

P0 | Parcial: restauracion local y copia externa verificadas | Desarrollo + Rodrigo

- [ ] Comparar `alembic current` y `alembic heads` en el servicio correcto.
- [x] Confirmar `alembic upgrade head` en pre-deploy y migraciones de inicio desactivadas.
- [x] Crear respaldo protegido y probar restauracion en una base separada.
- [x] Guardar segunda copia fuera del PC y preparar recuperacion portable de la clave.
- [ ] Ensayar recuperacion en otro computador y acceso a la contrasena sin el PC original.
  Rodrigo solicita dejar este ensayo para el cierre final (2026-09-09).
- [ ] Documentar recuperacion del backend y compatibilidad de esquema sin
  ejecutar downgrades destructivos sobre produccion.

Cierre: restauracion y recuperacion ensayadas; nunca pegar DATABASE_URL en Notion.
Consultas del 2026-09-07: conexion local y contenedor Railway coinciden con el
proyecto Supabase esperado, revision `e1f0a2b3c4d5`, rol `postgres` propietario.
Se preparo la nueva migracion `f2a4b6c8d010`; NO esta aplicada. Supabase Free no
incluye respaldos administrados. Tras autorizacion se genero una copia cifrada
fuera de Git, incluyendo los 13 archivos privados. Recuperacion local verificada:
21 tablas public y 13 archivos coincidentes, instancia apagada y temporales
eliminados. Referencia: `docs/private-backup-recovery.md`. No se contrato otro
plan ni se modifico produccion. Exportacion de clave portable implementada y
probada contra el respaldo real con contrasena efimera, sin usar DPAPI durante
la restauracion. Paquete definitivo creado por Rodrigo con su contrasena:
7.785.867 bytes, huella y contenido cifrado comprobados. Copia externa en Google
Drive verificada el 2026-09-09: ZIP con acceso Restringido, solo propietario,
descargado por Rodrigo y comparado byte por byte y por SHA-256 con el original.
No se extrajeron datos privados ni se modifico el ZIP. Falta ensayar otro equipo
y comprobar la recuperacion independiente de la contrasena.
Tras un FileNotFoundError informado por Rodrigo, se encontro y valido la clave
DPAPI original; copia protegida alternativa fuera de AppData y `--key-file`
comprobados. No se genero ni sustituyo la clave del respaldo. La exportacion
personal y la verificacion de descarga ya terminaron; evidencia en el informe
local `portable-report.json`. La instantanea no incluye datos posteriores al respaldo.
No se ensayo una restauracion completa de Supabase en otro proyecto.
La migracion y verificador pasaron 9/9 pruebas locales; ademas, 39 pruebas
HTTP/WebSocket pasaron sobre las 20 tablas de modelos y la candidata.
La historia completa ya paso desde vacio y esquema previo sintetico hasta
`f6b8c0d2e411`; esta revision nueva completa estructuras antiguamente creadas
por el arranque. Ninguna de las dos revisiones candidatas esta desplegada.
No sustituye recorrer la historia Alembic sobre el respaldo real ni verificar
la release desplegada. Se reforzo el
verificador tras comprobar que el pooler ignoraba opciones de arranque: ahora
confirma la transaccion de solo lectura y usa limites SET LOCAL.

### MVP-03 - Seguridad final del entorno desplegado

P0 | Parcial | Desarrollo + revision independiente

- [x] Regresion local por HTTP/WebSocket con PostgreSQL y usuarios sinteticos:
  39/39 con dependencias candidatas; incluye servidor Uvicorn en loopback.
- [ ] Probar HTTP con cliente A, cliente B, conductor y admin: cambiar IDs no
  permite leer ni alterar fletes, fotos, ubicacion, chat o liquidaciones ajenas.
  Repeticion pendiente en la candidata desplegada; no todos los endpoints estan cubiertos localmente.
- [ ] Verificar JWT expirado, rutas sin token, CORS, limites de intentos y logs.
- [x] Auditar dependencias Python instaladas y probar parches en entorno local.
  Auditoria final sin avisos conocidos; no equivale a auditar todo el sistema.
- [x] Retirar dependencia vulnerable de Transbank: SDK y Marshmallow eliminados,
  operaciones existentes reemplazadas por API REST oficial con contrato probado.
- [x] Caso aprobado con checkout/retorno y commit contra Transbank Integracion,
  completado el 2026-09-11. Monto y orden comprobados, sin dinero real.
- [x] Rechazo y cancelacion en el checkout externo, verificados el 2026-09-11.
- [x] Corregir en candidata la cancelacion por orden sin token y proteger
  estados financieros terminales; siete regresiones HTTP nuevas aprobadas.
- [ ] Desplegar y revalidar esa correccion: el hallazgo alto del callback
  NO queda cerrado en produccion con el cambio local.
- [ ] Probar flujo completo desde Flutter y persistencia en el backend desplegado.
  Las pruebas HTTP locales usan respuestas sinteticas del proveedor.
- [ ] Auditar imagen Linux final, secretos en archivos rastreados e historial
  Git; corregir hallazgos criticos/altos y repetir pruebas.
  Escaneo local de secretos realizado el 2026-09-11: coincidencias actuales
  corresponden a pruebas/ejemplos; claves Google historicas pendientes de
  validacion en GCP. Exclusiones Git/Docker reforzadas. Workflow Linux sin
  deploy aprobado para `fccc084` (corrida 34618327432): build, no-root, pip check
  y unitarias. Escaneo Grype operativo tras corregir el validador: imagen
  actualizada en `0e2520b`, endurecida en `fa4b683`: 183 unitarias Linux,
  permisos y arranque/cierre real aprobados. Quedan 183 coincidencias
  de auditoria (7 criticas / 58 altas). El bloqueo de seguridad sigue activo;
  revisar discrepancias con parches oficiales y hallazgos pendientes antes
  del merge. Ver `docs/source-secret-audit.md` y
  `docs/linux-image-security-audit.md` y `docs/runtime-image-hardening.md`.
  Ensayo PostgreSQL local repetido: 9 RLS, 8 migraciones y 39 HTTP/WebSocket
  aprobados. No hubo deploy.
- [x] Commit/push del backend y CI a `codex/mvp-supabase-rls-review`, separado
  de mobile/web/Splash. `main` intacto; sin autorizacion de merge ni deploy.
- [ ] Revisar acceso de admin a chat con motivo, trazabilidad y minimo privilegio.
  Regresion local aprobada; falta verificacion en el servicio candidato.
- [x] Investigar ResourceWarning: no se reproducen tras actualizar Starlette.
  TestClient y Uvicorn local verificados, con asercion de cierre de recursos.
- [ ] Repetir mediciones de memoria/latencia bajo carga sostenida y en Railway.
  No afirmar una fuga ni estabilidad prolongada en produccion sin evidencia.
- [ ] Aplicar y revalidar `f2a4b6c8d010` tras autorizacion: RLS en tablas recientes
  de chat, fotos, rechazos y evaluaciones. No hay permisos publicos efectivos
  en la consulta actual; falta esta capa adicional de proteccion.

Cierre: sin hallazgos criticos/altos abiertos. Las pruebas unitarias actuales
cubren parte de estas reglas, no una auditoria completa.

### MVP-04 - Documentos y fotos privados

P0 | Parcial | Desarrollo + Rodrigo

- [x] Confirmar bucket privado `muvv-private` en el mismo proyecto Supabase
  que usa Railway, sin politicas de lectura publica.
- [ ] Probar carga, descarga autorizada, expiracion de enlaces y acceso denegado
  para otro usuario. Validar MIME, contenido, extension, tamano y metadatos.
- [ ] Probar JPEG y HEIC reales, foto de carga antes de solicitar y visualizacion
  por conductor apto en detalles; repetir con imagen enviada por chat.

Cierre: cliente y conductor autorizados ven las fotos; terceros no.
Metadatos comprobados el 2026-09-07: bucket privado, limite 8 MiB y sin politicas
en `storage.objects`. Coincidencia con Railway confirmada. Falta probar cargas,
descargas y enlaces; no se cambio el bucket ni su lista MIME.

### MVP-05 - Conductores y vehiculos reales

P0 | Parcial | Operaciones + Desarrollo

- [ ] Revisar documentos reales, vigencia y aprobacion por admin.
- [ ] Probar multiples vehiculos y cambios sujetos a nueva aprobacion.
- [ ] Verificar catalogo de marcas/modelos y matching por servicio, capacidad
  y vehiculo aprobado. Una mudanza no debe llegar a un vehiculo incompatible.

Cierre: un conductor apto recibe el flete y uno no apto no puede aceptarlo.
Una cuenta de prueba aprobada no sustituye la validacion del conductor real.

### MVP-06 - Cobro al agendar y retencion

P0 | Pendiente de validacion comercial y tecnica | Rodrigo + Desarrollo

- [ ] Confirmar con el proveedor el producto y contrato compatibles con el
  modelo solicitado: cobro o preautorizacion al agendar y entrega de fondos posterior.
- [ ] Definir explicitamente diferencia entre preautorizacion, cobro y saldo
  pendiente de liquidar. No presentar un registro interno como custodia bancaria.
- [ ] Probar sandbox: exito, rechazo, abandono, callback duplicado, timeout,
  reintento y conciliacion. Confirmar importe siempre calculado por backend.
  Adaptador y checkout externos: exito/rechazo/cancelacion verificados. Falta
  completar el conjunto con Flutter, persistencia e incertidumbre financiera.
- [ ] Habilitar credenciales productivas solo despues de aprobacion y evidencia.

Codigo actual: integracion Webpay Plus create/commit y estado interno
`authorized`; los fletes disponibles exigen ese estado. No se verifico un flujo
de autorizacion diferida/captura posterior. Agregar tarjetas sigue pendiente.

### MVP-07 - Cancelacion, devolucion y compensacion

P0 | Pendiente | Rodrigo + revision legal/contable + Desarrollo

- [ ] Aprobar ventanas, importes, excepciones y destino de compensaciones;
  mostrarlos antes de confirmar el flete y registrar el consentimiento.
- [ ] Implementar y probar devolucion total/parcial, falta de conductor,
  cancelacion del conductor, reclamo y reintentos sin duplicar movimientos.
- [ ] Conciliar devolucion, compensacion y comision con el proveedor real.

Cierre: cancelar un flete pagado no deja dinero sin una resolucion registrada.
Cambiar el estado a `cancelled` no demuestra que el reembolso se haya ejecutado.

### MVP-08 - Comision y pago al conductor

P0 | Parcial | Rodrigo + Desarrollo

- [ ] Verificar que cobro al cliente, comision, costos del proveedor y neto del
  conductor cuadran, con reglas contables aprobadas.
- [ ] Definir responsable y mecanismo de transferencia al finalizar, incluyendo
  reclamos, reintentos, comprobante y plazo informado al conductor.
- [ ] Probar que no se paga antes de completar ni dos veces por el mismo servicio.

Codigo actual: `ensure_driver_payout` crea una liquidacion pendiente cuando
el flete esta completado y el pago autorizado. Admin puede registrar una
transferencia y su referencia; no es un envio automatico de dinero al banco.

### MVP-09 - Chat y notificaciones reales

P0 | Parcial | Desarrollo + QA

- [ ] Probar chat texto/foto, reconexion, orden y ausencia de duplicados entre
  dos dispositivos usando redes distintas.
- [ ] Verificar FCM con app en primer plano, segundo plano y pantalla bloqueada.
- [ ] Confirmar credenciales Firebase validas y alertas ante fallos de entrega.

Importante: el backend puede seguir sano y omitir push si la configuracion
Firebase es invalida. `/health` no certifica entrega de notificaciones.

### MVP-10 - Ubicacion y entrega

P0 | Parcial | Desarrollo + QA

- [ ] Verificar ventana previa al flete, permisos del sistema, inicio de
  seguimiento y posicion reciente; no dibujar datos viejos como ubicacion en vivo.
- [ ] Probar app minimizada, pantalla bloqueada, perdida de red y permisos
  denegados. Definir contingencia visible; no eludir controles del sistema.
- [ ] Probar evidencia de retiro/entrega, PIN y cierre una sola vez.
- [ ] Confirmar que el acceso a ubicacion termina al completar o cancelar.

### MVP-11 - Prueba completa entre dos personas

P0 | Pendiente en release candidata | QA + Rodrigo

- [ ] Ejecutar `docs/qa-end-to-end.md` de principio a fin, con cuentas de prueba
  separadas, fotos de prueba y cobro sandbox, sin cobros reales.
- [ ] Cubrir flete programado, urgente, mudanza, sin conductor disponible,
  desconexion, cancelacion y feedback de ambos participantes.
- [ ] Guardar resultado por paso, version, fecha y evidencia depurada.

Cierre: todos los flujos esenciales pasan; no basta probar navegacion.

### MVP-12 - Acceso, recuperacion y datos de perfil

P0 | Parcial | Desarrollo + QA

- [ ] Revalidar cuentas de prueba sin publicar sus credenciales; reemplazar
  contrasenas simples antes de incorporar usuarios reales.
- [ ] Probar registro/login Google, nombre importado, telefono requerido,
  consentimientos, edicion persistente y cambio cliente/conductor sin permisos admin.
- [ ] Verificar correo de recuperacion real, enlace expirado y cierre de sesion.

### MVP-13 - Soporte, privacidad y operacion del piloto

P0 | Pendiente de confirmacion | Rodrigo + Operaciones

- [ ] Definir telefono/WhatsApp, responsable y horario de soporte; ensayar un reclamo.
- [ ] Revisar terminos, privacidad, revision de chat, ubicacion, cancelaciones,
  retencion de documentos y procedimiento de eliminacion de cuenta.
- [ ] Confirmar invitados y conductor real; no abrir registro publico aun.
- [ ] Establecer protocolo de incidente, pausa de nuevas solicitudes y contacto
  con ambos participantes, sin imponer una zona geografica en la app.

### MVP-14 - Publicacion reproducible y control de versiones

P0 | Parcial | Desarrollo + Rodrigo

- [ ] Revisar cambios pendientes y separar mobile, backend, web y marketing.
- [ ] Commit/push/deploy de la candidata solo con autorizacion vigente.
- [ ] Registrar APK/AAB, version, hash, firma y commit del backend; probar
  instalacion/actualizacion manteniendo sesion y datos.
- [ ] Conservar paquete anterior y procedimiento de recuperacion.

La APK 1.0.7 instalada no significa que todos los cambios locales esten en GitHub.
El 2026-09-07 se autorizo el commit/push del paquete de seguridad a la rama de
revision `codex/mvp-supabase-rls-review`, sin fusionar a `main` ni desplegar.
Los cambios visuales, web, marketing y capturas locales quedan fuera del paquete.

### MVP-15 - Observabilidad y costos

P0 | Por verificar | Rodrigo + Desarrollo

- [ ] Definir alertas de disponibilidad, errores, DB, almacenamiento, push y pagos.
- [ ] Revisar cuotas y presupuestos Railway, Supabase, Maps/Places/Routes y Firebase.
- [ ] Establecer responsable de responder alertas y de conciliar cobros diarios
  durante el piloto. No se creo ningun monitor recurrente en esta tarea.

### MVP-16 - Apple y distribucion iOS

P1, bloquea iOS | Pendiente | Rodrigo + Desarrollo

- [ ] Configurar cuenta/certificados y compilacion firmada con Xcode/macOS.
- [ ] Implementar y verificar Sign in with Apple en backend y Flutter;
  actualmente el boton informa que falta configuracion, no autentica.
- [ ] Configurar Google iOS, push APNs, permisos y retorno desde pagos.
- [ ] Probar iPhone real: area segura, teclado, texto ampliado, fotos HEIC,
  ubicacion, chat, enlaces y actualizacion mediante el canal de pruebas elegido.

No marcar iOS aprobado a partir de una prueba Android o web.

### MVP-17 - Cotizacion manual y pantallas incompletas

P1/P2 segun flujo | Parcial | Desarrollo + Producto

- [ ] Verificar alternativa operativa cuando una carga necesita cotizacion manual.
- [ ] Completar o indicar claramente funciones pendientes: guardar tarjetas,
  direcciones, validacion de cupones y persistencia de algunas preferencias.
- [ ] No presentar promociones, pagos o configuraciones simuladas como funcionales.

### MVP-18 - Seguimiento en Notion

P1 | Plan publicado; ultima actualizacion pendiente | Rodrigo + Desarrollo

- [x] Acceder a Notion con sesion iniciada y crear borrador privado.
- [x] Publicar este plan sin credenciales ni datos de usuarios y verificar que se guardo.
- [x] Organizar por prioridad y estado, con responsable, evidencia y proxima accion.
- [ ] Reflejar el cierre de la copia externa y las pruebas del 2026-09-09 en Notion.

Plan guardado el 2026-09-07 y verificado tras recargar la pagina: 18 bloques,
prioridad, estado, responsable propuesto, criterios de cierre y casillas.
[Muvv - Despliegue MVP en Notion](https://app.notion.com/p/Muvv-Despliegue-MVP-3d306c6333fb80eca432e132f318cebe).
La pagina es privada y no contiene credenciales ni datos de usuarios.
Este archivo conserva la copia del repositorio. No hay sincronizacion automatica
con Git, integracion persistente ni monitor recurrente configurado.
El 2026-09-09 la conexion al editor agoto su tiempo de respuesta antes de editar.
No se confirmo una actualizacion remota; los avances mas recientes estan en este
archivo y en `docs/private-backup-recovery.md`.

## Orden de trabajo inmediato

1. Conexion Railway, restauracion local, copia externa y regresion HTTP local
   verificadas. Revisar los cambios candidatos, dependencias y avisos de recursos;
   tras autorizacion de despliegue, revalidar acceso/almacenamiento en produccion (01-04).
2. Cerrar el flujo de dinero y cancelaciones con el proveedor (06-08).
3. Probar notificaciones, ubicacion y servicio completo en dos telefonos (09-11).
4. Aprobar soporte, seguridad, version candidata y costos (03, 12-15).
5. Ensayar la recuperacion en otro computador, diferida al cierre por Rodrigo,
   y decidir GO/NO-GO del piloto; despues completar la salida iOS (16).

## Acta GO / NO-GO

- Fecha: pendiente.
- Version mobile / commit backend: pendiente de candidata final.
- Resultado: **NO-GO para servicio real con cobro** hasta cerrar P0.
- Responsable de aprobacion operativa: Rodrigo.
- Evidencias pendientes: ver MVP-01 a MVP-15.
- No se modificaron precios, Splash, configuracion productiva ni datos de usuarios
  al preparar este plan.
