# Inicio de sesion con Google

Muvv usa el flujo seguro de ID token: la aplicacion pide a Google una
credencial de corta duracion y el backend verifica su firma y audiencia antes
de emitir el JWT normal de Muvv. No se almacenan contrasenas de Google ni
OAuth client secrets.

## 1. Configurar Google y Firebase

1. Abre Firebase Console, proyecto `muvv-dev`, y entra a **Authentication**.
2. Pulsa **Comenzar** si aun no se ha creado Authentication.
3. En **Sign-in method**, habilita **Google**, elige el correo de soporte y
   guarda.
4. En Google Cloud Console del mismo proyecto entra a **APIs y servicios >
   Credenciales**. Crea o conserva el cliente OAuth 2.0 de tipo **Aplicacion
   web**. Copia solo su **Client ID**; no copies ni uses el Client Secret.
5. Crea o revisa el cliente OAuth de tipo **Android** con:
   - Paquete: `cl.muvv.app`
   - SHA-1 de desarrollo: ejecuta
     `keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android`
   - Para publicar en Play Store agrega tambien el SHA-1 de la llave de
     produccion y el de Play App Signing cuando exista.
6. Descarga el `google-services.json` actualizado y reemplaza el archivo local
   `mobile/android/app/google-services.json`. Ese archivo esta ignorado por Git.

## 2. Configurar Railway

En Railway > servicio `muvv-api` > **Variables**, agrega:

`GOOGLE_OAUTH_CLIENT_ID = <Client ID de Aplicacion web>`

No necesita secret. Railway desplegara el backend y el endpoint
`POST /auth/google` quedara disponible.

## 3. Compilar la app nativa

En PowerShell carga el entorno y define el Client ID para la compilacion:

```powershell
. .\scripts\new-google-account.env.ps1
$env:GOOGLE_OAUTH_CLIENT_ID = 'tu-client-id.apps.googleusercontent.com'
Set-Location .\mobile
flutter run --dart-define=API_BASE_URL=$env:API_BASE_URL --dart-define=GOOGLE_OAUTH_CLIENT_ID=$env:GOOGLE_OAUTH_CLIENT_ID
```

Para generar el APK release usa los mismos dos `--dart-define`.

## Comportamiento de cuentas

Por ahora Google permite **iniciar sesion solamente con una cuenta Muvv ya
creada que use el mismo correo y este activa**. La creacion de cuentas sigue
pidiendo telefono, perfil y consentimientos expresos de terminos y privacidad;
no se crean cuentas ni se registran aceptaciones legales automaticamente desde
Google.

## iPhone

Antes de distribuir iOS, crea tambien el cliente OAuth de tipo iOS para el
bundle `cl.muvv.app` y descarga `GoogleService-Info.plist`. El archivo se
configura desde Xcode junto con el URL scheme `REVERSED_CLIENT_ID`. Apple exige
ofrecer Sign in with Apple cuando Google sea una opcion principal de acceso.
