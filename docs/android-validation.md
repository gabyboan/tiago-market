# Validación Android

Fecha: 2026-06-13.

## Resultado automatizado

- `flutter analyze`: correcto.
- `flutter test`: correcto.
- `flutter build apk --debug`: correcto.
- APK instalada en emulador Pixel API 36.
- La aplicación inicia y renderiza la pantalla de bienvenida sin cierres.

## Flujo con credenciales

Para validar login, roles, búsqueda, imágenes y enlaces en un dispositivo o
emulador con Google Play Services:

```bash
flutter run -d <device> \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Verificar:

1. Login con Google.
2. Cerrar la aplicación desde Android sin cerrar sesión y volver a abrirla:
   debe entrar directamente al rol seleccionado.
3. Selección comprador/negocio y regreso entre modos.
4. Búsqueda y agrupación por producto.
5. Despliegue de tiendas ordenadas por precio.
6. Carga de imágenes y apertura del enlace oficial.

También puede usarse el archivo local ignorado
`apps/flutter_app/dart_defines.local.json` con
`--dart-define-from-file=dart_defines.local.json`.

Para generar la APK release configurada:

```bash
cd apps/flutter_app
flutter build apk --release --dart-define-from-file=dart_defines.local.json
```

No ejecutar `flutter build apk --release` sin ese argumento: las variables
`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` y `GOOGLE_WEB_CLIENT_ID` no se
incluyen automáticamente desde `.env`.

El archivo local actual también define `API_BASE_URL` con la Edge Function
desplegada. La aplicación espera la restauración de sesión de Supabase antes de
mostrar bienvenida o catálogo, evitando pedir nuevamente el login al reabrirla.
