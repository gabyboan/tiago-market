# Ingestion de precios reales y geolocalizables

Los scrapers deben producir NDJSON con un registro por precio observado. El
objetivo no es solo traer mas productos: para que la app recomiende por
ubicacion, cada precio local debe poder resolverse a una sucursal de
`public.branches` y terminar guardado con `price_snapshots.branch_id`.
En la experiencia principal actual, los precios reales sin sucursal no se
cargan ni se publican; quedan reservados para una futura seccion online.

No se cargan datos inventados en produccion. Las plantillas pueden existir para
probar el formato, pero deben marcarse con `is_synthetic = true` y nunca deben
pasar a `ingestion.publishable_source_prices`.

## Campos minimos para publicar

Cada registro real debe traer, como minimo:

- `source`, `store_brand`, `store_slug`.
- `source_product_name`, `normalized_name`, `category`, `presentation`.
- `price`, `currency`, `available`.
- `captured_at`, `observed_at`, `source_url`.
- `evidence_kind`, `confidence_score`, `is_synthetic = false`.
- `store_product_url` cuando exista ficha oficial.
- `branch_external_key`, `branch_name`, `branch_address`,
  `branch_municipality`, `branch_state`, `latitude` y `longitude`.
- `raw_payload` con la respuesta o fragmento original que produjo el precio.

Si falta evidencia de sucursal o coordenadas verificadas en Mexico, el registro
se rechaza en staging para la app principal.

## Reglas

- `source` debe existir en `ingestion.source_catalog`.
- `country_code` siempre es Mexico (`MX`) a nivel catalogo.
- `source_url` debe apuntar a una pagina, API, feed o recurso oficial usado como
  evidencia de captura.
- `observed_at` y `captured_at` deben ser fechas reales de observacion, no fechas
  generadas para rellenar.
- `evidence_kind` debe indicar de donde salio el dato: `product_page`,
  `store_api`, `official_feed`, `sitemap` o `manual_review`.
- `confidence_score` va de 0 a 1. Produccion solo publica registros aceptados con
  `confidence_score >= 0.70`.
- `is_synthetic = true` queda reservado para pruebas de formato. No se publica.
- Si `branch_name`, direccion o coordenadas faltan, el precio queda online y no
  debe cargarse en el pipeline geolocalizado actual.
- No se inventan coordenadas: se usan datos de la fuente o geocodificacion
  autorizada/manual.
- `store_product_url` debe apuntar a la ficha oficial cuando exista.

## Semaforo de confianza

- `1.00`: API/feed oficial con precio, moneda, disponibilidad y timestamp.
- `0.90`: pagina oficial de producto parseada correctamente.
- `0.75`: pagina/listado oficial con datos completos, pero sin timestamp propio.
- `0.60`: dato oficial incompleto que requiere revision manual.
- `< 0.50`: no publicar hasta conseguir mejor evidencia.

## Carga esperada

1. Crear un `ingestion.scrape_runs` con `status = 'running'`.
2. Guardar cada linea cruda en `ingestion.source_price_staging`.
3. Completar `source_url`, `observed_at`, `evidence_kind`, `confidence_score`,
   `content_hash` e `is_synthetic`.
   `content_hash` debe ser estable por fuente, URL, precio y disponibilidad; el
   cargador lo usa con `source` para omitir filas ya staged.
4. Validar y normalizar.
5. Marcar `review_status = 'accepted'` solo si el registro es real, no sintetico,
   tiene evidencia oficial y no tiene `validation_errors`.
6. Leer desde `ingestion.publishable_source_prices`.
7. Upsert a `stores`, `products`, `store_products` y `branches`.
8. Insertar `price_snapshots` con `branch_id` obligatorio.
9. Marcar el run como `success` o `failed`.

## Conector inicial: Chedraui

El primer conector exploratorio vive en
`tools/ingestion/bin/chedraui_sitemap_scraper.dart`. Lee el sitemap oficial de
Chedraui, valida `robots.txt`, descarga fichas de producto y genera NDJSON con
precios observados en la pagina oficial.
Como esas fichas no traen sucursal, no deben cargarse al pipeline principal
hasta sumar resolucion por sucursal/zona.

Generar una muestra chica:

```bash
dart run tools/ingestion/bin/chedraui_sitemap_scraper.dart \
  --limit 5 \
  --delay-ms 1500 \
  --out /tmp/chedraui_stage.ndjson
```

Generar SQL sin cargar:

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/chedraui_stage.ndjson \
  --run-source chedraui-mx \
  --sql-out /tmp/chedraui_stage.sql
```

La carga con `--execute` queda bloqueada si el NDJSON no incluye sucursal y
coordenadas validas de Mexico.

## Conector Mexico: Steren

`tools/ingestion/bin/steren_sitemap_scraper.dart` lee el sitemap oficial de
Steren Mexico, valida `robots.txt`, descarga fichas de producto y parsea
evidencia `Product/Offer` en JSON-LD. Es un conector reservado para una futura
seccion online: no se carga al pipeline principal porque no trae `branch_id`.

Generar una muestra chica:

```bash
dart run tools/ingestion/bin/steren_sitemap_scraper.dart \
  --limit 5 \
  --delay-ms 1500 \
  --out /tmp/steren_stage.ndjson
```

## Conector geolocalizable: The Home Depot Mexico

`tools/ingestion/bin/home_depot_mx_scraper.dart` usa endpoints publicos de Home
Depot Mexico que la web consume:

- `storelocator` por coordenadas para obtener sucursal, direccion, CP, `storeName`,
  `uniqueID`, latitud y longitud.
- `search/resources/api/v2/products` con `physicalStoreId=<storeName>` para
  obtener precio local.
- `inventories.<uniqueID>.quantity` para disponibilidad de esa sucursal.

El scraper emite solo registros con sucursal y coordenadas de Mexico. Por
defecto respeta `Crawl-delay: 7` usando `--delay-ms 7000`.

Generar una muestra chica cerca de CDMX:

```bash
dart run tools/ingestion/bin/home_depot_mx_scraper.dart \
  --latitude 19.432608 \
  --longitude -99.133209 \
  --branch home-depot-mx:8860 \
  --terms pintura \
  --limit 20 \
  --output /tmp/home-depot-branch.ndjson
```

Generar SQL sin cargar:

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/home-depot-branch.ndjson \
  --run-source home-depot-mx \
  --sql-out /tmp/home_depot_stage.sql
```

Importar el NDJSON a Supabase sin hardcodear secretos:

```bash
SUPABASE_DB_URL="$SUPABASE_DB_URL" \
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/home-depot-branch.ndjson \
  --run-source home-depot-mx \
  --execute
```

## Geolocalizacion en app

Cuando la API devuelve `distance_km`, Flutter ordena los precios de cada
producto por distancia en modo ubicacion y marca la primera opcion como
`Mas cerca`. La app principal debe recibir solo precios con `branch_id` y
coordenadas; los precios puramente online quedan fuera de este flujo.
