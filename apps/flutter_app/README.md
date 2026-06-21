# Tiago Market Flutter

Demo mínima del cliente Flutter. Incluye:

- búsqueda de productos;
- accesos rápidos;
- comparación ordenada por precio;
- cadena, sucursal, fuente y fecha de observación;
- datos demo solo para la interfaz cuando no se configura una API pública.
- inicio de sesión opcional con Google mediante Supabase Auth.

## Ejecutar demo

```bash
flutter pub get
flutter run -d chrome
```

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

## Elegir un precio de venta

Para justificar precio o presupuesto de venta:

- Muestra el flujo completo de onboarding y auth con Supabase.
- Destaca la búsqueda y comparación de precios, junto con la lista de compras persistente.
- Señala que ya hay pruebas unitarias y rutas nombradas en el proyecto.
- Si lo vendés como MVP, apunta a un rango de precio basado en horas de desarrollo + integración Supabase/API.

## Conectar API

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://api.example.com
```

La URL no debe terminar en `/`. Flutter consultará
`/api/v1/compare?query=...`.

La aplicación nunca debe incluir claves secretas de Supabase ni ejecutar
scraping. Para Supabase Auth sí usa una clave pública `publishable`; no consulta
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

Primer conector geolocalizable validado: The Home Depot Mexico, mediante
`tools/ingestion/bin/home_depot_mx_scraper.dart`. El scraper enlaza precio y
stock a sucursales oficiales del locator antes de generar NDJSON.

## Login con Google

La configuración concreta del proyecto actual está documentada en
[`../../docs/google-oauth-setup.md`](../../docs/google-oauth-setup.md).

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
