import "dotenv/config";
import { z } from "zod";

const envSchema = z.object({
  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  API_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).default(60_000),
  API_RATE_LIMIT_MAX: z.coerce.number().int().min(10).default(120),
  DIRECT_CATALOG_PAGE_LIMIT: z.coerce.number().int().min(1).max(100).default(2),
  DIRECT_CATALOG_START_PAGE: z.coerce.number().int().min(1).max(100).default(1),
  DIRECT_CATALOG_SOURCES: z.string().default("arteli,smart-final,chedraui,heb"),
  GEOCODING_MODE: z.enum(["dry_run", "live"]).default("dry_run"),
  MAPBOX_ACCESS_TOKEN: z.preprocess(
    (value) => (value === "" ? undefined : value),
    z.string().min(1).optional(),
  ),
  GOOGLE_CLIENT_ID: z
    .string()
    .min(1)
    .default("google-client-id-not-configured"),
  GEOCODING_BRANCH_LIMIT: z.coerce.number().int().min(1).max(100).default(10),
  GEOCODING_REQUEST_DELAY_MS: z.coerce
    .number()
    .int()
    .min(100)
    .max(10_000)
    .default(1100),
  GEOCODING_MIN_CONFIDENCE: z.coerce.number().min(0).max(1).default(0.8),
});

export const env = envSchema.parse(process.env);
