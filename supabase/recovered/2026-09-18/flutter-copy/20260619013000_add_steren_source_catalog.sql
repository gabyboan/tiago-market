insert into ingestion.source_catalog (
  source_slug,
  country_code,
  store_brand,
  vertical,
  capture_scope,
  geolocatable,
  priority,
  status,
  official_domain,
  robots_url,
  notes
) values (
  'steren-mx',
  'MX',
  'Steren',
  'electronica',
  'online',
  false,
  11,
  'active',
  'steren.com.mx',
  'https://www.steren.com.mx/robots.txt',
  'Conector por sitemap/ficha oficial; captura precios online Mexico sin branch_id.'
)
on conflict (source_slug) do update set
  country_code = excluded.country_code,
  store_brand = excluded.store_brand,
  vertical = excluded.vertical,
  capture_scope = excluded.capture_scope,
  geolocatable = excluded.geolocatable,
  priority = excluded.priority,
  status = excluded.status,
  official_domain = excluded.official_domain,
  robots_url = excluded.robots_url,
  notes = excluded.notes,
  updated_at = now();
