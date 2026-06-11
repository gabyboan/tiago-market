# Roadmap

## 1. Validación de scraping con mock y un supermercado

- [x] Ejecutar el flujo completo con datos mock.
- [x] Integrar QQP PROFECO como primera fuente real.
- [x] Validar calidad inicial, fechas y frecuencia conservadora.
- [ ] Evaluar nuevas fuentes autorizadas o acuerdos de datos.

## 2. Guardado en Supabase

- [x] Aplicar migraciones en un entorno de desarrollo.
- [x] Guardar mock y una muestra de precios reales.
- [ ] Medir duplicados, fallos y crecimiento del histórico.
- [ ] Automatizar el job con frecuencia conservadora.

## 3. API de comparación

- [x] Exponer búsqueda y comparación inicial.
- [ ] Validar búsquedas y equivalencias de productos.
- [ ] Agregar paginación, autenticación y límites de uso.
- [ ] Documentar el contrato de API.

## 4. API pública y automatización

- Desplegar la API con una URL estable.
- Automatizar la actualización periódica de precios.
- Agregar monitoreo, límites de uso y alertas.

## 5. Prototipo Flutter

- Consumir exclusivamente la API propia.
- Implementar búsqueda y comparación por tienda/sucursal.
- Mostrar fuente y fecha de última actualización.
- Diseñar favoritos, listas y alertas para fases posteriores.
- No conectar Flutter directamente a Supabase.

## 6. Publicación Play Store/App Store

- Preparar privacidad, términos, analítica y procesos de publicación.

## 7. Monitoreo y mantenimiento

- Alertar por fallos y cambios de selectores.
- Revisar calidad de datos y restricciones de fuentes mensualmente.
- Medir costos, rendimiento y cobertura.
