# Publicación en Google Play

## Estado

- Package: `com.tiagomarket.tiago_market_app`
- Versión actual: `0.2.0+2`
- Política pública:
  `https://fxxtjgalaiiwjpqhzahk.supabase.co/functions/v1/api/privacy`
- La configuración Gradle acepta un `android/key.properties` local ignorado.

## Firma

La clave de carga de Google Play debe mantenerse fuera del repositorio. Después
de generarla, crea `apps/flutter_app/android/key.properties` a partir de
`key.properties.example`.

La clave de carga actual se guardó localmente fuera del repositorio en
`~/.tiago-market-release/`. Su SHA-1 es:

```text
17:A4:BD:83:49:FA:68:35:AE:50:B5:A5:C5:A0:B2:3B:F5:51:3F:05
```

La SHA-1 y SHA-256 de carga ya están registradas en Firebase y la SHA-1 tiene su
cliente OAuth Android en Google Auth Platform. Al habilitar Play App Signing
también debe registrarse la SHA-1 de firma que Google Play asigne a la
aplicación y crear su cliente OAuth Android.

## Paquete

```bash
cd apps/flutter_app
flutter build appbundle --release --dart-define-from-file=dart_defines.local.json
```

La publicación final requiere acceso a Google Play Console, completar la ficha,
declaración de seguridad de datos, clasificación de contenido y una pista de
pruebas internas.

Firebase Crashlytics está integrado para builds release de Android. El
monitoreo Sentry también está disponible y se activa compilando con
`--dart-define=SENTRY_DSN=<dsn>`. Sin un DSN no se envían errores a Sentry.
