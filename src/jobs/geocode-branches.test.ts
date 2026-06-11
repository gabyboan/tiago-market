import assert from "node:assert/strict";
import test from "node:test";
import { statusForConfidence } from "./geocode-branches.js";

test("acepta un resultado que supera el umbral", () => {
  assert.equal(statusForConfidence(0.9, 0.8), "geocoded");
});

test("envía un resultado ambiguo a revisión", () => {
  assert.equal(statusForConfidence(0.65, 0.8), "review");
});
