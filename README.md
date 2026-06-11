# Tiago Market Prototype

Prueba técnica backend para validar un comparador de precios de supermercados
mexicanos antes de construir una web o app móvil.

## Etapa 0.1

El prototipo implementa el flujo:

`scraper mock -> normalización -> Supabase/PostgreSQL -> API -> comparación`

Los scrapers de Walmart y Soriana incluyen solamente la estructura inicial. No se
activan hasta validar términos de uso, comportamiento del sitio y selectores.

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
```

La `SUPABASE_SERVICE_ROLE_KEY` es exclusivamente para backend. Nunca debe
exponerse en una app web o móvil.

## Base de datos

Abrir el SQL Editor del proyecto Supabase, copiar el contenido de
`supabase/migrations/001_init.sql` y ejecutarlo una vez.

La migración crea tablas, índices, RLS y estas vistas:

- `latest_prices`: último precio conocido por producto de tienda.
- `compare_prices`: últimos precios disponibles, ordenables por `price_rank`.

RLS queda habilitado sin políticas públicas. La API usa la service role desde el
backend.

## Uso

Cargar precios falsos realistas:

```bash
npm run scrape:mock
```

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

## Limitaciones

El scraping puede romperse cuando una fuente cambia su sitio y requiere
validación y mantenimiento periódico. Antes de activar cada fuente hay que
revisar sus términos de uso y restricciones. Este proyecto no implementa bypass
de CAPTCHA, login privado ni otras protecciones anti-bot.

Ver [notas de scraping](docs/scraping-notes.md) y
[roadmap](docs/roadmap.md).
