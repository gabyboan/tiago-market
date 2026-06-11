import assert from "node:assert/strict";
import test from "node:test";
import {
  catalogPriceToScrapedProduct,
  selectLatestCatalogListings,
} from "./profeco-catalog.js";
import type { ProfecoPrice } from "./profeco.js";

const basePrice: ProfecoPrice = {
  producto: "LECHE, MARCA EJEMPLO, CAJA 1 L",
  tipo_producto: "LECHE ULTRAPASTEURIZADA",
  precio: 25,
  fecha_observacion: "2026-06-01",
  cadena_comercial: "TIENDA",
  establecimiento: "SUCURSAL CENTRO",
};

test("catálogo conserva solo la observación más reciente por listing", () => {
  const selected = selectLatestCatalogListings(
    [basePrice, { ...basePrice, precio: 24, fecha_observacion: "2026-06-09" }],
    100,
  );
  assert.equal(selected.length, 1);
  assert.equal(selected[0]?.precio, 24);
});

test("catálogo crea productos desde el nombre real PROFECO", () => {
  const product = catalogPriceToScrapedProduct(basePrice, "leche");
  assert.equal(product.internalProductName, basePrice.producto);
  assert.equal(product.category, basePrice.tipo_producto);
  assert.equal(product.storeProductUrl, null);
  assert.match(product.externalReference ?? "", /^https:\/\/qqp\.profeco/);
});

test("un límite pequeño reparte resultados entre productos", () => {
  const selected = selectLatestCatalogListings(
    [
      basePrice,
      { ...basePrice, establecimiento: "SUCURSAL NORTE" },
      { ...basePrice, producto: "ARROZ, MARCA EJEMPLO, BOLSA 1 KG" },
    ],
    2,
  );

  assert.equal(new Set(selected.map((price) => price.producto)).size, 2);
});
