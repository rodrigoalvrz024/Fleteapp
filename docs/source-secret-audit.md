# Muvv - Auditoria local de secretos

Fecha: 2026-09-11. Sin commit, push, rotacion de claves ni cambios en GCP/Railway.

## Alcance y resultados

Gitleaks 8.30.1 oficial, ZIP Windows x32 verificado por SHA-256:
`190ad53db301eec3e90afe3a1a75270768b8ebf89e731345e19421c32c1ae1a1`.
Se uso x32, compatible con este Windows, con huella publicada coincidente.
Reglas predeterminadas, sin baseline, sin allowlist ni excepciones inline.
Escaneo local: ningun archivo del repositorio se envio al proveedor del scanner.

| Alcance | Resultado bruto |
| --- | --- |
| Historia de todas las referencias Git locales, 123 commits alcanzables | 9 coincidencias |
| Backend, scripts y docs actuales, incluidos nuevos archivos no ignorados | 155 archivos, 4 coincidencias |
| Todos los archivos rastreados actuales + nuevos de backend/scripts/docs | 390 archivos, las mismas 4 coincidencias |
| Repeticion incluyendo nuevos archivos .github y guia de auditoria | 392 archivos, las mismas 4 coincidencias |

No se escanearon commits inalcanzables ni referencias remotas no descargadas.
Los archivos binarios y formatos no soportados conservan las limitaciones del
scanner. No es una prueba de ausencia absoluta de secretos.

## Clasificacion

### Codigo actual: cuatro coincidencias revisadas

- `backend/.env.example`: TRANSBANK_API_KEY esta vacio; coincidencia multilinea
  con la configuracion siguiente. No contiene credencial de comercio.
- `backend/app/services/transbank_service.py`: clave publica documentada de
  Transbank Integracion. El adaptador exige credenciales independientes para
  produccion y no tiene fallback productivo a esa clave.
- `backend/tests/test_jwt_compatibility.py`: cadena identificada como synthetic,
  usada por fixtures de prueba y sin conexion a cuentas reales.
- `backend/tests/test_transbank_rest.py`: cadena synthetic exclusiva de pruebas.

No se detectaron credenciales privadas reales en este alcance actual. Se
conserva el resultado bruto con exit code 1; no se ocultaron alertas para dejar
el scanner en verde. Cualquier cambio de valor requiere nueva revision.

### Historia: pendiente de cierre en Google Cloud

Ocho coincidencias de Google en seis valores distintos. Una coincidencia
adicional corresponde al mismo campo vacio del ejemplo Transbank.

Archivos historicos: `mobile/lib/firebase_options.dart`,
`mobile/ios/Runner/AppDelegate.swift`, `mobile/ios/Flutter/Debug.xcconfig`,
`mobile/android/app/src/main/AndroidManifest.xml` y
`backend/app/services/maps_service.py`.

Las claves no coinciden con el contenido actual de esos archivos. Tampoco se
encontraron literalmente en los tres archivos de configuracion local existentes
revisados: backend/.env, scripts/new-google-account.env.ps1 y
mobile/android/local.properties. Esto NO demuestra que esten revocadas ni que
no se usen en Railway, GCP, APK antiguos u otras configuraciones codificadas.
No se intentaron llamadas a APIs con las claves historicas.

GitHub confirma que `rodrigoalvrz024/Fleteapp` es publico. Por eso se requiere
revisar el estado y restricciones de cada clave historica en GCP antes de
cerrar este punto. Prioridad alta para la antigua clave del backend Maps si
sigue activa: sustituirla de forma coordinada y revocar la anterior, no solo
quitarla del codigo. No afirmar que hubo abuso o cobros sin evidencia.

Las claves Firebase limitadas a Firebase identifican el proyecto y no son por
si mismas credenciales de acceso a datos. En Maps hay que confirmar restricciones
de API y aplicacion apropiadas. No borrar indiscriminadamente las claves
actuales: podria romper mapas o login. No reescribir Git ni forzar un push como
sustituto de la revocacion. No se ha verificado todavia el estado en GCP.

## Protecciones agregadas

- `backend/.gitignore`: variantes .env, credenciales JSON, claves/certificados
  privados, keystores y material de recuperacion fuera de futuros git add.
  La plantilla .env.example se mantiene publicable. Esto no quita archivos
  previamente rastreados ni borra el historial.
- `backend/.dockerignore`: exclusiones equivalentes, incluidas subcarpetas,
  para no enviar ese material al contexto de build. La imagen Linux aun debe
  construirse y auditarse; no se certifico su contenido con Docker local.
- 14 rutas privadas sinteticas comprobadas con git check-ignore --no-index;
  cuatro archivos publicables esenciales conservados. No se crearon claves.
- Runner reproducible `scripts/audit-source-secrets.ps1`: lista archivos de Git,
  copia solo el alcance indicado a un directorio temporal, rechaza enlaces,
  escanea con secretos redactados y conserva manifiesto y metadatos del resultado.
  No lee archivos ignorados de configuracion. No imprime valores encontrados.
- Instantaneas temporales eliminadas. Se agrego reintento acotado tras un bloqueo
  transitorio de Windows; la ultima corrida completo tambien la limpieza.

## Evidencia local y repeticion

Reportes excluidos de Git bajo `.local-tools/secret-audit/`:

- `history-redacted.json`: resultado de historia.
- `scan-4e87bef2cec24b199308fe0d48a8d860`: backend/scripts/docs.
- `scan-a8e7593f921c4c7288a446cb40081ac4`: corrida de 390 archivos actuales.
- `scan-046f42e6df504cbf965daf75371c7964`: corrida final, 392 archivos incluyendo
  workflow Linux y esta guia; misma clasificacion, instantanea eliminada.

Los manifiestos confirman que no se incluyeron backend/.env,
backend/firebase-credentials.json ni scripts/new-google-account.env.ps1.
Si una credencial ya estuviera rastreada por Git, SI se inspeccionaria: ignorarla
no debe ocultar una filtracion. El script sigue devolviendo 1 ante coincidencias.

```powershell
.\scripts\audit-source-secrets.ps1 -GitleaksPath .\.local-tools\gitleaks-8.30.1-win32\gitleaks.exe -Scope History
.\scripts\audit-source-secrets.ps1 -GitleaksPath .\.local-tools\gitleaks-8.30.1-win32\gitleaks.exe -Scope WorkingTree
```

La ultima cifra incluye el workflow y la guia; el script incorpora archivos
nuevos de .github ademas de backend/scripts/docs. Repetir al cambiar el conjunto
publicable. Esta actualizacion de referencias de evidencia es posterior al escaneo.

## Reescaneo tras los commits

Historial en `fccc08448ca399c8d95d59cf1cdebd5c3bf3b356`, 2026-09-11
15:48:00 UTC: 12 coincidencias en el informe local ignorado
`.local-tools/secret-audit/scan-aec4937962064683b1c1193aa4f70326`.
Conserva las nueve anteriores y agrega tres ya revisadas en el arbol actual:
clave publica de Transbank Integracion y dos secretos sinteticos de pruebas.
No se detectaron credenciales privadas nuevas. Las ocho coincidencias Google
historicas siguen abiertas a comprobacion de vigencia/restricciones en GCP.
El escaner conserva salida 1 por coincidencias; no se presenta como cero hallazgos.

## Prueba Linux aprobada

`.github/workflows/backend-linux-candidate.yml` se activa solo al subir cambios
de backend/scripts a `codex/mvp-supabase-rls-review`. No corre en main ni despliega.
Runner Ubuntu estandar, tiempo maximo 20 minutos, permiso contents:read y checkout
fijado a SHA oficial de v7.0.1. Sin secrets ni credenciales productivas.
Construye Docker, comprueba usuario no-root, pip check y unitarias con red
desactivada, filesystem de solo lectura y datos ficticios. No publica imagenes.

Commit/push a la rama de seguridad y corrida Linux autorizados el 2026-09-11.
[Corrida 34618327432](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34618327432)
aprobada para `fccc08448ca399c8d95d59cf1cdebd5c3bf3b356` a las 15:49:18 UTC:
build, comprobacion no-root, pip check y unitarias. No hubo deploy ni merge.
Pendientes: auditoria de vulnerabilidades Python/SO de la imagen,
migraciones con respaldo representativo y prueba movil completa.
Las pruebas unitarias montan tests y scripts del mismo commit: no subir tests
de respaldo sin sus helpers, aunque formen un commit separado.

La sintaxis YAML/Bash y el alcance de rama/permisos pasaron validacion local;
esto no equivale a ejecutar Docker. Una comprobacion textual demasiado amplia
confundio inicialmente el modulo Python secrets (aleatoriedad local) con el
contexto secrets de GitHub; se corrigio la comprobacion y se verifico que no
hay referencias a credenciales de GitHub en el workflow.

Telefono: en la consulta final ya se detecta Huawei ANE-LX3 autorizado por USB.
No se reinstalo ni modifico la APK, y no se inicio ninguna operacion financiera.

## Fuentes oficiales

- [Gitleaks y modos de escaneo](https://github.com/gitleaks/gitleaks)
- [Release y checksums de Gitleaks](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1)
- [Claves de Firebase](https://firebase.google.com/docs/projects/api-keys)
- [Seguridad de claves Maps](https://developers.google.com/maps/api-security-best-practices)
- [Webpay Plus e Integracion](https://www.transbankdevelopers.cl/referencia/webpay)
- [Costos de GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

Con visibilidad publica, los runners hospedados estandar de GitHub Actions
son gratuitos segun la documentacion consultada. No se habilitaron runners
grandes, almacenamiento adicional ni otros productos de pago.
