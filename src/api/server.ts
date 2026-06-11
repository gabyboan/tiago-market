import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import { rateLimit } from "express-rate-limit";
import helmet from "helmet";
import { z } from "zod";
import { env } from "../config/env.js";
import { daysOld } from "../data-quality.js";
import { supabase } from "../db/supabase.js";

const API_VERSION = "v1";
const MAX_PAGE_SIZE = 50;
const PRICE_COLUMNS =
  "product_name,normalized_name,source_product_name,store_name,branch_id,branch_name,branch_address,branch_municipality,latitude,longitude,price,currency,source,captured_at,freshness,days_old,observation_url,store_product_url";
const COMPARE_COLUMNS = `${PRICE_COLUMNS},best_price,price_rank`;

export const SOURCE_CATALOG = [
  { source: "mock", enabled: true, mode: "mock" },
  { source: "profeco", enabled: true, mode: "live" },
  {
    source: "walmart",
    enabled: false,
    mode: "disabled",
    reason:
      "Automatización directa desactivada hasta validar una fuente estable.",
  },
  {
    source: "soriana",
    enabled: false,
    mode: "disabled",
    reason:
      "Automatización directa desactivada hasta validar una fuente estable.",
  },
  {
    source: "chedraui",
    enabled: false,
    mode: "experimental",
    reason: "Fuente pendiente de validación legal y técnica.",
  },
  {
    source: "bodega_aurrera",
    enabled: false,
    mode: "experimental",
    reason: "Fuente pendiente de validación legal y técnica.",
  },
] as const;

type Database = Pick<typeof supabase, "from" | "rpc">;

const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(MAX_PAGE_SIZE).default(20),
});

const priceQuerySchema = paginationSchema
  .extend({
    query: z.string().trim().min(1).max(100).optional(),
    store: z.string().trim().min(1).max(100).optional(),
    source: z.string().trim().min(1).max(50).optional(),
    available: z.enum(["true", "false"]).optional(),
    lat: z.coerce.number().min(-90).max(90).optional(),
    lng: z.coerce.number().min(-180).max(180).optional(),
    radius_km: z.coerce.number().positive().max(100).default(10),
    order_by: z.enum(["price", "distance"]).default("price"),
  })
  .superRefine((value, context) => {
    if ((value.lat === undefined) !== (value.lng === undefined)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "lat y lng deben enviarse juntos.",
        path: ["lat"],
      });
    }
  });

const nearbyQuerySchema = priceQuerySchema.refine(
  (value) =>
    value.query !== undefined &&
    value.lat !== undefined &&
    value.lng !== undefined,
  {
    message: "lat y lng son obligatorios para buscar precios cercanos.",
    path: ["lat"],
  },
);

const catalogQuerySchema = paginationSchema.extend({
  query: z.string().trim().min(1).max(100).optional(),
  category: z.string().trim().min(1).max(100).optional(),
});

const branchQuerySchema = paginationSchema.extend({
  query: z.string().trim().min(1).max(100).optional(),
  city_code: z.string().trim().min(1).max(20).optional(),
});

type Pagination = z.output<typeof paginationSchema>;
type PriceQuery = z.output<typeof priceQuerySchema>;

type ApiMeta = {
  apiVersion: typeof API_VERSION;
  page?: number;
  limit?: number;
  total?: number;
  totalPages?: number;
  query?: string;
  filters?: Record<string, string | boolean>;
};

function paginationMeta(
  pagination: Pagination,
  total: number,
  extra: Omit<
    ApiMeta,
    "apiVersion" | "page" | "limit" | "total" | "totalPages"
  > = {},
): ApiMeta {
  return {
    apiVersion: API_VERSION,
    page: pagination.page,
    limit: pagination.limit,
    total,
    totalPages: Math.ceil(total / pagination.limit),
    ...extra,
  };
}

function rangeFor({ page, limit }: Pagination): [number, number] {
  const from = (page - 1) * limit;
  return [from, from + limit - 1];
}

function sendSuccess(
  response: Response,
  data: unknown,
  meta: ApiMeta = { apiVersion: API_VERSION },
) {
  response.json({ data, meta });
}

function sendError(
  response: Response,
  status: number,
  code: string,
  message: string,
  details?: unknown,
) {
  response.status(status).json({
    error: { code, message, ...(details ? { details } : {}) },
    meta: { apiVersion: API_VERSION },
  });
}

function parseQuery<TSchema extends z.ZodTypeAny>(
  schema: TSchema,
  request: Request,
  response: Response,
): z.output<TSchema> | null {
  const parsed = schema.safeParse(request.query);

  if (!parsed.success) {
    sendError(
      response,
      400,
      "INVALID_QUERY",
      "Los parámetros de consulta no son válidos.",
      parsed.error.flatten().fieldErrors,
    );
    return null;
  }

  return parsed.data;
}

async function fetchPriceRows(
  database: Database,
  table: "latest_prices" | "compare_prices",
  query: PriceQuery,
) {
  if (query.lat !== undefined && query.lng !== undefined) {
    const [from, to] = rangeFor(query);
    return database
      .rpc("nearby_prices", {
        search_query: query.query!,
        user_latitude: query.lat,
        user_longitude: query.lng,
        radius_km: query.radius_km,
        source_filter: query.source ?? null,
        store_filter: query.store ?? null,
        only_available: query.available !== "false",
      })
      .order(query.order_by === "distance" ? "distance_km" : "price", {
        ascending: true,
      })
      .range(from, to);
  }

  let databaseQuery = database
    .from(table)
    .select(table === "compare_prices" ? COMPARE_COLUMNS : PRICE_COLUMNS, {
      count: "exact",
    });

  if (query.query) {
    databaseQuery = databaseQuery.ilike("normalized_name", `%${query.query}%`);
  }

  if (query.store) databaseQuery = databaseQuery.eq("store_slug", query.store);
  if (query.source) databaseQuery = databaseQuery.eq("source", query.source);
  if (query.available) {
    databaseQuery = databaseQuery.eq("available", query.available === "true");
  }

  const [from, to] = rangeFor(query);
  return databaseQuery.order("price", { ascending: true }).range(from, to);
}

function priceFilters(query: PriceQuery): Record<string, string | boolean> {
  return {
    ...(query.store ? { store: query.store } : {}),
    ...(query.source ? { source: query.source } : {}),
    ...(query.available ? { available: query.available === "true" } : {}),
    ...(query.lat !== undefined ? { lat: String(query.lat) } : {}),
    ...(query.lng !== undefined ? { lng: String(query.lng) } : {}),
    ...(query.lat !== undefined ? { radius_km: String(query.radius_km) } : {}),
    ...(query.lat !== undefined ? { order_by: query.order_by } : {}),
  };
}

function addNearbyRanking(
  rows: Array<Record<string, unknown>>,
): Array<Record<string, unknown>> {
  const bestByProduct = new Map<string, number>();
  const pricesByProduct = new Map<string, number[]>();

  for (const row of rows) {
    const product = String(row.normalized_name);
    const price = Number(row.price);
    bestByProduct.set(
      product,
      Math.min(bestByProduct.get(product) ?? price, price),
    );
    pricesByProduct.set(
      product,
      [...(pricesByProduct.get(product) ?? []), price].sort((a, b) => a - b),
    );
  }

  return rows.map((row) => {
    const product = String(row.normalized_name);
    const price = Number(row.price);
    const uniquePrices = [...new Set(pricesByProduct.get(product) ?? [])];
    return {
      ...row,
      best_price: bestByProduct.get(product),
      price_rank: uniquePrices.indexOf(price) + 1,
    };
  });
}

function registerPriceRoute(
  app: express.Express,
  database: Database,
  path: string,
  table: "latest_prices" | "compare_prices",
  schema: z.ZodTypeAny = priceQuerySchema,
) {
  app.get(path, async (request, response) => {
    const query = parseQuery(schema, request, response) as PriceQuery | null;
    if (!query) return;

    const { data, error, count } = await fetchPriceRows(database, table, query);
    if (error) {
      sendError(response, 500, "DATABASE_ERROR", error.message);
      return;
    }

    const rows =
      table === "compare_prices" &&
      query.lat !== undefined &&
      query.lng !== undefined
        ? addNearbyRanking((data ?? []) as Array<Record<string, unknown>>)
        : (data ?? []);

    sendSuccess(
      response,
      rows,
      paginationMeta(query, count ?? rows.length, {
        ...(query.query ? { query: query.query } : {}),
        filters: priceFilters(query),
      }),
    );
  });
}

function sourceHealth(latestSnapshotAt: string | null): string {
  if (!latestSnapshotAt) return "no_data";
  const age = daysOld(latestSnapshotAt);
  if (age < 7) return "healthy";
  if (age <= 21) return "stale";
  return "old";
}

function mergeSources(
  rows: Array<{
    source: string;
    latest_snapshot_at: string | null;
    total_snapshots: number;
  }>,
) {
  const stats = new Map(rows.map((row) => [row.source, row]));

  return SOURCE_CATALOG.map((source) => {
    const sourceStats = stats.get(source.source);
    return {
      ...source,
      latest_snapshot_at: sourceStats?.latest_snapshot_at ?? null,
      total_snapshots: sourceStats?.total_snapshots ?? 0,
    };
  });
}

function registerApiRoutes(app: express.Express, database: Database) {
  app.get(["/api/v1/health", "/health"], (_request, response) => {
    sendSuccess(response, {
      status: "ok",
      service: "tiago-market-api",
      version: "0.7.0",
      timestamp: new Date().toISOString(),
    });
  });

  registerPriceRoute(app, database, "/api/v1/prices", "latest_prices");
  registerPriceRoute(app, database, "/api/v1/compare", "compare_prices");
  registerPriceRoute(app, database, "/prices", "latest_prices");
  registerPriceRoute(app, database, "/compare", "compare_prices");

  app.get(["/api/v1/stores", "/stores"], async (request, response) => {
    const query = parseQuery(catalogQuerySchema, request, response);
    if (!query) return;

    let databaseQuery = database
      .from("stores")
      .select("id,name,slug,country,created_at", { count: "exact" })
      .eq("enabled", true);

    if (query.query)
      databaseQuery = databaseQuery.ilike("name", `%${query.query}%`);

    const [from, to] = rangeFor(query);
    const { data, error, count } = await databaseQuery
      .order("name")
      .range(from, to);

    if (error) {
      sendError(response, 500, "DATABASE_ERROR", error.message);
      return;
    }

    sendSuccess(
      response,
      data ?? [],
      paginationMeta(query, count ?? 0, {
        ...(query.query ? { query: query.query } : {}),
      }),
    );
  });

  app.get(["/api/v1/products", "/products"], async (request, response) => {
    const query = parseQuery(catalogQuerySchema, request, response);
    if (!query) return;

    let databaseQuery = database
      .from("products")
      .select("id,name,normalized_name,category,created_at", {
        count: "exact",
      });

    if (query.query) {
      databaseQuery = databaseQuery.ilike(
        "normalized_name",
        `%${query.query}%`,
      );
    }
    if (query.category)
      databaseQuery = databaseQuery.eq("category", query.category);

    const [from, to] = rangeFor(query);
    const { data, error, count } = await databaseQuery
      .order("name")
      .range(from, to);

    if (error) {
      sendError(response, 500, "DATABASE_ERROR", error.message);
      return;
    }

    sendSuccess(
      response,
      data ?? [],
      paginationMeta(query, count ?? 0, {
        ...(query.query ? { query: query.query } : {}),
        filters: query.category ? { category: query.category } : {},
      }),
    );
  });

  app.get(["/api/v1/branches", "/branches"], async (request, response) => {
    const query = parseQuery(branchQuerySchema, request, response);
    if (!query) return;

    let databaseQuery = database
      .from("branches")
      .select(
        "id,name,address,neighborhood,postal_code,municipality,state,city_code,city_name,latitude,longitude,geocoding_status,geocoding_provider,geocoding_confidence,geocoding_accuracy,source,stores(name,slug)",
        { count: "exact" },
      );

    if (query.query)
      databaseQuery = databaseQuery.ilike("name", `%${query.query}%`);
    if (query.city_code)
      databaseQuery = databaseQuery.eq("city_code", query.city_code);

    const [from, to] = rangeFor(query);
    const { data, error, count } = await databaseQuery
      .order("name")
      .range(from, to);

    if (error) {
      sendError(response, 500, "DATABASE_ERROR", error.message);
      return;
    }

    sendSuccess(response, data ?? [], paginationMeta(query, count ?? 0));
  });

  registerPriceRoute(
    app,
    database,
    "/api/v1/nearby",
    "latest_prices",
    nearbyQuerySchema,
  );

  app.get(["/api/v1/coverage", "/coverage"], async (_request, response) => {
    const [coverageResult, branchCoverageResult, sourceResult] =
      await Promise.all([
        database.from("coverage_summary").select("*").single(),
        database.from("branch_coverage_summary").select("*").single(),
        database
          .from("source_stats")
          .select("source,latest_snapshot_at,total_snapshots"),
      ]);

    if (
      coverageResult.error ||
      branchCoverageResult.error ||
      sourceResult.error
    ) {
      sendError(
        response,
        500,
        "DATABASE_ERROR",
        coverageResult.error?.message ??
          branchCoverageResult.error?.message ??
          sourceResult.error?.message ??
          "No se pudo consultar la cobertura.",
      );
      return;
    }

    const sources = mergeSources(sourceResult.data ?? []);
    sendSuccess(response, {
      ...coverageResult.data,
      ...branchCoverageResult.data,
      city_code: env.PROFECO_CITY_CODE,
      source_health: Object.fromEntries(
        sources.map((source) => [
          source.source,
          sourceHealth(source.latest_snapshot_at),
        ]),
      ),
    });
  });

  app.get(["/api/v1/sources", "/sources"], async (_request, response) => {
    const { data, error } = await database
      .from("source_stats")
      .select("source,latest_snapshot_at,total_snapshots");

    if (error) {
      sendError(response, 500, "DATABASE_ERROR", error.message);
      return;
    }

    sendSuccess(response, mergeSources(data ?? []));
  });
}

export function createApi(database: Database = supabase) {
  const app = express();

  if (env.NODE_ENV === "production") app.set("trust proxy", 1);

  app.disable("x-powered-by");
  app.use(helmet());
  app.use(express.json({ limit: "32kb" }));
  app.use(
    rateLimit({
      windowMs: env.API_RATE_LIMIT_WINDOW_MS,
      limit: env.API_RATE_LIMIT_MAX,
      standardHeaders: "draft-8",
      legacyHeaders: false,
      message: {
        error: {
          code: "RATE_LIMIT_EXCEEDED",
          message: "Demasiadas solicitudes. Intenta nuevamente más tarde.",
        },
        meta: { apiVersion: API_VERSION },
      },
    }),
  );

  registerApiRoutes(app, database);

  app.use((_request, response) => {
    sendError(response, 404, "NOT_FOUND", "Endpoint no encontrado.");
  });

  app.use(
    (
      error: unknown,
      _request: Request,
      response: Response,
      _next: NextFunction,
    ) => {
      console.error("Error no controlado en API:", error);
      sendError(response, 500, "INTERNAL_ERROR", "Error interno del servidor.");
    },
  );

  return app;
}

export function startApi() {
  return createApi().listen(env.PORT, () => {
    console.info(`API disponible en http://localhost:${env.PORT}`);
  });
}

if (process.argv[1]?.endsWith("server.ts")) {
  startApi();
}
