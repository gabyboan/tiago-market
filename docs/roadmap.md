# Roadmap

## Etapa 0.7: catálogo amplio y enlaces verificables

- [x] Permitir listar precios sin búsqueda obligatoria.
- [x] Crear importador masivo PROFECO con deduplicación.
- [x] Crear productos desde nombres observados reales.
- [x] Agregar paginación incremental en Flutter.
- [x] Separar enlaces de observación y fichas oficiales de tienda.
- [x] Mantener nulos los enlaces directos que no puedan verificarse.
- [x] Auditar repositorios externos propuestos como referencias.
- [ ] Evaluar fuentes directas autorizadas para obtener fichas oficiales.

## Etapa 0.6: geocodificación auditable

- [x] Integrar Mapbox Geocoding v6 en modo permanente.
- [x] Agregar job idempotente y modo `dry_run`.
- [x] Conservar consulta, confianza, precisión, respuesta y errores.
- [x] Separar resultados aceptados, ambiguos y fallidos.
- [x] Excluir resultados ambiguos de `/nearby`.
- [ ] Configurar cuenta/token Mapbox autorizado.
- [ ] Ejecutar geocodificación real y revisar resultados ambiguos.

## Etapa 0.5: sucursales y geolocalización

- [x] Normalizar sucursales y domicilios PROFECO.
- [x] Preparar coordenadas opcionales y estado de geocodificación.
- [x] Exponer `/branches` y `/nearby`.
- [x] Filtrar `/prices` y `/compare` por ubicación y radio.
- [x] Mostrar distancia y controles de ubicación en Flutter.
- [x] No persistir la ubicación precisa del usuario.
- [ ] Elegir y validar proveedor autorizado de geocodificación.
- [ ] Geocodificar las 32 sucursales pendientes y revisar precisión.

## Etapa 0.4: calidad PROFECO y preparación Flutter

- [x] Conservar snapshot auditable con fuente, captura y payload original.
- [x] Exponer freshness y antigüedad en precios y comparación.
- [x] Comparar por sucursal/listing sin perder contexto.
- [x] Exponer cobertura real y estado de fuentes.
- [x] Mostrar fuente, antigüedad y advertencia de precio antiguo en Flutter.
- [x] Mantener Walmart y Soriana directos desactivados.
- [ ] Aplicar la migración 005 en producción y desplegar la API 0.4.

## 1. Validación de scraping con mock y un supermercado

- [x] Ejecutar el flujo completo con datos mock.
- [x] Integrar QQP PROFECO como primera fuente real.
- [x] Validar calidad inicial, fechas y frecuencia conservadora.
- [ ] Evaluar nuevas fuentes autorizadas o acuerdos de datos.

## 2. Guardado en Supabase

- [x] Aplicar migraciones en un entorno de desarrollo.
- [x] Guardar mock y una muestra de precios reales.
- [ ] Medir duplicados, fallos y crecimiento del histórico.
- [x] Automatizar el job con frecuencia conservadora.

## 3. API de comparación

- [x] Exponer búsqueda y comparación inicial.
- [ ] Validar búsquedas y equivalencias de productos.
- [x] Agregar paginación y límites de uso.
- [x] Documentar el contrato de API.
- [ ] Definir autenticación antes de publicar Flutter.
- [x] Exponer fuente, sucursal, fecha, freshness y ranking.

## 4. API pública y automatización

- [ ] Desplegar la API con una URL estable.
- [x] Automatizar la actualización periódica de precios.
- [ ] Agregar monitoreo y alertas.

## 5. Prototipo Flutter

- [x] Crear demo mínima con búsqueda y comparación.
- [x] Preparar consumo exclusivo de la API propia.
- [x] Mostrar fuente y fecha de última actualización.
- [ ] Conectar la demo a la URL pública de producción.
- [ ] Diseñar favoritos, listas y alertas para fases posteriores.
- [x] No conectar Flutter directamente a las tablas de negocio de Supabase.
- [ ] Validar Google OAuth de extremo a extremo con credenciales reales.
- [x] Crear proyecto Google Cloud dedicado y documentar Google Auth Platform.
- [ ] Configurar App Links/Universal Links antes de publicar las apps móviles.

## 6. Publicación Play Store/App Store

- Preparar privacidad, términos, analítica y procesos de publicación.

## 7. Monitoreo y mantenimiento

- Alertar por fallos y cambios de selectores.
- Revisar calidad de datos y restricciones de fuentes mensualmente.
- Medir costos, rendimiento y cobertura.
