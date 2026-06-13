# Auditoría de referencias de scraping

Fecha de revisión: 2026-06-12.

Estos repositorios se revisaron como referencias técnicas. No se copiaron ni se
ejecutaron contra los comercios. Un repositorio público sin licencia no concede
automáticamente permiso para copiar, modificar o redistribuir su código.

## joseluam97/Supermarket-Price-Scraper

- URL: https://github.com/joseluam97/Supermarket-Price-Scraper
- Último commit observado: 2024-08-19.
- Alcance: Mercadona, Carrefour y Dia en España; no comercios mexicanos.
- Implementación: Python, APIs internas, cookies de Carrefour/Dia y exportación
  a Excel.
- Licencia: no se encontró archivo de licencia.
- Decisión: útil solo como referencia conceptual para separar fuentes y
  normalizar resultados. No reutilizar código ni cookies.

## omkarcloud/walmart-scraper

- URL: https://github.com/omkarcloud/walmart-scraper
- Último commit observado: 2026-05-19.
- Alcance: documentación de una API comercial externa orientada a
  `walmart.com`, con ejemplos en USD.
- Implementación publicada: README e imagen; no contiene código del scraper.
- Condiciones observadas: requiere API key y anuncia una cuota gratuita de 25
  solicitudes mensuales.
- Licencia: no se encontró archivo de licencia.
- Decisión: no integrarla hasta validar cobertura de Walmart México, contrato,
  tratamiento de datos, disponibilidad, costos y permiso de redistribución.

## jjsantos01/scrap_walmart

- URL: https://github.com/jjsantos01/scrap_walmart
- Último commit observado: 2023-05-11.
- Alcance: menú de departamentos, categorías y URLs de Walmart México; no
  obtiene productos ni precios.
- Implementación: una solicitud GraphQL con headers y versiones internas
  fijadas en 2023.
- Licencia: no se encontró archivo de licencia.
- Riesgos: endpoint y headers internos frágiles; no demuestra autorización ni
  funcionamiento actual.
- Decisión: sirve para entender la taxonomía histórica, pero no se incorpora ni
  habilita como fuente.

## Criterios para incorporar una fuente

1. Confirmar por escrito licencia o autorización de uso y redistribución.
2. Verificar que cubra México, sucursal y moneda MXN.
3. Probar con baja frecuencia sin evadir controles técnicos.
4. Validar nombre, presentación, precio, disponibilidad, URL y fecha.
5. Medir estabilidad y conservar payload original para auditoría.
6. Mantener la fuente desactivada hasta superar todos los criterios.
