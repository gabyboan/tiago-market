import { z } from "zod";
import { env } from "../config/env.js";
import type { ProductMeta } from "../products/products-test.js";
import type { ScrapedProduct, ScraperResult } from "./types.js";

const PROFECO_API_URL = "https://qqp.profeco.gob.mx/api/precios";
const PROFECO_RESULTS_URL = "https://qqp.profeco.gob.mx/results";

const profecoPriceSchema = z.object({
  producto: z.string().min(1),
  tipo_producto: z.string().min(1),
  precio: z.coerce.number().nonnegative(),
  fecha_observacion: z.string().date(),
  cadena_comercial: z.string().min(1),
  establecimiento: z.string().min(1),
  direccion: z.string().optional(),
  colonia: z.string().optional(),
  cp: z.string().optional(),
  municipio: z.string().optional(),
  entidad: z.string().optional(),
});

const profecoResponseSchema = z.object({
  success: z.boolean(),
  message: z.string(),
  data: z.object({
    productos: z.array(profecoPriceSchema),
  }),
});

type ProfecoPrice = z.infer<typeof profecoPriceSchema>;

type ProfecoProductRule = {
  apiSearchTerm: string;
  requiredTerms: string[];
};

const productRules: Record<string, ProfecoProductRule> = {
  "coca cola 600 ml": {
    apiSearchTerm: "refresco",
    requiredTerms: ["coca cola", "600 ml"],
  },
  "leche entera 1 l": {
    apiSearchTerm: "leche",
    requiredTerms: ["leche", "entera", "1 l"],
  },
  "arroz 1 kg": {
    apiSearchTerm: "arroz",
    requiredTerms: ["arroz", "1 kg"],
  },
  "azucar 1 kg": {
    apiSearchTerm: "azucar",
    requiredTerms: ["azucar", "1 kg"],
  },
  "aceite vegetal 1 l": {
    apiSearchTerm: "aceite",
    requiredTerms: ["aceite", "vegetal", "1 l"],
  },
  "huevo blanco 12 piezas": {
    apiSearchTerm: "huevo",
    requiredTerms: ["huevo", "blanco", "12"],
  },
  "pan blanco de caja": {
    apiSearchTerm: "pan de caja",
    requiredTerms: ["pan de caja"],
  },
  "detergente liquido 1 l": {
    apiSearchTerm: "detergente",
    requiredTerms: ["detergente", "liquido", "1 l"],
  },
  "papel higienico 4 rollos": {
    apiSearchTerm: "papel higienico",
    requiredTerms: ["papel higienico", "4 rollos"],
  },
  "cafe soluble 100 g": {
    apiSearchTerm: "cafe",
    requiredTerms: ["cafe soluble", "100 g"],
  },
};

function normalize(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\b(litros?|lts?|lt)\b/g, "l")
    .replace(/\b(kilogramos?|kgs?)\b/g, "kg")
    .replace(/\b(gramos?|grs?|gr)\b/g, "g")
    .replace(/\b(rollo|rollos)\b/g, "rollos")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function slugify(value: string): string {
  return normalize(value).replaceAll(" ", "-");
}

function matchesRule(price: ProfecoPrice, rule: ProfecoProductRule): boolean {
  const normalizedProduct = normalize(price.producto);
  return rule.requiredTerms.every((term) =>
    normalizedProduct.includes(normalize(term)),
  );
}

function buildExternalUrl(
  cityCode: string,
  apiSearchTerm: string,
  price: ProfecoPrice,
): string {
  const url = new URL(PROFECO_RESULTS_URL);
  url.searchParams.set("city", cityCode);
  url.searchParams.set("searchTerm", apiSearchTerm);
  url.hash = slugify(
    `${price.cadena_comercial}-${price.establecimiento}-${price.producto}`,
  );
  return url.toString();
}

function getPresentation(productName: string): string | null {
  const parts = productName.split(",").map((part) => part.trim());
  return parts.length >= 3 ? parts.slice(2).join(", ") : null;
}

function toScrapedProduct(
  price: ProfecoPrice,
  searchTerm: string,
  productMeta: ProductMeta,
  apiSearchTerm: string,
): ScrapedProduct {
  return {
    storeSlug: slugify(price.cadena_comercial),
    storeName: price.cadena_comercial,
    storeEnabled: true,
    source: "profeco",
    searchTerm,
    internalProductName: productMeta.internalName,
    normalizedName: productMeta.normalizedName,
    category: productMeta.category,
    externalName: `${price.producto} · ${price.establecimiento}`,
    price: price.precio,
    currency: "MXN",
    externalUrl: buildExternalUrl(env.PROFECO_CITY_CODE, apiSearchTerm, price),
    imageUrl: null,
    presentation: getPresentation(price.producto),
    available: true,
    scrapedAt: new Date(
      `${price.fecha_observacion}T12:00:00.000Z`,
    ).toISOString(),
  };
}

function selectLatestPrices(prices: ProfecoPrice[]): ProfecoPrice[] {
  const latestByListing = new Map<string, ProfecoPrice>();

  for (const price of prices) {
    const key = normalize(
      `${price.cadena_comercial}|${price.establecimiento}|${price.producto}`,
    );
    const current = latestByListing.get(key);

    if (!current || price.fecha_observacion > current.fecha_observacion) {
      latestByListing.set(key, price);
    }
  }

  return [...latestByListing.values()]
    .sort(
      (a, b) =>
        b.fecha_observacion.localeCompare(a.fecha_observacion) ||
        a.precio - b.precio,
    )
    .slice(0, env.PROFECO_MAX_RESULTS_PER_PRODUCT);
}

export async function scrapeProfeco(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  const rule = productRules[productMeta.normalizedName];

  if (!rule) {
    return {
      ok: false,
      storeSlug: "profeco",
      searchTerm,
      products: [],
      error: `No hay regla Profeco para ${productMeta.normalizedName}.`,
    };
  }

  const url = new URL(PROFECO_API_URL);
  url.searchParams.set("clave_ciudad", env.PROFECO_CITY_CODE);
  url.searchParams.set("busqueda", rule.apiSearchTerm);

  try {
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(30_000),
    });

    if (!response.ok) {
      throw new Error(`QQP Profeco respondió HTTP ${response.status}.`);
    }

    const parsed = profecoResponseSchema.parse(await response.json());
    if (!parsed.success) {
      throw new Error(parsed.message);
    }

    const matchingPrices = parsed.data.productos.filter((price) =>
      matchesRule(price, rule),
    );
    const selectedPrices = selectLatestPrices(matchingPrices);

    return {
      ok: true,
      storeSlug: "profeco",
      searchTerm,
      products: selectedPrices.map((price) =>
        toScrapedProduct(price, searchTerm, productMeta, rule.apiSearchTerm),
      ),
    };
  } catch (error) {
    return {
      ok: false,
      storeSlug: "profeco",
      searchTerm,
      products: [],
      error: error instanceof Error ? error.message : "Error desconocido",
    };
  } finally {
    await new Promise((resolve) =>
      setTimeout(resolve, env.PROFECO_REQUEST_DELAY_MS),
    );
  }
}
