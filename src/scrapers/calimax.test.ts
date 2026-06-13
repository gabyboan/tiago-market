import assert from "node:assert/strict";
import test from "node:test";
import type { ProductMeta } from "../products/products-test.js";
import {
  calimaxProductMatches,
  calimaxProductToScrapedProduct,
  parseCalimaxProducts,
} from "./calimax.js";

const productMeta: ProductMeta = {
  internalName: "Leche entera 1 gal",
  normalizedName: "leche entera 1 gal",
  category: "Lácteos",
  searchTerms: ["leche entera 1 gal"],
};

const product = {
  name: "LECHE ENTERA JERSEY 1-GAL",
  description: "LECHE ENTERA JERSEY",
  brand: "JERSEY",
  sku: 618010,
  ean: "7501362610058",
  stock: 63,
  price: 98.9,
  price_list: 98.9,
  category_name: "LÁCTEOS Y HUEVO",
  image_url_main: "https://example.com/leche.jpg",
  linkid: "leche-entera-jersey-1-gal-618010",
  fecha: "2026-06-12T17:46:25.167Z",
};

test("Calimax extrae productos únicos del estado público", () => {
  const html = `<script id="ng-state" type="application/json">${JSON.stringify({
    one: { b: { hits: [product] } },
    two: { b: { hits: [product] } },
  })}</script>`;
  assert.equal(parseCalimaxProducts(html).length, 1);
});

test("Calimax conserva imagen, precio y búsqueda oficial por SKU", () => {
  assert.equal(calimaxProductMatches(product, productMeta), true);
  const scraped = calimaxProductToScrapedProduct(
    product,
    "https://www.calimax.com.mx/productos?search=leche",
    "leche entera 1 gal",
    productMeta,
  );
  assert.equal(scraped.price, 98.9);
  assert.equal(
    scraped.storeProductUrl,
    "https://www.calimax.com.mx/productos?search=618010",
  );
  assert.equal(scraped.imageUrl, product.image_url_main);
});

test("Calimax rechaza una presentación diferente", () => {
  assert.equal(
    calimaxProductMatches(
      { ...product, name: "LECHE ENTERA JERSEY 0.5-GAL" },
      productMeta,
    ),
    false,
  );
});
