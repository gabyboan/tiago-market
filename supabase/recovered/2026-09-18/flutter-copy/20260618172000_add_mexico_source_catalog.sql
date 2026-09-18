create table if not exists ingestion.source_catalog (
  source_slug text primary key,
  country_code text not null check (country_code = 'MX'),
  store_brand text not null,
  vertical text not null,
  capture_scope text not null default 'unknown'
    check (capture_scope in (
      'unknown',
      'online',
      'national',
      'city',
      'postal_code',
      'branch'
    )),
  geolocatable boolean not null default false,
  priority integer not null default 100 check (priority > 0),
  status text not null default 'candidate'
    check (status in ('candidate', 'validated', 'active', 'blocked')),
  official_domain text,
  robots_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists source_catalog_priority_idx
  on ingestion.source_catalog (country_code, priority, status);

revoke all on ingestion.source_catalog from anon, authenticated;
grant all on ingestion.source_catalog to service_role;

insert into ingestion.source_catalog (
  source_slug,
  country_code,
  store_brand,
  vertical,
  capture_scope,
  geolocatable,
  priority,
  official_domain,
  robots_url,
  notes
) values
  (
    'chedraui-mx',
    'MX',
    'Chedraui',
    'supermercado',
    'unknown',
    true,
    1,
    'chedraui.com.mx',
    'https://www.chedraui.com.mx/robots.txt',
    'Priorizar si se puede resolver precio por sucursal o zona.'
  ),
  (
    'soriana-mx',
    'MX',
    'Soriana',
    'supermercado',
    'unknown',
    true,
    2,
    'soriana.com',
    'https://www.soriana.com/robots.txt',
    'Validar disponibilidad local antes de capturar precios.'
  ),
  (
    'bodega-aurrera-mx',
    'MX',
    'Bodega Aurrera',
    'supermercado-descuento',
    'unknown',
    true,
    3,
    'bodegaaurrera.com.mx',
    'https://www.bodegaaurrera.com.mx/robots.txt',
    'Usar solo catalogo Mexico; validar precio por CP/sucursal.'
  ),
  (
    'walmart-mx',
    'MX',
    'Walmart Mexico',
    'supermercado',
    'unknown',
    true,
    4,
    'walmart.com.mx',
    'https://www.walmart.com.mx/robots.txt',
    'Validar si comparte backend con Bodega Aurrera y si permite precio local.'
  ),
  (
    'farmacias-guadalajara-mx',
    'MX',
    'Farmacias Guadalajara',
    'farmacia',
    'unknown',
    true,
    5,
    'farmaciasguadalajara.com',
    'https://www.farmaciasguadalajara.com/robots.txt',
    'Buen complemento para farmacia, higiene y abarrotes ligeros.'
  ),
  (
    'farmacias-del-ahorro-mx',
    'MX',
    'Farmacias del Ahorro',
    'farmacia',
    'unknown',
    true,
    6,
    'farmaciasdelahorro.com.mx',
    'https://www.farmaciasdelahorro.com.mx/robots.txt',
    'Validar fuente por sucursal y politicas antes de scrapear.'
  ),
  (
    'oxxo-mx',
    'MX',
    'OXXO',
    'conveniencia',
    'unknown',
    false,
    7,
    'oxxo.com',
    'https://www.oxxo.com/robots.txt',
    'Candidato para conveniencia; revisar si existen precios publicos comparables.'
  ),
  (
    'seven-eleven-mx',
    'MX',
    '7-Eleven Mexico',
    'conveniencia',
    'unknown',
    false,
    8,
    '7-eleven.com.mx',
    'https://www.7-eleven.com.mx/robots.txt',
    'Validar cobertura y precios publicos en Mexico.'
  ),
  (
    'coppel-mx',
    'MX',
    'Coppel',
    'departamental',
    'unknown',
    true,
    9,
    'coppel.com',
    'https://www.coppel.com/robots.txt',
    'Util para electronica, hogar y ropa; mantener separado de supermercado.'
  ),
  (
    'home-depot-mx',
    'MX',
    'The Home Depot Mexico',
    'hogar-ferreteria',
    'unknown',
    true,
    10,
    'homedepot.com.mx',
    'https://www.homedepot.com.mx/robots.txt',
    'Util para abrir vertical hogar y ferreteria con disponibilidad local.'
  )
on conflict (source_slug) do update set
  country_code = excluded.country_code,
  store_brand = excluded.store_brand,
  vertical = excluded.vertical,
  capture_scope = excluded.capture_scope,
  geolocatable = excluded.geolocatable,
  priority = excluded.priority,
  official_domain = excluded.official_domain,
  robots_url = excluded.robots_url,
  notes = excluded.notes,
  updated_at = now();
