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

## Primera fuente real: QQP PROFECO

`src/scrapers/profeco.ts` consulta la API pública de Quién es Quién en los
Precios. Se eligió porque el servicio existe para difundir y comparar precios,
su `robots.txt` no restringe el acceso y expone fechas de observación.

La integración:

- consulta una ciudad configurable;
- normaliza unidades antes de filtrar;
- conserva la cadena y sucursal observadas;
- limita resultados y espera entre solicitudes;
- usa la fecha de observación publicada por PROFECO;
- no requiere credenciales privadas.

Walmart, Soriana, Chedraui y La Comer no se activaron como scrapers directos:
durante la validación sus reglas públicas o respuestas bloquearon o restringieron
la automatización. PROFECO permite obtener observaciones de varias de estas
cadenas sin evadir sus protecciones.

## Activar una fuente real

1. Revisar términos, robots y restricciones de la fuente.
2. Confirmar manualmente URL de búsqueda y selectores.
3. Implementar extracción y validación con `zod` si corresponde.
4. Probar con pocos productos y baja frecuencia.
5. Medir errores, bloqueos y calidad de resultados.
6. Crear un job explícito y conservador para activar el scraper.

Debe contemplarse una revisión mensual, además de alertas ante fallos repetidos.
