# Ingestion de precios reales y geolocalizables

Los scrapers deben producir NDJSON con un registro por precio observado. El
objetivo no es solo traer mas productos: para que la app recomiende por
ubicacion, cada precio local debe poder resolverse a una sucursal de
`public.branches` y terminar guardado con `price_snapshots.branch_id`.
Los precios reales sin sucursal se publican en el catálogo online. Las búsquedas
por ubicación siguen usando exclusivamente precios con sucursal verificada.

No se cargan datos inventados en produccion. Las plantillas pueden existir para
probar el formato, pero deben marcarse con `is_synthetic = true` y nunca deben
pasar a `ingestion.publishable_source_prices`.

El runbook V1, la matriz de cobertura y los riesgos operativos están en
[`docs/data-ingestion-v1-runbook.md`](../../docs/data-ingestion-v1-runbook.md).

## Campos minimos para publicar

Cada registro real debe traer, como minimo:

- `source`, `store_brand`, `store_slug`.
- `source_product_name`, `normalized_name`, `category`, `presentation`.
- `price`, `currency`, `available`.
- `price_scope`: `online` o `branch_local`.
- `captured_at`, `observed_at`, `source_url`.
- `evidence_kind`, `confidence_score`, `is_synthetic = false`.
- `store_product_url` cuando exista ficha oficial.
- Para `branch_local`: `branch_external_key`, `branch_name`, `branch_address`,
  `branch_municipality`, `branch_state`, `latitude` y `longitude`.
- Para `online`: los campos de sucursal y coordenadas deben ser `null`.
- `raw_payload` con la respuesta o fragmento original que produjo el precio.

Si falta evidencia de sucursal o coordenadas verificadas en Mexico, el registro
debe declararse `price_scope=online`; nunca se inventa una sucursal.

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
  se carga en el pipeline geolocalizado actual.
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
8. Insertar `price_snapshots` con `price_scope=online` y `branch_id` nulo para
  catálogo online, o con `price_scope=branch_local` y sucursal verificada para
  búsquedas cercanas.
9. Marcar el run como `success` o `failed`.

## Conector inicial: Chedraui

El primer conector exploratorio vive en
`tools/ingestion/bin/chedraui_sitemap_scraper.dart`. Lee el sitemap oficial de
Chedraui, valida `robots.txt`, descarga fichas de producto y genera NDJSON con
precios observados en la pagina oficial.
Como esas fichas no traen sucursal, se publican como catálogo online y aparecen
en `online_prices_v4`; no se mezclan con el pipeline geolocalizado.

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

La carga con `--execute` acepta Chedraui como catálogo online después de revisar
el preflight. No se le asigna una sucursal artificial.

## Conector Mexico: Steren

`tools/ingestion/bin/steren_sitemap_scraper.dart` lee el sitemap oficial de
Steren Mexico, valida `robots.txt`, descarga fichas de producto y parsea
evidencia `Product/Offer` en JSON-LD. Es un conector online porque no trae
`branch_id`; no se mezcla con las búsquedas por GPS.

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
El cierre de cada corrida informa por sucursal y término: candidatos crudos,
candidatos con evidencia local, emitidos, rechazos agrupados por causa,
advertencias, requests, reintentos y códigos HTTP.

Generar la muestra controlada de cobertura cerca de CDMX:

```bash
dart run tools/ingestion/bin/home_depot_mx_scraper.dart \
  --latitude 19.432608 \
  --longitude -99.133209 \
  --branch-limit 3 \
  --terms pintura,herramientas,escalera,sellador,focos,adhesivo \
  --search-limit 3 \
  --products-per-term 3 \
  --limit 54 \
  --delay-ms 7000 \
  --timeout-ms 20000 \
  --max-attempts 3 \
  --backoff-ms 2000 \
  --output /tmp/home-depot-cdmx-coverage.ndjson \
  2> /tmp/home-depot-cdmx-coverage-scraper-report.txt
```

Validar primero, sin generar SQL ni conectarse a Supabase:

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/home-depot-cdmx-coverage.ndjson \
  --run-source home-depot-mx \
  --validate-only \
  --report-out /tmp/home-depot-cdmx-coverage-report.txt
```

Si existe cualquier fila rechazada, la generación de SQL se bloquea. El modo
`--allow-partial` debe ser una decisión manual explícita. Los textos del NDJSON
se serializan sin compactar ni normalizar espacios internos.

Importar el NDJSON a Supabase sin hardcodear secretos:

```bash
SUPABASE_DB_URL="$SUPABASE_DB_URL" \
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/home-depot-branch.ndjson \
  --run-source home-depot-mx \
  --execute
```

El SQL generado requiere la restricción única de staging incluida en
`supabase/migrations/20260624000000_harden_ingestion_idempotency.sql`. Esa
migración también separa la identidad de snapshots online de la identidad
`(store_product_id, branch_id, captured_at)` usada para sucursales.

Reporte operativo de cobertura:

```bash
psql "$SUPABASE_DB_URL" \
  --set ON_ERROR_STOP=1 \
  --file tools/ingestion/sql/source_coverage_report.sql
```

## Geolocalizacion en app

Cuando la API devuelve `distance_km`, Flutter ordena los precios de cada
producto por distancia en modo ubicacion y marca la primera opcion como
`Mas cerca`. La app principal debe recibir solo precios con `branch_id` y
coordenadas; los precios puramente online quedan fuera de este flujo.

## Actualizacion de varias fuentes

El runner `multi_source_ingestion.dart` ejecuta los conectores disponibles de
forma secuencial y escribe un NDJSON separado por fuente. No publica
directamente ni mezcla registros entre cadenas:

```bash
dart run tools/ingestion/bin/multi_source_ingestion.dart \
  --sources home-depot-mx,chedraui-mx \
  --output-dir /tmp/tiago-market-ingestion \
  --latitude 19.432608 \
  --longitude -99.133209 \
  --branch-limit 3 \
  --terms leche,huevo,arroz \
  --limit 10 \
  --delay-ms 7000
```

Cada salida debe validarse por separado. Chedraui y Steren siguen siendo
fuentes online mientras no exista evidencia atribuible a una sucursal:

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/tiago-market-ingestion/home-depot-mx-<run>.ndjson \
  --run-source home-depot-mx \
  --validate-only

dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/tiago-market-ingestion/chedraui-mx-<run>.ndjson \
  --run-source chedraui-mx \
  --validate-only
```

Después de revisar el reporte, el NDJSON online puede publicarse con
`--execute`; nunca se usará para ordenar resultados por distancia.

El runner se detiene ante el primer fallo para evitar una corrida parcialmente
interpretada. `--continue-on-error` permite completar el diagnóstico, pero no
cambia el hecho de que cada fuente debe revisarse y publicarse por separado.

## Supermercado online: Merco Monterrey

`tools/ingestion/python/merco_online_scraper.py` captura fichas oficiales de
`adomicilio.merco.mx`. La fuente es `merco-mx` y la tienda se identifica como
`merco-monterrey-online`: la evidencia corresponde al catálogo online de
Monterrey, sin atribución a sucursal ni cobertura nacional demostrada.

Requiere Python 3, sin dependencias adicionales. Incluye seis URLs revisadas de
leche y despensa; `--urls archivo.json` permite usar una lista JSON de otras
fichas oficiales. El límite máximo por corrida es 20 y el intervalo mínimo es
cinco segundos. Se valida `robots.txt` en cada corrida; HTTP no exitoso,
redirección o desafío de acceso detienen la captura sin reintentos.

```bash
python3 tools/ingestion/python/merco_online_scraper.py \
  --limit 6 --delay-ms 5000 --out /tmp/merco-nueva-captura.ndjson

dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/merco-nueva-captura.ndjson --run-source merco-mx \
  --sql-out /tmp/merco-nueva-captura.sql
```

La carpeta `<salida>.evidence/` conserva respuestas, recibos con SHA256 y
`report.json`; no se sobrescriben capturas anteriores. Un rechazo o captura
incompleta devuelve código de salida 1. Revisar el reporte antes de publicar
cualquier archivo parcial. El hash conserva la fecha de observación: repetir
el mismo archivo no duplica snapshots; una captura nueva puede refrescar un
precio sin cambios.

El runner también permite `--sources merco-mx`. Para registrar la fuente se usa
`20260923151217_add_merco_online_source.sql`. El SQL de precios se genera con el
mismo staging que Chedraui, sin modificar sus reglas de evidencia.
