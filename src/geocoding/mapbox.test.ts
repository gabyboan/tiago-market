import assert from "node:assert/strict";
import test from "node:test";
import { buildGeocodingQuery, parseMapboxResult } from "./mapbox.js";

const branch = {
  id: "branch-id",
  name: "Sucursal Centro",
  address: "Av. Principal 123",
  neighborhood: "Centro",
  postal_code: "06000",
  municipality: "Cuauhtémoc",
  state: "Ciudad de México",
  geocoding_attempts: 0,
};

test("construye una consulta completa para México", () => {
  assert.equal(
    buildGeocodingQuery(branch),
    "Av. Principal 123, Centro, 06000, Cuauhtémoc, Ciudad de México, México",
  );
});

test("interpreta coordenadas, confianza y precisión de Mapbox", () => {
  const result = parseMapboxResult({
    features: [
      {
        id: "address.123",
        geometry: { coordinates: [-99.1332, 19.4326] },
        properties: {
          match_code: { confidence: "high" },
          coordinates: { accuracy: "rooftop" },
        },
      },
    ],
  });

  assert.deepEqual(result, {
    latitude: 19.4326,
    longitude: -99.1332,
    confidence: 0.9,
    accuracy: "rooftop",
    externalId: "address.123",
    payload: {
      features: [
        {
          id: "address.123",
          geometry: { coordinates: [-99.1332, 19.4326] },
          properties: {
            match_code: { confidence: "high" },
            coordinates: { accuracy: "rooftop" },
          },
        },
      ],
    },
  });
});

test("devuelve null cuando Mapbox no encuentra resultados", () => {
  assert.equal(parseMapboxResult({ features: [] }), null);
});
