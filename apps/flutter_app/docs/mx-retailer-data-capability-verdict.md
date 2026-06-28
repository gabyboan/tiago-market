# Veredicto de capacidad de datos de retailers en México

**Fecha de corte:** 24 de junio de 2026
**Alcance:** evaluación técnica, comercial y de cumplimiento basada únicamente
en fuentes públicas oficiales. No se usaron login, checkout, CAPTCHA, cuentas,
proxies, cookies privadas, endpoints no documentados ni recolección masiva de
productos.

## 1. Resumen ejecutivo

Tiago Market ya tiene una fuente local en vivo confirmada: **The Home Depot
México**. El conector validado conserva, en una misma observación, sucursal,
SKU, precio MXN, disponibilidad o stock local, coordenadas, evidencia oficial,
fecha de captura y `physicalStoreId`. Hay 18 registros NDJSON aceptados y
publicables para Centro 8860, Tlatilco 8763 y Linda Vista 8692. Por eso Home
Depot puede clasificarse como `branch_local_realtime`.

**Chedraui no está confirmado como fuente local.** Su ficha pública mostró
precio online, pero el flujo de sesión y pickup respondió HTTP 429 durante la
prueba controlada del 24 de junio de 2026. Debe permanecer como `blocked` para
ese probe o como `online_only` para el dato público observado; no como precio
por sucursal.

Para las cadenas evaluadas en este documento existe una oferta amplia de
catálogos online, localizadores y modalidades de retiro. Eso abre varias rutas
de cobertura, pero no demuestra por sí solo que el precio o inventario
publicado corresponda a una sucursal concreta. Al corte de esta evaluación,
**ninguna cadena adicional cumple todavía el estándar completo de
`branch_local_realtime`**.

La ampliación de Tiago Market no depende de prometer “todas las tiendas”. Puede
crecer mediante capas claramente rotuladas:

- precios y catálogos web como `online_only`;
- precios levantados y fechados por PROFECO como
  `observed_establishment_price`;
- feeds licenciados como `partner_feed`;
- carga directa de comercios;
- contribuciones de usuarios con ticket o fotografía como `user_contributed`;
- conectores locales solo después de verificar la atribución completa por
  sucursal.

El mejor siguiente paso comercial no es multiplicar scrapers: es conseguir un
**acuerdo con un retailer ancla para recibir un feed oficial incremental por
sucursal**, idealmente por API o, de forma más realista para un MVP, por
CSV/XLSX vía SFTP. Ese camino reduce ambigüedad, fragilidad técnica y riesgo de
uso no autorizado.

### Taxonomía de publicación

| Clasificación | Uso correcto en Tiago Market |
|---|---|
| `branch_local_realtime` | Observación oficial reciente que cumple todos los campos del estándar local definido en la sección 3. |
| `observed_establishment_price` | Precio observado en un establecimiento y fecha determinados, sin presentarlo como inventario o precio en vivo. |
| `online_only` | Catálogo o precio del canal web, nacional, regional o dependiente de zona, sin atribución completa a sucursal. |
| `partner_feed` | Datos entregados bajo API, feed, licencia o acuerdo directo que define alcance, frecuencia y derechos de uso. |
| `user_contributed` | Precio aportado por una persona con ticket/foto, fecha, sucursal y revisión; nunca se presume en vivo. |
| `not_recommended` | Fuente cuyo acceso, calidad, trazabilidad o riesgo de cumplimiento no justifica la integración. |

## 2. Matriz por cadena

En “dirección/coordenadas”, se separan ambos resultados para no confundir una
dirección visible con coordenadas oficiales reutilizables. “Probable” significa
que el flujo comercial muestra una señal fuerte, pero todavía no existe una
observación que satisfaga el contrato completo de la sección 3. La existencia
de un portal de proveedores o marketplace cuenta como programa partner, no como
API o licencia de datos.

| Cadena o fuente | Catálogo / precio online | Localizador | Dirección / coordenadas oficiales | Pickup / retiro | Precio por sucursal | Stock por sucursal | API, feed o partner | Riesgo técnico | Riesgo de cumplimiento | Clasificación recomendada | Veredicto | Fuente oficial y consulta |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Walmart México / Bodega Aurrera | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí | Probable | Probable | Sí: marketplace / “Vende con nosotros”; API o feed de datos no confirmado | Alto: experiencia dinámica por ubicación y controles anti-bot visibles | Alto sin licencia para extracción sostenida; separar productos propios de terceros | `online_only` hasta convenio o prueba completa | `partner_only` | [Walmart online](https://www.walmart.com.mx/), [locator Walmart](https://www.walmart.com.mx/buscador-de-tiendas), [formas de entrega Walmart](https://www.walmart.com.mx/ayuda/articulo/formas-de-entrega/0e0df991b68e46479672fb9f368fd2d1), [formas de entrega Bodega Aurrera](https://www.bodegaaurrera.com.mx/ayuda/articulo/formas-de-entrega/8b65c6e6881d483a91781c5d99a6d9a6). 24-06-2026 |
| Soriana | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí | Probable | Probable | Sí: portal y alta de proveedores; API/feed no confirmado | Medio/alto: selección de tienda, cobertura y disponibilidad condicionan el surtido | Medio/alto: términos de uso y ausencia de licencia pública de reutilización | `online_only` | `probe_later` | [compra online y Pick Up](https://www.soriana.com/ideas/comprar-en-linea-en-soriana.html), [buscador de tiendas](https://www.soriana.com/buscador-de-tiendas), [términos](https://www.soriana.com/customer-service/terms/terms.html), [proveedores](https://www.organizacionsoriana.com/proveedores.html). 24-06-2026 |
| La Comer / Fresko / City Market | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí | Probable | Probable | Sí: Provecomer; API/feed no confirmado | Medio: sesión y surtido dependen de la sucursal elegida | Medio/alto: términos limitan el sitio al servicio de compra; negociar reutilización | `online_only` | `probe_later` | [La Comer en tu casa](https://www.lacomer.com.mx/lacomer/), [Grupo La Comer y sucursales](https://grupolacomer.com.mx/corporativo/), [sucursales City Market](https://www.citymarket.com.mx/comprasbiencitymarket/sucursales/), [términos](https://www.lacomer.com.mx/resourceLacomer/TerminosyCondiciones.pdf). 24-06-2026 |
| H-E-B México | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí, Pick&Go | Probable | Probable | Sí: marketplace y “Vende con nosotros”; API/feed no confirmado | Medio: requiere seleccionar tienda y la compra requiere cuenta, aunque catálogo y ayuda son públicos | Medio/alto: no hay licencia pública para reutilización comercial del catálogo | `online_only` hasta verificar observación por tienda | `probe_later` | [tienda online](https://www.heb.com.mx/), [ubica tu tienda](https://www.heb.com.mx/ubica-tu-tienda), [centro de ayuda: selección de sucursal y Pick&Go](https://www.heb.com.mx/centro-de-ayuda). 24-06-2026 |
| Casa Ley | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí | Probable | Probable | Sí: portal/directorio de proveedores; API/feed no confirmado | Medio: plataforma de supermercado separada y dependiente de ubicación | Medio/alto: falta licencia de reutilización y deben revisarse términos del canal online | `online_only` | `probe_later` | [Tu Súper Casa Ley](https://tusuper.casaley.com.mx/), [localizador](https://www.casaley.com.mx/tiendas/), [preguntas frecuentes](https://tusuper.casaley.com.mx/preguntas-frecuentes), [sitio corporativo y proveedores](https://www.casaley.com.mx/). 24-06-2026 |
| Alsuper | Sí | Sí | Dirección: sí; coordenadas: no confirmado | No confirmado | No confirmado | Probable para el surtido online de una tienda seleccionada, no demostrado por sucursal | Sí: portal de proveedores; API/feed no confirmado | Medio: sitio dinámico con tienda/plaza seleccionada y textos de interfaz parcialmente no resueltos | Medio/alto: no existe licencia pública de datos; revisar términos antes de cualquier operación repetida | `online_only` | `probe_later` | [producto con precio](https://alsuper.com/producto/papas-388868), [tiendas](https://alsuper.com/tiendas), [términos](https://alsuper.com/nosotros/terminos), [portal de proveedores](https://proveedores.alsuper.com/). 24-06-2026 |
| Farmacias Guadalajara | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí, recolección en SuperFarmacia / locker | Probable | Probable | No confirmado | Medio: la propia web indica que precios e inventarios pueden variar según ubicación; falta unir producto, sucursal e identificador estable en una observación pública | Alto para automatización sin permiso; además hay sensibilidad regulatoria y sanitaria en medicamentos | `online_only` hasta prueba completa; luego candidato local | `probe_later` | [tienda online](https://www.farmaciasguadalajara.com/), [localizador](https://www.farmaciasguadalajara.com/buscar-tienda/?showMap=true), [proceso de compra](https://www.farmaciasguadalajara.com/centro-de-atencion/pagina-web/proceso-de-compra.html), [términos](https://www.farmaciasguadalajara.com/terminos-y-condiciones/). 24-06-2026 |
| Farmacias del Ahorro | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí, entrega en sucursal | No confirmado; el sitio rotula precios exclusivos online | Probable para cumplimiento del pedido, no demostrado como inventario público por sucursal | No confirmado; existe sección de alianzas, no un programa de datos verificado | Medio: ubicación y disponibilidad afectan el pedido; varios precios son expresamente exclusivos online | Alto para automatización sin permiso y por el contexto sanitario | `online_only` | `probe_later` | [tienda online](https://www.fahorro.com/), [localizador](https://www.fahorro.com/find-a-store.html), [entrega en sucursal](https://www.fahorro.com/aviso-entrega-pedidos-es), [disponibilidad](https://www.fahorro.com/aviso-cantidad-disponibilidad). 24-06-2026 |
| Farmacias San Pablo | Sí | Sí | Dirección: sí; coordenadas: no confirmado | No confirmado | No confirmado | No confirmado | No confirmado | Medio: catálogo y entrega digital están activos, pero la evidencia pública consultada no enlaza retiro, precio y stock a una sucursal | Alto para automatización sin permiso y por productos sujetos a regulación sanitaria | `online_only` | `probe_later` | [tienda online](https://www.farmaciasanpablo.com.mx/), [sucursales Querétaro](https://www.farmaciasanpablo.com.mx/sucursales-queretaro), [términos de devoluciones](https://assets1.farmaciasanpablo.com.mx/documentos/2401-Terminos%20y%20Condiciones%20Devoluciones.pdf). 24-06-2026 |
| Office Depot México | Sí | Sí | Dirección: sí; coordenadas: no confirmado | No confirmado | No confirmado | No confirmado | Sí: canal B2B con asesoría comercial; API/feed no confirmado | Medio: catálogo dinámico y disponibilidad condicionada por código postal | Medio/alto: términos y derechos del catálogo requieren revisión; preferible acuerdo comercial | `online_only` | `partner_only` | [tienda online](https://www.officedepot.com.mx/), [información y enlaces de tiendas](https://www.officedepot.com.mx/officedepot/en/Factura-Inf-compra-en-tienda-fisica), [Office Depot Negocios](https://b2b.officedepot.com.mx/), [términos del portal](https://www.officedepot.com.mx/officedepot/en/Terminos-Condiciones). 24-06-2026 |
| Steren | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí, retiro en tienda | No confirmado | Probable: muestra “en existencia” para retiro y advierte que el stock es orientativo | No confirmado | Bajo/medio para un probe manual: tienda, dirección y retiro son públicos; falta comprobar el contrato completo en una ficha de producto | Medio/alto para uso sostenido sin licencia; el propio sitio limita la precisión del stock | `online_only` hasta prueba completa | `probe_later` | [tienda Steren Santa Catarina](https://www.steren.com.mx/steren-monterrey-santa-catarina), [tienda Steren Lindavista](https://www.steren.com.mx/steren-shop-parque-lindavista), [términos generales](https://www.steren.com.mx/terminos-y-condiciones-generales). 24-06-2026 |
| Petco México | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí | Probable | Probable | No confirmado | Medio: requiere contexto de “Mi tienda” y el catálogo combina entrega nacional y retiro | Medio/alto: no hay licencia pública de reutilización; categorías veterinarias requieren especial cuidado | `online_only` | `probe_later` | [tienda online](https://www.petco.com.mx/), [buscador de tiendas](https://www.petco.com.mx/petco/en/store-finder), [términos](https://www.petco.com.mx/petco/en/terminos-condiciones). 24-06-2026 |
| Liverpool | Sí | Sí | Dirección: sí; coordenadas: no confirmado | Sí, Click & Collect | Probable | Probable: el selector informa tiendas con disponibilidad, pero falta una captura completa atribuible y repetible | Sí: marketplace comercial; API/feed no confirmado | Medio: selector dinámico por producto y tienda; distinguir vendedor Liverpool de terceros | Alto sin licencia por catálogo, imágenes, marcas y datos de marketplace | `online_only`; `partner_feed` solo mediante acuerdo | `partner_only` | [tienda online](https://www.liverpool.com.mx/tienda/home), [Click & Collect](https://www.liverpool.com.mx/tienda/paginas/comunicado), [localizador](https://www.liverpool.com.mx/tienda/browse/storelocator), [portal oficial de Marketplace](https://mkpsellerportal.liverpool.com.mx/). 24-06-2026 |
| PROFECO Quién es Quién en los Precios | Sí: precios observados, no catálogo transaccional | Sí: identifica establecimientos en los datos | Localización del establecimiento: sí; coordenadas: verificar por recurso | No aplica | Confirmado como observación fechada en establecimiento, no como precio actual en vivo | No | Sí: CSV oficial con licencia CC BY 4.0 | Bajo: recursos CSV públicos; controlar esquema, rezago y actualizaciones retroactivas | Bajo/medio: cumplir atribución CC BY 4.0 y no sugerir respaldo comercial de PROFECO | `observed_establishment_price` | `go` | [dataset 2025](https://www.datos.gob.mx/dataset/programa_quien_es_quien_precios_2025), [sitio QQP](https://www.gob.mx/profeco/articulos/quien-es-quien-en-los-precios-35141), [explicación oficial](https://www.gob.mx/profeco/documentos/que-es-el-qqp-y-como-funciona). 24-06-2026 |

### Lectura comercial de la matriz

- `go` no significa “tiempo real”: para PROFECO significa que existe una ruta
  oficial, descargable y licenciada para publicar observaciones históricas con
  atribución y fecha.
- `probe_later` autoriza únicamente un experimento técnico pasivo y acotado; no
  equivale a aprobación para scraping productivo.
- `partner_only` indica que la escala o la complejidad del canal hace más
  razonable negociar un acceso que depender de interfaces de consumo.
- “Probable” nunca habilita publicación como `branch_local_realtime`.
- No se usa `no_go` porque las fuentes públicas consultadas no bastan para
  declarar una imposibilidad permanente. Si una revisión jurídica o los
  términos aplicables prohíben el uso previsto, el veredicto debe cambiar a
  `no_go` o `not_recommended`.

## 3. Estándar de evidencia

Una observación solo puede clasificarse como `branch_local_realtime` cuando el
mismo artefacto oficial o una cadena de evidencia inequívoca y auditable
contiene:

```text
branch_external_key
+ SKU
+ precio
+ moneda
+ disponibilidad o stock
+ evidencia oficial
+ captured_at
```

Requisitos operativos adicionales:

1. `branch_external_key` debe identificar una sucursal física estable, no una
   ciudad, zona de reparto, código postal o región comercial.
2. El SKU debe ser estable y corresponder exactamente al producto y
   presentación publicados.
3. Precio y moneda deben pertenecer a esa misma sucursal y sesión de
   observación.
4. Disponibilidad debe indicar al menos disponible/no disponible para esa
   sucursal; una cantidad de stock es preferible.
5. La evidencia debe ser oficial, reproducible y conservar URL o referencia
   suficiente para auditoría.
6. `captured_at` debe registrar el momento real de la captura y no una fecha
   inferida o ficticia.
7. La sucursal debe poder enlazarse con nombre y dirección oficial; para la
   experiencia geolocalizada también debe tener coordenadas verificadas.

No son evidencia suficiente, por separado ni combinados de manera ambigua:

- un código postal;
- un precio nacional;
- un segmento regional;
- un catálogo online;
- un selector de tienda sin stock atribuible;
- pickup disponible sin identificar qué inventario lo habilita;
- una promesa de entrega rápida;
- una oferta de marketplace de un tercero;
- un precio observado por PROFECO.

El precio de PROFECO es valioso, pero representa una observación fechada en un
establecimiento. No prueba que el precio siga vigente ni que exista stock al
momento de la consulta del usuario.

## 4. Rutas alternativas al scraping

| Ruta | Viabilidad | Costo relativo | Beneficio | Condición mínima |
|---|---|---:|---|---|
| API o feed oficial del retailer | Alta técnicamente cuando existe; hoy no se confirmó una API pública de inventario local para estas cadenas | Medio/alto comercial; bajo operativo después de integrar | Mejor frescura, identificadores estables, menor ambigüedad y SLA negociable | Contrato, alcance de sucursales, licencia, rate limits, soporte y campos obligatorios |
| Acuerdo comercial directo | Alta para una cadena ancla si Tiago demuestra valor de adquisición o analítica | Alto al inicio | Puede habilitar precio y stock local, uso de marca, imágenes y promoción conjunta | Propuesta comercial, seguridad, privacidad, atribución, correcciones y terminación |
| Feed CSV/XLSX/SFTP | **Muy alta para un MVP B2B**; suele ser más simple que una API | Bajo/medio | Entrega rápida, auditable y compatible con sistemas legados | Archivo incremental con sucursal, SKU, precio, moneda, stock/disponibilidad y fecha |
| Marketplace o afiliados | Media/alta para catálogo y precio online | Medio | Cobertura rápida, monetización y enlaces de compra | Confirmar licencia de contenido, vendedor, vigencia, comisión y si el dato es solo online |
| PROFECO | Alta | Bajo | Cobertura multisector, establecimientos identificados, licencia CC BY 4.0 | Mostrar fecha de observación, atribución y etiqueta `observed_establishment_price` |
| Panel para comercios | Alta para comercios independientes y cadenas regionales | Medio de producto y soporte | Datos autorizados por el propio comercio, diferenciación local y correcciones rápidas | Verificación del comercio, roles, auditoría, caducidad y formato normalizado |
| Precios colaborativos con ticket/foto | Media | Medio por moderación y antifraude | Amplía cobertura donde no hay integración; fortalece comunidad | Consentimiento, ocultamiento de datos personales, sucursal, fecha, evidencia y revisión |

### Recomendación de arquitectura comercial

La secuencia más eficiente es:

1. integrar PROFECO como capa histórica claramente rotulada;
2. ofrecer un panel/feed simple a comercios regionales;
3. cerrar un acuerdo con una cadena ancla para un CSV incremental por SFTP;
4. solo después justificar una API de mayor frecuencia;
5. mantener los catálogos públicos sin licencia como investigación o enlaces
   online, no como base de una operación sostenida.

Un feed mínimo debería contener:

```text
retailer
branch_external_key
branch_name
branch_address
latitude
longitude
sku
gtin
product_name
presentation
price
currency
available
stock_quantity
effective_at
expires_at
source_revision
```

## 5. Priorización final

### Las 3 mejores candidatas para un probe técnico futuro

#### 1. H-E-B México

**Por qué:** tiene alto valor para supermercado, catálogo público, locator con
direcciones, selección explícita de sucursal y Pick&Go. La ayuda oficial afirma
que la compra se asigna o surte desde una tienda, pero falta demostrar la tupla
completa sin iniciar sesión.

**Experimento de máximo una hora:** elegir dos sucursales públicas y un mismo
SKU visible; revisar una ficha pública con cada tienda seleccionada, sin login,
carrito ni checkout, y registrar solo la evidencia necesaria.

**Evidencia necesaria:** identificador estable de cada sucursal, SKU, precio
MXN, disponibilidad/stock, nombre/dirección oficial y una referencia que
conserve la tienda seleccionada.

**Éxito:** obtener dos observaciones completas y atribuibles del mismo SKU, una
por sucursal, idealmente con diferencia de precio o disponibilidad.

**Abandono:** si exige cuenta, checkout, llamadas no documentadas, CAPTCHA,
aparece rate limiting o el dato solo se atribuye a ciudad/zona.

**Impacto esperado:** primera expansión fuerte de supermercado regional con
valor directo para comparación de canasta.

#### 2. Steren

**Por qué:** las páginas públicas de tienda muestran dirección y el flujo
oficial ofrece retiro en 60 minutos, “en existencia” y selección manual de
tienda. Es la señal pública más explícita de stock local entre las cadenas no
confirmadas, aunque el sitio advierte que es orientativo.

**Experimento de máximo una hora:** seleccionar dos tiendas públicas y revisar
un solo SKU en la ficha pública, sin automatización, para comprobar si precio y
existencia quedan asociados a la tienda elegida.

**Evidencia necesaria:** clave estable de tienda, SKU, precio, MXN,
disponibilidad, URL/evidencia oficial, dirección y hora de captura.

**Éxito:** dos tuplas completas por tienda y una señal local distinta o
reproducible, conservando la advertencia de stock orientativo.

**Abandono:** si el estado de existencia no queda ligado a una tienda estable,
si el precio es exclusivamente nacional o si se requiere carrito/login.

**Impacto esperado:** valida el patrón local en una vertical de electrónica y
hogar con menor complejidad de catálogo que un supermercado.

#### 3. Farmacias Guadalajara

**Por qué:** el sitio oficial declara expresamente que precios e inventarios
pueden variar según la ubicación seleccionada, ofrece locator y recolección en
SuperFarmacia/locker, y tiene amplia cobertura nacional.

**Experimento de máximo una hora:** usar un producto no sujeto a receta y dos
SuperFarmacias públicas; observar pasivamente si la ficha enlaza precio e
inventario a cada sucursal, sin cuenta ni pedido.

**Evidencia necesaria:** identificador de SuperFarmacia, SKU, precio MXN,
disponibilidad, dirección oficial, evidencia y `captured_at`.

**Éxito:** dos observaciones completas del mismo SKU con sucursal inequívoca.

**Abandono:** si la ubicación solo representa zona de entrega, si requiere
login/checkout o si el sitio ofrece disponibilidad únicamente después del
pedido.

**Impacto esperado:** cobertura nacional de farmacia y conveniencia; debe
iniciarse con productos de libre venta y consumo general para reducir riesgo.

### Las 3 mejores fuentes para catálogo/precio online

Estas prioridades son para una futura sección `online_only`, sujeta a permiso o
licencia; no habilitan extracción productiva por sí mismas.

#### 1. Walmart México / Bodega Aurrera

**Por qué:** amplitud nacional, surtido masivo, precios públicos y fuerte valor
de marca para usuarios.

**Experimento de máximo una hora:** documentar manualmente cinco fichas vendidas
por la propia cadena y verificar estabilidad de SKU, precio, moneda, vendedor,
URL e imagen, sin superar navegación humana normal.

**Evidencia necesaria:** distinción entre retailer y marketplace, precio
online, moneda, SKU/GTIN si aparece, URL y condiciones de vigencia.

**Éxito:** cinco fichas consistentes y una ruta comercial identificada para
licenciar o afiliar el catálogo.

**Abandono:** controles anti-bot, identidad humana obligatoria o imposibilidad
de separar vendedores externos.

**Impacto esperado:** mayor cobertura potencial de categorías y reconocimiento
inmediato para el comparador.

#### 2. Soriana

**Por qué:** catálogo amplio de supermercado, presencia nacional, pickup y
portal comercial oficial.

**Experimento de máximo una hora:** revisar cinco SKUs públicos de despensa,
separar catálogo extendido del surtido propio y documentar si el precio depende
de tienda o CP.

**Evidencia necesaria:** SKU, presentación, precio online, moneda, vendedor,
URL y alcance geográfico.

**Éxito:** catálogo propio distinguible y contacto partner/proveedor adecuado
para solicitar feed.

**Abandono:** precio solo visible tras login, atribución geográfica ambigua o
mezcla inseparable con terceros.

**Impacto esperado:** alta relevancia para canasta básica y complementariedad
geográfica con otras cadenas.

#### 3. Farmacias Guadalajara

**Por qué:** catálogo público con precios, presencia nacional y categorías que
incluyen farmacia, cuidado personal, hogar y conveniencia.

**Experimento de máximo una hora:** revisar cinco productos no sujetos a receta
y registrar precio online, SKU, presentación, URL y advertencias de ubicación.

**Evidencia necesaria:** alcance online, categoría regulatoria, precio, moneda,
SKU, presentación y restricciones.

**Éxito:** fichas estables y una política clara para excluir medicamentos
controlados o sujetos a receta de la primera versión.

**Abandono:** si la visibilidad exige datos personales, pedido o contexto
sanitario que Tiago no pueda representar correctamente.

**Impacto esperado:** amplía comparación de compras frecuentes con una cadena
de gran cobertura.

### Mejor ruta no-scraping para precio y stock por tienda

**Acuerdo comercial con una cadena ancla y feed incremental CSV por SFTP,
evolucionable a API.**

**Por qué se prioriza:** es más rápido de negociar e implementar que una API,
funciona con sistemas legados y puede incluir exactamente los campos que Tiago
necesita. También resuelve de forma contractual derechos de uso, frecuencia,
marcas, imágenes, correcciones y soporte.

**Experimento de máximo una hora:** preparar y enviar internamente una muestra
de especificación de feed con diez filas ficticias y validar que el pipeline
puede mapear cada campo sin inventar datos. El contacto externo requiere
aprobación comercial previa.

**Evidencia necesaria:** contrato/licencia, diccionario de datos, muestra real,
identificadores estables, frecuencia, SLA, política de corrección y contacto
operativo.

**Éxito:** el retailer entrega una muestra que contiene por fila
`branch_external_key + SKU + precio + moneda + disponibilidad/stock +
effective_at`, y autoriza su publicación.

**Abandono:** ausencia de derechos de publicación, sucursal no identificable,
actualización demasiado lenta para la etiqueta acordada o imposibilidad de
corregir/revocar datos.

**Impacto esperado:** primera cobertura escalable y defendible de precio y
stock por tienda, con menor costo operativo y legal que mantener conectores
frágiles.

## 6. Texto para presentar al cliente

> Tiago Market ya validó una integración local en vivo con The Home Depot
> México: los precios y la disponibilidad se vinculan a sucursales físicas
> identificadas y geolocalizadas. Otras cadenas —incluidos supermercados,
> farmacias, electrónica y tiendas departamentales— están en evaluación bajo el
> mismo estándar.
>
> Cuando una fuente solo publica un precio online, un catálogo o una
> observación histórica, Tiago la identifica como tal y no la presenta como
> stock de tienda. La cobertura se construye mediante conectores verificados,
> feeds autorizados, datos abiertos como PROFECO y aportes revisados de
> comercios o usuarios. Así se amplía la utilidad del producto sin prometer
> información local que la fuente no demuestra.

## 7. Cumplimiento y advertencia legal

Este documento es una evaluación técnica y comercial; **no constituye
asesoramiento jurídico**.

Antes de operar de forma comercial y sostenida debe realizarse una revisión
específica de:

- términos de uso, robots.txt y contratos aplicables, entendiendo que
  `robots.txt` no es autorización legal suficiente;
- licencias de bases de datos, textos, imágenes, catálogos y precios;
- uso de nombres comerciales, logotipos y otras marcas;
- derecho a almacenar, transformar, comparar y redistribuir información;
- Ley Federal de Protección de Datos Personales en Posesión de los Particulares
  y avisos de privacidad aplicables;
- consentimiento, minimización y precisión de geolocalización;
- tratamiento de tickets/fotografías y ocultamiento de datos personales;
- reglas sanitarias y publicitarias para medicamentos y productos regulados;
- atribución de PROFECO y condiciones de CC BY 4.0;
- mecanismo visible de retiro, rectificación y corrección de datos;
- canal de contacto para retailers, titulares de derechos y consumidores;
- conservación de evidencia, caducidad del dato e historial de cambios.

Antes del lanzamiento se recomienda consultar a un **abogado mexicano** con
experiencia en comercio electrónico, propiedad intelectual, protección de
datos, competencia y regulación sanitaria.

## Conclusión

El veredicto es favorable para una expansión por capas, no para una promesa
indiscriminada de stock local:

- Home Depot México permanece como el único
  `branch_local_realtime` confirmado;
- PROFECO puede incorporarse como `observed_establishment_price`;
- múltiples cadenas son útiles como `online_only`, sujeto a derechos de uso;
- H-E-B, Steren y Farmacias Guadalajara justifican probes pasivos futuros;
- Walmart/Bodega Aurrera, Office Depot y Liverpool deben priorizarse por vía
  comercial o partner antes que por recolección sostenida;
- el objetivo estratégico debe ser un feed oficial por sucursal.
