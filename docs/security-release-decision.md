# Decision de seguridad para el piloto Muvv

Fecha: 2026-09-14. Estado: BORRADOR PARA REVISION, NO AUTORIZA DESPLIEGUE.
Segunda revision por agente: realizada; aprobador del riesgo: pendiente. No es un archivo
VEX ni una lista de excepciones consumida por CI.

## En palabras simples

Las pruebas de funcionamiento pasan, pero el escaner registra 45 coincidencias
altas correspondientes a 13 avisos distintos. No significan 45 ataques
demostrados contra Muvv. Tampoco se pueden ignorar porque la app funcione.
Cambiar el plan de Railway no corrige las bibliotecas de esta imagen.

La siguiente accion es revisar y resolver cada aviso, no repetir la misma
compilacion esperando otro resultado. No se propone contratar servicios ni
actualizar paquetes desde Debian inestable.

## Evidencia que debe revisar la segunda persona o agente

- Codigo probado: `72f9f5fb5a60402fe9447853cadc288c0e4eeb4e`.
- Imagen: `sha256:1178e5973e7baf87c3a657b0186a16452006d375559c28db40720f5ed580c2f5`.
- [Corrida Linux completa](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34857584759): 224 unitarias, arranque, permisos, backports e inventario pasan; falla la politica de vulnerabilidades.
- 56 pruebas adicionales de PostgreSQL local aprobadas: 9 RLS, 8 migraciones y 39 HTTP/WebSocket. No equivalen a probar Supabase/PgBouncer por TLS.
- Artefacto `native-symbol-evidence`: 786 ELF, hashes e imports/exports; retencion de 14 dias. Las anotaciones publicas conservan resumen e identidad de imagen.
- Matriz y limites completos: [residual-image-review.md](residual-image-review.md).
- No se ha ejecutado ni aprobado un despliegue de esta candidata en `muvv-pruebas` o produccion.

## Propuestas por grupo

| Grupo | CVE / coincidencias altas | Propuesta, todavia no aplicada a CI | Que falta para cerrarlo |
| --- | --- | --- | --- |
| Cookies y recursion XML de Python | 2 / 2 | Revisar como corregidos en la version instalada, no como riesgo aceptado. | Confirmar correspondencia exacta entre imagen, CPython 3.11.16 y pruebas aprobadas; revision independiente. |
| Hash XML de Python | 1 / 1 | Backport, compilacion y ruta de 16 bytes observada en ambos parsers; candidato a cierre justificado, no exclusion aplicada. | Revisar el alcance de la evidencia de ejecucion y su correspondencia con la imagen; no mide calidad estadistica de entropia. |
| Herramientas del sistema: ncurses, Perl y util-linux | 6 / 37 | Mitigados o sin componente accesible en rutas comprobadas; NO llamarlos parcheados. | Revisar presencia real del componente, operacion privilegiada y hosting. Root de una consola no queda protegido por el guard de la API. |
| glibc y ACL | 3 / 4 | Menor exposicion observada, sin demostrar inalcanzabilidad completa. | Revisar uso dinamico/transitivo y comandos de operadores sobre rutas controladas por usuarios. |
| zlib | 1 / 1 | Posible discrepancia de versiones, no declarar falso positivo aun. | Vincular fuente exacta con biblioteca y resolver la discrepancia con el aviso del proveedor. |

### Dos correcciones confirmadas por el proveedor

La [publicacion oficial de Python 3.11.16](https://www.python.org/downloads/release/python-31116/)
identifica explicitamente CVE-2026-3644 (cookies) y CVE-2026-4224 (recursion XML)
como corregidos. La imagen informa esa version; las regresiones de cookies
y el rechazo acotado de XML profundo pasan en Linux. Esto sustenta proponer
su cierre como corregidos, manteniendo los hallazgos originales del escaner.
No se ha implementado ninguna exclusion para esos dos registros.

Para CVE-2026-7210, el [backport oficial](https://github.com/python/cpython/commit/cbaecf9f16da611a646d507c1cbca265c588fc56)
usa la funcion de 16 bytes condicionada por la version de las cabeceras de
Expat al compilar. `pyexpat.version_info` consulta la biblioteca en ejecucion;
no certifica por si sola aquellas cabeceras. La imagen usa Expat 2.8.3, pero
la prueba actual declara expresamente que no mide el comportamiento de entropia.
No convertir este tercer caso en una excepcion basandose solo en versiones.

### Avisos Debian restantes

Las fuentes primarias, reconsultadas el 2026-09-14, y sus criterios particulares
se detallan en la matriz enlazada. Entre ellas:

- [util-linux, CVE-2026-76642](https://security-tracker.debian.org/tracker/CVE-2026-76642): trixie sigue vulnerable; el arreglo listado esta en sid. No mezclar esas distribuciones en produccion.
- [ACL, CVE-2026-54369](https://security-tracker.debian.org/tracker/CVE-2026-54369): el cambio incorpora nueva ABI; Debian indica esperar actualizacion de la distribucion, no aplicar parches individuales a ciegas.
- [zlib, CVE-2026-85091](https://security-tracker.debian.org/tracker/CVE-2026-85091): el rango descrito y las versiones Debian marcadas no coinciden claramente. La disputa no es una resolucion.

## Orden para desbloquear el piloto

### Seguimiento de la segunda revision (2026-09-14)

La revision independiente por agente no aprobo produccion. Identifico dos
defectos en las herramientas de evidencia, corregidos localmente:

- `verify-runtime-image.py`: un modulo Perl `Archive::Tar` legible ahora
  genera una infraccion, bloquea el resultado y devuelve codigo de salida 1.
  Antes solo informaba esa condicion sin impedir la aprobacion del control.
- `report-native-symbols.py`: los nombres se validan y se comprueban contra
  duplicados antes de omitir enlaces, directorios u otras entradas no regulares.
  No se extraen archivos ni se siguen enlaces.

Las pruebas nuevas reprodujeron los defectos antes de corregirlos. Despues
pasaron 80 pruebas locales de controles de imagen, simbolos, reporte del
escaner, verificador de backports y arranque. Cubren ambos ordenes de
duplicacion, nombres inseguros y aceptacion de alias validos. Son pruebas
locales, no una nueva ejecucion de la candidata Linux ni una prueba en Railway.

La evidencia del hash XML, los descriptores privilegiados heredados, la
presencia de herramientas ACL y los otros avisos siguen pendientes. La
correccion de los controles no reduce por si sola las 45 coincidencias altas
del ultimo escaneo. No se cambiaron excepciones ni umbrales del escaner.

Antes de desplegar, conservar y promover exactamente la imagen aprobada,
o volver a analizar la imagen que se reconstruya. La base Docker no esta
fijada por digest y la instalacion de paquetes puede variar; un mismo commit
no garantiza un paquete identico. El flujo actual conserva evidencia, no
publica ni conserva la imagen completa para promocion.

### Pasos restantes

Preparacion local adicional de evidencia XML (2026-09-14): el verificador de
backports ahora calcula SHA-256 de `pyexpat` y `_elementtree` y prueba ambos
parsers con XML fijo y pequeno. El inventario ELF ahora incluye las funciones
`XML_SetHashSalt` y `XML_SetHashSalt16Bytes`, separando imports de exports.
Las pruebas locales del conjunto ampliado suman 86 aprobadas. La proxima
corrida Linux existente ejecutara estos controles sin agregar dependencias
ni modificar la imagen candidata para instrumentarla.

Estos cambios preparan evidencia; aun no se ejecutaron en GitHub ni Railway.
Comparar los hashes de las anotaciones del verificador con los archivos del
artefacto ELF de la misma corrida. Tanto el comportamiento probado como los
simbolos estaticos tienen limites: un XML valido no demuestra que se use la
funcion de 16 bytes, y `_elementtree` la invoca indirectamente mediante la
C API de `pyexpat`. Se mantienen `hash_salt_call_path_proven=false`,
`xml_hash_entropy_behavior_tested=false` y `scanner_findings_waived=false`.
No cerrar CVE-2026-7210 con esos datos sin evidencia adicional de la ruta.

La corrida de `3413ef6`, [34862145209](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34862145209),
aprobo pruebas, permisos, arranque e inventario. El escaner mantuvo 45 High
de 13 CVE y bloqueo la candidata. Imagen:
`sha256:fc53ab0c85785d742e7f80b890665b5a608959611e718dff985ef77c14833cc8`.
El inventario no observo imports XML coincidentes; no demuestra ausencia
del codigo, en particular cuando Expat esta integrado o usa nombres privados.

El siguiente control preparado lee solo metadatos de la capsula C API que
`pyexpat` comparte con `_elementtree`: version de cabeceras al compilar,
tamano de estructura y disponibilidad de la funcion de 16 bytes. Se limita
al ABI Linux CPython 3.11.16 de 64 bits y valida capsula, firma y tamano antes
de leer la estructura completa. No escribe memoria, llama punteros Expat,
lee entropia ni publica direcciones de memoria. Una version futura requiere
revision del control en lugar de interpretar un layout desconocido.
Se agregan los nombres privados `PyExpat_XML_*` al inventario estatico.
Las 91 pruebas locales pasan. El control se ejecuto en Linux en la corrida
de `9947485` indicada a continuacion.

Referencia de layout: [Include/pyexpat.h de CPython 3.11.16](https://github.com/python/cpython/blob/v3.11.16/Include/pyexpat.h).
La disponibilidad en C API es evidencia mas precisa que la version de la
biblioteca, pero no es un registro de llamadas ni una medida de entropia;
`hash_salt_call_path_proven` sigue siendo falso y no habilita excepciones.

Resultado Linux de `9947485`: [corrida 34863470989](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34863470989).
Pasaron pruebas, arranque, permisos, backports e inventario. La C API valida
tiene 224 bytes, identifica cabeceras Expat 2.8.3 y contiene un puntero no nulo
para `SetHashSalt16Bytes`. Esto resuelve la duda de version de compilacion y
disponibilidad en la interfaz, no demuestra ejecucion ni calidad de entropia.
Las huellas de los dos modulos coinciden con las de la corrida anterior:

- `pyexpat`: `27e28ee2600c7d6347130227616e4fd5ae1c59800ad01fa12e1f23c6f41f34e3`.
- `_elementtree`: `03bb0f3a57760a0afe252ffbb41acd6492552a2115ada2e42a277075ce7f49c5`.

Imagen nueva: `sha256:3836d4b73c8ebd96696edf33db585f05c313514190603b47ddebee2019cd4ac6`.
El inventario sigue sin imports XML observables, incluso con los alias:
no usarlo como prueba de ausencia. El escaner termina bloqueado con 45 High,
49 Medium y 0 Critical. No se aplicaron excepciones ni cambios en Railway.

## Prueba de ejecucion XML preparada

Se agrega una observacion mediante GDB en el host temporal de GitHub, no en
el contenedor publicado. Dos contenedores desechables de la imagen exacta
ejecutan tres constructores y lecturas XML sinteticas cada uno. Se ejecutan
sin red, sin credenciales, sin capacidades, con filesystem de solo lectura
y limites de memoria, CPU, procesos y tiempo. Se eliminan al terminar.

El observador valida PID, hashes de ambos modulos y que las direcciones de
las funciones correspondan al mapeo ejecutable de `pyexpat`. Usa breakpoints
de hardware en la funcion de 16 bytes y la heredada, sin leer argumentos de
entropia. Solo publica hashes y contadores; el control con direcciones y los
logs internos permanecen temporales y no se suben como artefactos.

El resultado exige tres llamadas nuevas, cero heredadas, tres lecturas
correctas, mismos hashes y salida normal para cada procesador. Un debugger
no disponible, layout diferente, fallo de permisos, optimizacion que impida
observar la funcion o cualquier observacion incompleta bloquea esta prueba;
no se considera una demostracion de vulnerabilidad por si solo.

Esto no mide calidad aleatoria, resistencia estadistica ni todos los usos XML.
Tampoco aplica exclusiones al escaner. Pasaron 97 pruebas locales y la
observacion de hardware fue validada en Linux como se detalla a continuacion.

### Resultado de ejecucion real (2026-09-14)

Codigo: `558d76c80ecec6e98d8c0f8c746b566eb9106c3a`.
[Corrida 34865212086](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34865212086).
Imagen: `sha256:2c459466540585c6b811e20f29eaa2b348017a99c2efc4915e082fc2a8fb971c`.
Artefacto: `xml-call-evidence`, retencion de 14 dias; resumen publico en
la anotacion `XML execution trace (not approval)`.

| Procesador | Llamadas funcion 16 bytes | Llamadas heredada | Lecturas correctas | Salida |
| --- | --- | --- | --- | --- |
| pyexpat | 3 | 0 | 3 | 0 |
| _elementtree | 3 | 0 | 3 | 0 |

Ambos resultados se obtuvieron mediante breakpoints de hardware en
contenedores separados de la misma imagen, sin agregar paquetes al runtime.
Los hashes de los dos modulos coinciden antes y despues y con los publicados
en la evidencia anterior. No se leyeron valores de salt ni argumentos.
Se observaron las rutas que faltaban, en el alcance sintetico descrito;
esto no es una auditoria de todas las formas de XML ni una prueba estadistica
de aleatoriedad. Los campos de las sondas anteriores que dicen no probar
ejecucion conservan ese significado: es esta sonda separada la que la observa.

El resto de pruebas, arranque, permisos e inventario pasaron. La corrida
sigue fallando unicamente por el escaner: 45 High, 49 Medium, 0 Critical,
155 coincidencias totales. No se cambio la politica ni se aprobo produccion.
El siguiente frente son los componentes del sistema pendientes (glibc, ACL,
util-linux, ncurses, Perl y zlib), no repetir la misma comprobacion XML.

## Retirada de herramientas no utilizadas

Preparacion del 2026-09-14: el backend y sus migraciones no contienen usos
de `infocmp` ni `nsenter`. Se retiran exactamente `/usr/bin/infocmp` y
`/usr/bin/nsenter` del filesystem efectivo de la imagen candidata, despues
de instalar sus dependencias. Antes estaban presentes con permisos 0700;
ahora el verificador exige ausencia mediante lstat, incluidos enlaces rotos.
Una denegacion de permisos no se interpreta como ausencia.

Se conservan las bibliotecas y los registros de paquetes Debian. Esto no
parchea libmount ni convierte todos los avisos de ncurses/util-linux en
resueltos. Tampoco impide el uso de un nsenter externo por un operador del
host ni elimina un descriptor privilegiado heredado desde ese host.

El inventario de todo el `docker export` registra rutas con nombres conocidos
de infocmp, nsenter, getfacl, setfacl, chacl y Archive/Tar.pm, incluyendo aliases
sin seguirlos. Distingue herramientas ACL de libacl y el modulo Archive::Tar
del interprete Perl. No prueba ausencia de copias renombradas, implementaciones
embebidas o componentes del host. No se leen documentos ni contenidos Perl.

Las fuentes primarias reconsultadas mantienen los avisos de las versiones
trixie. Se conservan las restricciones del escaner, sin repositorios sid:
[infocmp](https://security-tracker.debian.org/tracker/CVE-2025-69720),
[nsenter](https://security-tracker.debian.org/tracker/CVE-2026-78408),
[herramientas ACL](https://security-tracker.debian.org/tracker/CVE-2026-54370),
[Archive::Tar](https://security-tracker.debian.org/tracker/CVE-2026-9538).

Las 98 pruebas locales seleccionadas pasan. La corrida Linux de `b3bf98a`,
[34866565119](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34866565119),
aprobo pruebas, arranque, dependencias, permisos, inventario y observacion XML.
Imagen: `sha256:0f25b9d3014d4ce7bd8d606056d3d049466ab8671208b3385da25f76bbfd6261`.

- Los dos ejecutables retirados no existen en sus rutas, comprobado con lstat.
- Cero rutas con nombre infocmp en el filesystem efectivo.
- Una ruta con nombre nsenter: `/usr/share/bash-completion/completions/nsenter`.
  Es la ruta de autocompletado, no `/usr/bin/nsenter`; el contador por nombre
  no debe interpretarse como presencia del ejecutable vulnerable.
- Cero rutas con los nombres getfacl, setfacl y chacl.
- Cero rutas conocidas Archive/Tar.pm, y la sonda Perl tampoco lo encuentra
  legible en su lista de busqueda habitual.
- El verificador inspecciono 15516 entradas sin infracciones.

El escaner conserva 45 High, 49 Medium y 0 Critical. Los registros Debian
no se borraron ni manipularon y las bibliotecas permanecen: la retirada de
un ejecutable no elimina automaticamente los avisos de su paquete fuente.
La corrida falla solo por la politica de vulnerabilidades. No hay merge ni
despliegue de esta candidata.

Siguiente comprobacion del arranque: evitar conservar descriptores de archivo
heredados que puedan otorgar capacidades sobre cgroups u otros recursos, sin
interferir con entrada/salida y logs. Esto requiere pruebas especificas antes
de aplicarlo; el estado actual de UID/capacidades no demuestra que dichos
descriptores esten ausentes. Los otros avisos de bibliotecas siguen pendientes.

## Cierre de descriptores heredados antes de servir

Cambio candidato del 2026-09-14: `app.server` cierra los descriptores 3 en
adelante antes de importar Uvicorn. Usa `close_range(3, UINT_MAX,
CLOSE_RANGE_UNSHARE)` con tipos ctypes explicitos, despues de verificar un
solo hilo, identidad no root, capacidades vacias y no_new_privs. El cierre
es inmediato; no se limita a marcar close-on-exec ni al limite blando actual.
Un simbolo libc ausente o una llamada rechazada detienen el arranque con el
mensaje generico existente. No hay fallback que conserve accesos heredados.

Se preservan los descriptores 0, 1 y 2 para entrada/salida y logs. Esto supone
que el hosting los configura como canales de confianza: no se inspecciona
su destino ni se aprueba que apunten a un recurso privilegiado. Esta medida
no demuestra ausencia total de accesos concedidos por un host comprometido
ni resuelve por si sola todas las CVE de util-linux. La API crea sus propias
conexiones despues; no se admite socket activation ni un socket preabierto.
El CMD actual no usa workers, reload ni sockets heredados.

Pruebas: tipos y rango exactos, rechazo del kernel, funcion libc ausente,
orden de los controles y propagacion del fallo. La prueba Linux arranca un
subproceso con seis descriptores reales (archivo, socket, ambos extremos de
un pipe, directorio y duplicado numerado >=512). Baja RLIMIT_NOFILE a 256,
ejecuta el guard real y verifica EBADF antes de servir, preservacion de stdio
y de los handles del padre y apertura de un archivo nuevo despues del guard.
Solo el servidor Uvicorn esta sustituido en esta prueba; el workflow mantiene
ademas la prueba del CMD real, HTTP sin autenticar y apagado SIGTERM.

Local Windows: 104 pruebas seleccionadas, 103 aprobadas y una omitida por
requerir Linux. La verificacion Linux real esta pendiente del workflow; no
se presenta el resultado local como prueba de close_range en el contenedor.
No cambia el escaner, sus umbrales ni sus excepciones. No hay deploy.
Referencia: [close_range(2)](https://www.man7.org/linux/man-pages/man2/close_range.2.html).

1. Resolver la evidencia faltante senalada por la segunda revision para las 13 CVE y ejecutar nuevamente los controles sobre la candidata Linux. Una segunda revision de un agente no sustituye una auditoria profesional de produccion.
2. Las correcciones confirmadas se distinguen de riesgos mitigados. Cualquier excepcion propuesta debe identificar CVE, paquete, version, imagen, fundamento, alcance, vencimiento y condiciones de invalidacion; no basta autorizar "ignorar los altos".
3. Antes de aplicar excepciones o aceptar riesgos residuales, presentar al propietario la decision concreta. Este documento no presupone esa aprobacion.
4. Tras resolver la politica de seguridad, autorizar por separado el servicio temporal aislado y su presupuesto. Usar datos ficticios, base y bucket separados; comprobar TLS, UID/capacidades y comandos de mantenimiento en ese entorno.
5. Solo despues verificar los flujos con los telefonos y decidir la promocion. Pagos reales, documentos reales y produccion requieren sus propias condiciones de lanzamiento.

No modificar `scripts/grype-candidate.yaml` ni `scripts/report-image-audit.py`
como consecuencia automatica de este borrador. Los avisos medios y los otros
pendientes del MVP tampoco quedan aprobados por cerrar los altos.
