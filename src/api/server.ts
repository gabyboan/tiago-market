import express from "express";
import { z } from "zod";
import { env } from "../config/env.js";
import { supabase } from "../db/supabase.js";

const querySchema = z.object({
  query: z.string().trim().min(1).max(100),
});

export function createApi() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_request, response) => {
    response.json({ ok: true, service: "tiago-market-prototype" });
  });

  app.get("/prices", async (request, response) => {
    const parsed = querySchema.safeParse(request.query);
    if (!parsed.success) {
      response
        .status(400)
        .json({ error: "El parámetro query es obligatorio." });
      return;
    }

    const { data, error } = await supabase
      .from("latest_prices")
      .select("*")
      .ilike("normalized_name", `%${parsed.data.query}%`)
      .order("price", { ascending: true });

    if (error) {
      response.status(500).json({ error: error.message });
      return;
    }
    response.json({ query: parsed.data.query, prices: data });
  });

  app.get("/compare", async (request, response) => {
    const parsed = querySchema.safeParse(request.query);
    if (!parsed.success) {
      response
        .status(400)
        .json({ error: "El parámetro query es obligatorio." });
      return;
    }

    const { data, error } = await supabase
      .from("compare_prices")
      .select("*")
      .ilike("normalized_name", `%${parsed.data.query}%`)
      .order("price_rank", { ascending: true });

    if (error) {
      response.status(500).json({ error: error.message });
      return;
    }
    response.json({ query: parsed.data.query, comparison: data });
  });

  app.get("/stores", async (_request, response) => {
    const { data, error } = await supabase
      .from("stores")
      .select("id,name,slug,country,enabled,created_at")
      .eq("enabled", true)
      .order("name");

    if (error) {
      response.status(500).json({ error: error.message });
      return;
    }
    response.json({ stores: data });
  });

  app.get("/products", async (_request, response) => {
    const { data, error } = await supabase
      .from("products")
      .select("id,name,normalized_name,category,created_at")
      .order("name");

    if (error) {
      response.status(500).json({ error: error.message });
      return;
    }
    response.json({ products: data });
  });

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
