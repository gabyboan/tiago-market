# Notas de scraping

## Principios

- El scraping puede romperse cuando cambian los sitios.
- Cada fuente necesita validación propia y mantenimiento periódico.
- Hay que revisar los términos de uso y restricciones antes de activar una
  fuente.
- No se implementan bypass de CAPTCHA, login privado ni protecciones anti-bot.
- Se usan tiempos de espera razonables y una frecuencia conservadora.

## Arquitectura

Cada supermercado tiene un módulo independiente que devuelve `ScraperResult`.
Un fallo se registra y no detiene los demás productos o fuentes.

La app web o móvil no debe scrapear ni disparar scraping en tiempo real. Un job
actualiza PostgreSQL/Supabase y la API consulta los precios guardados, incluyendo
la fecha de última actualización.

## Activar una fuente real

1. Revisar términos, robots y restricciones de la fuente.
2. Confirmar manualmente URL de búsqueda y selectores.
3. Implementar extracción y validación con `zod` si corresponde.
4. Probar con pocos productos y baja frecuencia.
5. Medir errores, bloqueos y calidad de resultados.
6. Agregar el scraper a `activeScrapers` en `src/jobs/update-prices.ts`.

Debe contemplarse una revisión mensual, además de alertas ante fallos repetidos.
