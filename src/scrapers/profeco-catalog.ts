import { z } from "zod";
import { env } from "../config/env.js";
import type { ProductMeta } from "../products/products-test.js";
import {
  normalizeProfecoProduct,
  toProfecoScrapedProduct,
  type ProfecoPrice,
} from "./profeco.js";
import type { ScrapedProduct } from "./types.js";

const PROFECO_API_URL = "https://qqp.profeco.gob.mx/api/precios";

const catalogResponseSchema = z.object({
  success: z.boolean(),
  message: z.string(),
  data: z.object({
    productos: z.array(
      z.object({
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
      }),
    ),
  }),
});

export const profecoCatalogTerms = [
  "aceite",
  "agua",
  "arroz",
  "azucar",
  "atun",
  "cafe",
  "carne",
  "cereal",
  "cerveza",
  "chocolate",
  "crema",
  "detergente",
  "desodorante",
  "dulces",
  "frijol",
  "galletas",
  "harina",
  "huevo",
  "jabon",
  "jamon",
  "jugo",
  "leche",
  "mantequilla",
  "mayonesa",
  "pan",
  "panales",
  "papel higienico",
  "pasta",
  "pescado",
  "pollo",
  "queso",
  "refresco",
  "sal",
  "salchicha",
  "salsa",
  "shampoo",
  "suavizante",
  "te",
  "tortilla",
  "toallas sanitarias",
  "verdura",
  "vino",
  "yogur",
  "cepillo dental",
  "pasta dental",
  "limpiador",
  "cloro",
  "helado",
  "mermelada",
  "sopa",
  "papas",
  "botana",
  "alimento para bebe",
  "alimento para mascota",
] as const;

function productMeta(price: ProfecoPrice): ProductMeta {
  const normalizedName = normalizeProfecoProduct(price.producto);
  return {
    internalName: price.producto,
    normalizedName,
    category: price.tipo_producto,
    searchTerms: [normalizedName],
  };
}

export function catalogListingKey(price: ProfecoPrice): string {
  return normalizeProfecoProduct(
    `${price.producto}|${price.cadena_comercial}|${price.establecimiento}`,
  );
}

export function selectLatestCatalogListings(
  prices: ProfecoPrice[],
  maximum: number,
): ProfecoPrice[] {
  const latest = new Map<string, ProfecoPrice>();

  for (const price of prices) {
    const key = catalogListingKey(price);
    const current = latest.get(key);
    if (!current || price.fecha_observacion > current.fecha_observacion) {
      latest.set(key, price);
    }
  }

  const byProduct = new Map<string, ProfecoPrice[]>();
  for (const price of latest.values()) {
    const key = normalizeProfecoProduct(price.producto);
    byProduct.set(key, [...(byProduct.get(key) ?? []), price]);
  }

  const groups = [...byProduct.values()].map((group) =>
    group.sort(
      (a, b) =>
        b.fecha_observacion.localeCompare(a.fecha_observacion) ||
        a.precio - b.precio,
    ),
  );
  const selected: ProfecoPrice[] = [];

  for (let index = 0; selected.length < maximum; index += 1) {
    let added = false;
    for (const group of groups) {
      const price = group[index];
      if (!price) continue;
      selected.push(price);
      added = true;
      if (selected.length === maximum) break;
    }
    if (!added) break;
  }

  return selected;
}

export async function fetchProfecoCatalogTerm(
  searchTerm: string,
): Promise<ProfecoPrice[]> {
  const url = new URL(PROFECO_API_URL);
  url.searchParams.set("clave_ciudad", env.PROFECO_CITY_CODE);
  url.searchParams.set("busqueda", searchTerm);

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(60_000),
  });

  if (!response.ok) {
    throw new Error(`QQP Profeco respondió HTTP ${response.status}.`);
  }

  const parsed = catalogResponseSchema.parse(await response.json());
  if (!parsed.success) throw new Error(parsed.message);
  return parsed.data.productos;
}

export function catalogPriceToScrapedProduct(
  price: ProfecoPrice,
  searchTerm: string,
): ScrapedProduct {
  return toProfecoScrapedProduct(
    price,
    searchTerm,
    productMeta(price),
    searchTerm,
  );
}
