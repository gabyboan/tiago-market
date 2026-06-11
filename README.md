# Tiago Market Prototype

Backend y fuente de datos para una futura aplicación Flutter de comparación de
precios de supermercados mexicanos.

## Etapa 0.2

El prototipo implementa el flujo:

`fuente mock/real -> normalización -> Supabase/PostgreSQL -> API -> comparación`

La primera fuente real es la herramienta pública Quién es Quién en los Precios
(QQP) de PROFECO. Los scrapers directos de Walmart y Soriana permanecen
desactivados porque sus sitios bloquean o restringen la automatización.

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
PORT=3000
NODE_ENV=development
PROFECO_CITY_CODE=0901
PROFECO_PRODUCT_LIMIT=3
PROFECO_MAX_RESULTS_PER_PRODUCT=10
PROFECO_REQUEST_DELAY_MS=1000
```

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

- `GET /health`
- `GET /prices?query=coca`
- `GET /compare?query=coca`
- `GET /stores`
- `GET /products`

Ejemplos:

```bash
curl http://localhost:3000/health
curl "http://localhost:3000/prices?query=coca"
curl "http://localhost:3000/compare?query=coca"
```

## Decisiones técnicas

- Cada supermercado implementa un scraper independiente con un contrato común.
- El job captura errores por producto y scraper para continuar el procesamiento.
- La API nunca scrapea durante una búsqueda; consulta precios guardados.
- Cada ejecución agrega snapshots para conservar el histórico.
- Los productos internos se relacionan por `normalized_name`.
- Los listados externos se identifican por URL y, si falta, por nombre externo.
- Cada listado registra su fuente (`mock`, `profeco` o `direct`).
- Las tiendas mock quedan deshabilitadas para no mezclarlas con precios reales.
- Flutter será el único cliente de usuario y consumirá exclusivamente la API.
- La aplicación Flutter no accederá directamente a Supabase ni ejecutará
  scraping.

## Limitaciones

El scraping puede romperse cuando una fuente cambia su sitio y requiere
validación y mantenimiento periódico. Antes de activar cada fuente hay que
revisar sus términos de uso y restricciones. Este proyecto no implementa bypass
de CAPTCHA, login privado ni otras protecciones anti-bot.

Los precios QQP son referencias observadas por PROFECO y pueden variar después
de la fecha informada. Una cadena puede aparecer varias veces porque los precios
se registran por sucursal.

Ver [notas de scraping](docs/scraping-notes.md) y
[roadmap](docs/roadmap.md).
