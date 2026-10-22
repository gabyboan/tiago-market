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

No sobrescribir capturas anteriores. Publicar únicamente observaciones que
pasen todos los controles; las rechazadas quedan fuera y se informan.

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

## Actualización automática del catálogo

El workflow `refresh-online-catalog.yml` consulta las 14 fuentes de alimentos
con conectores actuales, todos los días a las **07:17 y 19:17 de Argentina**
(`10:17` y `22:17 UTC`). GitHub Actions puede iniciar la ejecución con demora.
También se puede ejecutar manualmente para todas las fuentes o un comercio.

Cada comercio tiene su propio job; se ejecutan hasta tres en paralelo. Un
bloqueo de una tienda no impide renovar las demás. Se respetan robots,
intervalos y límites de los conectores existentes. No depende de que esté
encendida una computadora ni de abrir la app.

Antes de iniciar los comercios, un control compartido comprueba la conexión
PostgreSQL, el esquema del catálogo y la RPC pública. Si falla, detiene la
matriz y muestra el diagnóstico de configuración sin exponer credenciales.
El diagnóstico distingue configuración, conexión de base y RPC pública. Los
artefactos identifican también el número de intento para permitir reejecuciones.

`python/scheduled_source_refresh.py` concilia cada captura nueva con las
identidades y presentaciones ya publicadas. Los productos nuevos o ambiguos
quedan fuera de la publicación automática. Cada lote pasa por el staging
existente y una transacción de prueba con rollback antes de confirmarse. Se
conservan las fechas HTTP originales y el historial; volver a procesar una
captura no renueva su vigencia.

Chedraui y Gran Bodega consultan los identificadores guardados en lotes de
hasta 50 productos. Se verifica que la API responda únicamente con esos IDs;
los productos ausentes o con cambios de identidad quedan pendientes. Completar
esas consultas no se presenta como un recorrido del catálogo completo de la tienda.

La renovación programada reintenta hasta dos veces las esperas agotadas de GET y los HTTP 500, 502, 503 y 504,
con espera creciente y dentro del presupuesto de solicitudes. La comprobación
de la RPC pública aplica el mismo límite de reintentos. Los bloqueos de acceso,
límites de frecuencia y challenges detienen la fuente; no se reintentan.

Después de publicar, compara precios, fechas, disponibilidad e identidades
contra el catálogo vigente y prueba la RPC pública de la app. Un catálogo
vacío o una verificación fallida marca el job como fallido. Una captura que se
interrumpe puede publicar su parte validada, pero queda marcada como parcial.

Actions requiere `SUPABASE_DB_URL` (URI completa del Session pooler) y
`SUPABASE_URL` como secretos, y `SUPABASE_PUBLISHABLE_KEY` como variable pública
(también acepta un secreto con ese nombre).
La conexión de base debe corresponder al mismo proyecto de la RPC. No se usa
una clave privilegiada en la app ni en la demo.

El resumen de cada job muestra los conteos y errores. Solo `report.json`, con
conteos y verificaciones, se conserva como artefacto por 14 días. Las capturas,
payloads, SQL y credenciales no se suben como artefactos públicos.

## Canasta revisada Chedraui–Merco

El workflow `update-chedraui-merco-basket.yml` queda disponible para ejecución
manual. Usa las ocho fichas de
`catalogs/chedraui_merco_basket.json` y el secreto `SUPABASE_DB_URL` de Actions.
Comparte el grupo de concurrencia con la renovación general para que ambas
ejecuciones no publiquen observaciones de las mismas tiendas simultáneamente.

`python/daily_basket_update.py` revisa ambas fuentes, identidad, presentación,
unidad, disponibilidad y evidencia antes de publicar la canasta completa en
una transacción, luego de comprobarla con rollback. Chedraui admite evidencia
JSON-LD o el estado VTEX de la ficha, vinculado al SKU, vendedor y moneda.
Si falla una fuente o una ficha requiere revisión, la
publicación se bloquea y los snapshots anteriores se conservan.

El workflow guarda solamente reportes de revisión y preflight durante 30 días
como artefactos de Actions. Las páginas capturadas, SQL y logs de base quedan
en el runner privado y no se adjuntan a los artefactos.

El flujo anterior de Profeco también queda manual. La renovación automática
del catálogo de la app la realiza `refresh-online-catalog.yml`.

## Pruebas

```bash
python3 -m unittest discover -s tools/ingestion/python -p 'test_*.py'
flutter test test/stage_ndjson_test.dart test/chedraui_sitemap_scraper_test.dart
```

Para el flujo completo y las limitaciones de instalación, ver
[arquitectura](../../../../docs/architecture.md) y
[desarrollo](../../../../docs/development.md).
