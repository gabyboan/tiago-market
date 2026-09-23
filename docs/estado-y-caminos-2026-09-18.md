# Tiago Market: estado y próximos caminos

> **Antecedente del 18/09.** Ver [estado actualizado](estado-2026-09-22.md) y [entrega Chedraui](chedraui-validation-2026-09-22.md). Los caminos comerciales aquí descritos no constituyen alcance acordado.

Revisión: 18 de septiembre de 2026.

## Situación actual

Tiago Market es un prototipo avanzado de comparación de precios con Flutter y backend Node/Supabase. Tiene búsqueda geográfica, favoritos, lista de compras, acceso invitado y autenticación opcional. Flutter está en `0.2.2+4`; el último avance previo a la consolidación es `969c8e4`, preparación del piloto v0.8.1. El paquete Node conserva la versión `0.8.0`.

La base Supabase está activa, con 23 migraciones registradas y la función `api` activa. El historial no registra las tres migraciones locales posteriores al 19 de junio. La auditoría de julio identificó el contrato RPC v2 como pendiente y necesario para una prueba conectada. Esta consolidación no desplegó SQL ni verificó datos comerciales actuales.

**Todavía no está listo para un piloto abierto:** faltan reconciliar/aplicar el contrato de base, un lote comercial reciente por sucursal, validar login en dispositivo y generar una build con firma custodiada. GitHub solo tiene configurados los secretos `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`; faltan los demás requeridos por el workflow Android. La evidencia histórica identifica Home Depot como fuente local comprobada, pero no acredita cobertura comercial actual.

Validación ejecutada hoy: 49 pruebas Flutter y 22 pruebas Node aprobadas; `flutter analyze`, `npm run build` y `npm run lint` sin errores. No se generó ni distribuyó una nueva APK.

## Caminos posibles

| Camino                                | Qué requiere                                                                       | Recomendación                                                  |
| ------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Comparador con enlaces de compra      | Precios verificables, frescura y cobertura por zona                                | Primer paso: piloto pequeño, una zona y una fuente             |
| Pedidos propios con comercios aliados | Catálogo autorizado, stock, cobro, preparación, cancelaciones y soporte            | Segunda etapa con uno o dos comercios                          |
| Entregas con Uber Direct              | Pedido confirmado y preparado, integración backend, cuenta y cobertura habilitadas | Probar en sandbox después de validar la operación del comercio |

## Uber: viabilidad y límites

**Uber Direct es la opción que mejor encaja para repartir pedidos generados en Tiago Market.** Permite solicitar y seguir entregas desde una tienda al cliente. La recomendación es una inferencia de su alcance: Tiago y el comercio deben resolver antes la compra, el stock y la preparación. Integrar reparto no convierte los precios obtenidos por scraping en productos que un comercio acepte vender. [Descripción oficial](https://developer.uber.com/docs/deliveries/overview).

Flujo propuesto: cliente elige una tienda → backend confirma productos/stock y cotiza envío → cliente confirma el total → comercio acepta/prepara → backend crea entrega → Tiago muestra seguimiento. Empezar con una sola tienda por pedido; comparar varias tiendas no resuelve una compra con varios retiros.

El backend debe guardar las credenciales, evitar pedidos duplicados y procesar estados mediante webhooks autenticados. Flutter muestra cotización y seguimiento. Es una propuesta, no una integración implementada. [Webhooks de Uber Direct](https://developer.uber.com/docs/deliveries/guides/webhooks).

Uber ofrece sandbox; el acceso productivo requiere cuenta habilitada y facturación. Hay que confirmar disponibilidad en la ciudad mexicana elegida y condiciones comerciales antes de prometer el servicio. No se verificaron credenciales, tarifas ni cobertura de una cuenta propia. [Alta y pruebas](https://developer.uber.com/docs/deliveries/get-started).

Uber Eats Marketplace sirve para gestionar tiendas, menús y pedidos de comercios conectados a Uber Eats. Requiere autorización del comercio y aprobación de permisos para producción; la documentación revisada no ofrece una API pública general para comprar en cualquier supermercado en nombre del usuario. [Marketplace](https://developer.uber.com/docs/eats/introduction) · [Autorización](https://developer.uber.com/docs/eats/guides/authentication).

**Siguiente paso recomendado:** cerrar el piloto del comparador y conseguir un comercio que confirme stock y prepare pedidos; luego probar cotización, entrega y seguimiento de Uber Direct en sandbox.

## Consolidación

Se conserva una única carpeta de trabajo: `tiago-market`. Las dos copias antiguas se eliminaron después de respaldar y verificar sus archivos no regenerables. Se recuperaron configuraciones locales, SQL histórico y el reporte de cobertura. Los respaldos privados están excluidos de Git. Ver [detalle del rescate](rescate-2026-09-18.md) y [SQL histórico](../supabase/recovered/2026-09-18/README.md).
