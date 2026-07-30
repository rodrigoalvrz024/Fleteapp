# Copia este archivo a scripts\new-google-account.env.ps1 y edita los valores.
# Luego cargalo en PowerShell con:
# . .\scripts\new-google-account.env.ps1
#
# No pongas claves secretas reales en este archivo si lo vas a commitear.

$env:PROJECT_ID = 'muvv-dev-CHANGE_ME'
$env:REGION = 'us-central1'
$env:SERVICE = 'muvv-api'

# Firebase Hosting
# El sitio app suele ser el sitio default del proyecto. El sitio publico se crea aparte.
$env:FIREBASE_APP_SITE_ID = $env:PROJECT_ID
$env:FIREBASE_PUBLIC_SITE_ID = "$($env:PROJECT_ID)-public"

# URLs publicas esperadas para builds estaticos.
$env:NEXT_PUBLIC_SITE_URL = "https://$($env:FIREBASE_PUBLIC_SITE_ID).web.app"
$env:NEXT_PUBLIC_APP_URL = "https://$($env:FIREBASE_APP_SITE_ID).web.app"
$env:PUBLIC_HOME_URL = $env:NEXT_PUBLIC_SITE_URL

# Backend recomendado en etapa sin ingresos: Render Free o local.
$env:NEXT_PUBLIC_API_URL = 'https://YOUR_RENDER_BACKEND.onrender.com'
$env:API_BASE_URL = $env:NEXT_PUBLIC_API_URL

# Firebase Web app config.
# Se obtiene desde Firebase Console > Configuracion del proyecto > Apps web.
$env:FIREBASE_WEB_API_KEY = ''
$env:FIREBASE_WEB_APP_ID = ''
$env:FIREBASE_MESSAGING_SENDER_ID = ''
$env:FIREBASE_PROJECT_ID = $env:PROJECT_ID
$env:FIREBASE_AUTH_DOMAIN = "$($env:PROJECT_ID).firebaseapp.com"
$env:FIREBASE_STORAGE_BUCKET = "$($env:PROJECT_ID).firebasestorage.app"

# Google Maps.
# Para gasto minimo, deja vacio y prueba flujos sin mapa hasta tener cuotas definidas.
$env:GOOGLE_MAPS_API_KEY = ''
$env:GOOGLE_MAPS_WEB_KEY_ID = ''

# Firebase mobile apps.
$env:ANDROID_PACKAGE_NAME = 'cl.muvv.app'
$env:IOS_BUNDLE_ID = 'cl.muvv.app'
$env:ANDROID_DISPLAY_NAME = 'Muvv Android'
$env:IOS_DISPLAY_NAME = 'Muvv iOS'

Write-Host "Entorno Muvv cargado para PROJECT_ID=$env:PROJECT_ID"
Write-Host "Public site: $env:NEXT_PUBLIC_SITE_URL"
Write-Host "App site: $env:NEXT_PUBLIC_APP_URL"
Write-Host "API: $env:API_BASE_URL"
