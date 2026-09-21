# Revision de imagen: 2026-09-21

Estado: BLOQUEADA. Revision y mejoras locales del diagnostico, sin nuevas
excepciones, despliegues, pagos ni ejecuciones de GitHub Actions.

## Evidencia consultada

Commit analizado: `94906ee0011e2c7d7c55f910c3219bcd09fbdcae`.

| Candidato | Corrida | Critical | High | Medium | Resultado |
| --- | --- | ---: | ---: | ---: | --- |
| Python 3.11 | [35645755917](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35645755917) | 0 | 45 | 55 | Bloqueado |
| Python 3.14 | [35645755944](https://github.com/rodrigoalvrz024/Fleteapp/actions/runs/35645755944) | 0 | 44 | 51 | Bloqueado |

Imagen 3.11:
`sha256:d36defd28329370052690d0bfaf8666ce448fa7f426d09ee338945aa39631e3d`.
Imagen 3.14:
`sha256:c5448a1a5ea6e0a940f9b72269f0492211e0befbdda09c7667480fb77ba30c83`.

Los contadores son coincidencias de paquetes, no ataques demostrados ni
vulnerabilidades necesariamente distintas. Las pruebas funcionales y de
arranque pasaron; eso no aprueba las vulnerabilidades de las imagenes.

## Causa exacta del rechazo de la aprobacion anterior

1. El escaneo 3.11 ya no contiene CVE-2026-3644, CVE-2026-4224 ni
   CVE-2026-7210. No corresponde descontar tres avisos del contador actual.
2. El hash de `pyexpat` cambio respecto de la evidencia aprobada. El rechazo
   por conjunto de avisos ocurria antes de llegar a esa segunda comprobacion.
3. Hay otro aviso High de Python: CVE-2026-82049. No esta cubierto por la
   aprobacion anterior. Los otros 44 registros High corresponden a los 11 CVE
   del sistema base ya pendientes.

Se agrego un diagnostico informativo que informa simultaneamente la ausencia
o duplicacion de avisos revisados y los modulos cambiados o faltantes. Solo
publica identificadores fijos y contadores; no copia contenido arbitrario de
la evidencia. No altera `evaluate`, hashes aprobados, fecha de vencimiento,
codigos de salida ni criterios de aceptacion. El control sigue cerrado ante
evidencia distinta, incompleta o expirada.

## Nuevo aviso de Python

[CVE-2026-82049](https://security-tracker.debian.org/tracker/CVE-2026-82049)
afecta la extraccion tar con enlaces preparados para salir del directorio de
destino. El [informe de CPython](https://github.com/python/cpython/issues/157190)
explica el cambio de comportamiento de enlaces que evita el problema en 3.14+.
El candidato 3.14 no presenta este aviso, pero sigue bloqueado por los del SO.

No se encontraron llamadas a `tarfile`, `extractall` o `unpack_archive` en
`backend/app`. El inventario de ELF usa `extractfile` solo para archivos
regulares y no extrae el tar al disco. Esta busqueda no cubre todos los flujos
dinamicos de dependencias y NO constituye una excepcion ni prueba de ausencia
de exposicion. El Python 3.11 de Debian 3.11.2, marcado no afectado por carecer
de filtros, no es el mismo interprete 3.11.16 de esta imagen.

## Disponibilidad consultada hoy

- [glibc / CVE-2026-19499](https://security-tracker.debian.org/tracker/CVE-2026-19499):
  trixie 2.41-12+deb13u4 sigue marcado vulnerable; hay correccion en forky/sid.
- [util-linux / CVE-2026-76642](https://security-tracker.debian.org/tracker/CVE-2026-76642):
  trixie 2.41.5-0+deb13u1 sigue vulnerable; forky/sid tienen version corregida.
- [ACL / CVE-2026-54369](https://security-tracker.debian.org/tracker/CVE-2026-54369):
  trixie sigue vulnerable y Debian desaconseja trasladar parches individuales
  por el cambio de ABI. No mezclar paquetes de sid con la base estable.
- [zlib / CVE-2026-85091](https://security-tracker.debian.org/tracker/CVE-2026-85091):
  Debian sigue marcando vulnerable. La [consulta upstream](https://github.com/madler/zlib/issues/1310)
  ahora figura cerrada y Debian enlaza un commit correctivo; esto NO demuestra
  que el paquete instalado contenga ese cambio ni justifica suprimir el aviso.

## Verificacion de los cambios locales

- Python 3.11: 14 pruebas de politica, 10 de revision y 26 del informe: 50 OK.
- Python 3.14.7: las mismas 14 pruebas de politica: 14 OK.
- Regresiones nuevas: un CVE nuevo nunca queda reconocido por la aprobacion
  antigua; ausencia y hash distinto se informan juntos; diagnostico acotado
  sin divulgar valores arbitrarios, incluso con evidencia mal formada.
- Se ejecuto el diagnostico sobre las 152 filas publicadas de la corrida 3.11,
  verificando cantidad de filas e identidad de imagen/commit. Resultado:
  tres avisos revisados ausentes y `pyexpat` cambiado; ningun aviso omitido.
- `git diff --check` sin errores. No se repitio la suite completa del backend
  ni la integracion PostgreSQL: no se modifico codigo de la aplicacion.

## Siguiente decision

Continuar con una base mantenida cuyos paquetes resuelvan los avisos, o una
revision independiente por CVE que determine aplicabilidad, controles,
riesgo residual y vigencia antes de solicitar excepciones especificas.
Actualizar solo Python a 3.14 no basta para desbloquear. No repetir builds
identicos ni cambiar umbrales para obtener un resultado verde. La aprobacion
del despliegue sigue pendiente y separada de cualquier commit/push de pruebas.
