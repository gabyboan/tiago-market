# Evaluacion de APIs de Walmart Mexico

Fecha de revision: 2026-09-23.

## Resultado

La documentacion oficial de Walmart Mexico confirma APIs para vendedores de
Marketplace y proveedores de soluciones aprobados. No confirma una API publica
para consultar el catalogo retail de Walmart o Bodega Aurrera, sus precios por
sucursal o su inventario completo para un comparador.

La pagina de WFS enlaza al Portal del Desarrollador y describe operaciones de
cuenta de vendedor, articulos, precios, inventario, pedidos y fulfillment. El
acceso requiere onboarding, credenciales y permisos de Marketplace.

## APIs confirmadas

- Token: `POST https://marketplace.walmartapis.com/v3/token`.
  Usa `client_credentials` con Client ID y Client Secret, o flujos de
  autorizacion/delegacion para un Solution Provider.
- Inventario Mexico: `GET https://marketplace.walmartapis.com/v3/mx/inventories`.
  Consulta inventario de un SKU del vendedor autenticado. Sus `shipNode` son
  nodos de fulfillment del vendedor, no un locator del inventario retail de
  Walmart.
- Asociaciones de items: `POST /v3/mx/associations`.
  Devuelve asociaciones como `shipNode` y plantilla de envio para items del
  vendedor.
- Precios promocionales: `PUT /v3/price?promo=true`.
  Actualiza precios promocionales de items del vendedor; no es un feed de
  precios retail para comparacion.
- WFS: endpoints de inbound shipments, fulfillment y cantidades de envio.
  Sirven para la operacion logistica del vendedor, no para descubrir precios
  de supermercado por sucursal.

Fuentes oficiales:

- [Portal Marketplace Mexico](https://developer.walmart.com/mx-marketplace/)
- [Global Marketplace APIs](https://developer.walmart.com/global-marketplace/docs/global-marketplace-apis)
- [Token API](https://developer.walmart.com/mx-marketplace/reference/tokenapi)
- [Inventario Mexico](https://developer.walmart.com/mx-marketplace/reference/getwhsinventory)
- [Asociaciones de items](https://developer.walmart.com/mx-marketplace/reference/getmwhitemassociations)
- [Documentacion WFS](https://developer.walmart.com/doc/mx/mx-mp/mx-mp-fulfillment/)

## Que significa para Tiago Market

La API oficial es util solo si Tiago Market opera como vendedor de Walmart,
es un Solution Provider aprobado o recibe autorizacion delegada de un vendedor.
En ese caso se puede construir un conector server-side para importar los SKUs,
precios e inventario autorizados de esa cuenta.

No resuelve por si sola la comparacion entre Walmart, Bodega Aurrera y otras
cadenas. La pagina publica de Bodega Aurrera si muestra fichas y precios online,
pero eso no demuestra precio local por sucursal ni disponibilidad geolocalizada.
Esos datos deben mantenerse como `online_only` hasta obtener evidencia local.

## Integracion pendiente

No se agregan Client ID, Client Secret, access tokens ni private keys al
repositorio. Si existe una cuenta autorizada, la integracion debe vivir en el
backend o en un job de ingesta con variables de entorno:

```dotenv
WALMART_CLIENT_ID=
WALMART_CLIENT_SECRET=
WALMART_MARKET=mx
WALMART_CONSUMER_CHANNEL_TYPE=
WALMART_SERVICE_NAME=
```

El job debe:

1. Obtener el token en cada corrida o reutilizarlo solo hasta `expires_in`.
2. Consultar unicamente SKUs autorizados para esa cuenta.
3. Conservar `source_url`, `captured_at`, respuesta original y el identificador
   de `shipNode`.
4. No convertir `shipNode` en sucursal retail sin evidencia adicional.
5. Generar NDJSON y pasar por `stage_ndjson.dart` antes de Supabase.
6. Mantener la fuente separada como `walmart-marketplace-mx`, distinta de
   `walmart-mx` retail.

## Decision actual

- `walmart-mx` retail: permanece bloqueado para ingesta automatica por CAPTCHA y
  falta de API publica confirmada.
- `bodega-aurrera-mx` retail: puede tener catalogo online publico, pero permanece
  `online_only` hasta demostrar atribucion por tienda.
- `walmart-marketplace-mx`: listo para implementarse cuando exista una cuenta y
  autorizacion validas; requiere un conector separado del scraper retail.
