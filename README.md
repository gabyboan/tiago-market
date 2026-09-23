# Tiago Market Prototype

Aplicación Flutter existente para comparar precios en México, con Supabase e
ingesta externa. Ver el [estado comprobado al 22/09/2026](docs/estado-2026-09-22.md)
y el [resultado de la validación Chedraui](docs/chedraui-validation-2026-09-22.md).
La próxima entrega se limita a validar una fuente de supermercado por sucursal
en CDMX; el preflight Chedraui quedó bloqueado por autorización de reutilización
no confirmada. No hay cobertura vigente de supermercados por sucursal.

## Etapa 0.8

El prototipo implementa el flujo:

`fuente -> evidencia/NDJSON -> staging -> snapshots por sucursal -> RPC Supabase -> Flutter`

Flutter también usa Supabase Auth. La Edge Function `api` atiende categorías y
feedback con la configuración local; el backend Node de este repositorio tiene
rutas distintas. La Edge Function desplegada todavía no está recuperada en Git.

La prerelease 0.8 integra el cliente Flutter `0.2.1+3`; la rama de preparación
del piloto avanza a `0.2.2+4`, endurece la ingesta idempotente, documenta el
estado verificable de las fuentes y separa build debug de release firmado. El
detalle histórico de lo validado, pendiente y no aplicado está en
[`docs/release-audit-v0.8.0.md`](docs/release-audit-v0.8.0.md).

La fuente reciente comprobada en Supabase es Home Depot: 18 observaciones del
21/09/2026, seis productos y tres sucursales. No es cobertura de supermercados.
Los datos de Chedraui y otras cadenas son online, de junio y sin sucursal.
PROFECO fue una fuente histórica; sus últimas seis ejecuciones consultadas
fallaron. Walmart y Soriana conservan scrapers incompletos.

## Requisitos

- Node.js 20 o superior
- Un proyecto de Supabase

## Instalación

```bash
npm install
cp .env.example .env
```

Completar `.env` con:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
PORT=3000
NODE_ENV=development
PROFECO_CITY_CODE=0901
PROFECO_PRODUCT_LIMIT=3
PROFECO_MAX_RESULTS_PER_PRODUCT=10
PROFECO_REQUEST_DELAY_MS=1000
PROFECO_BULK_TERM_LIMIT=50
PROFECO_BULK_MAX_LISTINGS=5000
API_RATE_LIMIT_WINDOW_MS=60000
API_RATE_LIMIT_MAX=120
GEOCODING_MODE=dry_run
MAPBOX_ACCESS_TOKEN=
GEOCODING_BRANCH_LIMIT=10
GEOCODING_REQUEST_DELAY_MS=1100
GEOCODING_MIN_CONFIDENCE=0.8
```

### Configuración de Google Sign In y Supabase

1. En Google Cloud Console, abre el proyecto correcto.
2. Ve a `APIs y servicios` → `Biblioteca` y habilita `Google Identity Services`.
3. Ve a `APIs y servicios` → `Credenciales` → `Crear credenciales` → `ID de cliente de OAuth`.
4. Selecciona `Aplicación web` y añade estos valores autorizados:
   - Origen autorizado: `https://your-project.supabase.co`
   - URI de redirección autorizado: `https://your-project.supabase.co/auth/v1/callback`
5. Copia el `Client ID` y `Client Secret`.
6. En Supabase, ve a `Authentication` → `Providers` → `Google` y pega el `Client ID` y el `Client Secret`.
7. Guarda y activa el proveedor Google.
8. Coloca `GOOGLE_CLIENT_ID` en tu `.env` con el valor de `Client ID`.

La `SUPABASE_SERVICE_ROLE_KEY` es exclusivamente para backend. Nunca debe
exponerse en la aplicación Flutter.

## Base de datos

El historial local y el remoto necesitan reconciliación antes del próximo despliegue. No hay actualmente una secuencia completa validada para reconstruir una base vacía.

El [SQL recuperado](supabase/recovered/2026-09-18/README.md) conserva migraciones históricas y una captura de esquema; incluye marcadores y definiciones solapadas. No ejecutar todos esos archivos ni aplicar `supabase db push` a ciegas.

El remoto enlazado registra 26 migraciones, incluidas `20260921121843`
(idempotencia), `20260921122029` (publicación por sucursal y contrato v2) y
`20260923104615` (separación online/local y RPC v3). Las RPC v3 y la columna
`price_scope` ya están desplegadas. La migración local `20260628055206` no está
aplicada en remoto y no debe ejecutarse automáticamente: pertenece a una
secuencia histórica anterior que aún necesita reconciliación.
El reporte de cobertura está en `apps/flutter_app/tools/ingestion/sql/source_coverage_report.sql`.

Cada snapshot conserva `captured_at`, nombres originales de producto, tienda y
sucursal, ciudad, referencia externa y `raw_payload` para auditoría.

Las imágenes no se descargan ni se almacenan como archivos en Supabase. Sólo se
conserva la URL original de la imagen y metadatos mínimos en `product_images`;
la aplicación la carga desde su CDN de origen cuando está disponible.

Las sucursales se normalizan en `branches` con domicilio estructurado y
coordenadas opcionales. PROFECO QQP no entrega latitud/longitud: deben
completarse mediante geocodificación autorizada o carga manual antes de aparecer
en búsquedas por radio.

La integración usa Mapbox Geocoding v6 en modo permanente y queda apagada por
defecto. Los resultados de alta confianza se aceptan; los ambiguos quedan en
`review` y no aparecen en búsquedas cercanas.

RLS queda habilitado sin políticas públicas. Los roles `anon` y `authenticated`
no reciben acceso directo; la API usa `service_role` exclusivamente desde el
backend.

## Uso del backend histórico

Los siguientes jobs escriben datos y no forman parte del preflight actual.
Su presencia no demuestra que la fuente opere hoy; no ejecutarlos sobre el
proyecto remoto como prueba de conectividad.

Cargar precios falsos realistas:

```bash
npm run scrape:mock
```

Cargar una muestra conservadora de precios reales desde QQP PROFECO:

```bash
npm run scrape:profeco
```

Importar un catálogo amplio de observaciones PROFECO:

```bash
npm run import:profeco-catalog
```

Este job consulta términos amplios, deduplica por producto y sucursal, y crea
productos usando el nombre observado real. Sus límites se controlan con
`PROFECO_BULK_TERM_LIMIT` y `PROFECO_BULK_MAX_LISTINGS`.

Revisar consultas de geocodificación sin llamar al proveedor:

```bash
npm run geocode:branches
```

Las llamadas reales requieren un token Mapbox autorizado y
`GEOCODING_MODE=live`.

Por defecto consulta los primeros tres productos en Ciudad de México, guarda
como máximo diez resultados por producto y espera un segundo entre consultas.
Los códigos de ciudad se obtienen de `https://qqp.profeco.gob.mx/api/ciudades`.

Iniciar la API:

```bash
npm run api
```

También se puede compilar e iniciar:

```bash
npm run build
npm start
```

## Endpoints

- `GET /api/v1/health`
- `GET /api/v1/prices?query=coca&page=1&limit=20`
- `GET /api/v1/compare?query=coca&store=wal-mart`
- `GET /api/v1/stores`
- `GET /api/v1/products`
- `GET /api/v1/coverage`
- `GET /api/v1/sources`
- `GET /api/v1/branches`
- `GET /api/v1/nearby?query=coca&lat=19.43&lng=-99.13&radius_km=10`

Ejemplos:

```bash
curl http://localhost:3000/api/v1/health
curl http://localhost:3000/api/v1/coverage
curl http://localhost:3000/api/v1/sources
curl "http://localhost:3000/api/v1/branches?city_code=0901"
curl "http://localhost:3000/api/v1/prices?query=coca&limit=10"
curl "http://localhost:3000/api/v1/prices?page=1&limit=50"
curl "http://localhost:3000/api/v1/compare?query=coca"
curl "http://localhost:3000/api/v1/nearby?query=coca&lat=19.43&lng=-99.13&radius_km=10"
```

Los endpoints anteriores sin `/api/v1` se mantienen temporalmente como alias.
El contrato estable para Flutter está documentado en
[`docs/api-v1.md`](docs/api-v1.md).

## Geocodificación

El job `npm run geocode:branches` funciona en `dry_run` por defecto. Las
ejecuciones reales se activan explícitamente con `GEOCODING_MODE=live` y un
token Mapbox autorizado para almacenamiento permanente. Existe además un
workflow manual `Geocode branches`; no se agenda automáticamente para evitar
costos o llamadas accidentales.

## Automatización

El workflow `.github/workflows/update-profeco-prices.yml` está programado de
lunes a viernes, pero las últimas seis ejecuciones consultadas fallaron. No hay
actualización automática exitosa comprobada para las fuentes directas. Requiere
los secretos `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`; programarlo no acredita
frescura de datos.

## Aplicación Flutter

La aplicación está en `apps/flutter_app`. Incluye onboarding, acceso invitado,
Google Auth opcional mediante Supabase, búsqueda, categorías, ubicación,
fallback explícito a precios online, favoritos y lista de compras persistente.
También separa precios por sucursal de referencias online y muestra fuente,
fecha y frescura de cada observación.

```bash
cd apps/flutter_app
flutter run -d chrome --dart-define-from-file=dart_defines.local.json
```

El archivo local ignorado debe incluir `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY` y `API_BASE_URL`; esta última apunta al servicio HTTP
(por ejemplo, `https://<ref>.supabase.co/functions/v1/api`). Los precios cercanos
requieren Supabase configurado aunque se use acceso invitado. Sin configuración
no se garantiza una demo con datos: puede aparecer “API no configurada”.

Para una build local configurada, usar un archivo ignorado por Git:

```bash
cd apps/flutter_app
flutter build apk --debug \
  --dart-define-from-file=dart_defines.local.json
```

La APK debug es sólo demostrativa. Las builds release fallan sin un keystore
real y configuración Firebase. Para una APK local con `dart-define` y Crashlytics,
seguir [la guía de release Android](apps/flutter_app/README.md#apk-release-local).
El workflow `.github/workflows/android-release.yml` genera APK/AAB sin publicar
en Play Store. La entrega local 0.2.3+5 está documentada en
[el informe del 23/09/2026](docs/android-local-release-2026-09-23.md).
El estado y los bloqueantes del piloto están en
[`docs/tiago-readiness.md`](docs/tiago-readiness.md).

## Decisiones técnicas

- Cada supermercado implementa un scraper independiente con un contrato común.
- El job captura errores por producto y scraper para continuar el procesamiento.
- La API nunca scrapea durante una búsqueda; consulta precios guardados.
- Cada ejecución agrega snapshots para conservar el histórico.
- La API clasifica observaciones como `fresh` (<7 días), `stale` (7 a 21 días)
  u `old` (>21 días).
- La ubicación del usuario se usa solo para la consulta y no se persiste.
- Las búsquedas geográficas excluyen sucursales todavía no geocodificadas.
- Las búsquedas geográficas excluyen coordenadas pendientes de revisión.
- `observation_url` debería conservar la evidencia de observación; en el lote
  actual devuelve un SKU, defecto pendiente. El raw payload conserva la URL oficial.
- `store_product_url` solo se devuelve cuando una fuente directa proporciona una
  ficha oficial verificable. PROFECO no entrega esos enlaces de tienda.
- Los productos internos se relacionan por `normalized_name`.
- Los listados externos se identifican por URL y, si falta, por nombre externo.
- Cada listado registra su fuente (`mock`, `profeco` o `direct`).
- Las tiendas mock quedan deshabilitadas para no mezclarlas con precios reales.
- Flutter consulta precios mediante RPC públicas de Supabase, usa Auth y consume
  HTTP para servicios auxiliares; no ejecuta scraping ni lee tablas protegidas.
- La API Node tiene paginación y límites por IP. No asumir que esas protecciones
  existen también en la Edge Function desplegada o las RPC.

## Limitaciones

El scraping puede romperse cuando una fuente cambia su sitio y requiere
validación y mantenimiento periódico. Antes de activar cada fuente hay que
revisar sus términos de uso y restricciones. Este proyecto no implementa bypass
de CAPTCHA, login privado ni otras protecciones anti-bot.

Los precios QQP son referencias observadas por PROFECO y pueden variar después
de la fecha informada. La comparación conserva cada sucursal/listing y no
presenta los datos como precios en tiempo real.

Ver [notas de scraping](docs/scraping-notes.md) y
[geolocalización](docs/geolocation.md), además del [roadmap](docs/roadmap.md).
