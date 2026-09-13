# Revision de los 13 avisos altos restantes

Fecha: 2026-09-13. Rama de seguridad, sin merge ni deploy. Este documento es
evidencia para revision: no es una aceptacion de riesgo, archivo VEX aprobado
ni lista de exclusiones del escaner.

## Base de evidencia

La [corrida 34763412239](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34763412239)
probo `ce1286b0112a3a06d1896c718afd180bff809091`, imagen
`sha256:004367efe34ef572a66d1c147cf76f1db1126f35ac43d938bf4ea4b2b0b140db`.
El informe contiene 45 coincidencias altas, correspondientes a 13 CVE.
Los permisos se comprobaron con UID 100, sin capacidades ni SUID/SGID, y
no-new-privileges habilitado por CI. Eso NO acredita esos ajustes en Railway.

## Matriz de revision

Todas las filas conservan el bloqueo del escaner hasta una resolucion revisada.
Los enlaces identifican la fuente primaria, consultada el 2026-09-13.

| CVE | Coincidencias | Evidencia y siguiente comprobacion |
| --- | ---: | --- |
| [CVE-2026-3644](https://github.com/python/cpython/commit/dae4b1a21f8df4570e30986affd61bbe4ade4cef) | 1 | Backport oficial 3.11 en cookies. Version instalada 3.11.16; regresiones de update, union, estado y salida JavaScript aprobadas en Linux. |
| [CVE-2026-4224](https://github.com/python/cpython/commit/642865ddf4b232da1f3b1f7abcfa3254c4bfe785) | 1 | Backport oficial 3.11 del limite de recursion C. Linux rechaza el modelo anidado con RecursionError, sin crash. |
| [CVE-2026-7210](https://github.com/python/cpython/commit/cbaecf9f16da611a646d507c1cbca265c588fc56) | 1 | Backport oficial 3.11 y Expat 2.8.3 instalado. La version de Expat sola no prueba el uso de entropia de 16 bytes; conservar procedencia del interprete y ambos requisitos. |
| [CVE-2025-69720](https://security-tracker.debian.org/tracker/CVE-2025-69720) | 4 | Afecta infocmp. El ejecutable existe pero app no puede leerlo ni ejecutarlo. El operador root sigue pudiendo utilizarlo; no declararlo eliminado. |
| [CVE-2026-9538](https://security-tracker.debian.org/tracker/CVE-2026-9538) | 1 | Archive::Tar no es legible en las rutas normales de Perl. No demuestra ausencia en cualquier ruta alternativa o futura imagen. |
| [CVE-2026-76642](https://security-tracker.debian.org/tracker/CVE-2026-76642) | 8 | Operaciones privilegiadas de montaje: paquete mount eliminado, proceso no-root y sin privilegios en CI. Revisar tambien bibliotecas retenidas y configuracion real del host. |
| [CVE-2026-78408](https://security-tracker.debian.org/tracker/CVE-2026-78408) | 8 | Requiere uso privilegiado de nsenter --join-cgroup. app no puede leer ni ejecutar nsenter; falta incluir el uso por operadores en la revision. |
| [CVE-2026-78409](https://security-tracker.debian.org/tracker/CVE-2026-78409) | 8 | Ruta privilegiada de X-mount.subdir. Sin mount ni SUID en candidata; verificar ausencia de configuracion equivalente/privilegios en hosting. |
| [CVE-2026-78410](https://security-tracker.debian.org/tracker/CVE-2026-78410) | 8 | Bind mount privilegiado con rutas controlables. Controles del contenedor reducen la exposicion, no corrigen libmount. |
| [CVE-2026-5435](https://security-tracker.debian.org/tracker/CVE-2026-5435) | 2 | glibc conserva funciones antiguas de impresion DNS vulnerables. No hay invocacion directa encontrada en backend/app; falta revisar llamadas nativas/transitivas, no basta buscar texto Python. |
| [CVE-2026-54369](https://security-tracker.debian.org/tracker/CVE-2026-54369) | 1 | libacl y rutas con enlaces simbolicos manipulables por un atacante. Biblioteca retenida; revisar callers privilegiados. No instalar paquetes de sid para ocultar el aviso. |
| [CVE-2026-54370](https://security-tracker.debian.org/tracker/CVE-2026-54370) | 1 | Carrera en herramientas ACL sobre rutas controlables. Verificar componentes y uso operativo, ademas de la identidad no-root de la API. |
| [CVE-2026-85091](https://security-tracker.debian.org/tracker/CVE-2026-85091) | 1 | Debian marca zlib 1.3.1 vulnerable, pero describe una funcion incorporada despues. Contrastar fuente/binario exactos y obtener resolucion del proveedor. |

## Comprobaciones Python reproducibles

`scripts/verify-python-backports.py` no cambia bibliotecas ni consume datos
de usuarios. Comprueba 33 caracteres de control para siete vias de cookies,
ademas de una cookie valida. No deserializa pickle externo. Para XML utiliza
menos de 1 KB y baja temporalmente el limite de recursion a 64: se exige
RecursionError con profundidad 128, no un crash ni cualquier otra excepcion.
El limite original se restaura incluso cuando falla la prueba.

CI ejecuta la prueba sin red, como app, con filesystem de solo lectura,
256 MB, una CPU, 32 procesos y 30 segundos de limite. Un error inesperado
produce salida 2 sin exponer su contenido; falta de proteccion produce salida 1.
El chequeo exige CPython estable 3.11.16 o posterior dentro de la serie 3.11
y Expat >= 2.8.0. Otra serie requiere revision; no se aprueba por comparacion
lexicografica de versiones. No mide dinamicamente la entropia XML ni autoriza
por si mismo una excepcion para CVE-2026-7210.

Control negativo local: Python 3.11.9 / Expat 2.6.0 falla las siete vias de
cookies y el limite XML, pero conserva la cookie valida. El verificador retorna
1, correctamente. Esto no describe la version del contenedor candidato.
Las 197 unitarias, incluidas nueve del nuevo verificador, pasaron localmente.

La [corrida 34767762044](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34767762044)
probo `87aea1930eed0f4b359d2e2de8ab0323a63a447a`, imagen
`sha256:aa9c46cfd3d768eea3ffcfc4d6de9292e771f81c56797ec4136e10965575acad`.
Las 197 unitarias Linux y las regresiones nuevas pasaron. Las siete vias de
cookies rechazaron los 33 caracteres; se mantuvo la cookie valida. El guard de
recursion XML respondio correctamente. CPython 3.11.16 y Expat 2.8.3 cumplieron
los requisitos de version. Esto no agrega una prueba dinamica de entropia XML.
Tambien pasaron permisos del contenedor, arranque/PID 1, seis rechazos de acceso
sin credenciales validas y cierre con SIGTERM.

El escaneo a `2026-09-13T16:11:54.923744933Z` sigue bloqueado (salida 1):
Critical 0, High 45, Medium 49, Low 9, Negligible 44, Unknown 8. No hay alertas
de paquetes/EOL. Se recuperaron las 155 coincidencias de anotaciones publicas;
no hay diferencias de CVE/paquete/version/severidad/procedencia con la corrida
base. No se desplego esta imagen ni se aceptaron excepciones.

## Discrepancia de zlib

La fuente Debian de la version instalada
[`1:1.3.dfsg+really1.3.1-1/gzwrite.c`](https://sources.debian.org/src/zlib/1:1.3.dfsg%2Breally1.3.1-1/gzwrite.c/)
no contiene `gz_vacate`, funcion nombrada por el aviso. Es evidencia adicional
de una posible diferencia en el rango afectado, no una prueba completa de
ausencia: falta vincular la biblioteca cargada con la fuente/compilacion
exacta y descartar otra implementacion de la misma ruta vulnerable.
La [consulta al proyecto zlib](https://github.com/madler/zlib/issues/1310)
sigue abierta y Debian aun no registra una correccion para trixie.

## Criterios para cerrar la revision

1. Registrar la imagen exacta y los resultados positivos de las regresiones;
   confirmar que el escaner mantiene todos sus hallazgos.
2. Revisar las rutas nativas pendientes (glibc, ACL y zlib) y el uso privilegiado
   por operadores. No confundir que la API no invoque una herramienta con que
   la herramienta o biblioteca no exista.
3. Comprobar en el entorno aislado de hosting UID/capacidades, elevacion,
   montajes y acceso a metadatos. No extrapolar los flags de Docker en CI a Railway.
4. Una eventual disposicion necesita revisor, motivo por CVE/componente,
   evidencia vinculada a imagen, alcance, vencimiento y condiciones de
   invalidacion. Esta tarea no agrega excepciones ni acepta riesgo en nombre
   del propietario. Si cambia una version, archivo, usuario o privilegio,
   repetir la evaluacion.

No hay parche estable trixie registrado para los diez avisos Debian de esta
matriz a la fecha de consulta. No se borraron registros de paquetes, no se
cambio a repositorios inestables y no se redujo el umbral de severidad.
Produccion, pagos, base de datos, APK y Splash permanecen intactos.
