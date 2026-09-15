# Continuar Muvv en Mac

Estado: 2026-09-14. Traspaso de desarrollo, NO aprobacion de produccion.

## Punto de partida

- Repositorio: https://github.com/rodrigoalvrz024/Fleteapp
- Rama: `codex/mvp-supabase-rls-review` (no cambiar a main por defecto).
- Flutter utilizado en Windows: 3.41.6; Dart: 3.11.4. Usar inicialmente
  la misma version para separar problemas del traslado de actualizaciones.
- Codigo mobile: 1.0.12+13. Ultima APK instalada y verificada en el Huawei:
  1.0.11+12. El logo ampliado y centrado posterior aun requiere nueva APK.
- La app conserva login Cliente/Conductor, navegacion de pagos y perfil,
  seleccion de objetos y recomendacion de vehiculo con precio del servidor.
- No modificar el splash aprobado ni sus recursos nativos.
- 33 pruebas Flutter enfocadas pasan. No equivalen a validar iOS fisico.

## No perder trabajo

El commit de continuidad incluye el codigo mobile y sus pruebas, no todo el
contenido de este PC. Web publica, marketing, algunos documentos y firebase.json
tienen cambios locales independientes pendientes de revision y guardado.
No borrar el PC ni asumir que clonar GitHub conserva esos cambios.
Tampoco se incluyen `output/`, `tmp/`, capturas, compilaciones o herramientas.

El ZIP cifrado ya guardado en Google Drive contiene un respaldo historico de
PostgreSQL y Storage, no una copia actualizada del codigo fuente. Consultar
`docs/private-backup-recovery.md`. No restaurarlo sobre produccion para desarrollar.
No copiar entornos virtuales Windows, node_modules, caches Flutter ni archivos
local.properties al Mac. Reinstalar las dependencias desde sus manifiestos.

## Preparar el Mac

Confirmar primero modelo/procesador y version de macOS. Instalar una version
compatible de Xcode, sus herramientas de linea de comandos, Flutter y las
dependencias nativas que indique `flutter doctor -v`.

Guias oficiales:
- https://docs.flutter.dev/install/manual
- https://docs.flutter.dev/platform-integration/ios/setup
- https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository

Tras autenticar Git con la cuenta que tiene acceso al repositorio:

```sh
mkdir -p ~/Developer
cd ~/Developer
git clone --branch codex/mvp-supabase-rls-review https://github.com/rodrigoalvrz024/Fleteapp.git
cd Fleteapp
git status --short
git log -1 --oneline
cd mobile
flutter --version
flutter doctor -v
flutter pub get
flutter test test/login_role_test.dart test/cargo_vehicle_flow_test.dart test/mobile_navigation_test.dart test/mobile_ui_regression_test.dart
```

Los tests citados simulan autenticacion y precios; no crean pedidos reales.
No reutilizar los comandos .ps1 de Windows como si fueran comandos de zsh.

## Bloqueo iOS identificado

Esta copia NO contiene `ios/Runner/AppDelegate.swift` ni `ios/Podfile`.
El proyecto Xcode, Info.plist, xcconfig y el workspace raiz tampoco estan
versionados; varias de estas rutas estan excluidas en .gitignore.
Las imagenes y storyboards existentes SI contienen trabajo que debe conservarse.

En el Mac, preparar una estructura iOS de referencia aparte con la misma version
de Flutter. Compararla antes de incorporar archivos faltantes: no ejecutar una
regeneracion indiscriminada sobre la unica copia del proyecto.
Revisar .gitignore para versionar fuentes/configuracion sin secretos, manteniendo
fuera GoogleService-Info.plist y credenciales locales. Confirmar en Xcode:

- Bundle ID `cl.muvv.app`, equipo de firma y compatibilidad de iOS.
- Integracion de plugins, Maps, Firebase, Google Sign-In y permisos con mensajes
  claros para ubicacion, camara y fotos; conservar el splash existente.
- Cliente OAuth iOS, esquema de retorno y cliente web usado por el backend.
- APNs/notificaciones y comportamiento en segundo plano en un dispositivo real.
- Apple Sign-In sigue pendiente: mostrar el boton no significa que funcione.

No afirmar que iOS compila hasta ejecutar Xcode/Flutter en el Mac.

## Configuracion y secretos

Railway y Supabase siguen alojando el backend y los datos: no es necesario moverlos
para cambiar de computador. `GOOGLE_OAUTH_CLIENT_ID` es un identificador publico,
no un client secret. Los dart-defines quedan dentro del binario de la app.
Nunca introducir alli SECRET_KEY, DATABASE_URL, Supabase service_role/secret,
credenciales de pagos ni claves privadas de Firebase/APNs.

Preparar los valores publicos de API/Maps/OAuth y los archivos iOS mediante
canales privados o sus consolas de origen; no pegarlos todos en el chat ni Git.
No activar servicios de prueba con costo sin autorizacion de presupuesto.

## Orden siguiente

1. Completar el guardado separado de web/marketing y registrar lo que se transfiere.
2. Confirmar Mac y preparar iOS sin tocar datos ni backend productivo.
3. Retomar `docs/security-release-decision.md`, `docs/security-batch-review.md`
   y `docs/mvp-deployment-plan.md`. La candidata sigue sin aprobacion de despliegue.
4. Probar iPhone con cuentas y cargas ficticias: login/roles, permisos, mapas,
   fotos privadas, precio/vehiculo, chat, regreso desde pagos y texto ampliado.
5. Solo despues de resolver bloqueos, autorizar un despliegue concreto.

No se han cerrado alertas, cambiado excepciones del escaner ni desplegado una
imagen por guardar este codigo en GitHub.
