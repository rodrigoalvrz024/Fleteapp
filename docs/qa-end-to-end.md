# Muvv QA end-to-end

Version: 2026-09-06

Plan de salida: [mvp-deployment-plan.md](mvp-deployment-plan.md).
Este documento es un guion pendiente de ejecutar en la release candidata;
una casilla sin marcar no representa una prueba aprobada.

## Objetivo

Validar que el MVP funciona de punta a punta despues del deploy:

- Web publica inicia una solicitud.
- Cliente crea y revisa fletes.
- Conductor completa onboarding, ve fletes y actualiza estados.
- Admin revisa documentos, monitoreo, auditoria y solicitudes de privacidad.
- Seguridad basica no queda rota por el flujo web.

## URLs

- Web publica: https://muvv-dev-public.web.app
- App web: https://muvv-dev.web.app
- Backend Railway: https://muvv-api-production.up.railway.app
- Estos son los destinos configurados, no una certificacion de disponibilidad.

## Antes de probar

- [ ] Registrar version/hash de APK, commit de backend, fecha y dos dispositivos.
- [ ] Usar cuentas y fotos de prueba, sin documentos personales en las evidencias.
- [ ] Separar sandbox de produccion; no simular pagos en produccion ni registrar
  un cobro como real por haber recibido un callback de integracion.
- [ ] Confirmar respaldo y plan de recuperacion antes de cualquier migracion.
- [ ] No crear, aceptar, cancelar o cerrar servicios reales durante QA.
- [ ] No aplicar restricciones geograficas; mantener solo los invitados acordados.
- [ ] Solo si hay despliegue autorizado, cargar el proyecto correcto antes del script:

```powershell
. .\scripts\new-google-account.env.ps1
if ($env:PROJECT_ID -ne 'muvv-dev') { throw 'Revisar proyecto Firebase antes de desplegar' }
powershell -ExecutionPolicy Bypass -File .\scripts\app-deploy.ps1
```

- [ ] Si PowerShell no encuentra Firebase CLI, abrir Firepit:

```powershell
.\.local-tools\firebase-tools-instant-win.exe
```

- [ ] Dentro del prompt `>` ejecutar:

```powershell
firebase deploy --only hosting:app --project muvv-dev
```

- [ ] Desplegar web publica si hubo cambios:

```powershell
firebase deploy --only hosting:public --project muvv-dev
```

- [ ] Confirmar que Google Maps carga en la app web.
- [ ] Confirmar que no hay errores visibles en consola del navegador.
- [ ] Confirmar `/health` y esquema Alembic en Railway; no inferir migraciones
  completas solo porque el proceso de API inicio.

## Prueba 1: Web publica a cliente

- [ ] Abrir la web publica.
- [ ] Escribir origen.
- [ ] Escribir destino.
- [ ] Presionar `Continuar`.
- [ ] Confirmar que abre login de la app.
- [ ] Iniciar sesion como cliente.
- [ ] Confirmar que redirige a `Solicitar flete`.
- [ ] Confirmar que origen/destino llegan prellenados.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 2: Cliente crea flete

- [ ] Completar ruta.
- [ ] Completar descripcion de carga.
- [ ] Completar peso.
- [ ] Seleccionar urgente o programado.
- [ ] Agregar peoneta si corresponde.
- [ ] Confirmar que aparece precio estimado.
- [ ] Crear flete.
- [ ] Confirmar exito.
- [ ] Abrir `Mis fletes`.
- [ ] Confirmar que el flete aparece.
- [ ] Abrir detalle del flete.
- [ ] Confirmar estado, ruta, carga y precio.
- [ ] Subir fotos antes de confirmar y verificar que permanecen en detalles.
- [ ] Comparar una lavadora con mudanza; mudanza debe respetar minimo de
  $50.000 y vehiculo adecuado, sin permitir cambiar precio desde el cliente.
- [ ] Verificar cotizacion expirada, carga fuera de capacidad y cotizacion manual.
- [ ] Repetir con programado y urgente usando datos de prueba.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 2B: Pago sandbox antes de asignacion

- [ ] Comprobar que un flete sin pago autorizado no se ofrece al conductor.
- [ ] Completar pago de integracion, sin tarjeta real ni cargo real.
- [ ] Verificar importe, orden y flete asociados en backend; no confiar en el
  resultado o precio enviado por Flutter.
- [ ] Repetir callback/reintento y verificar que no duplica pago ni liquidacion.
- [ ] Probar rechazo, abandono, perdida de red y consulta posterior del estado.
- [ ] Confirmar el flete visible para conductores solo tras el estado requerido.

Resultado: pendiente. No certifica retencion bancaria, reembolso ni pago al
conductor. Esos puntos deben cerrar MVP-06, MVP-07 y MVP-08 antes del servicio real.

## Prueba 3: Conductor acepta flete

- [ ] Iniciar sesion como conductor aprobado.
- [ ] Abrir fletes disponibles.
- [ ] Confirmar que el flete pendiente aparece.
- [ ] Abrir detalle.
- [ ] Verificar fotos de carga y vehiculo elegido antes de aceptar.
- [ ] Comprobar que conductor no aprobado o vehiculo incompatible no puede
  recibir/aceptar la solicitud, tampoco cambiando IDs directamente.
- [ ] Aceptar flete.
- [ ] Confirmar cambio de estado.
- [ ] Probar intento simultaneo de otro conductor: solo uno queda asignado.
- [ ] Registrar llegada y evidencia de retiro, sin compartir ubicacion fuera
  de la ventana del servicio ni con otros clientes.
- [ ] Iniciar viaje.
- [ ] Registrar evidencia de entrega y PIN correcto; rechazar PIN incorrecto.
- [ ] Marcar como completado.
- [ ] Confirmar que el cliente ve el nuevo estado.
- [ ] Responder preguntas de calificacion de cliente y conductor una sola vez.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 4: Onboarding conductor

- [ ] Crear o usar conductor sin aprobacion.
- [ ] Registrar datos de conductor.
- [ ] Subir licencia.
- [ ] Subir permiso de circulacion.
- [ ] Subir revision tecnica.
- [ ] Subir SOAP.
- [ ] Registrar vehiculo.
- [ ] Seleccionar marca/modelo del catalogo y probar segundo vehiculo.
- [ ] Enviar a revision.
- [ ] Confirmar estado pendiente.
- [ ] Aprobar por admin y comprobar vigencia; cambios no aprobados no habilitan
  automaticamente al conductor o al vehiculo.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 5: Admin

- [ ] Iniciar sesion como admin.
- [ ] Revisar metricas.
- [ ] Revisar conductores pendientes.
- [ ] Abrir documentos de conductor.
- [ ] Probar enlace expirado y acceso de terceros; no hacer publico el bucket.
- [ ] Aprobar o rechazar solicitud.
- [ ] Confirmar que el conductor ve el nuevo estado.
- [ ] Revisar historial/auditoria.
- [ ] Revisar chat desde admin con motivo de revision y registro auditable.
- [ ] Probar filtros de auditoria.
- [ ] Exportar CSV si corresponde.
- [ ] Revisar solicitudes de privacidad.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 6: Recuperacion de contrasena

- [ ] Abrir recuperar contrasena.
- [ ] Enviar email de recuperacion.
- [ ] Confirmar respuesta exitosa.
- [ ] Confirmar que el correo llega mediante Resend.
- [ ] Abrir link de reset.
- [ ] Cambiar contrasena.
- [ ] Iniciar sesion con la nueva contrasena.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 7: Privacidad y datos

- [ ] Abrir perfil.
- [ ] Solicitar copia de datos.
- [ ] Solicitar rectificacion.
- [ ] Solicitar eliminacion de cuenta.
- [ ] Confirmar que admin ve las solicitudes.
- [ ] Confirmar que queda auditoria.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Criterio de salida MVP

- [ ] Cliente puede crear flete sin ayuda tecnica.
- [ ] Conductor puede aceptar y completar flete.
- [ ] Admin puede aprobar conductor/documentos.
- [ ] Auditoria registra acciones importantes.
- [ ] Recuperacion de contrasena funciona.
- [ ] No hay secrets en git.
- [ ] Google Maps carga en web.
- [ ] No hay errores criticos en Railway logs.
- [ ] No hay errores criticos en consola web.
- [ ] Cobro, devolucion, comision y liquidacion cumplen los criterios del plan
  de despliegue y estan conciliados, sin dinero simulado en produccion.
- [ ] Soporte, privacidad, alertas, respaldo/restauracion y permisos tienen
  evidencia reciente y responsable confirmado.
- [ ] Todos los P0 del plan estan cerrados antes de aceptar un flete real.

## Prueba 8: Chat, push y ubicacion entre dos redes

- [ ] Telefono A cliente y telefono B conductor, con redes independientes.
- [ ] Enviar texto y foto en ambas direcciones; reconectar sin perder ni duplicar mensajes.
- [ ] Recibir push con app abierta, minimizada y pantalla bloqueada.
- [ ] Probar ubicacion antes de la ventana del servicio, dentro de ella,
  en trayecto, sin red y despues de completar/cancelar.
- [ ] Verificar que se distingue ubicacion desactualizada y que la app responde
  claramente al permiso denegado, sin eludirlo.

## Prueba 9: Cancelaciones y liquidacion

- [ ] Cancelar un flete sandbox pagado antes de retiro y verificar devolucion
  o compensacion segun la politica aprobada. No basta cambiar el estado del flete.
- [ ] Probar ausencia de conductor, cancelacion del conductor y reclamo.
- [ ] Confirmar liquidacion creada una sola vez al completar un flete pagado.
- [ ] Solo admin puede registrar transferencia, con referencia y auditoria.
- [ ] Marcar liquidacion pagada no se interpreta como transferencia bancaria
  automatica: comprobar el mecanismo real antes de cerrar esta prueba.

## Evidencia por ejecucion

Fecha, entorno, version mobile, commit backend, dispositivos, IDs exclusivos
de pruebas, resultado por paso, fallo y responsable. No incluir contrasenas,
JWT, claves API, documentos ni datos personales en el reporte compartido.
No borrar datos de prueba sin identificar el entorno y recibir autorizacion.

## Bugs encontrados

| Prioridad | Pantalla | Descripcion | Estado |
| --- | --- | --- | --- |
| P0 | | | |
| P1 | | | |
| P2 | | | |
