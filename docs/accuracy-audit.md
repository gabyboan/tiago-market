# Auditoría de exactitud

Fecha de revisión: 2026-06-12.

## Toolchain

- Node.js `22.22.3`, Corepack `0.34.6` y pnpm `11.5.3` quedaron instalados y
  verificados localmente.
- pnpm `11.5.3` requiere Node.js `>=22.13`; el requisito anterior de Node 20 era
  incompatible con el gestor fijado por el proyecto.
- Los tests de integración de la API escuchan únicamente en `127.0.0.1`; un
  sandbox que prohíba sockets locales debe conceder ese permiso para ejecutarlos.

## Autenticación

- Supabase recomienda una clave pública `publishable` para operaciones del
  cliente. Las claves secretas y la clave heredada `service_role` son solo para
  componentes backend controlados.
- Google OAuth requiere que la URI autorizada en Google coincida exactamente con
  el callback de Supabase: `https://<project-ref>.supabase.co/auth/v1/callback`.
- El `redirectTo` móvil debe estar en la lista de redirects permitidos de
  Supabase y registrado en Android/iOS.
- La integración compila y sus tests pasan, pero no puede considerarse validada
  de extremo a extremo hasta probarla con credenciales reales.
- Acción manual obligatoria: rotar la clave `service_role` del proyecto Supabase
  que apareció durante la auditoría local y actualizar `.env` y secretos de CI.

## Scraping y fuentes

- No se sostiene que el scraping de datos públicos sea legal de forma general.
  La evaluación depende de la fuente, términos, método, datos y finalidad.
- `robots.txt` expresa preferencias de rastreo; no sustituye términos,
  autorización ni análisis jurídico.
- El proyecto no evade CAPTCHA, login, paywalls ni protecciones anti-bot.
- Los precios de PROFECO son observaciones fechadas, no precios garantizados en
  tiempo real.

## Fuentes primarias consultadas

- Supabase, Login with Google:
  https://supabase.com/docs/guides/auth/social-login/auth-google
- Supabase, Native Mobile Deep Linking:
  https://supabase.com/docs/guides/auth/native-mobile-deep-linking
- Supabase, Understanding API keys:
  https://supabase.com/docs/guides/getting-started/api-keys
- Google, OAuth 2.0 for Web Server Applications:
  https://developers.google.com/identity/protocols/oauth2/web-server
- Cámara de Diputados, legislación federal vigente:
  https://www.diputados.gob.mx/LeyesBiblio/
