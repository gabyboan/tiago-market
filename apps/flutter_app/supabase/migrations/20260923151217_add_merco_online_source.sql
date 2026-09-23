-- Public online catalog for Monterrey. No physical branch attribution.
insert into ingestion.source_catalog (
  source_slug, country_code, store_brand, vertical, capture_scope,
  geolocatable, priority, status, official_domain, robots_url, notes
) values (
  'merco-mx', 'MX', 'Merco Monterrey', 'supermercado', 'online',
  false, 12, 'validated', 'adomicilio.merco.mx',
  'https://adomicilio.merco.mx/robots.txt',
  'Fichas publicas Product/Offer en MXN del catalogo Merco Monterrey. Sin sucursal seleccionada; solo online. Captura acotada, secuencial, con evidencia HTTP y sin reintentos ante bloqueos.'
)
on conflict (source_slug) do nothing;
