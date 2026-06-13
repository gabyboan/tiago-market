# Configuración Google OAuth

Estado revisado: 2026-06-13.

## Proyecto Google Cloud

- Nombre: `Tiago Market`
- Project ID: `tiago-market-20260611-0839`
- Project number: `99518273807`
- Cuenta administradora inicial: `gabrielboan14@gmail.com`
- Facturación: no habilitada; no es necesaria para el login básico.

## Google Auth Platform

Configurar en https://console.cloud.google.com/auth/overview?project=tiago-market-20260611-0839

### Branding

- App name: `Tiago Market`
- User support email: `gabrielboan14@gmail.com`
- Developer contact email: `gabrielboan14@gmail.com`
- No agregar logo, dominio, homepage o política de privacidad hasta disponer de
  un dominio público controlado.

### Audience

- User type: `External`
- Publishing status: `Testing`
- Test user: `gabrielboan14@gmail.com`

### Data access

Solicitar únicamente los scopes mínimos de Google Sign-In:

- `openid`
- `.../auth/userinfo.email`
- `.../auth/userinfo.profile`

### Cliente web para Supabase

- Application type: `Web application`
- Name: `Tiago Market Supabase Auth`
- Authorized JavaScript origin para desarrollo: `http://localhost:3001`
- Authorized redirect URI:
  `https://fxxtjgalaiiwjpqhzahk.supabase.co/auth/v1/callback`

La URI debe coincidir exactamente. El Client Secret generado debe cargarse
directamente en Supabase y nunca guardarse en Git.

### Clientes Android

Google Sign-In necesita un cliente Android diferente por cada certificado que
firme la aplicación. Todos deben usar el package
`com.tiagomarket.tiago_market_app`.

- Debug SHA-1 registrado:
  `74:FB:3B:D2:68:E9:94:4D:9B:3F:0C:C1:C9:1F:6E:EC:E8:AC:90:DB`
- Upload SHA-1 registrado en Firebase:
  `17:A4:BD:83:49:FA:68:35:AE:50:B5:A5:C5:A0:B2:3B:F5:51:3F:05`
- Pendiente: crear en **Google Auth Platform > Clients** un cliente Android
  para la Upload SHA-1.
- Pendiente al publicar: crear otro cliente Android con la SHA-1 de **App
  signing key certificate** que muestre Google Play Console.

La creación de clientes OAuth Android no está expuesta por la API pública de
Google Cloud ni por `gcloud`; se completa desde Google Auth Platform.

## Firebase

- Proyecto Firebase: `tiago-market-20260611-0839`
- App Android: `1:99518273807:android:f24e05a85bd4570ee9867a`
- `google-services.json` está versionado porque contiene identificadores
  públicos de la app, no secretos del servidor.
- Crashlytics está integrado y recopila errores únicamente en builds release
  de Android.

## Supabase

1. Abrir **Authentication > Providers > Google**.
2. Habilitar Google y cargar el Client ID y Client Secret.
3. En **Authentication > URL Configuration**:
   - Site URL de desarrollo: `http://localhost:3001`
   - Additional Redirect URL web: `http://localhost:3001/**`
   - Additional Redirect URL móvil:
     `com.tiagomarket.app://login-callback/`

## Prueba local

```bash
cd apps/flutter_app
flutter run -d chrome --web-port=3001 \
  --dart-define=SUPABASE_URL=https://fxxtjgalaiiwjpqhzahk.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<public-publishable-key>
```

## Antes de producción

- Publicar homepage y política de privacidad en un dominio controlado.
- Configurar y verificar branding en Google.
- Reemplazar el esquema móvil personalizado por App Links/Universal Links.
- Añadir únicamente orígenes y redirects HTTPS de producción.
