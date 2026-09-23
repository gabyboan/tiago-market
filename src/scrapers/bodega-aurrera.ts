import type { ProductMeta } from "../products/products-test.js";
import { scrapeWalmartFamily } from "./walmart-family.js";
import type { ScraperResult } from "./types.js";

export async function scrapeBodegaAurrera(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  return scrapeWalmartFamily(searchTerm, productMeta, {
    storeSlug: "bodega-aurrera-mx",
    storeName: "Bodega Aurrera",
    searchUrl: "https://www.bodegaaurrera.com.mx/search?q={query}",
  });
}