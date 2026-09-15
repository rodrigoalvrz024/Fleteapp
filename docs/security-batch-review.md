# Revision conjunta para desbloquear el piloto

Seguimiento 2026-09-15: el propietario autorizo reconocer exclusivamente las tres
correcciones Python verificadas. Implementacion, vigencia y condiciones en
[reconocimiento acotado](approved-python-corrections.md). Las referencias a
autorizacion pendiente mas abajo describen la ronda historica, no el estado actual.

Actualizacion 2026-09-15: [seguridad de sesiones y chat](session-security-review.md)
agrega correcciones locales de acceso. No modifica las disposiciones del escaner
de esta revision ni autoriza despliegue. Las corridas citadas abajo son anteriores
a esos cambios y no certifican la nueva candidata.

Fecha: 2026-09-14. Estado: revision tecnica; no autoriza excepciones ni deploy.

## Resultado para el propietario

Revisamos juntos los 13 avisos distintos que generan 45 coincidencias altas.
Tres arreglos ya estan incluidos en Python y sus pruebas los confirman. No
son parches nuevos de esta ronda: falta autorizar que el control reconozca
esas tres correcciones concretas. Las 45 alertas originales siguen visibles.
Una aprobacion limitada a esos tres dejaria 42 coincidencias, de diez CVE,
pendientes. No aprobaria el lanzamiento ni las alertas medias.

No hay una actualizacion estable de Debian que hoy cierre automaticamente
los diez restantes. No se cambia de proveedor ni se contratan servicios.

## Tres correcciones comprobadas

Imagen revisada: `sha256:69b8bb68d6bbc03b0d42f500dfe724dcd8d67ef16020e5853a59826ab146f4fa`.
Commit probado: `e8b42d5e508eea7bfc5b11050e406d8801f17dbb`.
[Corrida Linux](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34867936706).

| Aviso | Resultado tecnico | Explicacion simple |
| --- | --- | --- |
| CVE-2026-3644 | Arreglo de cookies en CPython 3.11.16; siete vias rechazan 33 controles y conservan una cookie valida. | Se comprueba que datos malformados no se acepten en esas operaciones de cookies. |
| CVE-2026-4224 | El parser rechaza XML profundamente anidado con RecursionError, sin caerse. | Esa prueba no logra tumbar el procesador de XML por exceso de profundidad. |
| CVE-2026-7210 | Cabeceras Expat 2.8.3 y llamadas reales a SetHashSalt16Bytes en pyexpat y ElementTree; cero llamadas a la funcion antigua. | Los dos procesadores usan la proteccion reforzada, no solo una version que dice tenerla. |

Fuente primaria: [publicacion oficial Python 3.11.16](https://www.python.org/downloads/release/python-31116/).
Limites: pruebas acotadas, no todas las entradas posibles; el tercer control
no mide calidad estadistica de entropia. No se exime Python completo.

`scripts/review-python-findings.py` coteja la evidencia publica de una misma
corrida: commit, imagen del escaner y traza, totalidad de las 155 coincidencias,
paquete/version/procedencia exactos y resultados de las pruebas. Requiere los
hashes revisados de ambos modulos; cambios de version o binario exigen revision.
No usa datos personales, lee argumentos de entropia ni modifica el informe
original. Su salida es una propuesta, no interviene en el gate de CI.
No equivale a una atestacion independiente o criptograficamente firmada.

## Decision conjunta de los diez restantes

| Grupo | CVE | Coincidencias | Estado real y accion pendiente |
| --- | --- | ---: | --- |
| infocmp | CVE-2025-69720 | 4 | Ejecutable retirado y ausencia comprobada; bibliotecas retenidas. Propuesta de no aplicabilidad limitada al componente, no parche del paquete entero. |
| Archive::Tar | CVE-2026-9538 | 1 | Modulo no localizado en rutas conocidas ni en include paths de Perl. No declarar ausencia de copias renombradas; revision de alcance pendiente. |
| Montajes/nsenter | CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410 | 32 | Herramientas retiradas, sin SUID/capacidades/root y cierre de descriptores >=3 probado. libmount permanece; el host y stdio siguen siendo condiciones de confianza. Mitigados, no parcheados. |
| Herramientas ACL | CVE-2026-54370 | 1 | No se encontraron getfacl/setfacl/chacl. libacl y otros callers siguen presentes; falta revision operativa de acciones privilegiadas. |
| Biblioteca ACL | CVE-2026-54369 | 1 | No corregido en estable. Nuevo ABI en 2.4.0; no parche individual ciego ni instalacion de sid. |
| Impresion DNS glibc | CVE-2026-5435 | 2 | Funciones obsoletas permanecen; cero imports estaticos no demuestra inalcanzabilidad dinamica. No corregido en estable. |
| zlib | CVE-2026-85091 | 1 | Discrepancia entre rango descrito y version marcada por Debian; consulta al proveedor abierta. No cerrar como falso positivo sin resolver procedencia/alcance. |

Fuentes reconsultadas en esta ronda:
[glibc](https://security-tracker.debian.org/tracker/CVE-2026-5435),
[ACL ABI](https://security-tracker.debian.org/tracker/CVE-2026-54369),
[montajes](https://security-tracker.debian.org/tracker/CVE-2026-76642),
[subdirectorios](https://security-tracker.debian.org/tracker/CVE-2026-78409),
[bind mounts](https://security-tracker.debian.org/tracker/CVE-2026-78410),
[zlib Debian](https://security-tracker.debian.org/tracker/CVE-2026-85091),
[consulta zlib abierta](https://github.com/madler/zlib/issues/1310).

## Siguiente decision concreta

1. El propietario autoriza o rechaza reconocer exclusivamente los tres arreglos
   Python, no una excepcion general ni los diez restantes. La pregunta se hizo
   en esta tarea; al escribir este documento la respuesta esta pendiente.
2. Si autoriza, integrar las condiciones de evidencia al control manteniendo
   dos contadores: hallazgos originales y pendientes. Falta de evidencia debe
   bloquear, nunca convertir un informe incompleto en limpio.
3. Para los diez restantes: elegir entre una disposicion tecnica especifica
   con alcance y aprobacion del riesgo, esperar parches estables o evaluar una
   imagen mantenida alternativa en una rama de prueba. No cambiar el sistema
   operativo ni sustituir bibliotecas criticas silenciosamente.
4. No desplegar en produccion hasta resolver el gate y probar el entorno aislado.

Pruebas locales de esta ronda: 114 seleccionadas, 113 aprobadas y una omitida
por requerir Linux. Diez pruebas nuevas del revisor cubren evidencia parcial,
proveniencia equivocada, distinta imagen/version/hash, regresiones de cookies,
XML, condiciones de compilacion, errores seguros y preservacion del gate.
El revisor tambien proceso la evidencia real de la corrida indicada y confirmo
exactamente tres candidatos; no se cambio el escaner ni su codigo de salida.

## Resultado de esta ronda Linux

Commit: `4e6f7486e606a74b43e0deb2aff4da15c50b5dcc`.
[Corrida 34869663192](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/34869663192).
Imagen: `sha256:3d4cfacb14d6b950af8285020175861203b9e08574b8b774f3012c082caaff58`.
Pasaron suite Linux, dependencias, descriptores heredados, backports, permisos,
arranque, rechazo root, apagado, inventario y traza XML. Falla solo el escaner:
0 Critical, 45 High, 49 Medium, 9 Low, 44 Negligible y 8 Unknown.

Se recuperaron las once anotaciones publicas relevantes de esa misma corrida
y el revisor las proceso con resultado valido: tres candidatos exactos y 42
coincidencias altas adicionales. El conjunto conserva los 155 hallazgos y
no concede aprobacion. No hubo cambios al codigo de la API, Dockerfile,
configuracion de Grype ni politica de despliegue en esta ronda.
