# Tiago Market · Flutter

Cliente móvil y multiplataforma para comparar precios observados de comercios
de México. La versión de la app es `0.2.6+8`.

Incluye búsqueda, comparación por comercio y sucursal, favoritos, lista de
compras, acceso invitado, Google Auth y carrito sincronizado por cuenta.
Muestra fuente y fecha y separa catálogo online de precios locales.
El checkout prepara un borrador; todavía no procesa pagos ni envíos.

## Desarrollo

Flutter 3.41.7 es la versión utilizada en CI.

```bash
flutter pub get
cp config/dart_defines.example.json dart_defines.local.json
# Completar con la configuración pública de un proyecto propio.
flutter run -d chrome --dart-define-from-file=dart_defines.local.json
```

- `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`: autenticación y RPC de precios.
- `API_BASE_URL`: categorías y feedback mediante HTTP.
- `GOOGLE_WEB_CLIENT_ID`: cliente OAuth web para el login nativo de Google.
- `APP_ENV` y `CRASHLYTICS_ENABLED`: entorno y diagnóstico opcional.

La app consulta `nearby_prices_v4`, `online_prices_v4` y `nearby_branches`.
El proyecto necesita esas RPC y datos publicados para responder búsquedas.
El backend Node y la Edge Function histórica tienen rutas distintas; el
código desplegado de esa función no está incluido en este checkout.

La clave pública de Supabase está diseñada para clientes. Nunca usar
`SUPABASE_SERVICE_ROLE_KEY`, conexiones PostgreSQL o secretos OAuth en
`dart-define`: los valores se pueden extraer del build.

## Login con Google

Configurar el proveedor Google en Supabase con un cliente OAuth propio.
La redirección web del proveedor es
`https://<project-ref>.supabase.co/auth/v1/callback`.
Agregar el origen web de desarrollo y
`com.tiagomarket.app://login-callback/` en las URLs permitidas de Supabase.
Para Android, registrar paquete y huellas de firma en los clientes OAuth
correspondientes. Los JSON descargados de Google permanecen fuera de Git.

Para iOS, copiar `ios/Flutter/Google.example.xcconfig` a
`ios/Flutter/Google.local.xcconfig` y completar los identificadores OAuth y el
esquema invertido del cliente iOS. Usar los mismos IDs en
`GOOGLE_IOS_CLIENT_ID` y `GOOGLE_WEB_CLIENT_ID` de los Dart defines.
Debug y Release incluyen ese archivo local opcional; `Info.plist` utiliza
variables de build en lugar de identificadores de una cuenta concreta.

El callback móvil actual usa un esquema personalizado. La publicación en
stores requiere completar App Links/Universal Links y revisar consentimiento
y políticas de privacidad.

## Pruebas

```bash
flutter analyze
flutter test
python3 -m unittest discover -s tools -p 'test_release_config.py'
python3 -m unittest discover -s tools/ingestion/python -p 'test_*.py'
```

Las pruebas usan fixtures y servicios simulados. Los tests de sesión y
persistencia cubren separación de cuentas, restauración y carrito invitado.

## APK release local

Preparar una clave de firma propia, `android/key.properties` y
`android/app/google-services.json`. Conservar una copia privada de la clave y
sus contraseñas: las actualizaciones requieren la misma firma.
Estos archivos quedan excluidos de Git.

```bash
cp config/dart_defines.release.example.json dart_defines.release.local.json
# Completar la configuración pública del piloto.
python3 tools/build_android_release.py --check-only
python3 tools/build_android_release.py
```

El script valida configuración pública, URLs HTTPS, firma real y Crashlytics.
El resultado es `build/app/outputs/flutter-apk/app-release.apk`.
Una build release no sustituye una firma faltante por la firma debug.
El workflow `android-release.yml` admite ejecución manual con secretos
configurados en GitHub Actions y no publica en Play Store.

## Organización

- `lib/auth`: integración de autenticación.
- `lib/src/controllers`: estado de búsqueda y comparación.
- `lib/src/models`: productos, carrito y borrador de checkout.
- `lib/src/services`: acceso a API y persistencia.
- `lib/src/pages` y `lib/src/widgets`: pantallas y componentes de interfaz.
- `tools/ingestion`: captura externa; no se ejecuta dentro de la app.
- `supabase`: migraciones y pruebas de contratos.

Ver [arquitectura](../../docs/architecture.md),
[ingesta](tools/ingestion/README.md) y
[contratos de envío y pagos](docs/envio-y-pagos.md).

## Demo de portafolio

[Probar la misma interfaz en el navegador](https://gabyboan.github.io/tiago-market/),
sin registro ni configuración de servicios. `lib/main_demo.dart` inyecta un
catálogo ficticio con `DemoMarketApi`; mantiene el aviso de demo en todas las
pantallas y deshabilita login, ubicación y formularios de datos personales.

```bash
flutter pub get
python3 tools/build_portfolio_demo.py --base-href=/
python3 -m http.server 8080 --directory build/portfolio-demo
```

El build no usa Dart defines de servicios, no inicializa Supabase, Firebase ni
Sentry y falla al arrancar si se intenta incluir configuración de servicios.
El workflow `portfolio-demo.yml` construye y publica en GitHub Pages desde
`main`, con el prefijo `/tiago-market/`. No requiere secretos de producción.

La versión 0.2.6 conserva los controles originales y permite leer los
detalles completos al desplegar un producto. El costo estimado de la lista suma sus subtotales; las ofertas
alternativas de distintas tiendas se comparan por separado.
