import assert from "node:assert/strict";
import test from "node:test";
import type { ScrapedProduct } from "../scrapers/types.js";
import { saveSnapshot, snapshotRecord } from "./save-scraped-product.js";
import { supabase } from "./supabase.js";

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

test("snapshots accept only idempotent conflicts and surface other database errors", async () => {
  for (const branchId of [null, "branch-id"]) {
    const index = branchId === null
      ? "price_snapshots_online_observation_unique"
      : "price_snapshots_store_product_branch_captured_unique";
    const snapshot = snapshotRecord(product, "store-product-id", branchId);
    for (const error of [
      null,
      { code: "23505", message: `duplicate key value violates unique constraint "${index}"` },
      { code: "23505", message: 'duplicate key value violates unique constraint "price_snapshots_pkey"' },
      { code: "42501", message: "permission denied" },
    ]) {
      const client = {
        from(table: string) {
          assert.equal(table, "price_snapshots");
          return {
            async insert(record: unknown) {
              assert.deepEqual(record, snapshot);
              return { error };
            },
          };
        },
      } as unknown as Pick<typeof supabase, "from">;
      if (error && !error.message.includes(`"${index}"`)) {
        await assert.rejects(saveSnapshot(snapshot, client), /No se pudo guardar el precio/);
      } else {
        await saveSnapshot(snapshot, client);
      }
    }
  }
});
