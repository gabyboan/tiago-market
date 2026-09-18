# Scraping y geolocalizacion

Este documento define como ampliar Tiago Market con mas tiendas de Mexico, sin
salir de Mexico y sin mezclar scraping dentro de la app Flutter. La app debe seguir siendo cliente:
consulta una API, muestra precios, pide ubicacion cuando el usuario lo decide y
guarda la lista localmente. La recoleccion de datos debe vivir en jobs externos
y actualizar Supabase mediante migraciones/procesos controlados.

## Alcance geografico

El alcance de datos queda limitado a Mexico:

- `country_code = MX` para targets nuevos.
- No mezclar tiendas, precios ni dominios de otros paises.
- Si una marca existe en varios paises, usar solamente el dominio/canal Mexico.
- Las pruebas de ubicacion pueden simular cualquier ciudad mexicana mas adelante,
  pero no se debe dejar una ciudad fija hardcodeada en la app.

## Estado actual

Supabase ya tiene una base util para MVP:

- `stores`: cadenas normalizadas.
- `products`: productos normalizados.
- `store_products`: relacion tienda-producto, URL oficial, imagen y
  presentacion.
- `price_snapshots`: historico de precios.
- `branches`: sucursales geocodificadas.
- Vistas: `latest_prices`, `compare_prices`, `source_stats`,
  `branch_coverage_summary`, `direct_quality_summary`.
- Edge Function activa: `api`.

Fuentes cargadas al 18 de junio de 2026:

- `smart-final-direct`
- `arteli-direct`
- `chedraui-direct`
- `heb-direct`
- `calimax-direct`

Limitacion importante: los precios cargados historicamente son online y no
tienen `branch_id`. Para la experiencia principal, esos precios no deben
publicarse ni mezclarse con busquedas por ubicacion. La app solo tiene sentido
cuando el precio esta enlazado a una sucursal geocodificada; los precios
puramente online quedan reservados para una seccion futura separada.

## Principios

- No poner scrapers ni claves secretas en Flutter.
- Usar solo fuentes permitidas: APIs publicas, feeds oficiales, sitemaps,
  paginas publicas permitidas por `robots.txt` y terminos del sitio.
- Identificar el crawler con `User-Agent` propio y contacto.
- Aplicar rate limit, backoff y cache.
- Guardar URL oficial y fecha de observacion de cada precio.
- Guardar evidencia, nivel de confianza y estado de revision antes de publicar
  un precio.
- No mezclar datos demo/sinteticos con datos de produccion. Las plantillas deben
  quedar marcadas con `is_synthetic = true` y rechazadas.
- No recolectar datos personales de usuarios ni cuentas de terceros.
- Si una tienda exige login, captcha o bloqueo anti-bot, no se fuerza: se busca
  integracion, feed, carga manual o se descarta.

## Checklist por tienda

Antes de crear un conector:

1. Revisar `https://dominio/robots.txt`.
2. Revisar terminos de uso y restricciones comerciales.
3. Buscar API publica, endpoints usados por la web, sitemap o feed oficial.
4. Confirmar si el precio es nacional, por ciudad, por CP o por sucursal.
5. Confirmar si hay URL oficial de producto e imagen usable.
6. Definir frecuencia de captura: diaria, cada 12 h, semanal.
7. Definir riesgo: bajo, medio, alto.

## Tiendas candidatas

Prioridad 1: supermercados y tiendas con valor directo para comparacion.

- Walmart Mexico / Bodega Aurrera / Walmart Express.
- Soriana.
- La Comer / Fresko / City Market.
- Chedraui, expandiendo cobertura.
- H-E-B Mexico, expandiendo cobertura.
- Casa Ley.
- Alsuper.
- Calimax, expandiendo cobertura.
- Smart & Final, expandiendo cobertura.
- Arteli, expandiendo cobertura.

Prioridad 2: farmacia, conveniencia y cuidado personal.

- Farmacias Guadalajara.
- Farmacias del Ahorro.
- Farmacias Benavides.
- Farmacia San Pablo.
- OXXO.
- 7-Eleven.

Prioridad 3: hogar, mascotas, oficina, electronica y departamental.

- The Home Depot Mexico.
- Office Depot / OfficeMax.
- Steren.
- Petco Mexico.
- Liverpool.
- Sears Mexico.
- Sanborns.
- Coppel.

Estas son candidatas, no autorizaciones. Cada una debe pasar el checklist antes
de recolectar datos.

La migracion `20260618172000_add_mexico_source_catalog.sql` guarda este abanico
como catalogo interno en `ingestion.source_catalog`. No esta atado a una ciudad:
sirve para decidir que conectores construir primero y cuales son aptos para
geolocalizacion.

## Contrato de salida de un scraper

Cada conector debe producir registros normalizados con esta forma. El bloque es
un contrato de campos, no un dato para cargar:

```json
{
  "source": "chedraui-direct",
  "store_slug": "chedraui-centro",
  "store_name": "Chedraui Centro",
  "source_product_name": "Leche entera 1 L",
  "normalized_name": "leche entera 1 l",
  "category": "Supermercado",
  "presentation": "1 l",
  "price": 35.5,
  "currency": "MXN",
  "available": true,
  "captured_at": "2026-06-18T18:00:00Z",
  "observed_at": "2026-06-18T18:00:00Z",
  "source_url": "https://...",
  "evidence_kind": "product_page",
  "confidence_score": 0.9,
  "is_synthetic": false,
  "store_product_url": "https://...",
  "image_url": "https://...",
  "external_reference": "https://...",
  "branch_external_key": "tienda-123",
  "branch_name": "Sucursal Centro",
  "branch_address": "Av. Ejemplo 123",
  "branch_municipality": "Cuauhtemoc",
  "branch_state": "Ciudad de Mexico",
  "latitude": 19.4326,
  "longitude": -99.1332,
  "raw_payload": {}
}
```

`branch_external_key`, `branch_name`, direccion, municipio/estado y coordenadas
deben venir poblados o resolverse antes de publicar. Si una fuente solo devuelve
precio online/nacional, no entra al pipeline principal geolocalizado.

`captured_at` es cuando el scraper guardo el dato. `observed_at` es cuando el
precio fue observado en la fuente. En capturas simples pueden coincidir, pero no
se deben rellenar con fechas ficticias.

Para que un precio sea publicable en la app principal, el proceso de ingestión
debe terminar con `price_snapshots.branch_id` poblado. Si no hay `branch_id`, el
precio se considera online o nacional y queda fuera de las vistas principales.
La plantilla operativa de NDJSON esta en `tools/ingestion/`.

Conectores exploratorios implementados:

- `tools/ingestion/bin/chedraui_sitemap_scraper.dart`: lee sitemap/fichas de
  producto oficiales de Chedraui, aplicando `robots.txt`, y emite NDJSON. No se
  publica hasta resolver sucursal/zona.
- `tools/ingestion/bin/steren_sitemap_scraper.dart`: lee sitemap/fichas de
  producto oficiales de Steren. Queda reservado para una futura seccion online.
- `tools/ingestion/bin/home_depot_mx_scraper.dart`: usa locator oficial por
  coordenadas y `search/resources/api/v2/products` con `physicalStoreId` para
  emitir precios por sucursal de The Home Depot Mexico.
- `tools/ingestion/bin/stage_ndjson.dart`: valida el NDJSON y lo carga en
  `ingestion.source_price_staging` como `pending` solo si trae sucursal y
  coordenadas mexicanas.

La operación V1 repetible está documentada en
[`data-ingestion-v1-runbook.md`](data-ingestion-v1-runbook.md). La evaluación
de la siguiente cadena está en
[`second-chain-evaluation.md`](second-chain-evaluation.md).

### Hallazgo validado: The Home Depot Mexico

Home Depot Mexico es el primer conector nuevo apto para la experiencia principal
geolocalizada. La web publica un flujo suficiente para enlazar cada precio a una
sucursal:

- `GET /wcs/resources/store/10351/storelocator/latitude/{lat}/longitude/{lon}`
  devuelve sucursales con `storeName`, `uniqueID`, direccion, CP, municipio,
  estado, latitud y longitud.
- `GET /search/resources/api/v2/products?...&physicalStoreId={storeName}` trae
  precios locales en `x_prices.{storeName}.mxn`.
- El stock local aparece como `inventories.{uniqueID}.quantity`.

En el scraper, `branch_external_key` queda como `home-depot-mx:{storeName}` y
el payload crudo conserva ambos identificadores para auditoria. Este conector
debe ejecutarse con rate limit; el `robots.txt` observado declara
`Crawl-delay: 7`.

## Pipeline recomendado

1. `discover`: encontrar URLs o IDs de productos.
2. `fetch`: descargar respuestas con rate limit y reintentos.
3. `parse`: extraer datos crudos sin normalizar.
4. `normalize`: nombres, categoria, presentacion, moneda, disponibilidad.
5. `validate`: descartar precios <= 0, URLs vacias, productos sin nombre.
6. `stage`: guardar lote en una tabla staging o archivo NDJSON.
7. `review`: aceptar solo datos reales con evidencia y confianza suficiente.
8. `upsert`: actualizar `stores`, `products`, `store_products`, `branches`.
9. `snapshot`: insertar nuevos `price_snapshots`.
10. `quality`: comparar cobertura, freshness, outliers y fallos del run.
11. `publish`: la API lee desde `latest_prices` y `compare_prices`.

## Calidad de datos

Los conectores pueden guardar registros crudos aunque esten incompletos, pero el
proceso de publicacion solo debe leer desde
`ingestion.publishable_source_prices`. Esa vista exige:

- `review_status = accepted`.
- `is_synthetic = false`.
- `source_url` oficial con esquema `http` o `https`.
- `evidence_kind` distinto de `unknown`.
- `observed_at` informado.
- `confidence_score >= 0.70`.
- `validation_errors` vacio.
- evidencia de sucursal: `branch_external_key`, `branch_name`, direccion,
  municipio/estado y coordenadas dentro de Mexico.

Semaforo sugerido para `confidence_score`:

- `1.00`: API/feed oficial con precio, moneda, disponibilidad y timestamp.
- `0.90`: pagina oficial de producto parseada correctamente.
- `0.75`: pagina/listado oficial con datos completos, pero sin timestamp propio.
- `0.60`: dato oficial incompleto que requiere revision manual.
- `< 0.50`: no publicar hasta conseguir mejor evidencia.

## Tablas a agregar

La base actual funciona, pero falta observabilidad del scraping. Proxima
migracion incluida en `supabase/migrations`:

```sql
create schema if not exists ingestion;

create table if not exists ingestion.scrape_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  status text not null check (status in ('running', 'success', 'failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  fetched_count integer not null default 0 check (fetched_count >= 0),
  inserted_snapshots integer not null default 0 check (inserted_snapshots >= 0),
  error_message text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists scrape_runs_source_started_at_idx
  on ingestion.scrape_runs (source, started_at desc);
```

Tambien conviene agregar una tabla staging si los conectores van a crecer:

```sql
create table if not exists ingestion.source_price_staging (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references ingestion.scrape_runs(id) on delete cascade,
  source text not null,
  payload jsonb not null,
  normalized_payload jsonb not null default '{}'::jsonb,
  source_url text,
  evidence_kind text not null default 'unknown',
  observed_at timestamptz,
  confidence_score numeric(3,2) not null default 0,
  is_synthetic boolean not null default false,
  review_status text not null default 'pending',
  reviewed_at timestamptz,
  review_notes text,
  content_hash text,
  validation_errors text[] not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists source_price_staging_run_id_idx
  on ingestion.source_price_staging (run_id);
```

La migracion `20260618173000_add_ingestion_quality_fields.sql` agrega los
campos de evidencia, constraints de calidad, indices de revision y la vista
`ingestion.publishable_source_prices`.

## Geolocalizacion

La experiencia principal de la app:

- Pedir ubicacion cuando el usuario quiera comparar cerca.
- Mostrar precios enlazados a sucursales geocodificadas.
- Ordenar por distancia y precio.
- No mezclar precios online/nacionales en esta pantalla.

Hoy `latest_prices` y `compare_prices` deben exponer solo filas con
`branch_id`, coordenadas y geocodificacion valida. La base ya tiene una funcion
`nearby_prices(...)`; la Edge Function deberia usarla cuando haya `lat/lng`.

Roadmap de geolocalizacion:

1. Mantener `branches` como catalogo verificado de sucursales.
2. Enlazar cada precio por sucursal con `price_snapshots.branch_id`.
3. Enlazar cada `store_products.branch_id` solo si el listing realmente depende
   de sucursal.
4. Cambiar `/api/v1/compare?lat=...&lng=...` para llamar `nearby_prices`.
5. Mas adelante, crear una seccion separada para precios puramente online.

## Comandos de Supabase

Traer estado remoto a migraciones locales:

```bash
supabase login
supabase init
supabase link --project-ref fxxtjgalaiiwjpqhzahk
supabase db pull
```

Crear cambios de schema:

```bash
supabase migration new scraping_pipeline
supabase db push --dry-run
supabase db push
```

Deploy de API:

```bash
supabase functions deploy api --project-ref fxxtjgalaiiwjpqhzahk
```

## Criterio de listo

Una tienda nueva esta lista cuando:

- Tiene conector documentado.
- Tiene robots/terminos revisados.
- Carga productos con URL oficial.
- Inserta snapshots con `captured_at`.
- Inserta snapshots con `branch_id`.
- Reporta `scrape_runs`.
- Tiene prueba con una muestra pequena.
- No rompe freshness ni categorias.
