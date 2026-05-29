# FleteApp QA end-to-end

Version: 2026-05-29

## Objetivo

Validar que el MVP funciona de punta a punta despues del deploy:

- Web publica inicia una solicitud.
- Cliente crea y revisa fletes.
- Conductor completa onboarding, ve fletes y actualiza estados.
- Admin revisa documentos, monitoreo, auditoria y solicitudes de privacidad.
- Seguridad basica no queda rota por el flujo web.

## URLs

- Web publica: https://fleteapp-public-8d8f7.web.app
- App web: https://fleteapp-8d8f7.web.app
- Backend Cloud Run: verificar URL vigente en Cloud Run antes de probar API directa.

## Antes de probar

- [ ] Ejecutar deploy de app:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\app-deploy.ps1
```

- [ ] Si PowerShell no encuentra Firebase CLI, abrir Firepit:

```powershell
.\.local-tools\firebase-tools-instant-win.exe
```

- [ ] Dentro del prompt `>` ejecutar:

```powershell
firebase deploy --only hosting:app --project fleteapp-8d8f7
```

- [ ] Desplegar web publica si hubo cambios:

```powershell
firebase deploy --only hosting:public --project fleteapp-8d8f7
```

- [ ] Confirmar que Google Maps carga en la app web.
- [ ] Confirmar que no hay errores visibles en consola del navegador.

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

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 3: Conductor acepta flete

- [ ] Iniciar sesion como conductor aprobado.
- [ ] Abrir fletes disponibles.
- [ ] Confirmar que el flete pendiente aparece.
- [ ] Abrir detalle.
- [ ] Aceptar flete.
- [ ] Confirmar cambio de estado.
- [ ] Iniciar viaje.
- [ ] Marcar como completado.
- [ ] Confirmar que el cliente ve el nuevo estado.

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
- [ ] Enviar a revision.
- [ ] Confirmar estado pendiente.

Resultado:

- Estado:
- Observaciones:
- Bug si aplica:

## Prueba 5: Admin

- [ ] Iniciar sesion como admin.
- [ ] Revisar metricas.
- [ ] Revisar conductores pendientes.
- [ ] Abrir documentos de conductor.
- [ ] Aprobar o rechazar solicitud.
- [ ] Confirmar que el conductor ve el nuevo estado.
- [ ] Revisar historial/auditoria.
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
- [ ] No hay errores criticos en Cloud Run logs.
- [ ] No hay errores criticos en consola web.

## Bugs encontrados

| Prioridad | Pantalla | Descripcion | Estado |
| --- | --- | --- | --- |
| P0 | | | |
| P1 | | | |
| P2 | | | |

