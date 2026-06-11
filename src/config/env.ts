import "dotenv/config";
import { z } from "zod";

const envSchema = z.object({
  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  PROFECO_CITY_CODE: z
    .string()
    .regex(/^\d{4}$/)
    .default("0901"),
  PROFECO_PRODUCT_LIMIT: z.coerce.number().int().min(1).max(10).default(3),
  PROFECO_MAX_RESULTS_PER_PRODUCT: z.coerce
    .number()
    .int()
    .min(1)
    .max(50)
    .default(10),
  PROFECO_REQUEST_DELAY_MS: z.coerce
    .number()
    .int()
    .min(500)
    .max(10_000)
    .default(1000),
  API_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).default(60_000),
  API_RATE_LIMIT_MAX: z.coerce.number().int().min(10).default(120),
});

export const env = envSchema.parse(process.env);
