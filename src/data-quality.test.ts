import assert from "node:assert/strict";
import test from "node:test";
import { freshnessFor } from "./data-quality.js";
import { snapshotRecord } from "./db/save-scraped-product.js";
import type { ScrapedProduct } from "./scrapers/types.js";

const now = new Date("2026-06-11T12:00:00.000Z");

test("marca un precio de menos de 7 días como fresh", () => {
  assert.equal(freshnessFor("2026-06-05T12:00:00.000Z", now), "fresh");
});

test("marca un precio de más de 21 días como old", () => {
  assert.equal(freshnessFor("2026-05-20T12:00:00.000Z", now), "old");
});

test("el snapshot conserva raw_payload y captured_at nunca es null", () => {
  const product: ScrapedProduct = {
    storeSlug: "tienda",
    source: "arteli-direct",
    sourceProductName: "Producto fuente",
    sourceStoreName: "Tienda",
    sourceBranchName: "Sucursal Centro",
    sourceBranchKey: "tienda-sucursal-centro",
    sourceAddress: "Av. Principal 123",
    sourceNeighborhood: "Centro",
    sourcePostalCode: "01000",
    sourceMunicipality: "Álvaro Obregón",
    sourceState: "Ciudad de México",
    sourceCityCode: "0901",
    sourceCityName: "Ciudad de México",
    externalReference: "https://example.com/reference",
    rawPayload: { precio: 19.5, original: true },
    searchTerm: "producto",
    internalProductName: "Producto",
    normalizedName: "producto",
    category: null,
    externalName: "Producto · Sucursal Centro",
    price: 19.5,
    currency: "MXN",
    externalUrl: null,
    storeProductUrl: null,
    imageUrl: null,
    presentation: null,
    available: true,
    scrapedAt: "2026-06-10T12:00:00.000Z",
  };

  const snapshot = snapshotRecord(product, "listing-id");
  assert.equal(snapshot.captured_at, product.scrapedAt);
  assert.deepEqual(snapshot.raw_payload, product.rawPayload);
});
