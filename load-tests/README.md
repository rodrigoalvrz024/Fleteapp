# FleteApp load tests

Pruebas de carga con `k6` para validar si backend, Supabase y Cloud Run soportan uso simultaneo.

## Instalacion

En Windows:

```powershell
winget install GrafanaLabs.k6
```

Cierra y abre PowerShell despues de instalar.

Si el instalador MSI de Windows se cancela o pide permisos, usa la version portable local:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-k6-portable.ps1
```

## Variables requeridas

Usa cuentas de prueba existentes. No pegues contrasenas en el chat ni las subas al repo.

```powershell
$env:CLIENT_EMAIL="cliente-test@fletgo.com"
$env:CLIENT_PASSWORD="TU_PASSWORD"
```

Opcional para simular lectura de conductor:

```powershell
$env:DRIVER_EMAIL="driver-test@fletgo.com"
$env:DRIVER_PASSWORD="TU_PASSWORD"
```

URL por defecto:

```powershell
$env:BASE_URL="https://fleteapp-api-i3wy5watea-uc.a.run.app"
```

## Smoke test

Primero ejecuta una prueba pequena:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\load-test-smoke.ps1
```

Por defecto usa 3 usuarios durante 45 segundos y no crea fletes.

Para crear fletes de prueba:

```powershell
$env:WRITE_FREIGHTS="true"
powershell -ExecutionPolicy Bypass -File .\scripts\load-test-smoke.ps1
```

## Prueba 200 usuarios

Primero ejecutala sin escritura para validar lectura/autenticacion y capacidad base:

```powershell
$env:WRITE_FREIGHTS="false"
powershell -ExecutionPolicy Bypass -File .\scripts\load-test-ramp200.ps1
```

Luego, si todo esta estable, ejecuta con creacion de fletes:

```powershell
$env:WRITE_FREIGHTS="true"
powershell -ExecutionPolicy Bypass -File .\scripts\load-test-ramp200.ps1
```

La prueba `ramp200` dura cerca de 17 minutos:

- 2 min hasta 25 usuarios
- 3 min hasta 75 usuarios
- 5 min hasta 200 usuarios
- 5 min sosteniendo 200 usuarios
- 2 min bajando a 0

## Indicadores a mirar

En la salida de `k6`:

- `http_req_failed`: ideal bajo 2%.
- `http_req_duration p(95)`: ideal bajo 1200 ms.
- `http_req_duration p(99)`: ideal bajo 2500 ms.
- `fleteapp_freight_creates`: cantidad de fletes creados si `WRITE_FREIGHTS=true`.
- `fleteapp_freight_list_latency`: latencia de listados de fletes.

Los scripts guardan automaticamente un resumen JSON en `reports/load-tests/`.
Esa carpeta queda fuera de Git porque contiene resultados locales de prueba.

Para reducir ruido en pruebas largas:

```powershell
$env:K6_QUIET="true"
powershell -ExecutionPolicy Bypass -File .\scripts\load-test-ramp200.ps1
```

En Cloud Run:

- CPU.
- Memory.
- Request count.
- Request latency.
- Instance count.
- 4xx/5xx.

En Supabase:

- conexiones activas.
- CPU.
- consultas lentas.
- errores de conexion.

## Criterio de decision

Con `max-instances=2` podemos partir si:

- error rate menor a 2%.
- p95 menor a 1.2 segundos.
- Cloud Run no llega sostenidamente a CPU alta.
- Supabase no muestra saturacion de conexiones.

Subir Cloud Run a `max-instances=5` si:

- p95 supera 1.2 segundos bajo carga.
- aparecen 5xx o timeouts.
- Cloud Run mantiene colas o latencia alta.
- los conductores tardan en ver fletes disponibles.

Antes de subir mucho Cloud Run, revisar pool de conexiones y Supabase, porque mas instancias tambien pueden abrir mas conexiones a la base.
