# Capa de datos V1: diagnóstico y runbook

## Diagnóstico técnico

La separación de seguridad es correcta: Flutter consume RPCs públicas limitadas,
la ingestión vive fuera de la app y las tablas sensibles mantienen RLS y grants
restringidos. `nearby_prices` publica precios con `branch_id`; `online_prices`
mantiene separado el catálogo sin sucursal.

Los riesgos encontrados antes de este endurecimiento eran operativos:

- el importador abortaba sin un reporte agregado y convertía implícitamente
  estados distintos de `rejected` en `accepted`;
- la deduplicación de staging dependía de `where not exists`, sin una restricción
  única que protegiera ejecuciones concurrentes;
- el índice histórico `(store_product_id, captured_at)` impedía representar la
  misma captura de un producto en varias sucursales;
- `store_products.branch_id` podía terminar apuntando a la última sucursal
  procesada aunque la URL del producto fuera compartida;
- Home Depot no tenía reintentos acotados ni desglose de rechazos por sucursal.

La implementación local corrige esos puntos. La migración se entrega sin aplicar.

## Matriz de cobertura confirmada

No se consultó una base remota porque este entorno no tiene
`SUPABASE_DB_URL`. Por eso no se inventan conteos. La columna “conteos” se obtiene
con la consulta operativa descrita abajo.

| Fuente | Modo confirmado | Sucursales/coordenadas | Snapshots locales | Conteos | Frescura | Calidad y bloqueo |
|---|---|---:|---:|---|---|---|
| `home-depot-mx` | `branch_local` | `home-depot-mx:8860`, `home-depot-mx:8763` y `home-depot-mx:8692`, confirmadas por locator oficial | Probe del 24 de junio de 2026 produjo 18/18 registros publicables, seis por sucursal | Ejecutar reporte SQL | Probe fresco | Precio `x_prices.<store>.mxn`, stock `inventories.<uniqueID>.quantity` y `physicalStoreId` coincidente confirmados en todas las filas |
| `chedraui-direct` | `online_only` | Sin evidencia enlazada a `branch_id` | 0 locales confirmados | Ejecutar reporte SQL | Ejecutar reporte SQL | No presentar como precio por sucursal |
| `heb-direct` | `online_only` | Sin evidencia enlazada a `branch_id` | 0 locales confirmados | Ejecutar reporte SQL | Ejecutar reporte SQL | No presentar como precio por sucursal |
| `arteli-direct` | `online_only` | Sin evidencia enlazada a `branch_id` | 0 locales confirmados | Ejecutar reporte SQL | Ejecutar reporte SQL | No presentar como precio por sucursal |
| `smart-final-direct` | `online_only` | Sin evidencia enlazada a `branch_id` | 0 locales confirmados | Ejecutar reporte SQL | Ejecutar reporte SQL | No presentar como precio por sucursal |
| `calimax-direct` | `online_only` | Sin evidencia enlazada a `branch_id` | 0 locales confirmados | Ejecutar reporte SQL | Ejecutar reporte SQL | No presentar como precio por sucursal |
| `chedraui-mx` | `experimental` | Selección de tienda existe, pero falta probar precio+stock atribuibles a una sucursal | Ninguno demostrado | Ejecutar reporte SQL | Sin captura local | Conector actual solo prueba ficha online |
| `steren-mx` | `experimental` | Sin evidencia local | Ninguno demostrado | Ejecutar reporte SQL | Sin captura local | Conector reservado para online |

El reporte completo incluye además todas las fuentes del catálogo y las clasifica
como `branch_local`, `online_only`, `experimental` o `inactive` a partir de
evidencia real:

```bash
psql "$SUPABASE_DB_URL" \
  --set ON_ERROR_STOP=1 \
  --file tools/ingestion/sql/source_coverage_report.sql
```

## Runbook operativo

### 1. Generar NDJSON

Probe mínimo antes de una captura:

```bash
dart run tools/ingestion/bin/home_depot_mx_scraper.dart \
  --branch home-depot-mx:8860 \
  --branch-limit 1 \
  --terms pintura \
  --search-limit 2 \
  --products-per-term 1 \
  --limit 1 \
  --delay-ms 7000 \
  --out /tmp/home-depot-probe.ndjson
```

Captura comercial controlada para CDMX, con máximo de tres sucursales y tres
productos por término:

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
  --out /tmp/home-depot-cdmx-coverage.ndjson \
  2> /tmp/home-depot-cdmx-coverage-scraper-report.txt
```

### 2. Validar sin generar SQL

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/home-depot-cdmx-coverage.ndjson \
  --run-source home-depot-mx \
  --validate-only \
  --report-out /tmp/home-depot-cdmx-coverage-report.txt
```

El reporte muestra `input_records`, `accepted`, `rejected`, `publishable`,
duplicados del archivo y desglose por fuente, sucursal y categoría. Los
contadores que dependen de base aparecen como `not_checked`.

### Resultado controlado del 24 de junio de 2026

La baja cobertura histórica de 13 candidatos y un registro no fue causada por
doce fallos de precio o stock. Ese probe se ejecutó con `--limit 1` y
`--products-per-term 1`: el primer candidato válido se emitió y el límite global
detuvo el resto. El scraper ahora registra esos candidatos no procesados como
`global_limit`, en lugar de dejarlos fuera del resumen.

La corrida controlada posterior usó tres sucursales, los seis términos y un
máximo configurado de tres emisiones por término/sucursal:

| Sucursal | Candidatos con evidencia local | Emitidos | Resultado por término |
|---|---:|---:|---|
| `home-depot-mx:8860`, Centro | 26 | 6 | `pintura=3`, `sellador=3`; cuatro términos sin `contents` |
| `home-depot-mx:8763`, Tlatilco | 26 | 6 | `pintura=3`, `sellador=3`; cuatro términos sin `contents` |
| `home-depot-mx:8692`, Linda Vista | 26 | 6 | `pintura=3`, `sellador=3`; un candidato sin stock y cuatro términos sin `contents` |

No hubo reintentos, timeouts, errores de socket ni respuestas HTTP no exitosas.
Los límites explican 50 exclusiones de candidatos; nueve fueron duplicados
entre términos y uno quedó fuera por stock cero. Las respuestas HTTP 200 sin
`contents` para `herramientas`, `escalera`, `focos` y `adhesivo` se clasifican
como respuesta no parseable/sin candidatos, no como precio local.

La semántica vigente durante esa corrida limitaba filas emitidas, no detalles
consultados. Por eso `home-depot-mx:8692` consultó cuatro detalles para
`sellador`: uno quedó sin stock y luego se emitieron tres. Después de la corrida
se corrigió `--products-per-term` para limitar detalles probados; no se hizo una
segunda prueba live.

`stage_ndjson.dart --validate-only` aceptó y consideró publicables las 18 filas,
sin duplicados. Una auditoría fila por fila confirmó:

- `store_slug=home-depot-mx`;
- sucursal, nombre, dirección y coordenadas mexicanas;
- precio positivo en MXN;
- stock local positivo;
- URL oficial con `physicalStoreId` igual al número de sucursal;
- `x_prices.<store>.mxn` e `inventories.<uniqueID>.quantity` coincidentes;
- `observed_at` con zona horaria.

Los artefactos locales son:

```text
/tmp/home-depot-cdmx-coverage.ndjson
/tmp/home-depot-cdmx-coverage-scraper-report.txt
/tmp/home-depot-cdmx-coverage-report.txt
/tmp/home-depot-cdmx-coverage-audit.txt
```

La muestra contiene siete SKU únicos. En los SKU compartidos el precio fue
igual entre sucursales, mientras que el stock sí cambió por sucursal.

No debe cargarse automáticamente el archivo completo: la categoría se deriva
del término y la respuesta live incluyó resultados cruzados, por ejemplo una
escalera y un sellador dentro de `pintura`. El primer lote comercial seguro
recomendado es de nueve filas —los SKU `111338`, `399790` y `981270` en las tres
sucursales— después de corregir/revisar sus categorías como Pintura, Escaleras
y Selladores respectivamente y repetir el preflight.

### 3. Generar SQL dry-run

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/home-depot-cdmx.ndjson \
  --run-source home-depot-mx \
  --sql-out /tmp/home-depot-cdmx.sql
```

Por defecto, un solo rechazo bloquea la generación. `--allow-partial` existe
para una decisión operativa explícita; nunca publica las filas rechazadas.

### 4. Revisar y aplicar manualmente

Primero revisar y aplicar, por el proceso normal de migraciones, la migración
local `20260624000000_harden_ingestion_idempotency.sql`. Antes de aplicar,
confirmar que sus dos auditorías de duplicados no fallan.

Luego:

```bash
less /tmp/home-depot-cdmx.sql
psql "$SUPABASE_DB_URL" \
  --set ON_ERROR_STOP=1 \
  --file /tmp/home-depot-cdmx.sql
```

La salida final del SQL informa `new_staging_rows`, `reused_staging`,
`publishable`, `inserted_snapshots`, `skipped_existing_snapshots` y el desglose
por fuente/sucursal/categoría.

### 5. Verificar publicación

```sql
select source, external_key, name, latitude, longitude, geocoding_status
from public.branches
where source = 'home-depot-mx'
order by external_key;

select
  ps.source,
  b.external_key,
  count(*) as snapshots,
  max(ps.captured_at) as latest_capture
from public.price_snapshots ps
join public.branches b on b.id = ps.branch_id
where ps.source = 'home-depot-mx'
group by ps.source, b.external_key
order by b.external_key;

select *
from public.nearby_prices(
  'pintura',
  19.432608,
  -99.133209,
  25,
  'home-depot-mx',
  'home-depot-mx',
  true
);
```

## Ejemplos NDJSON

- Válido: `tools/ingestion/examples/home_depot_valid_historical_probe.ndjson`.
  Es evidencia histórica del probe acotado; no debe reutilizarse como captura
  nueva.
- Rechazado: `tools/ingestion/examples/rejected_missing_branch.ndjson`.
  Falla por precio, moneda, fechas, URLs, evidencia, confianza, estado,
  sucursal y coordenadas.

## Scheduler futuro, no activado

Propuesta: una ejecución diaria fuera de horario pico, inicialmente limitada a
tres sucursales y los seis términos comerciales. Debe detener publicación si:

- el locator devuelve cero sucursales;
- más del 30% de candidatos falla por evidencia;
- desaparecen `x_prices.<store>.mxn` o `inventories.<uniqueID>.quantity`;
- cambia `robots.txt`;
- la última captura supera 36 horas;
- hay tres errores HTTP consecutivos para una sucursal.

No se agregó ni activó cron, Edge Function ni workflow remoto.

## Riesgos priorizados para producción

1. La migración de unicidad debe auditar y resolver duplicados históricos antes
   de aplicarse.
2. Los endpoints públicos de Home Depot no son un contrato formal y pueden
   cambiar campos, perfiles o políticas.
3. La identidad global de `products.normalized_name` puede fusionar variantes
   comerciales distintas; requiere revisión de catálogo antes de escalar.
4. `store_products` representa una ficha compartida y los snapshots representan
   la sucursal. Código futuro no debe inferir localidad desde
   `store_products.branch_id`.
5. Falta observabilidad programada: alertas de frescura, tasa de rechazo y
   cambios de robots/esquema.
6. Solo hay evidencia local demostrada en Home Depot; las cadenas de
   supermercado siguen siendo online o experimentales.
7. Deben revisarse términos de uso y contacto del crawler antes de una operación
   comercial sostenida.
8. La búsqueda puede devolver HTTP 200 sin `contents` para términos válidos; no
   se debe interpretar como stock cero.
9. Los resultados pueden cruzar categorías. La categoría basada solo en el
   término requiere revisión antes de una carga comercial.
10. La corrida conservada precede al ajuste que limita detalles probados. La
    próxima repetición puede emitir menos filas cuando encuentre stock cero.
