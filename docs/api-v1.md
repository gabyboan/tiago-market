# API v1 para Flutter

La aplicación Flutter debe consumir únicamente rutas bajo `/api/v1`.

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

Últimos precios guardados.

Parámetros:

- `query`: obligatorio; busca por nombre normalizado.
- `store`: slug opcional de cadena.
- `source`: fuente opcional, actualmente `profeco`.
- `available`: opcional, `true` o `false`.
- `page` y `limit`.

Ejemplo:

```text
/api/v1/prices?query=coca&source=profeco&page=1&limit=10
```

### `GET /api/v1/compare`

Mismos parámetros que `/prices`. Ordena por ranking de precio.

```text
/api/v1/compare?query=leche&store=wal-mart
```

### `GET /api/v1/stores`

Cadenas activas. Acepta `query`, `page` y `limit`.

### `GET /api/v1/products`

Catálogo interno. Acepta `query`, `category`, `page` y `limit`.

### `GET /api/v1/coverage`

Cobertura disponible por producto, incluyendo:

- cantidad de cadenas;
- cantidad de listados/sucursales;
- fuentes;
- observación más antigua y última actualización.

Acepta `query`, `category`, `page` y `limit`.

## Códigos de error

- `INVALID_QUERY`: parámetros inválidos.
- `NOT_FOUND`: endpoint inexistente.
- `RATE_LIMIT_EXCEEDED`: demasiadas solicitudes.
- `DATABASE_ERROR`: error consultando datos.
- `INTERNAL_ERROR`: error inesperado.

## Reglas para Flutter

- No almacenar ni incluir claves de Supabase.
- No consultar Supabase directamente.
- No ejecutar scraping.
- Mostrar siempre `last_updated_at` junto al precio.
- Tratar los precios PROFECO como referencias por sucursal.
- Manejar paginación y respuestas vacías.
