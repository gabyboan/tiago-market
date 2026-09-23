import assert from "node:assert/strict";
import test from "node:test";
import { parseProductVariant } from "./variant.js";

test("normaliza cantidad y unidad", () => {
  assert.deepEqual(parseProductVariant("Leche entera 1 litro"), {
    variantLabel: "leche entera",
    netQuantity: 1,
    unit: "l",
    packCount: null,
    canonicalVariantKey: "leche entera|qty=1l",
  });
});

test("extrae multipack sin confundirlo con cantidad neta", () => {
  assert.deepEqual(parseProductVariant("Papel higienico 4 rollos"), {
    variantLabel: "papel higienico",
    netQuantity: null,
    unit: null,
    packCount: 4,
    canonicalVariantKey: "papel higienico|pack=4",
  });
});