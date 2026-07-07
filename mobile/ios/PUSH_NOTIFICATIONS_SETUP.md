# FleteApp iOS Push Notifications

Las notificaciones iOS requieren configuracion externa en Apple Developer,
Firebase y Xcode. No guardar llaves privadas en el repositorio.

## 1. Firebase iOS

1. En Firebase Console, abre el proyecto `fleteapp-8d8f7`.
2. Agrega una app iOS con bundle id `com.fleteapp.fleteapp`.
3. Descarga `GoogleService-Info.plist`.
4. Copia el archivo en `mobile/ios/Runner/GoogleService-Info.plist`.
5. No lo subas a Git. Ya esta ignorado por `.gitignore`.

Estado local: `GoogleService-Info.plist` ya fue copiado en `Runner`.

## 2. Apple Developer

1. En Apple Developer, habilita Push Notifications para el App ID.
2. Crea o reutiliza una APNs Auth Key.
3. En Firebase Console > Project settings > Cloud Messaging, sube la APNs key.
4. Verifica Team ID, Key ID y bundle id.

## 3. Xcode

1. Abre `mobile/ios/Runner.xcworkspace` en macOS.
2. En `Runner` > Signing & Capabilities, agrega:
   - Push Notifications
   - Background Modes > Remote notifications
3. Verifica que `GoogleService-Info.plist` este incluido en el target Runner.
4. Verifica que el bundle id sea exactamente `com.fleteapp.fleteapp`.
5. Si Xcode no muestra el archivo plist en el target, arrastralo a `Runner`
   marcando `Copy items if needed` y seleccionando el target `Runner`.

## 4. Prueba

1. Ejecuta la app en un iPhone real. El simulador no es suficiente para validar
   push end-to-end.
2. Inicia sesion como conductor.
3. Acepta permisos de notificacion.
4. Crea un flete desde una cuenta cliente.
5. El conductor disponible deberia recibir una push y abrir el detalle del flete
   al tocarla.
