import { env } from "../config/env.js";
import { supabase } from "../db/supabase.js";
import {
  buildGeocodingQuery,
  geocodeWithMapbox,
  type GeocodingBranch,
} from "../geocoding/mapbox.js";

const BRANCH_COLUMNS =
  "id,name,address,neighborhood,postal_code,municipality,state,geocoding_attempts";

export function statusForConfidence(
  confidence: number,
  minimumConfidence: number,
): "geocoded" | "review" {
  return confidence >= minimumConfidence ? "geocoded" : "review";
}

async function updateBranch(id: string, values: Record<string, unknown>) {
  const { error } = await supabase
    .from("branches")
    .update({
      ...values,
      geocoding_last_attempt_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);

  if (error) throw new Error(error.message);
}

export async function geocodeBranches(): Promise<void> {
  const { data, error } = await supabase
    .from("branches")
    .select(BRANCH_COLUMNS)
    .in("geocoding_status", ["pending", "failed"])
    .order("updated_at")
    .limit(env.GEOCODING_BRANCH_LIMIT);

  if (error)
    throw new Error(`No se pudieron consultar sucursales: ${error.message}`);

  const branches = (data ?? []) as GeocodingBranch[];
  if (env.GEOCODING_MODE === "dry_run") {
    console.info({
      mode: "dry_run",
      pendingBranches: branches.length,
      queries: branches.map((branch) => ({
        id: branch.id,
        query: buildGeocodingQuery(branch),
      })),
    });
    return;
  }

  if (!env.MAPBOX_ACCESS_TOKEN) {
    throw new Error(
      "MAPBOX_ACCESS_TOKEN es obligatorio con GEOCODING_MODE=live.",
    );
  }

  let geocoded = 0;
  let review = 0;
  let failed = 0;

  for (const branch of branches) {
    try {
      const { query, result } = await geocodeWithMapbox(
        branch,
        env.MAPBOX_ACCESS_TOKEN,
      );

      if (!result) {
        failed += 1;
        await updateBranch(branch.id, {
          geocoding_status: "failed",
          geocoding_provider: "mapbox",
          geocoding_query: query,
          geocoding_error: "Mapbox no devolvió resultados.",
          geocoding_attempts: branch.geocoding_attempts + 1,
        });
        continue;
      }

      const status = statusForConfidence(
        result.confidence,
        env.GEOCODING_MIN_CONFIDENCE,
      );
      if (status === "geocoded") geocoded += 1;
      else review += 1;

      await updateBranch(branch.id, {
        latitude: status === "geocoded" ? result.latitude : null,
        longitude: status === "geocoded" ? result.longitude : null,
        geocoding_status: status,
        geocoded_at: status === "geocoded" ? new Date().toISOString() : null,
        geocoding_provider: "mapbox",
        geocoding_query: query,
        geocoding_confidence: result.confidence,
        geocoding_accuracy: result.accuracy,
        geocoding_external_id: result.externalId,
        geocoding_payload: result.payload,
        geocoding_error: null,
        geocoding_attempts: branch.geocoding_attempts + 1,
      });
    } catch (branchError) {
      failed += 1;
      await updateBranch(branch.id, {
        geocoding_status: "failed",
        geocoding_provider: "mapbox",
        geocoding_query: buildGeocodingQuery(branch),
        geocoding_error:
          branchError instanceof Error
            ? branchError.message
            : "Error desconocido",
        geocoding_attempts: branch.geocoding_attempts + 1,
      });
    } finally {
      await new Promise((resolve) =>
        setTimeout(resolve, env.GEOCODING_REQUEST_DELAY_MS),
      );
    }
  }

  console.info({
    mode: "live",
    processed: branches.length,
    geocoded,
    review,
    failed,
  });
}

if (process.argv[1]?.endsWith("geocode-branches.ts")) {
  geocodeBranches().catch((error: unknown) => {
    console.error("El job de geocodificación terminó inesperadamente:", error);
    process.exitCode = 1;
  });
}
