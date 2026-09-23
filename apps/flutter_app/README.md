# Tiago Market Flutter

Estado vigente: [diagnóstico del 22/09/2026](../../docs/estado-2026-09-22.md).
Chedraui: [preflight bloqueado y evidencia](../../docs/chedraui-validation-2026-09-22.md).

Demo mínima del cliente Flutter. Incluye:

- búsqueda de productos;
- accesos rápidos;
- comparación ordenada por precio;
- cadena, sucursal, fuente y fecha de observación;
- requiere configuración de Supabase para precios cercanos; sin configuración puede mostrar “API no configurada”.
- inicio de sesión opcional con Google mediante Supabase Auth.

## Estado de la versión 0.2.3+5

- Filtra precios por sucursal, disponibilidad y frescura; la exigencia de URL
  de evidencia local y la revalidación de favoritos/lista siguen incompletas.
- Separa claramente el fallback de precios online de los precios por sucursal.
- Incluye íconos de Tiago Market en Android, iOS y web.
- Unifica el ícono de instalación con la canasta de la esquina superior izquierda.
- La release Android incorpora los `dart-define` locales y Firebase Crashlytics.
- La APK de desarrollo puede instalarse localmente; una build release requiere
  un keystore de piloto y nunca usa la firma debug como sustituto.

## Ejecutar demo

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=dart_defines.local.json
```

## APK release local

Preparar `android/key.properties` con una clave propia de Tiago y el archivo
`android/app/google-services.json` correspondiente al paquete Android. Ambos
archivos y el keystore quedan fuera de Git. Conservar una copia privada de la
clave y sus contraseñas: las futuras actualizaciones deben usar la misma firma.

```bash
cp config/dart_defines.release.example.json dart_defines.release.local.json
# Completar con la configuración pública del proyecto.
python3 tools/build_android_release.py --check-only
python3 tools/build_android_release.py
```

El resultado es `build/app/outputs/flutter-apk/app-release.apk`. El script exige
URLs HTTPS, claves públicas y Crashlytics activo; rechaza variables desconocidas
y claves privilegiadas. `dart-define` se puede extraer de la APK: no es un lugar
para secretos. `APP_ENV=pilot` identifica esta versión en los diagnósticos.

Crashlytics se activa sólo en release Android mediante `CRASHLYTICS_ENABLED=true`.
Firebase recibe los errores de Flutter y los errores asíncronos no capturados;
los handlers conservan la integración opcional con Sentry. Referencia:
[configuración oficial de Crashlytics](https://firebase.google.com/docs/crashlytics/flutter/get-started).
La recepción del primer informe se debe comprobar en un dispositivo y en Firebase.

El login nativo de Google requiere registrar las huellas SHA-1/SHA-256 de la
firma release en Firebase/Google Cloud y actualizar `google-services.json`.
Una instalación anterior firmada con debug no puede actualizarse con esta firma;
desinstalarla borra sus datos locales. No hacerlo sin guardar listas y favoritos.

Para regenerar los íconos desde el mismo glifo Material de la cabecera:

```bash
uv run --with fonttools --with cairosvg --with pillow tools/generate_brand_icons.py
```

Los SVG y la licencia de Material Icons están en `assets/branding/`.

## Mantenimiento de dependencias

Este proyecto usa Flutter/Dart y gestiona paquetes con `flutter pub`, no con `pnpm` ni `npm`.

Para revisar actualizaciones de dependencias puedes usar:

```bash
flutter pub outdated
```

Para instalar dependencias y actualizar el lockfile:

```bash
flutter pub get
```

Para actualizar las dependencias compatibles automáticamente:

```bash
flutter pub upgrade
```

## Pruebas

```bash
flutter test test/widget_test.dart test/search_controller_test.dart
```

## Flujo de navegación y auth

- La aplicación arranca en `AuthFlowGate`.
- Si no hay sesión válida, se muestra `WelcomePage`.
- `WelcomePage` permite continuar como invitado o iniciar sesión con Google.
- Si el usuario inicia sesión y no tiene rol, se muestra `RoleSelectionPage`.
- Si el rol es `buyer`, se muestra `SearchPage`.
- Si el rol es `seller`, se muestra `BusinessComingSoonPage`.
- El botón de continuar como invitado usa la ruta nombrada `AppRoutes.search`.
- Las rutas principales están definidas en `lib/src/navigation/app_routes.dart`.

## Conectar API

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<public-publishable-key> \
  --dart-define=API_BASE_URL=https://<ref>.supabase.co/functions/v1/api
```

Con Supabase configurado, los precios se consultan por `nearby_prices_v4` y
`online_prices_v4`, que incluyen metadatos estructurados de variante y conteo
de imágenes. El conteo de sucursales usa `nearby_branches`.
`API_BASE_URL` se usa para categorías y feedback. El fallback HTTP online
no tiene una ruta equivalente en la Edge Function actual (404).

La aplicación nunca debe incluir claves secretas de Supabase ni ejecutar
scraping. Para Auth y RPC usa una clave pública `publishable`; no consulta
directamente las tablas de precios.

## Scraping y geolocalización

El cliente Flutter no ejecuta scraping. La recolección de precios debe hacerse
desde jobs externos y publicarse en Supabase/API. El estado actual, el pipeline
recomendado, las tiendas candidatas y el roadmap para precios por sucursal están
documentados en [`docs/scraping-and-geolocation.md`](docs/scraping-and-geolocation.md).
Los registros reales deben pasar por staging con URL oficial, fecha de
observación, evidencia, confianza, sucursal y coordenadas mexicanas. Los precios
puramente online no se publican en la experiencia principal; quedarán para una
sección separada más adelante.

Las fotos siguen la misma política de bajo almacenamiento: sólo se guarda la
dirección URL proporcionada por la tienda. No se descargan imágenes ni se usa
Supabase Storage para copiarlas.

Primer conector geolocalizable validado: The Home Depot Mexico, mediante
`tools/ingestion/bin/home_depot_mx_scraper.dart`. El scraper enlaza precio y
stock a sucursales oficiales del locator antes de generar NDJSON.

## Login con Google

La guía `docs/google-oauth-setup.md` referenciada anteriormente no está en este
checkout. El login real en dispositivo sigue pendiente de verificación.

1. En Google Cloud, crea un cliente OAuth Web y agrega como URI de redirección:
   `https://<project-ref>.supabase.co/auth/v1/callback`.
   Debe coincidir exactamente, incluyendo esquema y barra final si la hubiera.
2. En Supabase, abre **Authentication > Providers > Google**, habilita el
   proveedor y carga el Client ID y Client Secret de Google.
3. En **Authentication > URL Configuration**, agrega las URLs web donde se
   ejecutará Flutter y `com.tiagomarket.app://login-callback/` como redirect
   URLs permitidas.
4. Inicia la aplicación pasando la URL y la clave pública `anon`/publishable:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<public-publishable-key>
```

Para combinar autenticación y API, agrega también `--dart-define=API_BASE_URL`.
La clave pública de Supabase está diseñada para clientes. La variable histórica
`SUPABASE_ANON_KEY` también funciona, pero nunca pases la
`SUPABASE_SERVICE_ROLE_KEY` a Flutter.

Para desarrollo Android local se puede crear un archivo ignorado por Git:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "<public-publishable-key>",
  "API_BASE_URL": "https://api.example.com"
}
```

Luego ejecutar:

```bash
flutter run --dart-define-from-file=dart_defines.local.json
flutter build apk --debug --dart-define-from-file=dart_defines.local.json
flutter build apk --release --dart-define-from-file=dart_defines.local.json
```

`dart-define` se incorpora durante la compilación. Por eso, ejecutar solamente
`flutter build apk --release` genera una APK sin la configuración de Supabase y
la pantalla mostrará `Configura Supabase para iniciar sesión`.

El callback móvil usa un esquema personalizado. Es válido para desarrollo, pero
otra aplicación instalada podría registrar el mismo esquema. Antes de publicar
en tiendas debe migrarse a Android App Links e iOS Universal Links con un
dominio controlado.

## Estado de verificación del login

- Verificado: compilación web, análisis estático, tests Flutter, llamada
  `signInWithOAuth`, escucha de cambios de sesión y configuración del callback
  móvil.
- Pendiente: prueba de inicio/cierre de sesión de extremo a extremo contra un
  proyecto real de Supabase y un cliente OAuth de Google configurado.
- Pendiente para producción: App Links/Universal Links, branding/verificación
  del consentimiento de Google y políticas de privacidad.
