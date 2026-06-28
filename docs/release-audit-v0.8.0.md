# Auditoría de publicación v0.8.0

**Fecha de corte:** 27 de junio de 2026

**Aplicación Flutter:** `0.2.1+3`

**Alcance:** código, build Android, configuración local, historial Git,
dependencias, pruebas, documentación e ingesta Supabase.

## Resultado ejecutivo

La versión deja una demo Android reproducible y el avance técnico documentado,
sin publicar claves privadas ni afirmar coberturas no verificadas. El cliente
Flutter separa precios locales de referencias online, y la ingesta rechaza
evidencia incompleta antes de producir SQL.

El repositorio puede hacerse público con estas salvedades:

- `dart_defines.local.json`, `.env`, keystores y configuraciones Firebase
  locales permanecen ignorados;
- la clave `service_role` sólo se usa en backend y workflows;
- el historial contiene una configuración Firebase Android anterior. Sus API
  keys de cliente no autentican por sí solas, pero deben mantenerse restringidas
  por aplicación/API en Google Cloud;
- la APK release de esta etapa usa firma debug porque no existe un keystore de
  producción local. Sirve para demostración y pruebas, no para Play Store;
- la migración nueva se entrega revisada, pero no se aplicó a una base remota.

## Qué quedó implementado

### Flutter

- onboarding, invitado y Google Auth opcional con Supabase;
- búsqueda, categorías, ordenamiento, ubicación y radio;
- fallback controlado desde resultados por sucursal hacia precios online;
- favoritos, historial y lista de compras persistente;
- avisos claros sobre alcance, frescura y evidencia;
- configuración de release por `dart-define` usando sólo URL, clave publicable y
  IDs de cliente OAuth.

### Ingesta y datos

- scraper Home Depot con límites globales/por término, reintentos acotados,
  backoff y resumen de rechazos;
- probe pasivo de Chedraui que respeta `robots.txt` y clasifica bloqueos sin
  persistir datos;
- staging NDJSON con validación estricta, reporte agregado, dry-run SQL y
  deduplicación por `source + content_hash`;
- migración idempotente para separar observaciones online y por sucursal;
- reporte SQL de cobertura, frescura, calidad y bloqueos por fuente.

## Evidencia disponible

- Home Depot México: 18 de 18 filas del probe controlado aceptadas como
  publicables para tres sucursales; la carga comercial completa no se ejecutó.
- Chedraui: precio online visible, pero la prueba por sucursal quedó bloqueada
  por HTTP 429; no se clasifica como fuente local.
- Steren: catálogo online verificable, pero las rutas de inventario local están
  restringidas o no documentadas; permanece `online_only`.
- H-E-B: el preflight se detuvo por restricciones expresas de uso; no se creó
  scraper.

La evidencia, comandos, límites y riesgos están desarrollados en:

- [`data-ingestion-v1-runbook.md`](../apps/flutter_app/docs/data-ingestion-v1-runbook.md)
- [`mx-retailer-data-capability-verdict.md`](../apps/flutter_app/docs/mx-retailer-data-capability-verdict.md)
- [`second-chain-evaluation.md`](../apps/flutter_app/docs/second-chain-evaluation.md)

## Seguridad revisada

- sin `.env`, keystore, `key.properties`, claves privadas ni `service_role`
  dentro del cliente;
- variables Flutter limitadas a configuración pública incorporada en build;
- endpoints de perfil/rol cambiados de un `x-user-id` confiado a validación de
  `Authorization: Bearer <token>` mediante Supabase Auth;
- RLS y permisos de tablas sensibles permanecen cerrados al cliente;
- índice parcial único para staging y claves distintas para capturas online y
  por sucursal;
- escaneo de nombres y patrones sensibles sobre el árbol actual y el historial.

## Validaciones ejecutadas

- `flutter analyze`;
- `flutter test` — 43 tests;
- `npm test` — 22 tests;
- `npm run build`;
- `npm run lint`;
- `npm audit`;
- revisión de formato y secretos antes del commit;
- build APK release con `dart-define` local.

## Artefacto Android verificado

- archivo: `tiago-market-v0.8.0-android.apk`;
- application ID: `com.tiagomarket.tiago_market_app`;
- version name: `0.2.1`;
- version code: `3`;
- SHA-256:
  `3b79bba6168826773fd25e89153bed3d2467e1c4baa2e076aa41bbae5ff6264f`;
- firma: certificado Android Debug, apto sólo para demo/pruebas.

## Pendiente explícito

- aplicar y verificar la migración en un proyecto Supabase controlado;
- ejecutar el reporte de cobertura contra la base remota;
- probar login/cierre de sesión Google extremo a extremo;
- configurar App Links/Universal Links;
- crear y custodiar un keystore de producción;
- repetir el probe Home Depot después del ajuste de límite por término;
- revisar manualmente categorías antes de publicar el primer lote comercial;
- restringir/rotar la API key Firebase histórica si la consola no tiene las
  restricciones esperadas.
