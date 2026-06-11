import { z } from "zod";

const MAPBOX_FORWARD_URL = "https://api.mapbox.com/search/geocode/v6/forward";

const mapboxFeatureSchema = z.object({
  id: z.string(),
  geometry: z.object({
    coordinates: z.tuple([z.number(), z.number()]),
  }),
  properties: z
    .object({
      match_code: z
        .object({
          confidence: z.enum(["exact", "high", "medium", "low"]).optional(),
        })
        .passthrough()
        .optional(),
      coordinates: z
        .object({
          accuracy: z.string().optional(),
        })
        .passthrough()
        .optional(),
    })
    .passthrough(),
});

const mapboxResponseSchema = z
  .object({
    features: z.array(mapboxFeatureSchema),
  })
  .passthrough();

const confidenceScores = {
  exact: 1,
  high: 0.9,
  medium: 0.65,
  low: 0.35,
} as const;

export type GeocodingBranch = {
  id: string;
  name: string;
  address: string | null;
  neighborhood: string | null;
  postal_code: string | null;
  municipality: string | null;
  state: string | null;
  geocoding_attempts: number;
};

export type MapboxResult = {
  latitude: number;
  longitude: number;
  confidence: number;
  accuracy: string | null;
  externalId: string;
  payload: Record<string, unknown>;
};

export function buildGeocodingQuery(branch: GeocodingBranch): string {
  const query = [
    branch.address,
    branch.neighborhood,
    branch.postal_code,
    branch.municipality,
    branch.state,
    "México",
  ]
    .filter(Boolean)
    .join(", ");

  return query.split(/\s+/).slice(0, 20).join(" ").slice(0, 256);
}

export function parseMapboxResult(payload: unknown): MapboxResult | null {
  const parsed = mapboxResponseSchema.parse(payload);
  const feature = parsed.features[0];
  if (!feature) return null;

  const [longitude, latitude] = feature.geometry.coordinates;
  const confidenceName = feature.properties.match_code?.confidence;

  return {
    latitude,
    longitude,
    confidence: confidenceName ? confidenceScores[confidenceName] : 0.5,
    accuracy: feature.properties.coordinates?.accuracy ?? null,
    externalId: feature.id,
    payload: parsed as Record<string, unknown>,
  };
}

export async function geocodeWithMapbox(
  branch: GeocodingBranch,
  accessToken: string,
): Promise<{ query: string; result: MapboxResult | null }> {
  const query = buildGeocodingQuery(branch);
  const url = new URL(MAPBOX_FORWARD_URL);
  url.searchParams.set("q", query);
  url.searchParams.set("country", "MX");
  url.searchParams.set("language", "es");
  url.searchParams.set("limit", "1");
  url.searchParams.set("autocomplete", "false");
  url.searchParams.set("permanent", "true");
  url.searchParams.set("access_token", accessToken);

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(30_000),
  });

  if (!response.ok) {
    throw new Error(`Mapbox respondió HTTP ${response.status}.`);
  }

  return { query, result: parseMapboxResult(await response.json()) };
}
