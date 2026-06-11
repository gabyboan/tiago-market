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

## 4. Demo web

- Crear una interfaz simple de búsqueda y comparación.
- Mostrar disponibilidad y fecha de última actualización.

## 5. App Flutter

- Consumir exclusivamente la API propia.
- Diseñar favoritos, listas y alertas.

## 6. Publicación Play Store/App Store

- Preparar privacidad, términos, analítica y procesos de publicación.

## 7. Monitoreo y mantenimiento

- Alertar por fallos y cambios de selectores.
- Revisar calidad de datos y restricciones de fuentes mensualmente.
- Medir costos, rendimiento y cobertura.
