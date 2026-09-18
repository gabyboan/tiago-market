update ingestion.source_catalog
set
  capture_scope = 'online',
  geolocatable = false,
  status = 'active',
  notes = concat_ws(
    ' ',
    notes,
    'Conector inicial por sitemap/ficha oficial; captura precios online sin branch_id.'
  ),
  updated_at = now()
where source_slug = 'chedraui-mx';
