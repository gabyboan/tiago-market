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
- [x] Automatizar el job con frecuencia conservadora.

## 3. API de comparación

- [x] Exponer búsqueda y comparación inicial.
- [ ] Validar búsquedas y equivalencias de productos.
- [x] Agregar paginación y límites de uso.
- [x] Documentar el contrato de API.
- [ ] Definir autenticación antes de publicar Flutter.

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
- [x] No conectar Flutter directamente a Supabase.

## 6. Publicación Play Store/App Store

- Preparar privacidad, términos, analítica y procesos de publicación.

## 7. Monitoreo y mantenimiento

- Alertar por fallos y cambios de selectores.
- Revisar calidad de datos y restricciones de fuentes mensualmente.
- Medir costos, rendimiento y cobertura.
