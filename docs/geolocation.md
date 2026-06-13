# Geolocalización

## Estado actual

PROFECO QQP aporta domicilio, pero no latitud ni longitud. Tiago Market
normaliza esa información en `branches` y usa Mapbox Geocoding v6 para preparar
coordenadas auditables.

La integración usa `permanent=true`, porque las coordenadas y la respuesta deben
conservarse. Mapbox exige una tarjeta válida o contrato empresarial para
almacenamiento permanente.

Referencia oficial:

- [Mapbox Geocoding API](https://docs.mapbox.com/api/search/geocoding/)
- [Almacenamiento de resultados](https://docs.mapbox.com/api/search/geocoding/#storing-geocoding-results)

## Configuración

El modo predeterminado es `dry_run`: muestra las consultas, pero no llama al
proveedor.

```dotenv
GEOCODING_MODE=dry_run
MAPBOX_ACCESS_TOKEN=
GEOCODING_BRANCH_LIMIT=10
GEOCODING_REQUEST_DELAY_MS=1100
GEOCODING_MIN_CONFIDENCE=0.8
```

Para una ejecución real:

```dotenv
GEOCODING_MODE=live
MAPBOX_ACCESS_TOKEN=<token>
```

```bash
pnpm geocode:branches
```

También existe el workflow manual `Geocode branches`. Requiere los secretos
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y `MAPBOX_ACCESS_TOKEN`.

## Clasificación

- `geocoded`: supera el umbral y puede aparecer en `/nearby`.
- `review`: resultado ambiguo; conserva la respuesta para revisión, pero no publica coordenadas.
- `failed`: sin resultado o error del proveedor; puede reintentarse.
- `manual`: coordenada validada manualmente; puede aparecer en `/nearby`.

Cada intento conserva proveedor, consulta, confianza, precisión, identificador,
respuesta, error y cantidad de intentos.

## Carga manual

```sql
update public.branches
set
  latitude = 19.432600,
  longitude = -99.133200,
  geocoding_status = 'manual',
  geocoded_at = now(),
  updated_at = now()
where id = '<branch-id>';
```

## Privacidad

La API recibe la ubicación del usuario únicamente como parámetros de consulta.
No se guarda en PostgreSQL ni debe incluirse en logs de aplicación o analítica.
