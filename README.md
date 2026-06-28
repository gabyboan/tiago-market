# Tiago Market Prototype

Backend y fuente de datos para una futura aplicación Flutter de comparación de
precios de tiendas en mexico

## Etapa 0.8

El prototipo implementa el flujo:

`fuente -> snapshots auditables -> sucursales -> API geográfica -> Flutter`

La etapa 0.8 integra el cliente Flutter `0.2.1+3`, endurece la ingesta
idempotente, documenta el estado verificable de las fuentes y agrega una build
Android de demostración configurada mediante `dart-define`. El detalle de lo
validado, pendiente y no aplicado está en
[`docs/release-audit-v0.8.0.md`](docs/release-audit-v0.8.0.md).

La primera fuente real es la herramienta pública Quién es Quién en los Precios
(QQP) de PROFECO. Sus precios son observaciones con fecha, fuente y sucursal;
pueden variar y no representan precios consultados en tiempo real. Los scrapers
directos de Walmart y Soriana permanecen desactivados hasta validar una fuente
legal y técnicamente estable.

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

Vincular el proyecto y aplicar todas las migraciones:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push
```

Como alternativa, las migraciones de `supabase/migrations/` se pueden ejecutar
en orden desde el SQL Editor de Supabase.

La migración crea tablas, índices, RLS y estas vistas:

- `latest_prices`: último precio conocido por producto de tienda.
- `compare_prices`: últimos precios disponibles, ordenables por `price_rank`.
- `source_stats`: actividad y última observación por fuente.
- `coverage_summary`: métricas reales de cobertura e histórico.

Cada snapshot conserva `captured_at`, nombres originales de producto, tienda y
sucursal, ciudad, referencia externa y `raw_payload` para auditoría.

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

## Uso

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

El workflow `.github/workflows/update-profeco-prices.yml` actualiza los precios
de PROFECO de lunes a viernes y también puede ejecutarse manualmente desde
GitHub Actions. Requiere los secretos `SUPABASE_URL` y
`SUPABASE_SERVICE_ROLE_KEY`.

## Aplicación Flutter

La aplicación está en `apps/flutter_app`. Incluye onboarding, acceso invitado,
Google Auth opcional mediante Supabase, búsqueda, categorías, ubicación,
fallback explícito a precios online, favoritos y lista de compras persistente.
También separa precios por sucursal de referencias online y muestra fuente,
fecha y frescura de cada observación.

```bash
cd apps/flutter_app
flutter run -d chrome
```

Para conectarla a la API desplegada:

```bash
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

Para una build local configurada, usar un archivo ignorado por Git:

```bash
cd apps/flutter_app
flutter build apk --release \
  --dart-define-from-file=dart_defines.local.json
```

La APK de esta etapa es demostrativa mientras use firma debug. Publicar en Play
Store requiere keystore de producción, App Links/Universal Links y completar la
verificación extremo a extremo de OAuth.

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
- `observation_url` enlaza a la consulta pública PROFECO.
- `store_product_url` solo se devuelve cuando una fuente directa proporciona una
  ficha oficial verificable. PROFECO no entrega esos enlaces de tienda.
- Los productos internos se relacionan por `normalized_name`.
- Los listados externos se identifican por URL y, si falta, por nombre externo.
- Cada listado registra su fuente (`mock`, `profeco` o `direct`).
- Las tiendas mock quedan deshabilitadas para no mezclarlas con precios reales.
- Flutter será el único cliente de usuario y consumirá exclusivamente la API.
- La aplicación Flutter no accederá directamente a Supabase ni ejecutará
  scraping.
- La API pública usa contrato versionado, paginación y límites por IP.

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
