# Arquitectura

## Clientes

`apps/flutter_app` contiene la experiencia de compra: onboarding, autenticación,
búsqueda, comparación, favoritos y lista de compras. Separa controladores,
modelos, servicios, páginas y widgets bajo `lib/src`.

El cliente utiliza RPC de Supabase para precios locales y online
(`nearby_prices_v4`, `online_prices_v4`) y Supabase Auth para identidad.
Los servicios HTTP auxiliares se configuran mediante `API_BASE_URL`.
El carrito autenticado utiliza `shopping_carts`, con acceso por propietario y
caché local por cuenta; el carrito invitado se mantiene separado.

`apps/price_web` es una web independiente en TypeScript y Vite. Consulta el
catálogo online mediante `online_prices_v2`. No comparte la navegación ni
todas las funciones de Flutter.

## Demo independiente

`main_demo.dart` utiliza la misma aplicación e inyecta `DemoMarketApi` mediante
el constructor de `TiagoMarketApp`. El catálogo vive en memoria, sin URLs de
servicios ni credenciales. La demo no inicializa autenticación ni telemetría;
un aviso permanente identifica productos, comercios y precios ficticios.

La navegación de demo ofrece búsqueda, comparación, favoritos y carrito
invitado. Desactiva ubicación y entrada de datos personales. Se construye como
sitio estático separado y el pipeline lo publica en GitHub Pages.

## Captura y publicación

Los conectores de `apps/flutter_app/tools/ingestion` se ejecutan fuera de los
clientes. Generan NDJSON con producto, presentación, precio, moneda,
disponibilidad, URL de origen y fechas de observación.

El staging valida los registros y rechaza datos sintéticos, incompletos o sin
evidencia suficiente. La deduplicación evita reprocesar una misma observación.
Los snapshots conservan el histórico de precios.

Los datos declaran su alcance: `online` para catálogos web y `branch_local`
cuando existe evidencia de sucursal. Las consultas por ubicación requieren
sucursales con coordenadas verificadas. Las imágenes de productos se cargan
desde las URLs de la fuente; los logos de comercios son assets locales con
origen documentado.

`refresh-online-catalog.yml` renueva automáticamente las observaciones de
productos existentes dos veces por día. Cada comercio se captura, concilia,
publica y verifica de forma independiente. Un fallo de una tienda no bloquea
las demás; las capturas originales y los rechazos se mantienen separados de
los resúmenes de ejecución públicos.

El workflow manual de la canasta Chedraui–Merco usa un manifiesto acotado. La
publicación exige que ambas fuentes y todos los productos superen la revisión;
una captura parcial no basta para publicar.

## Backend y persistencia

`src` contiene una API Express, jobs de captura y geocodificación y validación
de configuración con Zod. La API lee datos almacenados, pagina resultados y
limita solicitudes. Su contrato HTTP está en [API v1](api-v1.md).

La API Node y la Edge Function usada en instalaciones anteriores tienen rutas
distintas. El código de esa Edge Function no está recuperado en este checkout;
su despliegue no se reproduce desde este repositorio.

Las migraciones del cliente están en `apps/flutter_app/supabase/migrations`.
`supabase/recovered` conserva SQL histórico para su reconciliación. No existe
todavía una secuencia completa validada para construir una base vacía.
Los fixtures SQL de tests son escenarios aislados, no un bootstrap productivo.

## Límites de confianza

- Las claves privilegiadas pertenecen a jobs y servidores. Flutter y Vite
  reciben exclusivamente configuración pública.
- El cliente presenta precios estimados; una futura compra requiere
  revalidación del servidor con la tienda.
- El checkout mantiene el borrador en memoria. Los gateways de envío y pago
  son interfaces sin proveedor remoto activo.
- Una captura, un conector o un workflow programado no demuestran que una
  fuente tenga datos vigentes. La consulta muestra fecha y procedencia.

## Pruebas

El backend usa el test runner de Node con fixtures. Flutter tiene pruebas de
widgets, modelos, búsqueda, sesión y persistencia. Python prueba parsers,
revisión de lotes y decisiones de publicación. Estas pruebas no reemplazan
la validación en dispositivo ni la revisión de una fuente real.
