# Android local 0.2.3+5 — 23/09/2026

Entrega local de APK firmada; el código y los avances del catálogo se publican
en GitHub. No se publica un binario en GitHub Releases ni Google Play.

## Cambios

- Logo de la cabecera (`shopping_basket_rounded`) en los íconos Android, iOS y
  web; SVG reproducibles y licencia de Material Icons en `assets/branding/`.
- Versión Flutter 0.2.3+5, configuración de cliente mediante `dart-define` y
  validación previa con `tools/build_android_release.py`.
- Bienvenida restaurada con «Continuar con Google» y «Continuar sin cuenta»;
  la escucha de sesión permanece activa durante el login para avanzar después
  de autenticarse. El botón de Google se mantiene visible aun sin configuración,
  deshabilitado en ese caso.
- Crashlytics activo en release Android, con etiqueta `APP_ENV=pilot`; errores
  del framework y asíncronos conservan los handlers opcionales de Sentry.
- Firma exclusiva de Tiago Market guardada fuera del repositorio; no se usa la
  firma debug como alternativa. Firebase y las credenciales locales se ignoran.
- Consolidación de los avances pendientes de catálogo local/online, variantes,
  imágenes por URL, ingestión y el sitio `apps/price_web`.

## Verificación

- `flutter analyze`: sin problemas.
- `flutter test`: 62 pruebas aprobadas.
- Backend: 28 pruebas, compilación TypeScript y ESLint aprobados.
- Web: typecheck y build Vite aprobados.
- Python: 14 pruebas de ingestión y 6 de configuración segura aprobadas.
- RPC públicas `online_prices_v4` y `nearby_prices_v4`: HTTP 200 con la clave
  pública del cliente. Esta comprobación no modifica datos.
- Gitleaks sobre los archivos candidatos a Git: sin hallazgos después de
  identificar y anotar un ID ficticio de sucursal en un test.
- Huellas SHA-1 y SHA-256 de la firma release registradas en la app Android de
  Firebase; `google-services.json` actualizado y excluido de Git.

## Configuración y pendientes

Para repetir la compilación, seguir
[la guía de APK local](../apps/flutter_app/README.md#apk-release-local).
Las URLs e identificadores de cliente se incorporan a la APK; nunca se deben
incluir contraseñas, claves de servicio ni tokens administrativos.

No hubo un dispositivo ADB conectado. Quedan pendientes la instalación, el
login completo con Google y comprobar en la consola de Firebase la recepción de
un fallo de prueba. Compilar con Crashlytics no demuestra la recepción de eventos.

La firma release es distinta de la debug. Una instalación debug anterior no se
puede actualizar directamente; antes de desinstalarla, guardar sus listas y
favoritos. Conservar una copia privada del keystore y sus contraseñas para
mantener la posibilidad de actualizar futuras versiones.
