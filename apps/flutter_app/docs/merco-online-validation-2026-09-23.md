# Merco Monterrey online — 23 de septiembre de 2026

Fuente nueva: `merco-mx`. Tienda: `merco-monterrey-online`.
Alcance: catálogo público online de Monterrey; no demuestra precio nacional,
entrega a cualquier código postal ni inventario de una sucursal física.

## Evidencia y contrato

- Dominio oficial: <https://adomicilio.merco.mx>, enlazado desde
  <https://merco.mx/terminos-y-condiciones>.
- `robots.txt` respondió HTTP 200 y no impidió las seis fichas consultadas.
- Fichas con un `Product`, SKU y URL coincidentes, una oferta en MXN y
  disponibilidad explícita `InStock`.
- Categoría tomada del breadcrumb de la ficha. Presentación conservada a partir
  del nombre, con normalización de unidades; no se inventa `1 pieza`.
- `price_scope=online`; todos los campos geográficos nulos.
- Observación y captura conservan la fecha real de descarga, y `raw_payload`
  incluye el objeto original y SHA256 de la respuesta.
- Sin login, carrito, selección de tienda, reintentos ni cambio de identidad
  para superar bloqueos. La muestra no activa una captura periódica.

## Lote inicial

| SKU | Producto | MXN observado |
|---|---|---:|
| 10248783 | Leche Fresca Lala Entera 1 Lto. | 31.00 |
| 10244586 | Leche Lala Chocolala Tetrapack 500 ml | 26.00 |
| 10244557 | Leche Lala 100 Sin Lactosa Reducida en Grasa 1 L | 51.50 |
| 10263357 | Arroz Mimarca Extra 906 gr | 13.99 |
| 10250882 | Aceite Vegetal Comestible Ave Cocina 850 ml | 38.99 |
| 10246078 | Pasta Barilla Para Sopa de Fideo N° 0 200 g | 11.03 |

Son precios observados en esa captura, sujetos a cambios. Las fichas enlazadas
en cada registro son la evidencia; no se usaron precios de resultados de búsqueda.

Artefactos locales de esta corrida:

```text
/tmp/tiago-merco-20260923.ndjson
/tmp/tiago-merco-20260923.ndjson.evidence/
/tmp/tiago-merco-20260923-preflight.txt
/tmp/tiago-merco-20260923.sql
```

El preflight aceptó 6/6 filas sin duplicados. La prueba remota dentro de una
transacción revertida aceptó seis staging y seis snapshots, sin cambiar el
contrato de evidencia.

La migración `20260923151217` y el lote se aplicaron a Supabase. La RPC pública
`online_prices_v4` confirmó los seis productos, en MXN, con sucursal y distancia
nulas. La búsqueda local cerca de Monterrey no devuelve esta fuente. Cuatro
productos tienen imagen dentro de la ruta CDN verificada; dos quedan sin imagen.
Una repetición del mismo SQL dentro de una transacción revertida reutilizó seis
filas de staging e insertó cero snapshots. Los siete SHA256 de los recibos
coinciden con sus respuestas archivadas.

Validación de código: 14 pruebas Python (incluidas las ocho existentes de
`online_catalog`), tres pruebas Flutter del runner y análisis Dart sin errores.
Comprobación pública guardada en
`/tmp/tiago-merco-20260923-rpc-verification.json`.

## Otros candidatos revisados

- Soriana: HTTP 403 en `robots.txt` desde este entorno; no se capturaron fichas.
- La Comer: `Disallow: /` para el crawler genérico; no se capturaron fichas.
- Alsuper: la ficha consultada respondió 200, pero no aportó una oferta
  `Product/Offer` verificable al parser HTML. No se publicaron precios.
- Super Kompras: `/robots.txt` devolvió HTML de la aplicación, no reglas robots.
  No se validó ni incorporó una fuente.

Estas observaciones describen este entorno y esta fecha; no implican que las
fuentes sean inaccesibles por todos los medios o permanentemente.
