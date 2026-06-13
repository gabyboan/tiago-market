import { z } from "zod";
import {
  normalizeProductName,
  normalizedPresentation,
  presentationFromText,
} from "../products/normalize.js";
import type { ProductMeta } from "../products/products-test.js";
import type { ScrapedProduct, ScraperResult } from "./types.js";

const CALIMAX_HOST = "www.calimax.com.mx";

const calimaxProductSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional().default(""),
  brand: z.string().optional().default(""),
  sku: z.coerce.number().int().positive(),
  ean: z.string().optional().default(""),
  stock: z.coerce.number().nonnegative(),
  price: z.coerce.number().positive(),
  price_list: z.coerce.number().positive(),
  category_name: z.string().optional().default(""),
  image_url_main: z.string().url(),
  linkid: z.string().min(1),
  fecha: z.string().optional(),
});

export type CalimaxProduct = z.infer<typeof calimaxProductSchema>;

function searchQuery(productMeta: ProductMeta): string {
  return (
    normalizeProductName(productMeta.normalizedName)
      .split(" ")
      .find((term) => term.length > 2 && !/^\d/.test(term)) ??
    productMeta.normalizedName
  );
}

function extractState(html: string): unknown {
  const match = html.match(
    /<script id="ng-state" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match?.[1]) throw new Error("Calimax no publicó estado estructurado.");
  return JSON.parse(match[1]);
}

function collectHits(value: unknown, hits: CalimaxProduct[]): void {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    for (const entry of value) collectHits(entry, hits);
    return;
  }

  const record = value as Record<string, unknown>;
  if (Array.isArray(record.hits)) {
    for (const candidate of record.hits) {
      const parsed = calimaxProductSchema.safeParse(candidate);
      if (parsed.success) hits.push(parsed.data);
    }
  }
  for (const nested of Object.values(record)) collectHits(nested, hits);
}

export function parseCalimaxProducts(html: string): CalimaxProduct[] {
  const products: CalimaxProduct[] = [];
  collectHits(extractState(html), products);
  return [
    ...new Map(products.map((product) => [product.sku, product])).values(),
  ];
}

export function calimaxProductMatches(
  product: CalimaxProduct,
  productMeta: ProductMeta,
): boolean {
  const candidate = normalizeProductName(product.name);
  const requested = normalizeProductName(productMeta.normalizedName);
  const requestedPresentation = normalizedPresentation(requested);
  const candidatePresentation = normalizedPresentation(candidate);
  if (
    requestedPresentation &&
    requestedPresentation !== candidatePresentation
  ) {
    return false;
  }
  const ignored = new Set([
    "de",
    "el",
    "la",
    "l",
    "ml",
    "g",
    "kg",
    "pza",
    "rollo",
    "rollos",
    "gal",
  ]);
  const terms = requested
    .split(" ")
    .filter((term) => term.length > 1 && !ignored.has(term));

  return terms.every((term) => candidate.includes(term));
}

export function calimaxProductToScrapedProduct(
  product: CalimaxProduct,
  requestUrl: string,
  searchTerm: string,
  productMeta: ProductMeta,
): ScrapedProduct {
  const verificationUrl = `https://${CALIMAX_HOST}/productos?search=${product.sku}`;
  return {
    storeSlug: "calimax-online",
    storeName: "Calimax online",
    storeEnabled: true,
    source: "calimax-direct",
    sourceProductName: product.name.trim(),
    sourceStoreName: "Calimax online",
    sourceBranchName: null,
    sourceBranchKey: null,
    sourceAddress: null,
    sourceNeighborhood: null,
    sourcePostalCode: null,
    sourceMunicipality: null,
    sourceState: null,
    sourceCityCode: null,
    sourceCityName: null,
    externalReference: requestUrl,
    rawPayload: {
      sku: product.sku,
      ean: product.ean,
      brand: product.brand,
      stock: product.stock,
      listPrice: product.price_list,
      sourceUpdatedAt: product.fecha,
      verificationMode: "official-search-by-sku",
    },
    searchTerm,
    internalProductName: productMeta.internalName,
    normalizedName: productMeta.normalizedName,
    category: productMeta.category,
    externalName: product.name.trim(),
    price: product.price,
    currency: "MXN",
    externalUrl: verificationUrl,
    storeProductUrl: verificationUrl,
    imageUrl: product.image_url_main,
    presentation: presentationFromText(product.name),
    available: product.stock > 0,
    scrapedAt: new Date().toISOString(),
  };
}

export async function scrapeCalimax(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  try {
    const url = new URL("/productos", `https://${CALIMAX_HOST}`);
    url.searchParams.set("search", searchQuery(productMeta));
    const requestUrl = url.toString().replace(/\+/g, "%20");
    const response = await fetch(requestUrl, {
      headers: { Accept: "text/html" },
      signal: AbortSignal.timeout(30_000),
    });
    if (response.status === 404) {
      return {
        ok: true,
        storeSlug: "calimax-online",
        searchTerm,
        products: [],
      };
    }
    if (!response.ok) {
      throw new Error(`Calimax respondió HTTP ${response.status}.`);
    }

    const selected = parseCalimaxProducts(await response.text())
      .filter((product) => product.stock > 0)
      .filter((product) => calimaxProductMatches(product, productMeta));

    return {
      ok: true,
      storeSlug: "calimax-online",
      searchTerm,
      products: selected.map((product) =>
        calimaxProductToScrapedProduct(
          product,
          requestUrl,
          searchTerm,
          productMeta,
        ),
      ),
    };
  } catch (error) {
    return {
      ok: false,
      storeSlug: "calimax-online",
      searchTerm,
      products: [],
      error: error instanceof Error ? error.message : "Error desconocido",
    };
  }
}
