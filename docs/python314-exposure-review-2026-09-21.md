# Revision de exposicion de la candidata Python 3.14

Fecha: 2026-09-21. Estado: BLOQUEADA, sin nuevas excepciones ni deploy.
Esta revision prioriza trabajo; no es una aprobacion VEX ni aceptacion de riesgo.

## Evidencia y limites

Commit `c1d9cca521b70ba362720a61cb4b62b08ad70d09`.
[Actions 35669571540](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35669571540),
job `106562776187`, imagen
`sha256:91440550843b1f025bc2eebae8f3abc001d553acb2ee44a45ee7ffb5f6b931d3`.

El escaner conserva 44 filas High correspondientes a 11 CVE diferentes.
Se revisaron las anotaciones publicas, no el JSON completo del artefacto:
784 ELF; 33 archivos con imports de carga dinamica (solo 12 visibles en la
anotacion); cinco importadores ACL y dos gzip_write, ambos grupos completos
en las anotaciones. Cero imports encontrados para monetary_format y legacy_dns.

El verificador anterior aprobo UID 100, GID 101, capacidades efectivas y
permitidas cero y no_new_privs=1. El arranque real comprobo su propio guard.
Son resultados de contenedores de CI, NO del hosting Railway. Los enlaces no
se resuelven en el inventario y no se detectan por nombre copias renombradas.
Ninguna ausencia de imports demuestra inalcanzabilidad por si sola.

## Priorizacion de las 44 filas

| Grupo de trabajo, no disposicion | Filas High | CVE | Accion |
| --- | ---: | ---: | --- |
| Herramienta o modulo afectado no encontrado por nombre | 14 | 4 | Corroborar copias, enlaces y operaciones administrativas antes de proponer revision acotada. |
| Montajes que requieren condiciones privilegiadas | 24 | 3 | Mantener protecciones; verificar condiciones reales del hosting y callers de libmount. No declarar parche aplicado. |
| Bibliotecas retenidas que necesitan revision de llamadas o parche | 6 | 4 | Priorizar glibc, libacl y zlib; incluir carga dinamica y procedencia del binario. |
| Total | 44 | 11 | Todos siguen abiertos para el control de despliegue. |

### Herramientas o modulos: 14 filas

- [CVE-2025-69720](https://security-tracker.debian.org/tracker/CVE-2025-69720),
  cuatro filas ncurses: afecta analyze_string de infocmp, no demuestra un fallo
  en cada biblioteca ncurses. No se encontraron rutas llamadas infocmp.
  Falta revisar aliases/copias y validar que la operacion no introduce la herramienta.
- [CVE-2026-78408](https://security-tracker.debian.org/tracker/CVE-2026-78408),
  ocho filas util-linux: requiere nsenter --join-cgroup usado con privilegios y
  un descriptor heredado. La unica coincidencia nsenter es autocompletado Bash,
  no el ejecutable. El guard de Muvv cierra descriptores, pero no protege todas
  las herramientas que un operador pueda ejecutar fuera de ese arranque.
- [CVE-2026-54370](https://security-tracker.debian.org/tracker/CVE-2026-54370),
  una fila ACL: afecta carreras en getfacl/setfacl/chacl sobre rutas controlables
  por un atacante cuando se usan con privilegios. Cero rutas con esos nombres.
  Esto NO resuelve el aviso distinto de libacl descrito mas abajo.
- [CVE-2026-9538](https://security-tracker.debian.org/tracker/CVE-2026-9538),
  una fila Perl: afecta lectura TAR en Archive::Tar. Cero rutas conocidas
  Archive/Tar.pm y probe @INC negativo. No equivale a Perl completamente corregido.

### Montajes privilegiados: 24 filas

- [CVE-2026-76642](https://security-tracker.debian.org/tracker/CVE-2026-76642),
  ocho filas: libmount ejecuta operaciones posteriores aunque falle un helper.
  El [aviso upstream](https://github.com/util-linux/util-linux/security/advisories/GHSA-m25x-3hj9-m26f)
  detalla mount SUID y una entrada fstab autorizada. La herramienta mount fue
  retirada y CI verifica privilegios restringidos. libmount sigue instalada;
  no se ha inventariado exhaustivamente su uso dinamico ni la configuracion del host.
- [CVE-2026-78409](https://security-tracker.debian.org/tracker/CVE-2026-78409),
  ocho filas: X-mount.subdir puede atravesar enlaces intermedios en su ruta
  rapida de Linux >=6.15. No se infiere la version del kernel de Railway.
  El contenedor probado no tiene mount ni privilegios efectivos; falta hosting.
- [CVE-2026-78410](https://security-tracker.debian.org/tracker/CVE-2026-78410),
  ocho filas: bind mount privilegiado puede redirigirse cambiando una ruta
  autorizada de fstab. No ejecutar montajes ni tareas root sobre rutas que
  clientes o conductores puedan modificar. No se realizo ningun exploit.

### Bibliotecas retenidas: seis filas

- [CVE-2026-19499](https://security-tracker.debian.org/tracker/CVE-2026-19499),
  dos filas glibc: desbordamiento en strfmon/strfmon_l con cierto relleno de ancho.
  Cero imports directos observados, pero hay carga dinamica. No es prueba de un
  fallo en el calculo de precios de Muvv ni prueba de inalcanzabilidad.
- [CVE-2026-5435](https://security-tracker.debian.org/tracker/CVE-2026-5435),
  dos filas glibc: impresion DNS antigua de TSIG. Cero imports directos observados.
  No confundir estas funciones con toda resolucion DNS; misma limitacion dinamica.
- [CVE-2026-54369](https://security-tracker.debian.org/tracker/CVE-2026-54369),
  una fila libacl: requiere procesamiento privilegiado de rutas manipulables.
  cp, install, mv, sed y tar importan funciones afectadas. No eliminar libacl
  sin comprobar dependencias. Debian advierte de cambios de ABI en la correccion;
  no mezclar paquetes de sid ni copiar parches aislados a ciegas.
- [CVE-2026-85091](https://security-tracker.debian.org/tracker/CVE-2026-85091),
  una fila zlib: escritura gzip no bloqueante con buffers obsoletos. dpkg-deb
  y libapt-pkg importan gzwrite/gzclose; eso no demuestra la secuencia vulnerable.
  El rango descrito y la version Debian marcada requieren revision de procedencia.
  No confundir deflate/gzip de HTTP con esa API ni declarar falso positivo por version.

Las fuentes de Debian consultadas siguen marcando los paquetes de trixie como
vulnerables. Un arreglo publicado en unstable o upstream no es un paquete
compatible ya instalado en esta imagen. No se modificaron requisitos ni Dockerfiles.

## Cuatro brechas del verificador corregidas localmente

1. Classic revisaba permisos de escritura/propietario solo en /app y /usr/local,
   aunque ya recorria /usr. Ahora incluye bibliotecas y directorios de /usr.
2. Faltaban capacidades heredables y ambientales; ahora los cuatro campos son
   obligatorios y cualquier valor no cero bloquea. No se exige CapBnd=0: el
   conjunto limite no es un privilegio concedido por si solo.
3. Solo comprobaba UID/GID efectivos y grupos. Ahora verifica tambien identidades
   reales y guardadas, igual que el guard de arranque existente de la app.
4. La busqueda de Archive/Tar.pm fuera de @INC solo bloqueaba en DHI. Ahora
   bloquea tambien en classic dentro de las raices recorridas.

Son correcciones de la verificacion previa, no cuatro CVE eliminadas ni cambios
de permisos aplicados a produccion. No alteran login, roles, pagos o interfaz.

Limitacion detectada en esta primera revision: os.walk no sigue directorios enlazados fuera de las
raices. Una biblioteca o arbol externo enlazado no queda completamente auditado
por ampliar /usr. No se amplia el alcance a /etc, /proc o montajes del host
sin un diseno acotado y probado para evitar recorridos arbitrarios.

## Decision siguiente

No repetir builds identicos ni habilitar excepciones generales. Esta revision
separa trabajo sobre bibliotecas, condiciones de privilegios y componentes
ausentes. Para cerrar cada aviso se necesita parche mantenido comprobado o una
evaluacion acotada independiente con condiciones de invalidacion y autorizacion.
La validacion Linux de las correcciones locales del verificador sigue pendiente.
No hubo push, nueva corrida de Actions, deploy ni contratacion en esta ronda.

## Verificacion local y segunda revision

- Suite completa en Python 3.14.7 y Python 3.11: 420 casos en cada interprete,
  417 aprobados y tres omitidos por requerir Linux. No son 834 casos distintos.
- 24 pruebas especificas del verificador, ocho mas que antes. Incluyen identidad
  real/guardada root, cada capacidad no cero/ausente, copia de Archive/Tar.pm
  fuera de @INC y recorrido de biblioteca/directorio inseguros con salida 1.
- El fixture de permisos recorre archivos temporales reales con metadatos
  simulados. No demuestra permisos efectivos de una imagen Linux.
- Ambiente sin credenciales heredadas; DATABASE_URL local en puerto 1, clave
  aleatoria de pruebas, HOME/USERPROFILE y directorio de trabajo temporales.
  El primer intento omitio HOME/USERPROFILE y dos modulos de pruebas de respaldo
  no pudieron importarse. Se corrigio el lanzador local, no la aplicacion;
  las dos ejecuciones completas posteriores finalizaron correctamente.
- Revision estatica independiente sin P1/P2 nuevos. Confirma la suma de la
  matriz y mantiene abierta la limitacion P2 sobre destinos enlazados.
- git diff --check sin errores. Cambios locales sin commit/push en esta ronda.

Antes de consumir otro build, completar el diseno y las pruebas del recorrido
de enlaces externos del verificador. No resolverlo ignorando enlaces ni siguiendo
arboles arbitrarios del host. Luego ejecutar juntas las verificaciones Linux y
mantener el escaneo High/Critical obligatorio, sin descuentos automaticos.

## Seguimiento: enlaces del verificador

Se implemento localmente `inspect_symlink` en el mismo verificador. En vez de
ignorar el destino, comprueba metadatos por cada componente de la ruta,
incluidos padres y enlaces intermedios. No abre contenidos ni ejecuta destinos.
La comprobacion incluye propiedad, permisos, acceso de escritura, setid y
capacidades de archivos, y conserva controles de bibliotecas OpenSSL antiguas
y Archive/Tar.pm cuando aparecen como destinos.

- Limites por enlace: 40 saltos, 256 pasos de resolucion y 4096 caracteres
  por ruta/valor de enlace. Son limites de trabajo, no un deadline independiente.
- Rechaza ciclos, destinos rotos/inaccesibles, archivos especiales y rutas
  virtuales /proc, /sys, /dev y /run. Un error no se convierte en aprobacion.
- Conserva el orden de resolucion: primero el enlace, despues `..`. No colapsa
  lexicalmente una ruta que pueda atravesar un padre inseguro.
- Archivo externo: valida metadatos de toda su ruta; eso no es un inventario
  de sus dependencias ni un escaneo de vulnerabilidades de su contenido.
- Directorio externo: `symlink_external_directory_unreviewed` bloquea, sin
  recorrerlo. Solo se considera cubierto un directorio final dentro de raices
  protegidas y recorridas por el verificador. No hay allowlist de certificados.
- Una raiz del recorrido que sea en si misma un enlace se rechaza, para no
  comenzar la inspeccion en un arbol distinto del declarado.
- Salida JSON conserva campos previos y agrega contador de enlaces y politica.
  Las incidencias se asocian al enlace de origen, sin volcar su valor ni errores.

Esto evita aprobar silenciosamente un arbol externo no revisado; NO acredita
que todos los enlaces actuales de la imagen sean compatibles. Por ejemplo,
un enlace legitimo a /etc/ssl/certs puede quedar bloqueado por falta de revision.
La ejecucion Linux debe identificar estos casos antes de decidir un alcance
adicional. No sortearlos silenciando el control ni leyendo claves privadas.

Pruebas locales posteriores: 436 casos por interprete (Python 3.11 y 3.14.7),
433 aprobados y tres omitidos por plataforma. Los 40 casos del verificador
incluyen 16 nuevos de enlaces, rutas y propagacion al veredicto. El resolvedor
POSIX se prueba con filesystem simulado; el recorrido integrado usa fixtures
temporales y metadatos simulados. Falta ejecutar contra enlaces reales Linux.

Limites restantes: no es una inspeccion atomica frente a un administrador root
que modifique la imagen concurrentemente; se usa sobre una candidata aislada de
CI, no un servidor vivo con volumenes de usuarios. No inventaria copias
renombradas, codigo enlazado estaticamente ni todos los archivos del host.
No cambia ninguno de los 44 avisos High, los umbrales ni la decision NO-GO.

### Cierre de revision previa al push autorizado

La segunda revision detecto que os.walk clasifica destinos antes de aplicar
el resolvedor, aun con followlinks=False. Se sustituyo por enumeracion de
nombres con os.scandir y lstat por entrada; no se invoca DirEntry.is_dir/stat.
No se expanden directorios con infracciones. El presupuesto global es de
200.000 entradas; excederlo es inspeccion incompleta (salida 2), nunca aprobacion.
Los directorios ascendientes de una raiz protegida tambien se protegen.

Un fixture integrado verifica /usr/link -> /proc/self/fd/3 con el resolvedor
real: consultar el destino o clasificar DirEntry haria fallar la prueba.
Se agregaron regresiones de directorio inseguro sin enumeracion y limite de
entradas. La revision estatica posterior cierra este P2 acotado, sin nuevos
P1/P2; no sustituye la ejecucion Linux ni resuelve los avisos del escaner.
Las anotaciones de ambos perfiles incluyen hasta ocho ejemplos de infracciones
con rutas de origen limitadas a 200 caracteres, sin valores de enlaces.

El propietario autorizo commit/push a la rama de pruebas y consumo de Actions
tras la revision. No incluye main, Railway, despliegue, APK ni publicaciones.
Se activaran los workflows existentes cuyos filtros incluyan el verificador:
clasico, Python 3.14 y DHI. No se modificaron workflows ni sus umbrales.

Validacion final antes de publicar: 440 pruebas por interprete, 437 aprobadas
y tres omitidas, tanto en Python 3.11 como en 3.14.7; 44 casos del verificador.
Las cifras de 420/436 anteriores corresponden a estados intermedios del lote.

## Resultado Linux del commit eb041fc

Commit publicado: `eb041fc36f3eb16fb6ba4c378f17ce86f5a10e19`, solo en
`codex/mvp-supabase-rls-review`. main permanece en
`590e8fec432f094619355dad89dcb068c4bd649f`. Todas las corridas terminaron.

| Evaluacion | Corrida | Resultado |
| --- | --- | --- |
| Clasica | [35673329997](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35673329997) | Build y tests aprobados; verificador bloquea; escaneo posterior omitido. |
| DHI | [35673330001](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35673330001) | Build y tests aprobados; verificador bloquea; escaneo posterior omitido. |
| Python 3.14 | [35673330055](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35673330055) | Build y tests aprobados; verificador y escaneo bloquean. |
| PostgreSQL independiente | Job 106574458329 de Python 3.14 | Todos los pasos aprobados: HTTP, permisos, pagos de prueba, TLS, migraciones vacia/legado y limpieza. |

No trasladar resultados de pasos omitidos desde corridas anteriores. En
particular, los nuevos pasos de arranque posteriores al verificador y los
inventarios nativos no se ejecutaron. No hay contador CVE nuevo de clasica/DHI.

Python 3.14, imagen `sha256:cfad0f9de5ebb6ea156f8b2d54c57181e15d212b59f7ec2c37c49250593923c8`:
Grype 0.118.0, Debian 13.7, 0 Critical, 44 High, 51 Medium, 7 Low,
43 Negligible y 1 Unknown. El escaneo obligatorio se ejecuto aunque fallo el
verificador. No hubo nuevas excepciones ni aprobacion de despliegue.

El verificador examino 172 enlaces en cada candidata clasica/Python 3.14:

- Cuatro `code_group_or_world_writable`: /usr/share/man/man1, man5, man7 y man8.
  Son permisos de directorios de manuales; no se registro `code_writable_by_app`
  para ellos. No describirlos como cuatro exploits o fallos de bibliotecas.
- Dos `symlink_external_directory_unreviewed`: /usr/lib/ssl/certs y
  /usr/lib/ssl/private. El bloqueo explicito esperado evita aprobar arboles
  externos no inspeccionados; NO acredita una vulnerabilidad de certificados.

DHI examino 253 enlaces: los mismos dos directorios SSL no revisados y dos
`symlink_unresolved`, /usr/share/zoneinfo/localtime y /usr/share/doc/base-files/FAQ.
La anotacion no distingue inexistente de inaccesible: no afirmar la causa
exacta sin inspeccionar metadatos. No se leyeron contenidos de claves privadas.

Las cuatro capacidades son cero y no_new_privs=1 en los tres verificadores.
Esto solo describe esas invocaciones en CI, no el hosting ni los pasos omitidos.

### Proxima correccion concreta

1. Ajustar permisos de los cuatro directorios de manuales en la candidata,
   conservando lectura/ejecucion necesarias; probar el cambio, no excluir el aviso.
2. Definir una inspeccion acotada de las rutas SSL con metadatos solamente y
   sin enumerar/leer claves privadas. No agregar una excepcion general /etc.
3. Aclarar los dos enlaces DHI sin resolver antes de cualquier disposicion.
4. Ejecutar un nuevo lote solo cuando exista un cambio real verificable;
   mantener separados estos resultados y los 44 registros High del escaner.

No se modificaron Dockerfiles, permisos del hosting, datos, APK ni Splash.
Este registro posterior de resultados queda local para evitar otra corrida
innecesaria. La conclusion sigue siendo NO-GO.

## Lote local posterior: permisos de manuales y diagnostico de enlaces

Alcance preparado, todavia sin commit/push ni construccion Linux de este lote:

- `backend/Dockerfile` y `backend/Dockerfile.python314`: validacion previa de
  ocho entradas (cuatro ascendientes y cuatro directorios man1/man5/man7/man8)
  con lstat, tipo directorio real y propietario root. Solo despues se quitan
  bits 0022 de los cuatro directorios. No se cambia contenido, propietario,
  lectura/ejecucion ni el resto de /usr; no hay chmod recursivo nuevo.
- `scripts/verify-runtime-image.py`: diagnosticos acotados a ocho enlaces y
  rutas de origen de hasta 200 caracteres. Los errores de sistema se traducen
  a categorias fijas missing/denied/not_directory/loop/io_error; no se publican
  mensajes de excepciones, nombres de destinos arbitrarios ni valores de enlaces.
  Los directorios externos solo informan categoria SSL conocida u otro,
  propietario y modo. No se enumeran ni se leen claves privadas.
- El veredicto no cambia: los enlaces externos no revisados y los errores de
  resolucion siguen bloqueando. Una categoria de error no demuestra por si sola
  la causa de los dos enlaces DHI; falta ejecutar contra la imagen real.
- `backend/tests/test_manual_directory_permissions.py`: ejecuta el mismo Python
  extraido de las recetas con lstat/chmod simulados; verifica los cuatro cambios,
  preservacion de bits y rechazo antes de modificar ante enlaces, archivos,
  propietario no root o directorios ausentes.
- `backend/tests/test_runtime_image_security.py`: prueba errores categorizados,
  redaccion de datos, ausencia de lecturas/enumeracion SSL y conservacion del
  bloqueo, salida 1 y anotacion con diagnosticos acotados.

Validacion local: 451 casos por interprete, 448 aprobados y tres omitidos por
plataforma tanto en Python 3.11 como en Python 3.14.7; 50 pruebas del verificador
y cinco de permisos de manuales. Entorno de pruebas sin variables de produccion,
URL de base de datos sintetica local y directorio de usuario temporal.
Los mensajes de limpieza de clusters provienen de fixtures de esta suite;
no representan una nueva prueba PostgreSQL real en este lote.

Segunda revision estatica independiente: sin P1/P2 concretos en el alcance
modificado. No ejecuto Docker ni red. Los mocks no prueban el parser Docker ni
chmod real en Linux, que siguen pendientes de la siguiente corrida autorizada.
git diff --check aprobado (solo advertencias de conversion LF/CRLF de Git).

No se modificaron reglas de CVE, workflows, DHI, main, Railway, APK, Splash,
pagos ni datos. No hay escaneo nuevo: los 44 High anteriores siguen pendientes.
El propietario autorizo commit/push de este lote a la rama de pruebas y su
consumo de Actions. No autoriza despliegue, Railway ni APK. La validacion Linux
se registrara por separado; la autorizacion no modifica el estado NO-GO.
