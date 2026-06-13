# Notas de scraping

## Fuentes directas activas

- Arteli: catálogo oficial VTEX.
- Smart & Final México: Store API oficial de WooCommerce.
- Calimax: estado estructurado publicado por su tienda.
- Chedraui: catálogo oficial VTEX y directorio público de puntos de retiro.
- H-E-B México: catálogo oficial VTEX.

La app muestra precios online cuando la fuente no publica una asociación
verificable entre precio y sucursal. Las sucursales físicas de Chedraui se
guardan con coordenadas, pero no se atribuyen precios locales sin evidencia.

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

La aplicación Flutter no debe scrapear ni disparar scraping en tiempo real.
Puede acceder a Supabase Auth con una clave pública, pero consulta los precios
guardados exclusivamente mediante la API propia.

Las fuentes históricas o indirectas no se publican en el comparador. Cada precio
visible debe provenir directamente de la tienda y conservar una ficha oficial
verificable. La migración `012_remove_profeco.sql` elimina los datos indirectos
y demo existentes.

## Fuentes directas verificables

### Arteli online

`src/scrapers/arteli.ts` consulta conservadoramente el catálogo público estructurado
de Arteli y conserva la ficha oficial del producto en `store_product_url`.
La integración obtiene nombre, EAN, precio, existencia e imagen sin iniciar
sesión ni evadir controles técnicos.

El precio se identifica como `Arteli online` y no se asigna a una sucursal:
la respuesta pública consultada no demuestra que corresponda a una tienda física
o ubicación específica. Antes de ampliar frecuencia o cobertura debe revisarse
periódicamente la estabilidad, reglas públicas y calidad del catálogo.

### Smart & Final México online

`src/scrapers/smart-final.ts` consulta la API pública de tienda WooCommerce y
conserva la ficha oficial en `store_product_url`. Valida moneda MXN, convierte
los precios publicados en unidades menores, exige disponibilidad y filtra
presentaciones o variantes no comparables.

El precio se identifica como `Smart & Final México online`. Tampoco se asigna a
una sucursal porque la respuesta pública no demuestra una ubicación concreta.
La API marca productos con existencia pero no comprables en línea; ese indicador
se conserva para auditoría y no se interpreta como ausencia de precio.

### Calimax online

`src/scrapers/calimax.ts` extrae el estado JSON estructurado publicado por la
búsqueda oficial de Calimax. Conserva nombre, EAN, stock, precio, categoría,
imagen y fecha. Como Calimax no publica una ficha individual estable, el enlace
verificable apunta a la búsqueda oficial por SKU y se identifica así en el
payload de auditoría.

El comparador exige coincidencia exacta de presentación para evitar mezclar, por
ejemplo, `900 g` con `1 kg` o galones con litros.

Evaluación técnica del 2026-06-12:

- Arteli, Smart & Final México y Calimax: integrados; precio, imagen y enlace
  oficial verificables.
- H-E-B México: ficha oficial verificable, pero su catálogo rechaza
  explícitamente consultas desde scripts; no activar.
- Alsuper, Calimax, Merco y Súper Akí: factibilidad media; requieren
  estudiar sus APIs o HTML propios.
- Chedraui: técnicamente viable, pero no activar sin autorización por las
  restricciones publicadas en `robots.txt`.
- Walmart, Soriana, Casa Ley, Farmacias Guadalajara y La Comer: descartados por
  ahora por bloqueos o restricciones públicas.

En una prueba conservadora sobre los diez productos iniciales, ambas fuentes
aportaron resultados verificables para categorías complementarias. Una ausencia
de resultados se conserva como ausencia y nunca se rellena con productos de
otra presentación.

## Activar una fuente real

1. Revisar términos, robots y restricciones de la fuente.
2. Confirmar manualmente URL de búsqueda y selectores.
3. Implementar extracción y validación con `zod` si corresponde.
4. Probar con pocos productos y baja frecuencia.
5. Medir errores, bloqueos y calidad de resultados.
6. Crear un job explícito y conservador para activar el scraper.

Debe contemplarse una revisión mensual, además de alertas ante fallos repetidos.

La evaluación de repositorios compartidos como referencia se conserva en
[`scraper-reference-audit.md`](scraper-reference-audit.md). Ninguno se incorpora
sin confirmar licencia, autorización, alcance mexicano y estabilidad actual.
