# Muvv - Respaldo privado y recuperacion

Verificacion local: 2026-09-08. Copia externa verificada: 2026-09-09.
Operacion autorizada expresamente por Rodrigo.

## Resultado

- Respaldo: `20260908T025031Z-bcdc953a`.
- Archivo: `C:\Users\casa\MuvvBackups\20260908T025031Z-bcdc953a\backup.fernet`.
- Informe depurado en la misma carpeta: `report.json`.
- Clave: archivo `20260908T025031Z-bcdc953a.backup.dpapi` dentro de
  `%LOCALAPPDATA%\MuvvBackupKeys`, separado del paquete.
- Copia alternativa de esa misma clave protegida, preparada y comprobada
  el 2026-09-08: `C:\Users\casa\MuvvRecoveryKeys\20260908T025031Z-bcdc953a.backup.dpapi`.
  Solo el propietario Windows y SYSTEM tienen acceso. La original se conserva.
- Paquete autenticado y cifrado con Fernet; clave aleatoria protegida con
  Windows DPAPI CurrentUser. No se guardaron claves ni datos privados en Git.
- 7.775.736 bytes cifrados; SHA-256:
  `a251d6f49eaf793328dad69f834d958eec7611c1361cc0d963be4f5ed0e6d6a3`.
- Volcado logico completo PostgreSQL mediante pg_dump 18, usando session pooler,
  transaccion REPEATABLE READ/READ ONLY e instantanea exportada compartida.
- Incluye inventario y contenido de los 13 archivos de `muvv-private`:
  5.337.010 bytes. Segunda lectura e inventario final comprobaron estabilidad.
- No se ejecuto POST/DELETE en Storage, migracion, deploy, cobro ni notificacion.

## Ensayo realizado

Se descifro el paquete, se autentico antes de procesarlo y se restauro el esquema
public en PostgreSQL 18.3 temporal con SCRAM, solo en 127.0.0.1. No se inicio la
aplicacion. Los roles auxiliares locales son NOLOGIN, NOSUPERUSER y NOBYPASSRLS.

Las 21 tablas (20 modelos y Alembic) coinciden en cantidad de filas, huella de
datos, propietario y estado RLS. Se preservaron las ACL del volcado. Revision
recuperada: `e1f0a2b3c4d5`. Los 13 archivos se escribieron solo en una carpeta
temporal privada y se verifico su SHA-256 tras la escritura.

En el primer intento falto el esquema public vacio del destino. En el segundo
la serializacion numerica difirio: el origen usa extra_float_digits=0 y el
destino 1. Se repitio con el formato del origen y las huellas coincidieron.
El archivo cifrado original no se modifico. El formato 2 del ejecutor fija 3
explicitamente en origen y destino para futuras comparaciones.

La instancia temporal quedo apagada y su directorio eliminado. Los diagnosticos
anteriores permanecen cifrados; no contienen informacion en el informe publico.
Eliminar archivos temporales no equivale a borrado forense seguro de un SSD.

## Repetir localmente

Requiere este usuario/perfil Windows, Python del backend y PostgreSQL 18 en la
ruta configurada en el script. No necesita credenciales de produccion para
verificar un respaldo ya creado:

```powershell
Set-Location C:\Users\casa\Documents\Fleteapp
& .\backend\venv\Scripts\python.exe -B .\scripts\backup-muvv-private.py verify --run 20260908T025031Z-bcdc953a
```

El comando no acepta un destino remoto de restauracion. Inicia una base nueva,
comprueba el contenido y elimina exclusivamente su directorio temporal.
Un fallo no debe considerarse recuperacion aprobada; revisar el diagnostico
cifrado sin publicar filas, fotos, documentos ni credenciales.

## Preparar la copia portable

Implementado el 2026-09-08. Se probo con el respaldo real: envoltura de clave
mediante Argon2id + Fernet, descifrado y restauracion de las 21 tablas y 13 archivos.
La restauracion no pudo recurrir a DPAPI: se bloqueo esa funcion durante la
prueba. Contrasena de ensayo aleatoria solo en memoria; no se genero con ella
un paquete permanente. Temporales eliminados e instancia detenida.

Google Drive: carpeta `Muvv - Respaldos` creada en Mi unidad de Rodrigo el
2026-09-08. [Carpeta privada](https://drive.google.com/drive/folders/1KuMziMMfjlZO8DHE2ur_lzuwewYuRlT_).
Permisos comprobados en el dialogo Compartir: una persona (propietario),
acceso general Restringido. No se agregaron invitados ni se genero un enlace
publico. Los mismos permisos se comprobaron tambien sobre el ZIP subido,
no solamente sobre su carpeta. MFA y recuperacion de cuenta no
verificados en esta operacion.

**Exportacion definitiva completada:** Rodrigo ejecuto el comando con su
contrasena en la consola. El informe registra creacion a las
`2026-09-09T00:27:32.999511+00:00` (8 de septiembre, 21:27 en Santiago),
descifrado portable verificado y 21 tablas/13 archivos. El asistente no recibio
la contrasena. Paquete de 7.785.867 bytes, SHA-256:
`0c04e6fe23b2cfbbd5bab7b533dd51efd3d4a13c18cd03ceeba3dba3d3f9c378`.
Se comprobo el hash del ZIP, sus cinco miembros permitidos y que el respaldo
cifrado interior coincide con el original. No se expuso la clave cifrada.

**Copia externa verificada:** el ZIP esta presente en la carpeta privada de
Google Drive. Rodrigo lo descargo a
`C:\Users\casa\Downloads\muvv-recovery-20260908T025031Z-bcdc953a.zip`.
Se comprobo igualdad byte por byte y SHA-256 con el paquete original, los cinco
miembros permitidos y la huella del respaldo cifrado interior. No se extrajeron
datos privados ni se pidio la contrasena. La descarga automatizada fue bloqueada
por Chrome; se uso la descarga manual del usuario sin cambiar protecciones.
`portable-report.json` registra la evidencia y `offsite_copy_verified=true`;
el ZIP y su informe historico interior no se modificaron.

**Pendiente:** ensayar recuperacion desde otro computador y comprobar que Rodrigo
pueda recuperar la contrasena sin depender de este PC. El descifrado portable
se verifico al exportar, pero la comprobacion posterior de la descarga fue de
integridad, no un nuevo ensayo de descifrado. No volver a exportar ni cambiar
claves solo por este paso pendiente. Los pasos siguientes son el procedimiento
de repeticion, no instrucciones para reemplazar el paquete ya verificado.

1. Generar en un gestor una contrasena unica de 24 caracteres aleatorios o una
   frase de seis palabras elegidas aleatoriamente. Guardarla separada del
   respaldo, con acceso recuperable si se pierde este PC. No usar la contrasena
   de Google, de la app ni las credenciales de prueba. La longitud minima
   aceptada es 20 caracteres; eso solo no garantiza suficiente entropia.
2. Desde una consola interactiva, ejecutar:

```powershell
Set-Location C:\Users\casa\Documents\Fleteapp
& .\backend\venv\Scripts\python.exe -B .\scripts\backup-muvv-private.py export-portable --run 20260908T025031Z-bcdc953a --key-file C:\Users\casa\MuvvRecoveryKeys\20260908T025031Z-bcdc953a.backup.dpapi
```

3. Introducirla dos veces en el prompt oculto. Nunca pasarla como argumento,
   variable de entorno, archivo de texto, chat o Notion. El comando se niega a
   leerla por una tuberia o si getpass no puede ocultar la entrada.
4. Se crea, sin sobrescribir el respaldo ni la clave DPAPI:
   `C:\Users\casa\MuvvBackups\20260908T025031Z-bcdc953a\muvv-recovery-20260908T025031Z-bcdc953a.zip`.
   El ZIP es un contenedor normal: sus datos privados y su clave ya estan
   cifrados por separado. Incluye `backup.fernet`, `recovery-key.json`,
   `report.json`, `muvv_backup_portable.py` y `RECUPERAR.txt`.
5. Subir solo ese paquete a una carpeta privada, por ejemplo
   `Muvv - Respaldos`, de la cuenta elegida. Sin enlaces publicos ni personas
   adicionales, con MFA y metodos de recuperacion de cuenta comprobados.
   No subir el directorio de claves DPAPI ni guardar la contrasena en esa carpeta.
6. Esperar a que termine la subida. Descargar nuevamente el ZIP desde la nube
   a otra carpeta privada fuera del repositorio. Comparar primero el SHA-256
   del ZIP descargado con `package_sha256` de `portable-report.json` y extraer
   solamente despues de confirmar la coincidencia.
   Una carpeta sincronizada local no acredita por si sola una copia remota.
7. Ejecutar el verificador sobre los archivos descargados. En este PC se puede
   usar el Python del backend; en otro equipo, Python 3.11+ y `cryptography==46.0.6`:

```powershell
python -m pip install cryptography==46.0.6
python muvv_backup_portable.py
```

Estos dos comandos se ejecutan dentro de la carpeta extraida en el otro equipo.
El verificador es independiente de Windows, DPAPI, PostgreSQL y las credenciales
productivas. Pide la contrasena, autentica el paquete y comprueba el volcado y
los archivos en memoria; no escribe los datos descifrados ni ejecuta SQL.
Un resultado correcto prueba descifrado e integridad, no la restauracion completa
de los servicios administrados de Supabase. No imprimir ni extraer el manifiesto
privado para documentar el resultado.

Para repetir la restauracion SQL local en un Windows nuevo, con el proyecto y
sus dependencias confiables y PostgreSQL 18 instalado, colocar `backup.fernet`,
`report.json` y `recovery-key.json` en `%USERPROFILE%\MuvvBackups\20260908T025031Z-bcdc953a`.
Desde la raiz del proyecto ejecutar:

```powershell
& .\backend\venv\Scripts\python.exe -B .\scripts\backup-muvv-private.py verify --run 20260908T025031Z-bcdc953a --portable-key "$env:USERPROFILE\MuvvBackups\20260908T025031Z-bcdc953a\recovery-key.json"
```

No restaura sobre una base remota: crea su instancia temporal local habitual.
El archivo de clave usa sal aleatoria de 16 bytes, Argon2id (64 MiB, tres pasadas,
cuatro lanes, 32 bytes derivados) y Fernet autenticado. El formato fija los
parametros de coste y vincula dentro del contenido autenticado la clave al ID
y SHA-256 del respaldo. Cambiar la contrasena de la cuenta de Google no cambia
esta contrasena. Perderla junto al perfil DPAPI puede impedir la recuperacion.
Cambiar o retirar una contrasena exige revisar tambien las copias antiguas.

## Incidencia de ruta de clave

Rodrigo recibio FileNotFoundError al exportar y su consola informo que no
encontraba la clave en LOCALAPPDATA. La comprobacion local con permiso de acceso
si encontro el archivo DPAPI original de 300 bytes; autentico y descifro el
respaldo existente en memoria. Su ACL contiene solamente propietario y SYSTEM.
No se confirmo la causa de la diferencia entre los dos contextos de ejecucion;
no se debe interpretar Test-Path false como prueba concluyente de perdida.

Se preparo una copia identica del archivo DPAPI en `C:\Users\casa\MuvvRecoveryKeys`,
con los mismos destinatarios de permisos, fuera de AppData, del repositorio y
del directorio de respaldos. No se genero otra clave, no se escribio la clave
descifrada ni se amplio el acceso a Everyone/Users. Esta copia sigue dependiendo
del mismo perfil Windows; no reemplaza la exportacion portable por contrasena.

El ejecutor acepta `--key-file` para check, verify y export-portable, y distingue
ausencia, denegacion de acceso y un fallo de apertura DPAPI sin imprimir claves.
El siguiente diagnostico es de solo lectura, sin red, escritura de datos privados
ni instancia PostgreSQL. Fue aprobado usando la copia alternativa:

```powershell
& .\backend\venv\Scripts\python.exe -B .\scripts\backup-muvv-private.py check --run 20260908T025031Z-bcdc953a --key-file C:\Users\casa\MuvvRecoveryKeys\20260908T025031Z-bcdc953a.backup.dpapi
```

Resultado esperado: `Respaldo y clave original comprobados`, 21 tablas y 13
archivos. Si falla desde otra consola, conservar el mensaje depurado con la ruta;
no listar el contenido de la clave, no copiarla a Git ni ejecutar init para
reemplazarla. El respaldo necesita su clave original.

## Limites y siguientes pasos

- Esta es una copia manual, no un respaldo automatico ni una politica de retencion.
- Segunda copia cifrada en Google Drive privado y descarga verificada. Es una
  instantanea del 2026-09-08 UTC, no incluye cambios posteriores en produccion.
  Falta ensayar la recuperacion en otro equipo y el acceso independiente a la
  contrasena. Copiar solo DPAPI no basta: depende del perfil Windows original.
- El volcado contiene los esquemas gestionados de Supabase, pero el ensayo solo
  restauro public. No recrea Auth, Realtime, Vault ni Storage como servicios.
- No se respaldaron secretos de Railway, contrasenas de roles globales ni la
  clave raiz de cifrado de Vault. No es una clonacion integra de la plataforma.
- Los archivos estan recuperados en bytes y con inventario cifrado, pero falta
  ensayar su importacion en otro Storage privado y las URLs/permisos de la app.
- La migracion RLS candidata sigue sin aplicarse a produccion. Tampoco se probo
  HTTP cliente/conductor/admin contra la base restaurada.
  Si se aprobo una suite separada de 24 pruebas HTTP/WebSocket en una base
  creada desde los modelos con datos sinteticos; ver `docs/http-permissions-regression.md`.
- Rodrigo solicita el 2026-09-09 dejar el ensayo desde otro computador para
  el cierre final. Sigue pendiente; no impide avanzar las verificaciones locales.
- No abrir al publico ni habilitar cobros reales por aprobar solo este ensayo.

Referencias:
[Respaldos Supabase](https://supabase.com/docs/guides/platform/backups),
[Migracion y recuperacion](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore),
[Fernet y contrasenas](https://cryptography.io/en/46.0.6/fernet/#using-passwords-with-fernet),
[Argon2id](https://cryptography.io/en/46.0.6/hazmat/primitives/key-derivation-functions/#argon2id).
