import assert from "node:assert/strict";
import test from "node:test";
import {
  comparisonKey,
  normalizedPresentation,
  normalizeProductName,
} from "./normalize.js";

test("normaliza unidades equivalentes a una misma presentación", () => {
  assert.equal(normalizedPresentation("Leche 1 L"), "1000:ml");
  assert.equal(normalizedPresentation("Leche 1000 ml"), "1000:ml");
  assert.equal(normalizedPresentation("Arroz 1 kg"), "1000:g");
  assert.equal(normalizedPresentation("Arroz 1000 gramos"), "1000:g");
});

test("la clave de comparación incluye la presentación", () => {
  assert.notEqual(
    comparisonKey("Leche entera", "1 l"),
    comparisonKey("Leche entera", "2 l"),
  );
});

test("iguala unidades equivalentes pero conserva multipacks", () => {
  assert.equal(
    comparisonKey("Leche entera 1 l"),
    comparisonKey("Leche entera 1000 ml"),
  );
  assert.notEqual(
    comparisonKey("Yoghurt bebible 6 piezas de 220 g"),
    comparisonKey("Yoghurt bebible 220 g"),
  );
});

test("normaliza acentos y separa cantidades", () => {
  assert.equal(normalizeProductName("Café 100g"), "cafe 100 g");
});
