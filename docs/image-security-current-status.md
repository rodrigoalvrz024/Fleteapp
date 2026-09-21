# Estado actual de seguridad de la imagen

## Seguimiento 2026-09-21

Consulta de fuentes oficiales, no un nuevo escaneo. El ultimo resultado de CI
registrado corresponde a `171c757`, imagen
`sha256:e8a7f80a4f9485349b84c05df47845a782de098d1289e3c9b2362fcef0fd7c55`,
con 44 coincidencias High pendientes despues de las tres correcciones Python
ya autorizadas. Ver [resultado exacto](storage-dependency-cleanup.md).
Los resultados historicos que siguen se conservan sin reescribirlos.

Hay una novedad concreta en zlib: upstream publico el
[arreglo df84af2](https://github.com/madler/zlib/commit/df84af25dc1942490e1d1c899a07619152a46148)
para CVE-2026-85091 y la consulta #1310 ahora figura cerrada. La
[receta Wolfi](https://github.com/wolfi-dev/os/blob/main/zlib.yaml) consultada
usa `1.3.2.1_rc20260601-r0` con un parche para el mismo manejo del buffer.
Esto reemplaza la observacion anterior de que no habia evidencia de arreglo;
NO acredita que la imagen Muvv anterior contenga ese cambio.

La [pagina actual de Python de Chainguard](https://images.chainguard.dev/directory/image/python/vulnerabilities)
ya no muestra zlib en su tabla, pero si muestra CVE-2026-19499 como High en
`glibc-2.44 2.44-r6`, ademas de cinco Medium y un Low. No se obtuvo un nuevo
digest ni se verifico firma/SBOM: es informacion del proveedor, no resultado
de nuestro escaner. No equivale a una base aprobada ni a compatibilidad de Muvv.

En Debian trixie siguen figurando vulnerables las versiones estables de
[glibc monetario](https://security-tracker.debian.org/tracker/CVE-2026-19499),
[glibc DNS](https://security-tracker.debian.org/tracker/CVE-2026-5435),
[util-linux](https://security-tracker.debian.org/tracker/CVE-2026-76642) y
[ACL](https://security-tracker.debian.org/tracker/CVE-2026-54369).
Debian ahora enlaza el arreglo upstream de
[zlib](https://security-tracker.debian.org/tracker/CVE-2026-85091), pero mantiene
sus paquetes listados como vulnerables. No mezclar paquetes sid con trixie.

Decision: mantener bloqueo, sin cambiar excepciones, versiones de dependencias
ni imagen de Railway. Antes de repetir la comparacion Wolfi, revisar una
actualizacion mantenida de glibc o solicitar al proveedor evidencia especifica
de ese aviso. La consulta anterior centrada en zlib ya no debe enviarse sin
actualizarla. No se envio ninguna consulta ni se contrato ningun servicio.

En paralelo, las [pruebas TLS](database-tls-preflight.md) locales y una conexion
real autorizada desde este PC al pooler Supabase pasaron con `verify-full` y
modo de solo lectura, sin consultas a tablas. El operador descargo el certificado
tras el bloqueo inicial de Chrome; no se desactivaron protecciones. La
configuracion efectiva y conectividad desde Railway siguen pendientes. Este
resultado no elimina avisos del contenedor ni autoriza desplegar.

## Revision anterior

Fecha de revision: 2026-09-15 (America/Santiago).
Estado: BLOQUEADA. No modifica autorizaciones, excepciones ni produccion.

## Evidencia exacta

- Commit: `7d4e9a6caed754ac54e487794da962f1e51cbb4b`.
- [Corrida 35045218540](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35045218540).
- Imagen: `sha256:b49572f8674087c85d41b5adeb14353ba14b966bb99bfd959852006b51cb5f04`.
- Escaneo UTC: `2026-09-16T01:46:21.555150705Z`.
- Originales: 0 Critical, 47 High, 51 Medium, 9 Low, 44 Negligible, 4 Unknown.
- Tres correcciones Python reconocidas segun la autorizacion existente.
- Pendientes High: 44 coincidencias de paquetes, correspondientes a 11 CVE.

Los 44 registros no son 44 vulnerabilidades independientes ni 44 ataques
demostrados. Tampoco es correcto descartarlos porque las pruebas funcionales
pasen. Los 11 CVE siguen abiertos y el control conserva las filas originales.

## Matriz de trabajo

| Familia | CVE distintos | Coincidencias High pendientes | Siguiente accion |
| --- | ---: | ---: | --- |
| util-linux | 4 | 32 | Version estable corregida o revision acotada de componentes y privilegios del hosting; no confundir controles no-root con parche. |
| glibc | 2 | 4 | Revisar llamadas nativas DNS y formato monetario; esperar actualizacion estable o evidencia revisada por aviso. |
| ncurses | 1 | 4 | La herramienta infocmp fue retirada, pero siguen registros y bibliotecas. Revisar alcance completo antes de proponer disposicion. |
| ACL | 2 | 2 | Esperar paquete mantenido compatible; cambios de ABI desaconsejan parches individuales improvisados. |
| Perl | 1 | 1 | Conservar evidencia de ausencia del modulo afectado y revisar uso operativo. |
| zlib | 1 | 1 | Resolver discrepancia entre rango publicado y version instalada con el proveedor; no declarar falso positivo. |
| Total | 11 | 44 | Sin excepciones nuevas ni autorizacion de despliegue. |

## Cambio del contador de 42 a 44

El aviso adicional es [CVE-2026-19499](https://security-tracker.debian.org/tracker/CVE-2026-19499),
registrado para `libc-bin` y `libc6`, ambos `2.41-12+deb13u4`.
El proveedor describe escritura fuera del buffer en `strfmon`/`strfmon_l`
al aplicar determinado relleno de ancho. No es un fallo demostrado en la
logica de precios de Muvv. La descripcion no acredita que sea inalcanzable.

No se encontraron llamadas directas a `strfmon`, `setlocale` ni
`locale.currency` en `backend/app`. Hay uso de ctypes en el guard de arranque
para prctl y close_range; no es una llamada al formateador monetario. Esta
busqueda no cubre todas las dependencias ni las llamadas dinamicas.

Se amplia el inventario ELF existente con `monetary_format`, incluyendo
simbolos publicos, internos conocidos y nombres versionados. Se distinguen
imports de exports: que libc exporte la funcion no demuestra que Muvv la llame.
No se ejecutan payloads contra el servidor ni se leen documentos o dinero real.
Los informes previos NO recopilaron ese grupo: no equivalen a cero llamadas.
El nuevo inventario aun debe ejecutarse en Linux sobre una imagen concreta.

## Disponibilidad reconsultada

Consultas de solo lectura del 15 de septiembre, sin instalaciones:

- [glibc: formato monetario](https://security-tracker.debian.org/tracker/CVE-2026-19499)
  y [DNS](https://security-tracker.debian.org/tracker/CVE-2026-5435): trixie sigue
  marcado vulnerable; el arreglo listado no esta en la version estable usada.
- [util-linux](https://security-tracker.debian.org/tracker/CVE-2026-76642): arreglo
  listado en sid, no justifica mezclar esa distribucion con trixie.
- [ACL](https://security-tracker.debian.org/tracker/CVE-2026-54369): Debian indica
  esperar actualizacion del paquete; no hacer backports individuales a ciegas.
- [zlib](https://security-tracker.debian.org/tracker/CVE-2026-85091): estable aun
  marcado vulnerable; la [consulta upstream](https://github.com/madler/zlib/issues/1310)
  sigue abierta sin una resolucion verificable en la pagina consultada.

## Plan para desbloquear, sin repetir builds identicos

1. Ejecutar el inventario ampliado y revisar el nuevo aviso de glibc en la
   imagen exacta. Conservar las limitaciones de busqueda estatica/dinamica.
2. Continuar consultas concretas a proveedores ya preparadas para DHI y Wolfi;
   no contratar servicios ni enviar datos/consultas en nombre del propietario
   sin autorizacion. Las comparaciones anteriores tambien quedaron bloqueadas.
3. Elegir una actualizacion mantenida que resuelva los avisos, o encargar una
   evaluacion independiente por CVE con alcance, pruebas, vencimiento y
   condiciones de invalidacion. No aceptar riesgos implicitamente.
4. Solo tras resolver el control de imagen, verificar PostgreSQL/TLS y hosting
   aislado, luego desplegar backend compatible y actualizar la APK con permiso.

No requiere cambiar el plan de Railway ni pagar por Docker para preparar
estas pruebas. No se inicia un servicio nuevo. Una eventual ejecucion de CI
utilizara la cuota existente de GitHub Actions; servicios externos se cotizan
y autorizan por separado. No hay promesa de cero costo por consumos del plan.

## Verificacion de esta ampliacion

Suite local: 346 pruebas ejecutadas, 345 aprobadas y una omitida por requerir
Linux. Dos regresiones nuevas comprueban simbolos monetarios versionados,
separacion entre imports/exports, identidad de imagen y limites del informe.
Segunda revision estatica: sin hallazgos P1/P2 en este diff acotado; no ejecuto
inventarios ni verifico de forma independiente fuentes externas o escaneos.

El propietario autorizo commit/push de estos tres archivos a la rama de pruebas
y ejecucion en GitHub, sin despliegue. El resultado Linux se registrara tras
la corrida; las pruebas locales no demuestran cuantos callers tiene la imagen
ni resuelven alguno de los 44 registros pendientes.
