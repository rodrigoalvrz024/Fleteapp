# Decision de seguridad para el piloto Muvv

Fecha: 2026-09-14. Estado: BORRADOR PARA REVISION, NO AUTORIZA DESPLIEGUE.
Revisor independiente y aprobador del riesgo: pendientes. No es un archivo
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
| Hash XML de Python | 1 / 1 | Evidencia de backport y version compatible; conservar revision pendiente. | Acreditar la configuracion de compilacion y la ruta de 16 bytes, no solamente la version de Expat cargada. |
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

1. Un revisor evalua las 13 filas con la evidencia exacta y senala errores o informacion faltante. Una segunda revision de un agente no sustituye una auditoria profesional de produccion.
2. Las correcciones confirmadas se distinguen de riesgos mitigados. Cualquier excepcion propuesta debe identificar CVE, paquete, version, imagen, fundamento, alcance, vencimiento y condiciones de invalidacion; no basta autorizar "ignorar los altos".
3. Antes de aplicar excepciones o aceptar riesgos residuales, presentar al propietario la decision concreta. Este documento no presupone esa aprobacion.
4. Tras resolver la politica de seguridad, autorizar por separado el servicio temporal aislado y su presupuesto. Usar datos ficticios, base y bucket separados; comprobar TLS, UID/capacidades y comandos de mantenimiento en ese entorno.
5. Solo despues verificar los flujos con los telefonos y decidir la promocion. Pagos reales, documentos reales y produccion requieren sus propias condiciones de lanzamiento.

No modificar `scripts/grype-candidate.yaml` ni `scripts/report-image-audit.py`
como consecuencia automatica de este borrador. Los avisos medios y los otros
pendientes del MVP tampoco quedan aprobados por cerrar los altos.
