import assert from "node:assert/strict";
import test from "node:test";
import type { ScrapedProduct } from "../scrapers/types.js";
import { snapshotRecord } from "./save-scraped-product.js";

const product: ScrapedProduct = {
  storeSlug: "tienda",
  storeName: "Tienda",
  source: "profeco",
  sourceProductName: "Producto observado",
  sourceStoreName: "Tienda",
  sourceBranchName: "Sucursal",
  sourceBranchKey: "branch-key",
  sourceAddress: null,
  sourceNeighborhood: null,
  sourcePostalCode: null,
  sourceMunicipality: null,
  sourceState: null,
  sourceCityCode: "0901",
  sourceCityName: "Ciudad de Mexico",
  externalReference: "https://example.com/observation",
  rawPayload: { source: "test" },
  searchTerm: "producto",
  internalProductName: "Producto",
  normalizedName: "producto",
  category: "Categoria",
  externalName: "Producto observado - Sucursal",
  price: 10,
  currency: "MXN",
  externalUrl: "https://example.com/listing",
  storeProductUrl: null,
  imageUrl: null,
  presentation: null,
  available: true,
  scrapedAt: "2026-06-09T12:00:00.000Z",
};

test("snapshotRecord conserva la clave idempotente de la observacion", () => {
  const snapshot = snapshotRecord(product, "store-product-id", "branch-id");

  assert.equal(snapshot.store_product_id, "store-product-id");
  assert.equal(snapshot.captured_at, product.scrapedAt);
  assert.equal(snapshot.price, product.price);
  assert.equal(snapshot.branch_id, "branch-id");
});
