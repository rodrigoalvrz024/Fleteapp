# Python 3.14: evaluacion local de compatibilidad

Fecha: 2026-09-21. Estado: compatibilidad local comprobada, NO aprobacion de
imagen ni de despliegue. No se cambiaron Dockerfiles, workflows ni produccion.
El propietario autorizo commit y push de este lote a la rama de pruebas.
La autorizacion no incluye desplegar ni cambiar el runtime de produccion.
Commit/push completados: `7d9a4a4`. Linux #35 aprobo las pruebas y los controles
de arranque, pero termino bloqueado por el analisis de imagen. Esa imagen sigue
usando Python 3.11.16; no constituye una validacion Linux de Python 3.14.

## Problemas encontrados y correcciones

- SQLAlchemy 2.0.30 impedia importar la aplicacion con Python 3.14.7:
  `TypeError: Can't replace canonical symbol for '__firstlineno__'`.
  Se actualizo el pin a 2.0.54, dentro de la serie 2.0. El error desaparecio.
  Ver [changelog oficial](https://docs.sqlalchemy.org/en/20/changelog/changelog_20.html).
- Dos tests del verificador de backports daban falsos negativos: Python 3.14
  emite cookies JavaScript usando `decodeURIComponent` en lugar de asignacion
  literal. El control positivo ahora exige el script completo en uno de los
  dos formatos y el header exacto, incluidos HttpOnly y Path. No ejecuta JS.
  Se agregaron dos tests para formatos validos, atributos/valores alterados,
  salida vacia, wrapper incompleto y contenido extra.
- Las guardas ABI, versiones admitidas, hashes y excepciones NO se ampliaron.
  Se agrego un caso explicito que sigue rechazando Python 3.14 en la politica
  de backports 3.11. Este trabajo no reutiliza aquella autorizacion.

## Evidencia local

| Comprobacion | Python 3.11 | Python 3.14.7 |
| --- | --- | --- |
| Suite unitaria final | 373 aprobadas, 2 omitidas | 373 aprobadas, 2 omitidas |
| RLS en PostgreSQL temporal | 9 aprobadas | 9 aprobadas |
| TLS de base de datos | 5 aprobadas | 5 aprobadas |
| Migraciones Alembic | 11 aprobadas | 11 aprobadas |
| API HTTP y WebSocket | 58 aprobadas | 58 aprobadas |

Los dos tests omitidos requieren Linux: permisos del certificado en /app y
herencia real de descriptores. No se cuentan como aprobados. Las pruebas de
integracion usaron PostgreSQL 18.3 local desechable; ambos clusters quedaron
detenidos y eliminados. Sin datos de usuarios ni base externa.

Se probaron permisos por rol/propiedad, revocacion de sesiones, chat, fotos
privadas, precios y callbacks de pago con proveedores simulados. Esto NO
equivale a un pago real, entrega push real o prueba en telefonos.

pip-audit: 83 dependencias fijadas, 0 vulnerabilidades conocidas, 0 omitidas.
Reporte local: `.local-tools/anyio-audit/sqlalchemy254-audit.json`.
No cubre el sistema operativo, el interprete ni vulnerabilidades desconocidas.

Python 3.14.7 se instalo con uv en `.local-tools/python314-runtime`, sin
modificar PATH ni registro. Se uso `.local-tools/python314-test` como venv.
Es un runtime Windows de prueba, NO el artefacto Linux de produccion.
La resolucion previa de wheels Linux tampoco prueba ejecucion en Linux.

Una segunda revision estatica no encontro P1/P2 en los cambios de SQLAlchemy
y del verificador. No ejecuto independientemente estas suites.

## Repetir las comprobaciones

Desde backend, con APP_ENV=test, DATABASE_URL sintetica no productiva,
SECRET_KEY de prueba y RUN_STARTUP_MIGRATIONS=false:

```powershell
& '..\.local-tools\dependency-audit\venv\Scripts\python.exe' -B -m unittest discover -s tests -q
& '..\.local-tools\python314-test\Scripts\python.exe' -B -m unittest discover -s tests -q
```

Desde la raiz, repetir para cada interprete:

```powershell
& '.local-tools\python314-test\Scripts\python.exe' -B scripts/test-supabase-rls-isolated.py --pg-bin 'C:\Program Files\PostgreSQL\18\bin' --tls --http --migrations
```

## Pendientes antes de migrar

1. Construir un candidato Linux aislado con base mantenida e identidad fija.
2. Ejecutar las protecciones reales de arranque y los tests especificos Linux.
3. Escanear la imagen completa, sin trasladar excepciones de Python 3.11.
4. Resolver o evaluar formalmente cada aviso bloqueante; no descontar avisos
   por estas pruebas locales ni mezclar paquetes de distribuciones inestables.
5. Conservar el bloqueo observado en CI #35 hasta validar un candidato seguro.
   No desplegar.

El ultimo escaneo de la imagen sigue siendo el documentado en
[estado de seguridad](image-security-current-status.md): 0 Critical y 45 High.
No hubo una nueva corrida de GitHub Actions durante esta evaluacion local;
posteriormente el push autorizado ejecuto #35, no una prueba 3.14 Linux.
