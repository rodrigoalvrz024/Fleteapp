# Preinscripción de conductores

## Estado

Implementada en `/conductores`, enlazada desde la portada. No desplegada. El modo de prueba local guarda únicamente en `tmp/preregistration-preview.db`, sin enviar correos ni escribir en Google Sheets. La vista de prueba tiene un aviso visible.

La base de datos del backend es el registro principal. La tabla `driver_preregistrations` es independiente de las cuentas de la app: preinscribirse no crea un usuario ni aprueba a un conductor.

## Planilla seleccionada

https://docs.google.com/spreadsheets/d/1JPkf6ml1O4UHrepH-WKpkiuz0UkQ3X7D91aeUcN9SQI/edit

El responsable restringió el acceso; se comprobó que la sesión anónima dejó de poder leerla. La cuenta dedicada, el secreto de Railway y el permiso de editor están configurados. Se verificaron escritura, lectura y reintento con datos ficticios en ambas pestañas; los datos de prueba fueron retirados. No se han sincronizado registros reales.

## Conectar Google Sheets

1. Mantener el acceso general en **Restringido**.
2. Crear una pestaña nueva, vacía y exclusiva llamada `Preinscripciones`. No reutilizar una pestaña con información existente. Preparar al menos 10.000 filas; si se alcanza esa capacidad, ampliarla antes de continuar la sincronización.
3. Habilitar Google Sheets API en el proyecto de Google Cloud y crear una cuenta de servicio dedicada. Compartir únicamente esta planilla con su correo como editor. No requiere acceso general a Drive ni roles de administrador del proyecto.
4. Guardar su JSON de credenciales como secreto del servidor en `PREREGISTRATION_SHEETS_CREDENTIALS_JSON`. No pegar la clave en el chat, la web, el repositorio ni variables `NEXT_PUBLIC_*`.
5. Configurar `PREREGISTRATION_SHEETS_ID=1JPkf6ml1O4UHrepH-WKpkiuz0UkQ3X7D91aeUcN9SQI` en el backend.
6. Probar una inscripción identificada como prueba en un entorno autorizado, confirmar que aparece una sola vez y retirar sus datos según el procedimiento de pruebas.

La integración escribe A:K en una fila estable según el ID de la base de datos. Reintentar no añade filas duplicadas. No ordenar físicamente, insertar, eliminar ni mover filas en esta pestaña de origen. Usar vistas de filtro o una pestaña separada para gestión. L y M pueden contener `Estado de contacto` y `Notas internas`; la sincronización no las sobrescribe. Proteger el rango de origen para evitar cambios accidentales.

Cabeceras automáticas: ID, Fecha UTC, Nombre, Correo, Celular, Comuna, Vehículo, Disponibilidad, Contacto autorizado, Promociones autorizadas, Versión consentimiento. Se usa `RAW` para que texto introducido por usuarios no se ejecute como fórmula.

## Backend y despliegue

- Aplicar las migraciones `c4e8f2a61093` y `d5f9a3b72104` desde la entrega acotada, basada en la revisión de producción `e1f0a2b3c4d5`. En el árbol de desarrollo se conserva una unión de ramas de migraciones para los cambios independientes de seguridad. No se aplicó ninguna migración en producción durante esta tarea.
- La tabla habilita RLS y revoca acceso a PUBLIC, anon y authenticated en PostgreSQL. El acceso debe ser exclusivo del backend mediante el rol autorizado que ya administra las tablas; comprobar sus privilegios antes de activar.
- Habilitar `DRIVER_PREREGISTRATION_ENABLED=true` después de la migración. Por defecto está deshabilitado.
- Incluir `https://muvv.cl` y, si se usa, `https://www.muvv.cl` en `CORS_ORIGINS`. Si Railway tiene un valor explícito, este reemplaza los valores por defecto del código.
- Compilar la web con `NEXT_PUBLIC_PREREGISTRATION_API_URL=https://muvv-api-production.up.railway.app` y `NEXT_PUBLIC_PREREGISTRATION_PREVIEW=false` después de verificar el endpoint. Si no se define URL, el formulario explica que aún no está habilitado y no finge guardar.
- La CSP existente del target público permite la API de Railway.
- No publicar `out` de la vista de prueba: recompilar para producción.

## Fiabilidad y seguimiento

El endpoint confirma solo después del commit. La copia a Sheets se intenta en segundo plano. Si falla o el proceso se interrumpe, el registro conserva `sheets_synced_at=NULL` para reintentarlo.

El trabajador integrado realiza reintentos automáticamente cuando está habilitado. Para recuperación manual, ejecutar en el servidor con las mismas variables y acceso a la base:

```sh
python -m app.services.preregistration_sheets
```

Procesa hasta 100 pendientes por ejecución; sale con error si no logra sincronizar todos los intentados. Monitorizar ese resultado y la cola pendiente. El trabajador automático ya está implementado; su variable de activación está guardada en Railway para el próximo despliegue. No guardar datos personales ni credenciales en logs.

El endpoint no permite listar inscripciones. Correos normalizados son únicos. Reenvíos no sobrescriben datos ni autorizaciones existentes; las correcciones se gestionan con soporte. Cuenta con validación de campos, campo trampa y límite de 5 intentos por IP/hora. El limitador actual es por proceso: antes de escalar a varias réplicas o campañas de alto tráfico, aplicar control compartido/antibot adicional. No sustituye la verificación de contacto.

## Privacidad y operación pendientes

- Definir conservación y proceso de eliminación antes de recibir datos reales. Una eliminación/corrección debe aplicarse tanto a la base como a la fila vinculada en Sheets, incluyendo cualquier copia operativa.
- Registrar y respetar la retirada de autorizaciones. No contactar con promociones cuando `marketing_consent=false`.
- La app no envía correos de confirmación en esta etapa: la confirmación es en pantalla. No se prometen ingresos, aprobación ni cupos.
- Cuenta dedicada creada: `muvv-launch-sheets@muvv-dev.iam.gserviceaccount.com`, sin roles de proyecto. Clave guardada en Railway; Google Sheets API habilitada. Permiso de editor confirmado y verificado mediante API el 28-09-2026.

## Pruebas locales

`backend/tests/test_driver_preregistration.py` cubre persistencia, normalización, duplicados sin sobrescritura, consentimiento, entradas inválidas, formulario trampa, modo deshabilitado, fallos de base y reintentos de Sheets con escritura RAW en fila estable.

Arrancar la API aislada desde la raíz: `backend/venv/Scripts/python.exe tmp/preregistration-preview.py` (puerto 8013). Compilar la web para pruebas con `NEXT_PUBLIC_PREREGISTRATION_API_URL=http://127.0.0.1:8013` y `NEXT_PUBLIC_PREREGISTRATION_PREVIEW=true`; servir el export en el puerto 3013. Estas variables son exclusivas de la prueba local.


## Lista de aviso de la app (28-09-2026)

Implementada en `/descargar#aviso-lanzamiento`, con botones Google Play y App Store también en la portada. Los enlaces pendientes seleccionan la plataforma; cuando se configuren las URL oficiales, los botones abren las tiendas. Los iconos indican expresamente «Próximamente · Avísame» hasta ese momento.

Endpoint: `POST /public/launch-signups`. Tabla independiente `launch_signups`; migración `d5f9a3b72104` después de `c4e8f2a61093`. Nombre, correo, celular chileno, plataforma, fecha UTC, consentimiento de correo, consentimiento de WhatsApp y versión del aviso. Se exige al menos un canal; ambos empiezan desmarcados. El teléfono y el correo son obligatorios, pero solo se debe contactar por los canales autorizados. El correo se normaliza y es único; un reenvío no modifica datos ni permisos. No verifica la titularidad del correo o teléfono y no crea una cuenta de la app.

Crear una segunda pestaña dedicada y vacía `Lanzamiento` (10.000 filas). Columnas A:I: ID, Fecha UTC, Nombre, Correo, Celular, Plataforma, Aviso por correo, Aviso por WhatsApp, Versión consentimiento. No ordenar ni eliminar filas físicas: utilizar vistas de filtro. Las columnas J en adelante quedan disponibles para seguimiento interno.

Activación en Railway, después de verificar migraciones y permisos:

- `LAUNCH_CLIENT_IP_SOURCE=railway`
- `LAUNCH_SIGNUP_ENABLED=true`
- `DRIVER_PREREGISTRATION_ENABLED=true`
- `LAUNCH_SHEETS_SYNC_ENABLED=true`
- `PREREGISTRATION_SHEETS_ID=1JPkf6ml1O4UHrepH-WKpkiuz0UkQ3X7D91aeUcN9SQI`
- `PREREGISTRATION_SHEETS_CREDENTIALS_JSON`: credencial dedicada, almacenada como secreto únicamente.

El proceso de API ejecuta un trabajador de sincronización al arrancar si está habilitado. Revisa ambas colas en lotes de hasta cinco registros, espera 60 segundos y vuelve a intentar. Un reinicio conserva los pendientes. El envío inicial también intenta copiar después del commit. Las escrituras utilizan una fila estable y modo RAW. Se conserva la opción manual `python -m app.services.preregistration_sheets` para recuperar pendientes. Con varias réplicas los reintentos pueden repetir la misma escritura, sin crear filas nuevas.

### Avisos futuros

Esta entrega captura los datos y la autorización; no envía campañas, confirmaciones ni WhatsApp automáticamente. Para el anuncio de lanzamiento, filtrar por plataforma disponible y canal autorizado. Antes de enviar, atender bajas/correcciones, comprobar titularidad de los contactos y configurar el proveedor del canal: Resend para correo y WhatsApp Business para automatización de WhatsApp. No convertir la lista de lanzamiento en una lista de promociones. Se debe registrar cada envío y excluir a quienes retiren la autorización. Para WhatsApp, el remitente empresarial y la plantilla de lanzamiento siguen pendientes.

### Verificación y bloqueo actual

18 pruebas de backend pasan (incluyendo duplicados, consentimiento, error de base, límite de intentos y reintento RAW). La web compila. La prueba de navegador guardó un único contacto ficticio local para iPhone con correo=false y WhatsApp=true; nunca se envió a Sheets ni a un proveedor de mensajes.

Railway y Firebase Hosting son accesibles. La cuenta dedicada, su clave en Railway y Google Sheets API están configuradas. El permiso de editor y la escritura/lectura en ambas pestañas se verificaron con datos ficticios retirados al terminar. Falta la prueba completa desde producción después del despliegue. No se desplegó esta entrega; la base local sigue aislada.

El repositorio contiene cambios adicionales de seguridad y app en curso. Preparar una entrega acotada de backend o revisar esos cambios antes de desplegar el árbol completo; no publicar trabajo ajeno accidentalmente.


## Preparación de publicación (estado actualizado)

- Usuario autorizó expresamente la clave y el acceso de editor limitado a la planilla original, con ambas listas en pestañas separadas.
- Cuenta creada y una única clave emitida. Secreto configurado en Railway sin redeploy; también los flags de ambos formularios y del trabajador. CORS conserva los dos dominios Firebase existentes y añade `https://muvv.cl` y `https://www.muvv.cl`.
- `scripts/setup-launch-sheets.py --credentials RUTA_JSON` prepara solo pestañas nuevas autorizadas y verifica cabeceras antes de escribir. No ordena ni borra hojas existentes. No imprime la clave.
- La revisión automática bloqueó la publicación directa en main. La alternativa preparada es una solicitud de cambios desde `codex/muvv-launch-signups`, con base en la versión de producción `590e8fe`, sin los demás cambios en desarrollo. Aún no se ha desplegado.
- No se configura envío automático de campañas en esta entrega. Resend/WhatsApp requieren un flujo posterior de envío, bajas y comprobación de titularidad antes del anuncio real.
