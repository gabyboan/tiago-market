import assert from "node:assert/strict";
import test from "node:test";
import type { ProductMeta } from "../products/products-test.js";
import {
  smartFinalProductMatches,
  smartFinalProductToScrapedProduct,
} from "./smart-final.js";
import type { WooStoreProduct } from "./woocommerce.js";

const productMeta: ProductMeta = {
  internalName: "Leche entera 1 L",
  normalizedName: "leche entera 1 l",
  category: "Lácteos",
  searchTerms: ["leche entera 1 l"],
};

const product: WooStoreProduct = {
  id: 49803,
  name: "Leche entera Santa Clara",
  permalink:
    "https://www.smartnfinal.com.mx/tienda/desayuno-y-reposteria/leche-entera-santa-clara-2/",
  sku: "7951",
  short_description: "<p><strong>1 l</strong></p>",
  prices: {
    price: "3800",
    regular_price: "3800",
    sale_price: "3800",
    currency_code: "MXN",
    currency_minor_unit: 2,
  },
  images: [{ src: "https://example.com/leche.jpg" }],
  categories: [{ name: "Lácteos" }],
  is_purchasable: true,
  is_in_stock: true,
};

test("Smart & Final convierte centavos y conserva la ficha oficial", () => {
  const scraped = smartFinalProductToScrapedProduct(
    product,
    "https://www.smartnfinal.com.mx/wp-json/wc/store/v1/products?search=leche",
    "leche entera 1 l",
    productMeta,
  );

  assert.equal(scraped.price, 38);
  assert.equal(scraped.storeProductUrl, product.permalink);
  assert.equal(scraped.presentation, "1 l");
});

test("Smart & Final evita presentaciones y variantes no comparables", () => {
  assert.equal(smartFinalProductMatches(product, productMeta), true);
  assert.equal(
    smartFinalProductMatches(
      { ...product, short_description: "<p>6 pzas</p>" },
      productMeta,
    ),
    false,
  );
  assert.equal(
    smartFinalProductMatches(
      { ...product, name: "Leche entera deslactosada Santa Clara" },
      productMeta,
    ),
    false,
  );
});
