# Preparación de envío y métodos de pago

Desde **Mi lista de compras → Preparar envío y pago** se elige una tienda que
cubra toda la lista, entrega a domicilio, datos de contacto y forma
de pago. Se puede revisar el borrador y volver a editarlo. El flujo está
preparado para México y MXN, como el catálogo actual.

El borrador vive únicamente en memoria mientras la pantalla permanece abierta.
No crea órdenes, no solicita cotizaciones ni envía datos personales. No hay
credenciales, números de cuenta, campos de tarjeta ni costos de envío ficticios.
Las opciones de pago son preferencias sujetas a habilitación futura;
no acreditan acuerdos comerciales con los supermercados.

**Requisito para las próximas versiones:** ofrecer únicamente envío a domicilio.
No incluir retiro en tienda ni permitir borradores sin dirección de entrega.

## Puntos de integración

- `lib/src/models/checkout.dart`: `CheckoutDraft.toJson()` entrega un contrato
  versionado con referencias de productos, tienda/sucursal, cantidades,
  precios observados, contacto y preferencias. Los importes se expresan en
  centavos enteros. Cada cesta separa las sucursales y los precios online.
- `lib/src/services/checkout_gateway.dart`: `ShippingGateway` expone cotización
  y seguimiento; `PaymentGateway` expone creación de sesión y estado de pago.
  Son interfaces sin proveedor ni implementación remota activa.
- `lib/src/pages/checkout_page.dart`: formulario y revisión. Actualmente no
  llama a los gateways. Una integración futura puede inyectar implementaciones
  HTTP y añadir selección de cotización y confirmación después de la revisión.

## Secuencia para habilitar compras reales

1. Crear un backend de checkout y los adaptadores del transportista y pasarela
   elegidos. Mantener sus credenciales en el servidor. Resolver allí las
   referencias observadas a IDs comerciales autorizados de tienda y producto.
2. Revalidar todos los campos, cantidades, stock, moneda y precios con la
   tienda. Los importes enviados por Flutter son estimaciones, nunca una
   autoridad para el cobro. Rechazar listas incompletas y ofertas inválidas.
3. Consultar cobertura y servicios de envío a domicilio reales. Mostrar
   cotización, moneda, vigencia y plazos del proveedor. Confirmar compatibilidad
   de cada medio de pago con la tienda y el servicio elegido.
4. Crear una orden en el servidor con el total definitivo y la cotización
   seleccionada. Vincular las cotizaciones a la cesta y dirección; invalidarlas
   cuando cambien los datos o expiren. Usar idempotencia al crear órdenes,
   pagos y envíos.
5. Crear una sesión de pago mediante `PaymentGateway.createSession` y abrir
   únicamente la URL HTTPS validada del proveedor o su SDK de tokenización.
   Para transferencias o efectivo, mostrar instrucciones reales del servidor.
6. Verificar firma y procesar webhooks de forma idempotente en el backend.
   Consultar el estado verificado por `PaymentGateway.status`; una redirección
   del navegador no confirma un cobro. Definir reservas, expiración,
   cancelaciones y reembolsos según los acuerdos comerciales.
7. Crear el envío cuando corresponda al estado de la orden y consultar
   `ShippingGateway.track`. Incorporar estados, incidencias y seguimiento a
   una pantalla de pedidos.

Antes de almacenar direcciones, definir acceso por propietario, retención y
eliminación. El borrador actual no necesita tablas ni migraciones.
