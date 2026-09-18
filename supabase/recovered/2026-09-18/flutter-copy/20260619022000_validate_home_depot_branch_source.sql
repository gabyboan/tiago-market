update ingestion.source_catalog
set
  capture_scope = 'branch',
  geolocatable = true,
  status = 'validated',
  notes = 'Validado con endpoints publicos oficiales: storelocator por coordenadas devuelve sucursal con storeName, uniqueID, direccion y lat/lon; search/resources/api/v2/products permite precio por physicalStoreId y stock por uniqueID. Usar con rate limit y review antes de publicar.',
  updated_at = now()
where source_slug = 'home-depot-mx';
