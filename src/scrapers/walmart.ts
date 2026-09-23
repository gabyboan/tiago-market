import type { ProductMeta } from "../products/products-test.js";
import { scrapeWalmartFamily } from "./walmart-family.js";
import type { ScraperResult } from "./types.js";

export async function scrapeWalmart(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  return scrapeWalmartFamily(searchTerm, productMeta, {
    storeSlug: "walmart-mx",
    storeName: "Walmart México",
    searchUrl: "https://super.walmart.com.mx/search?q={query}",
  });
}
