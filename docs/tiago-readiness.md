# Tiago Market: readiness para piloto

> **Documento histórico de julio.** Para el estado vigente ver [auditoría del 22/09/2026](estado-2026-09-22.md). Las RPC v2 ya están disponibles y existe un lote Home Depot del 21/09; siguen pendientes calidad de datos, cobertura de supermercados y firma. Las afirmaciones de validación de favoritos/lista de este documento no se sostienen en el código actual.

**Última revisión:** 26 de julio de 2026

**Rama auditada:** `codex/release-tiago-market-v0.8.0` / PR #5

**Objetivo:** piloto Android con precios reales por sucursal; no Play Store.

## Bloqueantes reales

- La migración que crea `nearby_prices_v2` y `online_prices_v2` está validada
  contra el esquema real con `ROLLBACK`, pero todavía no está aplicada. La app
  de esta PR depende de ese contrato antes de una prueba conectada.
- La cobertura comercial todavía es estrecha: hay una fuente local confirmada
  y el primer lote curado no fue publicado. Chedraui, Steren y H-E-B no son
  fuentes locales habilitadas.
- El workflow firmado está preparado, pero no puede certificarse de extremo a
  extremo hasta configurar un keystore de piloto y los secretos del repositorio.
- La PR todavía no tiene checks remotos obligatorios; la validación realizada en
  esta rama fue local y contra RPC pública/DB remota de forma reversible.

## Riesgos de datos

- La cobertura puede degradarse a cero si una fuente deja de entregar branch,
  disponibilidad, fecha o evidencia. La app ahora lo muestra como “sin precios
  confiables” en vez de relajar el contrato.
- Los datos `stale` de 7 a 21 días se permiten con advertencia; más de 21 días se
  descartan. Para productos volátiles, el piloto puede necesitar un umbral más
  estricto por categoría.
- Los favoritos anteriores a esta versión no tienen snapshot de evidencia y no
  pueden agregarse a la lista hasta buscarlos nuevamente.
- La prueba pública de CDMX respondió con 46 sucursales válidas y un resultado
  local reciente para la consulta controlada, pero la RPC omitió
  `available` y URLs. La RPC `v2` corrige ese contrato y, dentro de la prueba
  transaccional, devolvió cero filas inválidas. Esto confirma infraestructura,
  no cobertura suficiente para un piloto abierto.

## Riesgos de seguridad

- No se detectaron secretos o `service_role` en el cliente actual. Las tablas
  `price_snapshots`, `store_products`, `branches` y `user_feedback` rechazaron
  acceso directo con la clave pública (HTTP 401).
- La app usa RPC públicas para precios; el backend y workflows son los únicos
  consumidores previstos de `service_role`.
- El historial contiene un `google-services.json` cliente. No es una credencial
  de servidor, pero su API key debe estar restringida por aplicación y API.
- Las funciones públicas son `security definer`; hoy revocan `PUBLIC` y
  conceden sólo `anon`/`authenticated`, pero cualquier cambio futuro debe
  mantener `search_path` vacío y grants mínimos.
- El advisor remoto marca como advertencia esperada que las RPC de catálogo son
  `security definer` ejecutables por invitados. Es una decisión funcional para
  búsqueda pública, pero exige límites estrictos, contrato de sólo lectura y
  monitoreo de abuso antes de ampliar el piloto.
- El advisor remoto también informa `pg_trgm` en `public` y protección de
  contraseñas filtradas desactivada. No bloquean la prueba de precios, pero deben
  resolverse antes de una apertura general de cuentas.

## Qué está listo

- Separación entre ingesta, tablas protegidas y RPC de lectura controlada.
- Sucursales geocodificadas reales y consulta por distancia operativa.
- Validación cliente de tienda, branch, disponibilidad, moneda, fecha, frescura
  y fuente antes de agrupar o sumar precios.
- Fallback online visible y separado; no se agrega como compra en sucursal.
- RLS activa, tablas sensibles cerradas y la suite Flutter/backend en verde.
- Ingesta con preflight, evidencia, idempotencia y documentación de fuentes.
- APK de demostración reproducible con `dart-define` público.
- Release `0.2.2+4` separado de debug: sin keystore real, Gradle falla. El
  workflow manual genera y verifica APK/AAB firmados sin publicar en Play.

## Qué no está listo para piloto

- Ejecutar una prueba conectada sin aplicar la migración RPC `v2`.
- Publicar el lote Home Depot sin aplicar la migración, corregir
  categorías y ejecutar el reporte de cobertura remoto.
- Distribuir una build firmada hasta ejecutar el workflow con un keystore de
  piloto y verificar el artefacto resultante.
- Declarar cobertura general: el piloto debe limitar zona, fuentes y productos
  a evidencia efectivamente cargada y reciente.

## Puerta de entrada al piloto

El piloto puede empezar sólo cuando: la RPC endurecida esté aplicada; la app
descarte filas ambiguas o vencidas; exista al menos un lote curado y verificable
por sucursal; el reporte remoto confirme cobertura/frescura; y el APK/AAB se
genere con una clave de firma de piloto custodiada fuera de Git.
