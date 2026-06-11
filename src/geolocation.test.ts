import assert from "node:assert/strict";
import test from "node:test";
import { distanceKm } from "./geolocation.js";

test("calcula distancia aproximada entre dos coordenadas", () => {
  const distance = distanceKm(19.4326, -99.1332, 19.427, -99.1677);
  assert.ok(distance > 3.5 && distance < 4.5);
});

test("la distancia al mismo punto es cero", () => {
  assert.equal(distanceKm(19.4326, -99.1332, 19.4326, -99.1332), 0);
});
