# Evaluación de la segunda cadena local

> **Actualización 22/09/2026:** un nuevo preflight Chedraui quedó bloqueado por autorización de reutilización no confirmada. No se consultaron sesiones ni productos; el 429 de abajo sigue siendo evidencia de junio. Ver [informe y artefactos actuales](../../../docs/chedraui-validation-2026-09-22.md).

## Conclusión

El experimento mínimo de Chedraui México del **24 de junio de 2026** quedó
`blocked`. Chedraui no debe marcarse como `branch_local`; su clasificación y
datos existentes no se modificaron.

## Flujo público confirmado

- `robots.txt` respondió HTTP 200, publica el sitemap y permite fichas de
  producto. Bloquea expresamente login, checkout y búsqueda:
  <https://www.chedraui.com.mx/robots.txt>.
- La tienda carga `chedrauimx.locator@2.1.6`. Su código público construye la
  región de una tienda como `base64("SW#chedrauimx0" + id_store)` y la envía
  por `POST /api/sessions`; no hace falta login para iniciar ese flujo.
- La ficha pública del SKU `3061483`, Refresco Coca-Cola Original 1 L,
  respondió HTTP 200 y expuso una oferta online de **31.00 MXN** con
  `AvailableQuantity = 99999`:
  <https://www.chedraui.com.mx/refresco-coca-cola-original-1l-3061483/p>.
- El selector público también referencia
  `GET /api/intelligent-search/v0/pickup-point-availability/...` y
  `GET /api/dataentities/CS/search`, pero esas rutas y `POST /api/sessions`
  respondieron HTTP 429 desde el entorno del experimento. No se reintentó con
  otro agente, credenciales, checkout ni mecanismos de evasión.

## Targets y resultado

Se eligieron dos tiendas de Ciudad de México incluidas en documentación oficial
de Chedraui:
<https://www.chedraui.com.mx/arquivos/TYCOS-PROMO-BARILLA-Y-YEMINA-140426.pdf>.

| Target | Región esperada | Dirección | Resultado |
|---|---|---|---|
| `chedraui-mx:013`, Chedraui México Buen Tono | `SW#chedrauimx0013` | Buen Tono 8, Centro, Cuauhtémoc, CP 06070 | `POST /api/sessions` devolvió HTTP 429; sin precio/stock atribuible |
| `chedraui-mx:016`, Chedraui México Ánfora | `SW#chedrauimx0016` | Ánfora 71, Col. Madero, Venustiano Carranza, CP 15320 | no consultada después del bloqueo, para no insistir sobre la ruta limitada |

La oferta online no conserva una de esas tiendas en la misma observación. Por
lo tanto no existen dos tuplas verificables
`(branch_external_key, sku, price, stock, evidence_url)` y no hay evidencia para
promover Chedraui a `branch_local`.

## Herramienta y evidencia

`tools/ingestion/bin/chedraui_branch_probe.dart` ejecuta el preflight de
`robots.txt`, guarda una línea base online, intenta como máximo una sesión y una
ficha por target, y clasifica el resultado como `confirmed_branch_local`,
`online_only`, `ambiguous` o `blocked`. No genera NDJSON, no importa datos y no
persiste cookies.

La corrida validada guardó sus artefactos en:

```text
/tmp/tiago-chedraui-branch-probe-20260624-v2
```

## Condiciones para un conector productivo

Antes de avanzar deben cumplirse todas:

1. acceso estable y permitido al selector público, sin HTTP 429, login, captcha
   ni checkout;
2. dos sesiones de tiendas distintas que devuelvan y conserven el `regionId`
   esperado;
3. para el mismo SKU, una respuesta oficial que enlace tienda, precio, moneda y
   disponibilidad;
4. una diferencia real de precio o stock entre las dos tiendas;
5. identificador estable, nombre y dirección o coordenadas oficiales para cada
   pickup point;
6. rate limit y frecuencia documentados para una operación repetible.

Hasta entonces conviene evaluar otra cadena y mantener Chedraui como fuente
online/experimental, no local.

---

## Evaluación de Steren México

### Conclusión

El experimento mínimo de Steren México del **24 de junio de 2026** quedó
`blocked` para precio/disponibilidad por sucursal. La clasificación publicable
de Steren debe permanecer `online_only`; no hay evidencia suficiente para
promoverla a `branch_local_realtime`.

El bloqueo no significa que Steren carezca de inventario local en sus sistemas.
Significa que la única vía encontrada para consultarlo usa rutas excluidas
expresamente por `robots.txt` o un servicio de inventario no documentado. No se
llamó ninguna de esas rutas.

### Preflight público

- `robots.txt` respondió HTTP 200, publica el sitemap y permite recursos bajo
  `/pub/` y archivos JavaScript, pero bloquea expresamente `/rest/`,
  `/graphql`, `/checkout/` y `/customer/`:
  <https://www.steren.com.mx/robots.txt>.
- Los términos públicos fueron consultados sin login:
  <https://www.steren.com.mx/terminos-y-condiciones-generales>.
  No se encontró un programa o documentación oficial que autorice una API de
  precio/inventario local para terceros.
- El JavaScript público del selector de tienda usa
  `rest/V1/storepickup/storesInfo`,
  `rest/V1/storepickup/getStoreInfoForStoresList` y
  `rest/V1/storepickup/geolocalizedStoreInfo`. Todas quedan bajo `/rest/`.
- El componente público de disponibilidad de producto recibe desde la ficha
  una URL externa de inventario,
  `https://Fyi.steren.com.mx/WSStock/api/POSStock/GetMaterialExists`, y un token
  embebido. El cliente envía SKU e IDs de tienda y procesa `AVLBL`, pero ese
  servicio no está documentado como API pública o partner. No se consultó.
- La misma interfaz advierte que la información de stock de las tiendas es
  orientativa. El texto HTML inicial “En existencia” forma parte del componente
  global: aparece incluso en páginas que no son productos y está sujeto a
  bindings de JavaScript. Por sí solo no prueba stock de una sucursal.

`robots.txt` no se trata como autorización legal; en este caso sí funciona como
una restricción técnica expresa que impide usar las rutas `/rest/` dentro del
experimento permitido.

### SKU observado

Se eligió un único accesorio estable y de bajo riesgo:

| Campo | Evidencia pública |
|---|---|
| Producto | Cable HDMI 2.0 certificado de alta velocidad, de 2 m |
| SKU | `295-502` |
| URL | <https://www.steren.com.mx/cable-hdmi-2-0-de-alta-velocidad-de-2-m.html> |
| Precio | `149.00 MXN` |
| Disponibilidad | `InStock`, solo a nivel de la oferta online |
| Fecha de captura | `2026-06-24T19:14:49Z` |

La ficha expone precio, moneda, SKU y `InStock` mediante metadatos y JSON-LD.
También incrusta un directorio de sucursales. Sin embargo, ni el JSON-LD ni el
HTML estático enlazan `InStock` con una sucursal particular.

### Comparación de las dos tiendas

Las dos tiendas aparecen en el directorio oficial incrustado en la ficha del
mismo SKU:

| Tienda | Claves oficiales observadas | Dirección oficial | Resultado para SKU `295-502` |
|---|---|---|---|
| Steren Shop Parque Lindavista | registro locator `254`; `id_store = 580033`; clave candidata `steren-mx:580033` | Avenida Riobamba No. 589, Col. Magdalena de las Salinas, Gustavo A. Madero, CDMX, CP 07760 | precio online `149.00 MXN`; sin disponibilidad atribuible a esta tienda |
| Steren Shop Encuentro Fortuna | registro locator `663`; `id_store = 580539`; clave candidata `steren-mx:580539` | Avenida Fortuna No. 334 local SS09, Col. Magdalena de las Salinas, Gustavo A. Madero, CDMX, CP 07760 | precio online `149.00 MXN`; sin disponibilidad atribuible a esta tienda |

Las claves se marcan como candidatas porque no deben publicarse como
`branch_external_key` hasta obtener una observación local permitida. Ambas
tiendas comparten el CP 07760, por lo que una selección por código postal
tampoco distingue por sí sola cuál sucursal aporta el inventario.

No se obtuvieron estas tuplas:

```text
steren-mx:580033 + 295-502 + 149.00 + MXN + disponibilidad local
steren-mx:580539 + 295-502 + 149.00 + MXN + disponibilidad local
```

### Clasificación

- `confirmed_branch_local`: **no**; falta disponibilidad vinculada de forma
  permitida e inequívoca a cada tienda.
- `regional_or_ambiguous`: describe la señal visual de selector/retiro, pero no
  es el resultado operativo final porque la vía que resolvería la ambigüedad
  está restringida o no documentada.
- `online_only`: **sí** para la ficha pública, precio y disponibilidad web.
- `blocked`: **sí** para el probe de sucursal, por restricción expresa de
  `/rest/` y ausencia de una API/feed local documentado.

### Herramienta y evidencia

No se creó `steren_branch_probe.dart`: bajo las reglas del experimento no hay
una ruta local permitida y reproducible que el probe pueda consultar. El
scraper de sitemap existente debe continuar limitado a catálogo online.

Los artefactos pasivos de la corrida quedaron en:

```text
/tmp/tiago-steren-branch-probe-20260624
```

Comando mínimo reproducible, sin llamar inventario, carrito ni rutas
restringidas:

```bash
UA='TiagoMarketBot/0.1 (+https://tiago-market.local/contact)'
curl -fsS --compressed -A "$UA" https://www.steren.com.mx/robots.txt
curl -fsS --compressed -A "$UA" \
  https://www.steren.com.mx/cable-hdmi-2-0-de-alta-velocidad-de-2-m.html \
  -o /tmp/steren-product.html
rg -n 'product:price|product:availability|295-502|580033|580539|webapi_existencia_tiendas|url_existencias' \
  /tmp/steren-product.html
```

### Recomendación

Mantener Steren como `online_only` y pasar el siguiente probe local a H-E-B.
Steren solo debe reconsiderarse si publica documentación de API/feed para
terceros o concede acceso partner que permita consultar SKU, precio y
disponibilidad por `id_store` con condiciones de uso y frecuencia definidas.

---

## Evaluación de H-E-B México

### Conclusión

El preflight mínimo de H-E-B México del **24 de junio de 2026** quedó
`blocked`. No debe clasificarse como `branch_local_realtime` ni construirse un
probe automatizado sobre el sitio actual.

La evaluación se detuvo antes de solicitar una ficha de producto: los términos
públicos prohíben expresamente obtener o extraer, directa o indirectamente,
información de HEB.COM.MX, así como reutilizar su contenido con fines públicos
o comerciales. `robots.txt` también declara como objetivo el bloqueo de
crawlers y comparadores de precios. Tiago Market encaja precisamente en esa
actividad.

### Preflight público

- `robots.txt` respondió HTTP 200 y publica
  <https://www.heb.com.mx/sitemap.xml>, pero incluye el encabezado
  “Bloquea herramientas Crawlers/Comparadores de precios” y bloquea por nombre
  numerosos crawlers:
  <https://www.heb.com.mx/robots.txt>.
- Los términos oficiales fueron consultados sin login:
  <https://www.heb.com.mx/terminos-y-condiciones>. Exigen:
  - abstenerse de usar HEB.COM.MX o sus contenidos comercialmente;
  - abstenerse de copiar, reutilizar, transmitir, distribuir, descargar,
    publicar o usar el contenido para fines públicos o comerciales;
  - abstenerse de obtener o extraer, directa o indirectamente, cualquier
    información contenida en HEB.COM.MX.
- La ayuda oficial indica que para comprar se debe iniciar sesión o registrar
  una cuenta, seleccionar el método de entrega o sucursal preferida, agregar
  productos al carrito y confirmar el pedido:
  <https://www.heb.com.mx/centro-de-ayuda>.
- Los términos confirman que los precios pueden variar según zona y tienda,
  pero que los precios correspondientes a la compra son los mostrados al
  realizar y confirmar la orden.
- También confirman que la disponibilidad corresponde a la existencia física
  de la tienda seleccionada, pero la gestión de faltantes y sustituciones se
  realiza desde el carrito, y que Pick&Go queda sujeto a la disponibilidad
  indicada al confirmar la compra.

Estas últimas señales prueban que H-E-B opera con surtido físico por tienda,
pero no proporcionan una vía pública permitida para que Tiago observe
`tienda + SKU + precio + disponibilidad` sin cuenta, carrito ni confirmación de
pedido.

### Tiendas seleccionadas

Se eligieron dos tiendas de la ciudad de Monterrey visibles en el localizador
oficial:

| Tienda | Dirección oficial | Pick&Go | Resultado |
|---|---|---|---|
| HEB TEC | Eugenio Garza Sada #3431, Col. Arroyo Seco, Monterrey, Nuevo León, CP 66740 | Sí | sin `branch_external_key` público verificado; no se consultó SKU, precio ni stock por el bloqueo de cumplimiento |
| HEB EL URO | Carretera Nacional #5000, Col. El Uro, Monterrey, Nuevo León | Sí | sin `branch_external_key` público verificado; no se consultó SKU, precio ni stock por el bloqueo de cumplimiento |

Fuente: <https://www.heb.com.mx/ubica-tu-tienda>.

Los nombres y direcciones oficiales son suficientes para identificar los
targets humanos del experimento, pero no para inventar una
`branch_external_key`. Pick&Go tampoco demuestra que un SKU concreto tenga
precio o existencia en una de esas tiendas.

### SKU y observaciones

No se eligió ni solicitó una ficha de SKU. El orden del experimento exigía
revisar primero permisos y términos y detenerse al primer bloqueo técnico o de
cumplimiento. Continuar con un SKU después de encontrar una prohibición
explícita de extracción habría incumplido esa regla.

Por lo tanto se obtuvieron **cero** observaciones del contrato:

```text
branch_external_key
+ branch_name
+ dirección
+ SKU
+ precio
+ moneda
+ disponibilidad/stock
+ evidencia oficial
+ captured_at
```

### Clasificación

- `confirmed_branch_local`: **no**; no existen dos observaciones permitidas por
  tienda.
- `regional_or_ambiguous`: hay selección de sucursal y Pick&Go, pero no se
  avanzó a resolver la atribución debido a la restricción de cumplimiento.
- `online_only`: no se valida como resultado del probe, porque incluso la
  extracción del catálogo/precio para reutilización está expresamente
  restringida por los términos.
- `blocked`: **sí**; términos incompatibles con extracción/reutilización,
  intención restrictiva en `robots.txt` y disponibilidad local ligada al
  carrito/confirmación.

### Herramienta y evidencia

No se creó una herramienta nueva. No existe una ruta pública que pueda
automatizarse bajo las condiciones permitidas del experimento.

Las respuestas pasivas del preflight quedaron en:

```text
/tmp/tiago-heb-branch-probe-20260624
```

Comando reproducible limitado al preflight:

```bash
UA='TiagoMarketBot/0.1 (+https://tiago-market.local/contact)'
curl -fsS --compressed -A "$UA" \
  https://www.heb.com.mx/robots.txt \
  -o /tmp/heb-robots.txt
curl -fsS --compressed -A "$UA" \
  https://www.heb.com.mx/terminos-y-condiciones \
  -o /tmp/heb-terms.html
rg -n 'Comparadores de precios|uso comercial|fines públicos o comerciales|obtener o extraer' \
  /tmp/heb-robots.txt /tmp/heb-terms.html
```

### Recomendación

No crear un conector local ni un conector `online_only` por extracción de
HEB.COM.MX. Pasar el siguiente probe técnico a Farmacias Guadalajara.

H-E-B solo debe reconsiderarse mediante acuerdo comercial, API o feed oficial
que autorice expresamente el uso de sucursal, SKU, precio y disponibilidad,
junto con frecuencia, atribución y reglas de corrección.
