import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import { rateLimit } from "express-rate-limit";
import helmet from "helmet";
import { z } from "zod";
import { env } from "../config/env.js";
import { supabase } from "../db/supabase.js";

const API_VERSION = "v1";
const MAX_PAGE_SIZE = 50;

const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(MAX_PAGE_SIZE).default(20),
});

const priceQuerySchema = paginationSchema.extend({
  query: z.string().trim().min(1).max(100),
  store: z.string().trim().min(1).max(100).optional(),
  source: z.string().trim().min(1).max(50).optional(),
  available: z.enum(["true", "false"]).optional(),
});

const catalogQuerySchema = paginationSchema.extend({
  query: z.string().trim().min(1).max(100).optional(),
  category: z.string().trim().min(1).max(100).optional(),
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
  table: "latest_prices" | "compare_prices",
  query: PriceQuery,
) {
  let databaseQuery = supabase
    .from(table)
    .select("*", { count: "exact" })
    .ilike("normalized_name", `%${query.query}%`);

  if (query.store) databaseQuery = databaseQuery.eq("store_slug", query.store);
  if (query.source) databaseQuery = databaseQuery.eq("source", query.source);
  if (query.available) {
    databaseQuery = databaseQuery.eq("available", query.available === "true");
  }

  const [from, to] = rangeFor(query);
  return databaseQuery
    .order(table === "compare_prices" ? "price_rank" : "price", {
      ascending: true,
    })
    .range(from, to);
}

function priceFilters(query: PriceQuery): Record<string, string | boolean> {
  return {
    ...(query.store ? { store: query.store } : {}),
    ...(query.source ? { source: query.source } : {}),
    ...(query.available ? { available: query.available === "true" } : {}),
  };
}

function registerPriceRoute(
  app: express.Express,
  path: string,
  table: "latest_prices" | "compare_prices",
) {
  app.get(path, async (request, response) => {
    const query = parseQuery(priceQuerySchema, request, response);
    if (!query) return;

    const { data, error, count } = await fetchPriceRows(table, query);
    if (error) {
      sendError(response, 500, "DATABASE_ERROR", error.message);
      return;
    }

    sendSuccess(
      response,
      data ?? [],
      paginationMeta(query, count ?? 0, {
        query: query.query,
        filters: priceFilters(query),
      }),
    );
  });
}

function registerApiRoutes(app: express.Express) {
  app.get(["/api/v1/health", "/health"], (_request, response) => {
    sendSuccess(response, {
      status: "ok",
      service: "tiago-market-api",
      version: "0.3.0",
      timestamp: new Date().toISOString(),
    });
  });

  registerPriceRoute(app, "/api/v1/prices", "latest_prices");
  registerPriceRoute(app, "/api/v1/compare", "compare_prices");
  registerPriceRoute(app, "/prices", "latest_prices");
  registerPriceRoute(app, "/compare", "compare_prices");

  app.get(["/api/v1/stores", "/stores"], async (request, response) => {
    const query = parseQuery(catalogQuerySchema, request, response);
    if (!query) return;

    let databaseQuery = supabase
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

    let databaseQuery = supabase
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

  app.get("/api/v1/coverage", async (request, response) => {
    const query = parseQuery(catalogQuerySchema, request, response);
    if (!query) return;

    let databaseQuery = supabase
      .from("product_coverage")
      .select("*", { count: "exact" });

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
      .order("last_updated_at", { ascending: false })
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
}

export function createApi() {
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

  registerApiRoutes(app);

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
