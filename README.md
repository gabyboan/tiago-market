# Tiago Market Prototype

Backend y fuente de datos para una futura aplicación Flutter de comparación de
precios de tiendas en mexico

## Etapa 0.7

El prototipo implementa el flujo:

`tienda directa -> snapshots auditables -> API -> Flutter`

Las fuentes activas son Arteli, Smart & Final México y Calimax. Cada resultado
conserva precio, imagen y un enlace oficial verificable. Las fuentes históricas,
demo o indirectas no se publican.

## Requisitos

- Node.js 22.13 o superior
- pnpm mediante Corepack
- Un proyecto de Supabase

La versión local verificada está fijada en [`.node-version`](.node-version).

## Instalación

```bash
corepack enable
pnpm install
cp .env.example .env
```

Completar `.env` con:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
PORT=3000
NODE_ENV=development
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

Las sucursales opcionales se normalizan en `branches` con domicilio estructurado
y coordenadas cuando una fuente directa las proporciona.

La integración usa Mapbox Geocoding v6 en modo permanente y queda apagada por
defecto. Los resultados de alta confianza se aceptan; los ambiguos quedan en
`review` y no aparecen en búsquedas cercanas.

RLS queda habilitado sin políticas públicas. Los roles `anon` y `authenticated`
no reciben acceso directo; la API usa `service_role` exclusivamente desde el
backend.

## Uso

Cargar precios directos verificables:

```bash
pnpm scrape:arteli
pnpm scrape:smart-final
pnpm scrape:calimax
pnpm import:direct-catalog
```

Revisar consultas de geocodificación sin llamar al proveedor:

```bash
pnpm geocode:branches
```

Las llamadas reales requieren un token Mapbox autorizado y
`GEOCODING_MODE=live`.

Iniciar la API:

```bash
pnpm api
```

También se puede compilar e iniciar:

```bash
pnpm build
pnpm start
```

## Endpoints

- `GET /api/v1/health`
- `GET /api/v1/prices?query=coca&page=1&limit=20`
- `GET /api/v1/compare?query=coca&store=wal-mart`
- `GET /api/v1/stores`
- `GET /api/v1/products`
- `GET /api/v1/coverage`
- `GET /api/v1/sources`
- `GET /api/v1/quality`
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

El job `pnpm geocode:branches` funciona en `dry_run` por defecto. Las
ejecuciones reales se activan explícitamente con `GEOCODING_MODE=live` y un
token Mapbox autorizado para almacenamiento permanente. Existe además un
workflow manual `Geocode branches`; no se agenda automáticamente para evitar
costos o llamadas accidentales.

## Automatización

El workflow `.github/workflows/update-direct-prices.yml` actualiza las tres
fuentes y amplía gradualmente el catálogo de lunes a viernes. También puede
ejecutarse manualmente desde GitHub Actions. Requiere los secretos `SUPABASE_URL` y
`SUPABASE_SERVICE_ROLE_KEY`.

## Demo Flutter

La demo mínima está en `apps/flutter_app`. Consume exclusivamente la API y
muestra productos agrupados, precios ordenados, supermercado, imagen, enlace
oficial, fuente y freshness.
Usa datos de ejemplo mientras la API no tenga una URL pública:

```bash
cd apps/flutter_app
flutter run -d chrome
```

Para conectarla a la API desplegada:

```bash
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

La demo también admite login opcional con Google mediante Supabase Auth. La
configuración y los comandos están documentados en
[`apps/flutter_app/README.md`](apps/flutter_app/README.md#login-con-google).

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
- `store_product_url` enlaza a la ficha oficial verificable.
- `image_url` conserva la imagen publicada por la tienda.
- Los productos internos se relacionan por `normalized_name`.
- Los listados externos se identifican por URL y, si falta, por nombre externo.
- Cada listado registra su fuente directa.
- Flutter será el único cliente de usuario y consumirá la API propia para datos
  de precios.
- Flutter puede usar Supabase Auth con una clave pública `publishable`, pero no
  consulta directamente las tablas de negocio ni ejecuta scraping.
- La API pública usa contrato versionado, paginación y límites por IP.

## Limitaciones

El scraping puede romperse cuando una fuente cambia su sitio y requiere
validación y mantenimiento periódico. Antes de activar cada fuente hay que
revisar sus términos de uso y restricciones. Este proyecto no implementa bypass
de CAPTCHA, login privado ni otras protecciones anti-bot.

Los precios pueden variar después de la fecha informada. La comparación muestra
la última captura directa disponible y permite verificarla en la tienda.

Ver [notas de scraping](docs/scraping-notes.md) y
[auditoría de referencias externas](docs/scraper-reference-audit.md),
[geolocalización](docs/geolocation.md), además del [roadmap](docs/roadmap.md).
