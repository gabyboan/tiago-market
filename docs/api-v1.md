# API v1 para Flutter

La aplicación Flutter debe consumir únicamente rutas bajo `/api/v1`.

## Despliegue activo

La API pública está desplegada como Supabase Edge Function:

```text
https://fxxtjgalaiiwjpqhzahk.supabase.co/functions/v1/api
```

Flutter debe compilarse con esa dirección como `API_BASE_URL`.

La función también expone:

- `GET /api/v1/categories`: categorías y cantidad de precios.
- `GET /api/v1/branches?lat=...&lng=...&radius_km=...`: sucursales verificadas.
- `POST /api/v1/feedback`: comentarios voluntarios de pruebas.
- `GET /privacy`: política pública de privacidad.

## Formato de respuesta

Respuesta exitosa:

```json
{
  "data": [],
  "meta": {
    "apiVersion": "v1",
    "page": 1,
    "limit": 20,
    "total": 88,
    "totalPages": 5
  }
}
```

Respuesta de error:

```json
{
  "error": {
    "code": "INVALID_QUERY",
    "message": "Los parámetros de consulta no son válidos."
  },
  "meta": {
    "apiVersion": "v1"
  }
}
```

## Paginación

Los endpoints de listas aceptan:

- `page`: entero desde `1`, predeterminado `1`.
- `limit`: entero entre `1` y `50`, predeterminado `20`.

## Endpoints

### `GET /api/v1/health`

Estado y versión del servicio.

### `GET /api/v1/prices`

Últimos precios observados guardados. `query` es opcional: sin ese parámetro
devuelve el catálogo paginado completo. No ejecuta scraping durante la búsqueda.
Cada resultado incluye:

- `product_name` y `normalized_name`;
- `store_name` y `branch_name`;
- `price` y `currency`;
- `source` y `captured_at`;
- `freshness`: `fresh`, `stale` u `old`;
- `days_old`.
- `store_product_url`: ficha oficial verificable de tienda, cuando existe.
- `image_url`: imagen publicada por la tienda, cuando existe.
- domicilio y coordenadas de sucursal cuando estén disponibles.
- `distance_km` cuando se envían coordenadas.

Parámetros:

- `query`: opcional; busca por nombre normalizado.
- `store`: slug opcional de cadena.
- `source`: fuente directa opcional, por ejemplo `arteli-direct`.
- `available`: opcional, `true` o `false`.
- `page` y `limit`.
- `lat` y `lng`: coordenadas opcionales; deben enviarse juntas.
- `radius_km`: radio entre `0` y `100`, predeterminado `10`.
- `order_by`: `price` o `distance`.

Ejemplo:

```text
/api/v1/prices?query=coca&source=arteli-direct&page=1&limit=10
```

### `GET /api/v1/compare`

Mismos parámetros que `/prices`. Compara y conserva cada sucursal/listing,
ordena por precio ascendente y agrega `best_price` y `price_rank`.

```text
/api/v1/compare?query=leche&store=wal-mart
```

### `GET /api/v1/stores`

Cadenas activas. Acepta `query`, `page` y `limit`.

### `GET /api/v1/branches`

Lista sucursales normalizadas, domicilio, ciudad, coordenadas opcionales y
`geocoding_status`, proveedor, confianza y precisión. Acepta `query`,
`city_code`, `page` y `limit`.

### `GET /api/v1/nearby`

Busca precios observados dentro de un radio. Requiere `query`, `lat` y `lng`;
acepta `radius_km`, `order_by`, `store`, `source`, `page` y `limit`.

Solo devuelve sucursales `geocoded` o `manual`; excluye resultados `review`.

### `GET /api/v1/products`

Catálogo interno. Acepta `query`, `category`, `page` y `limit`.

### `GET /api/v1/coverage`

Resumen real de cobertura, incluyendo:

- `total_products`, `total_stores`, `total_branches`;
- `total_price_snapshots`;
- `latest_snapshot_at` y `oldest_snapshot_at`;
- `snapshots_by_source`, `products_by_source`, `stores_by_source`;
- `city_code`;
- `source_health`.
- `total_normalized_branches`, `total_geocoded_branches` y
  `total_pending_geocoding`.

### `GET /api/v1/sources`

Lista las fuentes directas habilitadas y las candidatas deshabilitadas. Cada
fuente informa `enabled`, `mode`, motivo cuando aplica, `latest_snapshot_at` y
`total_snapshots`.

Arteli y Smart & Final México son fuentes directas habilitadas.

### `GET /api/v1/quality`

Devuelve métricas de confianza de las fuentes directas: cobertura, imágenes,
enlaces oficiales, precios frescos, antiguos e implausibles.

## Freshness

- `fresh`: menos de 7 días.
- `stale`: entre 7 y 21 días.
- `old`: más de 21 días.

## Códigos de error

- `INVALID_QUERY`: parámetros inválidos.
- `NOT_FOUND`: endpoint inexistente.
- `RATE_LIMIT_EXCEEDED`: demasiadas solicitudes.
- `DATABASE_ERROR`: error consultando datos.
- `INTERNAL_ERROR`: error inesperado.

## Reglas para Flutter

- No almacenar ni incluir claves secretas de Supabase.
- Usar Supabase directamente solo para Auth con una clave pública `publishable`;
  consultar los datos de negocio exclusivamente mediante la API propia.
- No ejecutar scraping.
- Mostrar siempre `captured_at`, fuente y freshness junto al precio.
- Advertir al usuario cuando `freshness` sea `old`.
- No describir las observaciones guardadas como precios en tiempo real.
- Solicitar ubicación solo ante una acción explícita del usuario.
- No persistir ni registrar coordenadas precisas del usuario.
- Manejar paginación y respuestas vacías.
- Etiquetar claramente los enlaces oficiales de tienda.
