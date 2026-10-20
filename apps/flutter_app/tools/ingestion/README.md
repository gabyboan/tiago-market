# Ingesta de precios

Conectores externos en Dart y Python para capturar precios observados,
validarlos y publicarlos en Supabase. El cliente Flutter no ejecuta scraping.

## Contrato de observación

Cada línea NDJSON identifica fuente, producto, presentación, precio, moneda,
disponibilidad, fechas de captura y observación y URL oficial de evidencia.
Incluye `confidence_score`, `evidence_kind` e `is_synthetic`.

- `price_scope=online`: sin atribución de sucursal ni coordenadas inventadas.
- `price_scope=branch_local`: requiere sucursal, dirección y coordenadas
  verificadas en México.
- Los datos sintéticos quedan reservados para pruebas y no se publican.
- Los productos con presentación, moneda o evidencia ambigua requieren revisión.
- Las fechas se conservan; reprocesar una captura no la convierte en reciente.

Los payloads originales y reportes son evidencia operativa local. Guardarlos
fuera del contenido público, en una carpeta nueva por corrida.

## Herramientas

| Herramienta | Función |
| --- | --- |
| `bin/chedraui_sitemap_scraper.dart` | Captura de fichas Chedraui |
| `bin/steren_sitemap_scraper.dart` | Captura de fichas Steren |
| `bin/home_depot_mx_scraper.dart` | Precios vinculados a sucursales Home Depot |
| `python/merco_online_scraper.py` | Catálogo online Merco Monterrey |
| `python/expand_grocery_sources.py` | Capturas acotadas de distintas cadenas |
| `python/refresh_grocery_catalogs.py` | Recorrido de catálogos registrados |
| `python/prepare_grocery_batch.py` | Conciliación de identidad y presentación |
| `bin/stage_ndjson.dart` | Preflight, deduplicación y generación de SQL |
| `python/publish_grocery_batch.py` | Preparación, rollback de prueba y publicación explícita |
| `python/verify_catalog_rpc.py` | Comparación del lote esperado con las RPC |

`catalogs/grocery_retailers.json` registra las fuentes y sus capacidades.
La existencia de un conector no garantiza cobertura actual, stock físico ni
un acuerdo comercial con una cadena.

## Capturar una muestra

Ejecutar desde `apps/flutter_app`, con dependencias de Flutter instaladas.
Revisar términos y reglas de la fuente antes de capturar. Los conectores
aplican límites e intervalos y se detienen ante bloqueos o desafíos de acceso.

```bash
dart run tools/ingestion/bin/chedraui_sitemap_scraper.dart \
  --limit 5 --delay-ms 1500 --out /tmp/chedraui-nueva-captura.ndjson

python3 tools/ingestion/python/merco_online_scraper.py \
  --limit 6 --delay-ms 5000 --out /tmp/merco-nueva-captura.ndjson
```

No sobrescribir capturas anteriores ni publicar automáticamente un lote parcial.

## Validar sin conectarse a la base

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/chedraui-nueva-captura.ndjson \
  --run-source chedraui-mx --validate-only \
  --report-out /tmp/chedraui-preflight.txt
```

Para generar SQL y revisarlo localmente:

```bash
dart run tools/ingestion/bin/stage_ndjson.dart \
  --input /tmp/chedraui-nueva-captura.ndjson \
  --run-source chedraui-mx --sql-out /tmp/chedraui-stage.sql
```

La ejecución explícita con `--execute` requiere `SUPABASE_DB_URL` en el entorno.
Revisar proyecto de destino, preflight, alcance del precio e historial de
migraciones antes de cualquier escritura. La carga conserva la separación
online/local y la identidad idempotente de las observaciones.

## Canasta diaria Chedraui–Merco

El workflow `update-chedraui-merco-basket.yml` se ejecuta a las `11:30 UTC` y
admite ejecución manual. Usa las ocho fichas de
`catalogs/chedraui_merco_basket.json` y el secreto `SUPABASE_DB_URL` de Actions.

`python/daily_basket_update.py` revisa ambas fuentes, identidad, presentación,
unidad, disponibilidad y evidencia antes de publicar la canasta completa en
una transacción. Si falla una fuente o una ficha requiere revisión, la
publicación se bloquea y los snapshots anteriores se conservan.

El workflow guarda reportes y comprobantes durante 30 días como artefactos de
Actions. Revisar esos artefactos antes de compartirlos; no forman parte del
código publicado.

## Pruebas

```bash
python3 -m unittest discover -s tools/ingestion/python -p 'test_*.py'
flutter test test/stage_ndjson_test.dart test/chedraui_sitemap_scraper_test.dart
```

Para el flujo completo y las limitaciones de instalación, ver
[arquitectura](../../../../docs/architecture.md) y
[desarrollo](../../../../docs/development.md).
