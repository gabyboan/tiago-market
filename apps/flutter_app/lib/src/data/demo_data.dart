import 'package:tiago_market_app/src/models/models.dart';

const demoPrices = [
  PriceResult(
    storeName: 'Arteli online',
    productName: 'Refresco Coca-Cola sin Azúcar 600ml',
    price: 15,
    source: 'arteli-direct',
    capturedAt: '2026-06-13T02:57:31.493Z',
    imageUrl:
        'https://arteli.vteximg.com.br/arquivos/ids/201431/7501055320639_00.jpg?v=638576437520930000',
    storeProductUrl:
        'https://www.arteli.com.mx/refresco-coca-cola-sin-azucar-600ml-3062158/p',
  ),
  PriceResult(
    storeName: 'Smart & Final México online',
    productName: 'Soda Coca Cola light 600 ml',
    price: 24,
    source: 'smart-final-direct',
    capturedAt: '2026-06-13T02:57:29.956Z',
    imageUrl:
        'https://www.smartnfinal.com.mx/wp-content/uploads/2021/07/91024-Soda-sabor-cola-ligera-Coca-Cola-600-ml.jpg',
    storeProductUrl:
        'https://www.smartnfinal.com.mx/tienda/aguas-y-bebidas/soda-sabor-cola-ligera-coca-cola/',
  ),
];

const demoMilkPrices = [
  PriceResult(
    storeName: 'Smart & Final México online',
    productName: 'Leche entera Santa Clara 1 l',
    price: 38,
    source: 'smart-final-direct',
    capturedAt: '2026-06-13T02:57:29.956Z',
    imageUrl:
        'https://www.smartnfinal.com.mx/wp-content/uploads/2022/11/7951-Leche-entera-Santa-Clara-1-l.jpg',
    storeProductUrl:
        'https://www.smartnfinal.com.mx/tienda/desayuno-y-reposteria/leche-entera-santa-clara-2/',
  ),
];

const demoRicePrices = [
  PriceResult(
    storeName: 'Arteli online',
    productName: 'Arroz SOS integral 1Kg',
    price: 16.5,
    source: 'arteli-direct',
    capturedAt: '2026-06-13T02:57:31.493Z',
    imageUrl:
        'https://arteli.vteximg.com.br/arquivos/ids/214145/7501111105095_00.jpg?v=638576494379770000',
    storeProductUrl:
        'https://www.arteli.com.mx/arroz-sos-integral-1kg-3008400/p',
  ),
];

const demoEggPrices = [
  PriceResult(
    storeName: 'Arteli online',
    productName: 'Huevo San Juan Blanco 12 Piezas',
    price: 28.5,
    source: 'arteli-direct',
    capturedAt: '2026-06-13T02:57:31.493Z',
    imageUrl:
        'https://www.arteli.com.br/arquivos/ids/256360/7503000555011_00.jpg?v=638635805372130000',
    storeProductUrl:
        'https://www.arteli.com.mx/huevo-san-juan-blanco-12-piezas-3101213/p',
  ),
];

List<PriceResult> demoPricesFor(String query) {
  final normalized = query.toLowerCase();
  if (normalized.contains('leche')) return demoMilkPrices;
  if (normalized.contains('arroz')) return demoRicePrices;
  if (normalized.contains('huevo')) return demoEggPrices;
  return demoPrices;
}
