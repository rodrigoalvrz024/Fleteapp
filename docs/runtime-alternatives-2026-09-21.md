# Alternativas de runtime: verificacion previa

Fecha de consulta: 2026-09-21. Revision de metadatos publicos y fuentes del
mantenedor, no prueba de ejecucion ni aprobacion de despliegue.

## Punto de partida

El commit de pruebas `1efdd8a23c2e33ada9b76c910cdafc4a8558bda0` aprobo
la integracion PostgreSQL en Linux. Las imagenes completas siguen bloqueadas:
45 filas High con Python 3.11 y 44 con Python 3.14. No son 45/44 ataques
demostrados. Ver resultados y limites en [pruebas PostgreSQL](isolated-postgres-portability.md).

## Ubuntu mantenido

Ubuntu publica correcciones para los dos avisos glibc revisados:

| Aviso | Ubuntu 26.04 LTS | Ubuntu 24.04 LTS |
| --- | --- | --- |
| [CVE-2026-19499](https://ubuntu.com/security/CVE-2026-19499) | 2.43-2ubuntu2.4 | 2.39-0ubuntu8.9 |
| [CVE-2026-5435](https://ubuntu.com/security/CVE-2026-5435) | 2.43-2ubuntu2.3 | 2.39-0ubuntu8.8 |

Esto justifica investigar Ubuntu; no acredita que una imagen descargada
contenga esos paquetes ni resuelve todos los avisos. Ubuntu mantiene
[CVE-2026-85091 en zlib](https://ubuntu.com/security/CVE-2026-85091)
como vulnerable, con correccion aplazada, para ambas versiones LTS consultadas.
El aviso fue actualizado el 16 de septiembre: puede existir desfase frente a
upstream. No se interpreta ese desfase como parche instalado o falsa alarma.

Decision: no sustituir Debian ni construir un runtime propio solo para quitar
las filas glibc. Faltan paquetes mantenidos, procedencia y escaneo de la imagen
completa. No mezclar bibliotecas de distribuciones o versiones incompatibles.

## Python oficial sobre Alpine

El [inventario oficial de Docker](https://github.com/docker-library/official-images/blob/master/library/python)
publica `python:3.14.7-alpine3.24`, con soporte amd64. Se verifico tambien la
[receta fuente fijada](https://github.com/docker-library/python/blob/688a0b86bb44289df16a363e9f41d90514c1a5f9/3.14/alpine3.24/Dockerfile).
No se descargo ni ejecuto esa imagen. Su uso de musl no demuestra ausencia de
otros defectos ni equivalencia funcional con glibc.

Comprobacion de los 83 requisitos fijados en `backend/requirements.txt`:

- Metadatos JSON por paquete/version en PyPI; sin instalar ni ejecutar paquetes.
- Etiquetas de `packaging.tags` para CPython 3.14, ABI cp314 y compatibles abi3,
  musllinux_1_2_x86_64 y musllinux_1_1_x86_64, incluyendo wheels universales.
- Se excluyeron archivos retirados (yanked) e incompatibles con Requires-Python
  para 3.14.7. Se leyo el archivo como UTF-8 con BOM.
- 82 de 83 requisitos tienen al menos un wheel compatible segun esos metadatos.
- `google-crc32c==1.8.0` no tiene wheel compatible. La ultima version publicada
  consultada tambien es 1.8.0. [Archivos del mantenedor en PyPI](https://pypi.org/project/google-crc32c/1.8.0/#files).

Esto no resuelve dependencias transitivas, markers, integridad de descargas,
importaciones, comportamiento ni vulnerabilidades. El modo actual
`--only-binary=:all:` impide instalar ese requisito en este destino.
No se habilita compilacion desde fuentes ni se elimina Firebase para sortearlo.

El [registro oficial Alpine 3.24 main](https://secdb.alpinelinux.org/v3.24/main.json)
consultado no incluye CVE-2026-85091 entre las correcciones declaradas de zlib.
La ausencia en ese registro NO equivale a no afectado ni a corregido. Faltan el
inventario exacto y el escaneo completo del candidato.

## Consulta a Docker

La [discusion 596](https://github.com/orgs/docker-hardened-images/discussions/596)
respondio HTTP 200 y mostraba `Unanswered`, `0 comments` en esta consulta.
No se publico otro mensaje ni se configuro seguimiento automatico.

## Decision y siguiente paso

Ninguna de estas comprobaciones cambia el estado bloqueado. No hubo Docker
build, nuevas ejecuciones Actions, push, despliegue, contratacion ni operaciones
con datos de usuarios en esta revision.

Antes de consumir otra compilacion debe existir una diferencia verificable:
paquete mantenido corregido y disponible, respuesta del proveedor con
procedencia, o una alternativa con requisitos compatibles y sin un bloqueo
conocido equivalente. Luego fijar digest, comprobar inventario, ejecutar los
controles de privilegios/arranque y pruebas funcionales, y escanear la misma
imagen completa. Un resultado de la base vacia no aprueba Muvv.

Mientras falte esa evidencia, se pueden avanzar revisiones de exposicion por
CVE y pruebas del piloto aislado; no cuentan como parches ni permiten cambiar
el umbral. Cualquier propuesta de aceptacion de riesgo requiere alcance,
responsable, vencimiento y autorizacion especifica, separada del despliegue.

## Segunda revision y consulta preparada

La revision independiente de solo lectura coincide en posponer ambos cambios:
el arreglo glibc no resuelve zlib, y los wheels disponibles no prueban ejecucion.
No es una auditoria global ni aprobacion de una nueva imagen.

Borrador para google-crc32c, NO ENVIADO. Antes de publicar, revisar si existe
una consulta equivalente para evitar duplicados. No incluye datos del proyecto.

Subject: CPython 3.14 musllinux x86_64 wheel availability

We are evaluating CPython 3.14.7 on Alpine 3.24, linux/amd64, with binary-only
dependency installation. PyPI release metadata for google-crc32c 1.8.0, checked
on 2026-09-21, contains no wheel matching CPython 3.14 with
musllinux_1_2_x86_64 or musllinux_1_1_x86_64 (including compatible abi3 and
universal tags). Version 1.8.0 was also the latest release returned by PyPI.

Is this platform supported for published wheels, or is there an existing issue
tracking support? We have not executed a source build or changed dependencies.
Please point us to the maintained installation approach or tracking issue.

Public evidence: https://pypi.org/pypi/google-crc32c/1.8.0/json

## Seguimiento documental del mantenedor

La [documentacion vigente de google-crc32c](https://github.com/googleapis/google-cloud-python/blob/main/packages/google-crc32c/README.md)
indica compilar con herramientas C cuando no hay wheel para la plataforma.
El repositorio anterior `googleapis/python-crc32c` esta archivado y remite a
`googleapis/google-cloud-python/packages/google-crc32c`.

Por tanto, falta un wheel publicado compatible, no toda via tecnica de
instalacion. Compilar una dependencia nativa es una opcion de ingenieria,
no una vulnerabilidad por si misma; requeriria un builder aislado, fuente y
herramientas verificadas, inventario del resultado y pruebas en musl. No esta
implementada ni aprobada como sustitucion del runtime en este seguimiento.
El borrador anterior no se envia para preguntar lo que el README ya responde.
No se encontro en la busqueda web realizada una incidencia especifica de
musllinux para este paquete; eso no demuestra que no exista.
