# Muvv - Candidata del backend

Actualizado: 2026-09-12. Estado: commits publicados en la rama de seguridad;
build Docker y unitarias Linux aprobados; auditoria de imagen aun bloqueada.
Sin merge ni deploy autorizado.
No autoriza cobros reales ni apertura publica. Splash, APK y diseno sin cambios.

## Hallazgo al ensayar una instalacion limpia

La historia anterior alcanzaba `f2a4b6c8d010` sin errores pero dejaba fuera seis
tablas y 36 columnas requeridas por los modelos. Es un bloqueador de despliegue
o recuperacion desde cero, no evidencia de que esas tablas falten en Supabase.
El esquema real previamente inspeccionado tenia las 20 tablas de modelos.

Tablas ausentes en la instalacion limpia: `audit_events`, `data_privacy_requests`,
`driver_payouts`, `driver_review_audits`, `password_reset_tokens`, `user_consents`.
Columnas ausentes en `users` (2), `drivers` (17), `vehicles` (3),
`freight_requests` (11) y `payments` (3). Dependian de la antigua preparacion
por modelos y ajustes de arranque, desactivada correctamente en Railway.

## Correccion candidata

Nueva revision `f6b8c0d2e411`, posterior a `f2a4b6c8d010`:

- Definiciones congeladas de las seis tablas, con enums, claves foraneas,
  indices y unicidad para tokens y liquidaciones. No importa modelos vivos.
- Agrega solo tablas/columnas ausentes. No altera tipos existentes, ni rellena
  pagos o liquidaciones, ni reescribe migraciones ya publicadas.
- Mantiene privadas las 20 tablas de la aplicacion: RLS y revocacion de permisos
  de tabla, columna y secuencia a PUBLIC/anon/authenticated. No aplica FORCE RLS,
  no cambia otras tablas/esquemas ni elimina politicas existentes.
- El propietario usado por FastAPI conserva acceso. Otros roles y privilegios
  heredados deben revisarse en el entorno real; no se supone que sean seguros.
- Limite local de espera de bloqueos de cinco segundos para esta revision.
  No sustituye medir locks/duracion con el volumen real antes de publicar.
- Downgrade no destructivo: no elimina datos ni vuelve a habilitar acceso.
  NO usar una cadena de downgrades antiguos como mecanismo de rollback.

## Evidencia local

PostgreSQL 18.3 en Windows, puertos loopback aleatorios y roles propietarios
sin superusuario/BYPASSRLS. Credenciales nuevas de prueba, sin .env ni red externa.

| Comprobacion | Resultado |
| --- | --- |
| Unitarias del workspace | 148/148 |
| RLS y verificador | 9/9 |
| HTTP/WebSocket sobre historia Alembic completa | 39/39 |
| Migraciones desde base vacia | 8/8 |
| Migraciones desde esquema previo simulado | 8/8 |

Total: 212 casos aprobados, contando los dos escenarios de migracion por
separado y sin sumar repeticiones de la suite RLS. Los tres casos externos de
Webpay se documentaron aparte, no se repitieron ni se cobro dinero en esta pasada.

Se comprobaron revision head, repeticion, tablas/columnas, lectura de los
modelos, indices, FK, unicidad, RLS, revocacion de permisos por columna y una
tabla ajena intacta. El escenario previo contiene usuarios/flete/pago autorizado
y liquidacion pagada sinteticos: valores y filas permanecen iguales.
Un fallo inicial de esa fixture se debio a peso de carga obligatorio omitido;
se completo el dato ficticio y se repitio con exito.

HTTP ya NO usa create_all: ejecuta la historia Alembic completa antes de sus
39 pruebas de cliente, conductor y admin. El escenario previo de migraciones
SI usa modelos y stamp, exclusivamente en una base temporal verificada vacia,
para simular una instalacion antigua; no es una restauracion del respaldo real.
Los clusters y servidores temporales se apagaron y eliminaron al terminar.

```powershell
& .\.local-tools\dependency-audit\venv\Scripts\python.exe -B .\scripts\test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --migrations --http
& .\.local-tools\dependency-audit\venv\Scripts\python.exe -B .\scripts\test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --migrations --migration-start models
```

No ejecutar los modulos de integracion directamente ni pasar una DATABASE_URL
existente. El ejecutor construye su entorno limpio y se niega a reutilizar bases.

## Publicacion y validacion Linux

Rama `codex/mvp-supabase-rls-review`, subida autorizada el 2026-09-11:

- `fd99ab6`: helpers de respaldo cifrado, pruebas y guia; sin respaldos ni claves.
- `4535946`: seguridad del backend, migracion aditiva y regresiones.
- `fccc084`: CI Linux sin deploy, exclusiones de secretos y guias de auditoria.

[Ejecucion Linux 34618327432](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34618327432)
terminada con success el 2026-09-11 a las 15:49:18 UTC. SHA probado:
`fccc08448ca399c8d95d59cf1cdebd5c3bf3b356`.
Build de `backend/Dockerfile`, usuario app no-root, pip check y descubrimiento
completo de unitarias aprobados. Los tests corrieron sin red, con filesystem
de solo lectura y credenciales ficticias. No se publico la imagen ni hubo deploy.
Las 148 unitarias tambien se repitieron localmente antes de los commits.

Esa primera corrida Linux no ejecuto los ensayos PostgreSQL ni escaneo
vulnerabilidades del SO: no deben darse por aprobados por ese resultado.
`main` consultado despues de la corrida sigue en
`590e8fec432f094619355dad89dcb068c4bd649f`. Mobile/web/Splash quedaron fuera.

## Alcance para revision y publicacion

Separar los cambios visuales de mobile/web, Firebase, marketing y archivos
temporales. No usar git add . ni publicar todo el arbol de trabajo.

Runtime candidato: `backend/requirements.txt`, `backend/app/core/security.py`,
`backend/app/services/storage_service.py`, `backend/app/services/transbank_service.py`,
`backend/app/routers/payments.py` y la nueva revision Alembic. `f2a4b6c8d010` ya
esta en la rama de seguridad, pero aun no se ha confirmado su despliegue.

Incluir junto a cada cambio sus pruebas y guias correspondientes. El runner
de HTTP/RLS y migraciones vive en `scripts/test-supabase-rls-isolated.py`; los
dos modulos estan en `backend/integration_tests`. Las pruebas de respaldo
dependen de sus scripts: conservarlas como conjunto
separado y registrar el numero de pruebas del commit final, no solo del workspace.

## Orden pendiente antes del despliegue

1. Revisar diff y escanear secretos del conjunto exacto de commits e historial.
   Escaneo local realizado el 2026-09-11: cuatro coincidencias actuales revisadas
   como fixtures/clave publica de integracion/ejemplo vacio. Ocho coincidencias
   historicas de Google requieren verificar vigencia y restricciones en GCP;
   no se considera cerrado ese riesgo. Ver `docs/source-secret-audit.md`.
2. Build Linux y unitarias completados en la corrida vinculada arriba.
   Pendiente cerrar la auditoria de paquetes Python y del SO en la imagen
   final y repetir integracion con PostgreSQL representativo. El pip check
   aprobado verifica compatibilidad de dependencias, no vulnerabilidades.
   Escaneo agregado en `33aa6ed`; el error inicial del validador (salida 2)
   quedo corregido en `78fde6b` / `b126de4`, conservando todos los hallazgos.
   Imagen actualizada en `0e2520b`: corrida 34706140887 con build/no-root,
   pip check y 171 unitarias aprobados; informe valido, bloqueo por hallazgos
   (salida 1). Registra 189 coincidencias: 7 criticas y 62 altas, no CVE unicas.
   Varias contradicen versiones que Debian/Python documentan como corregidas;
   requieren contrastar procedencia y version, sin ignorarlas en bloque.
   Detalle y fuentes en `docs/linux-image-security-audit.md`.
   Diagnostico adicional en `6ab5df3`: corrida 34720388243 con build y 174
   unitarias Linux aprobados, mismas 189 coincidencias y bloqueo activo.
   Confirmados Python 3.11.16 / Expat 2.8.3. Se documentaron parches instalados
   para 23 coincidencias; otras 46 altas corresponden a 10 CVE aun abiertas
   en Debian y pendientes de revision. No se agregaron excepciones.
   Endurecimiento `fa4b683`: corrida 34733438698 con 183 unitarias Linux,
   permisos del contenedor y arranque/cierre real aprobados. Codigo protegido
   contra escritura, sin SUID/SGID y sin paquete mount. Auditoria aun bloqueada:
   183 coincidencias (7 criticas / 58 altas). Las 10 CVE Debian abiertas siguen
   presentes en 42 coincidencias. Ensayo local repetido: 9 RLS, 8 migraciones
   y 39 HTTP/WebSocket aprobados. Ver `docs/runtime-image-hardening.md`.
   Seguimiento `ce1286b`: corrida 34763412239 con 188 unitarias Linux,
   permisos y arranque/cierre aprobados. infocmp y nsenter no son legibles ni
   ejecutables por app; Archive::Tar no es legible en el include path de Perl.
   Informe valido del 2026-09-13: 155 coincidencias, cero criticas y 45 altas
   (13 CVE distintas). Las 20 coincidencias Debian altas/criticas con parches
   previamente documentados ya no aparecen; no se agregaron exclusiones.
   El bloqueo sigue activo. Se repitieron localmente las 56 comprobaciones
   PostgreSQL/RLS/migraciones/HTTP con exito y se elimino el cluster temporal.
   Regresiones de backports `87aea19`: corrida 34767762044, 197 unitarias
   Linux y pruebas especificas de cookies/recursion XML aprobadas. No hubo
   cambios en las 155 coincidencias ni excepciones. Matriz de los 13 CVE,
   fuentes y condiciones pendientes en `docs/residual-image-review.md`.
3. Ensayar sobre una restauracion aislada representativa del esquema real;
   comparar datos, permisos, enums, locks y tiempos. Recuperacion en OTRO PC
   sigue aplazada para el cierre final por decision de Rodrigo.
4. Commit/push de la candidata revisada completado en la rama de seguridad.
   El despliegue requiere otra autorizacion. Desplegar primero para pruebas
   con DB/Storage separados, sin clonar secretos productivos
   ni enviar notificaciones a usuarios reales. Mantener Transbank integration.
5. Verificar commit e imagen exactos, `alembic current` igual a `alembic heads`
   (head candidato `f6b8c0d2e411`), pre-deploy exitoso, RUN_STARTUP_MIGRATIONS=false,
   salud, permisos y recepcion del callback. No usar stamp para ocultar errores.
6. Probar en telefonos: login, fotos privadas, solicitud/aceptacion, chat,
   seguimiento y Webpay aprobado/rechazado/cancelado con persistencia. ADB ya
   detecta el Huawei ANE-LX3 en la consulta final del 2026-09-11; no se reinstalo
   ni modifico la APK durante la auditoria de secretos.
7. Publicacion del piloto solo tras cerrar los P0 del plan. Todavia pendientes
   conciliacion, devoluciones, acuerdo de cobro/retencion y pago al conductor.

Rollback: conservar imagen/commit anterior y respaldo protegido reciente.
Revertir codigo solo tras verificar compatibilidad con el esquema aditivo;
no borrar tablas ni estados financieros, y no reintroducir el callback vulnerable.
La correccion alta de pagos y las migraciones siguen sin aplicarse en produccion.
