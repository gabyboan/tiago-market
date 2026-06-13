import assert from "node:assert/strict";
import test from "node:test";
import type { ScrapedProduct } from "../scrapers/types.js";
import { validateDirectProduct } from "./direct-product.js";

const product: ScrapedProduct = {
  storeSlug: "store",
  source: "store-direct",
  sourceProductName: "Producto",
  sourceStoreName: "Tienda",
  sourceBranchName: null,
  sourceBranchKey: null,
  sourceAddress: null,
  sourceNeighborhood: null,
  sourcePostalCode: null,
  sourceMunicipality: null,
  sourceState: null,
  sourceCityCode: null,
  sourceCityName: null,
  externalReference: "https://example.com/search",
  rawPayload: {},
  searchTerm: "producto",
  internalProductName: "Producto",
  normalizedName: "producto",
  category: "Categoría",
  externalName: "Producto",
  price: 10,
  currency: "MXN",
  externalUrl: "https://example.com/producto",
  storeProductUrl: "https://example.com/producto",
  imageUrl: "https://example.com/producto.jpg",
  presentation: null,
  available: true,
  scrapedAt: new Date().toISOString(),
};

test("acepta un producto directo verificable", () => {
  assert.deepEqual(validateDirectProduct(product), {
    accepted: true,
    issues: [],
  });
});

test("rechaza resultados sin imagen o enlace oficial", () => {
  const quality = validateDirectProduct({
    ...product,
    imageUrl: null,
    storeProductUrl: null,
  });
  assert.equal(quality.accepted, false);
  assert.deepEqual(quality.issues, ["missing_official_link", "missing_image"]);
});
