import type { ProductMeta } from "../products/products-test.js";
import { createBrowserPage } from "./browser.js";
import type { ScraperResult } from "./types.js";

export async function scrapeSoriana(
  searchTerm: string,
  _productMeta: ProductMeta,
): Promise<ScraperResult> {
  const { browser, page } = await createBrowserPage();

  try {
    await page.goto(
      `https://www.soriana.com/buscar?q=${encodeURIComponent(searchTerm)}`,
      { waitUntil: "domcontentloaded" },
    );

    // TODO: validar términos de uso y confirmar selectores antes de activar.
    return {
      ok: false,
      storeSlug: "soriana",
      searchTerm,
      products: [],
      error: "Scraper Soriana pendiente de selectores validados.",
    };
  } catch (error) {
    return {
      ok: false,
      storeSlug: "soriana",
      searchTerm,
      products: [],
      error: error instanceof Error ? error.message : "Error desconocido",
    };
  } finally {
    await browser.close();
  }
}
