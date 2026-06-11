import { saveScrapedProduct } from "../db/save-scraped-product.js";
import { productsTest } from "../products/products-test.js";
import { scrapeMock } from "../scrapers/mock.js";
import type { StoreScraper } from "../scrapers/types.js";

const activeScrapers: StoreScraper[] = [scrapeMock];

export async function updatePrices(): Promise<void> {
  const startedAt = Date.now();
  let processedProducts = 0;
  let savedPrices = 0;
  let errors = 0;

  for (const productMeta of productsTest) {
    for (const searchTerm of productMeta.searchTerms) {
      for (const scrape of activeScrapers) {
        processedProducts += 1;

        try {
          const result = await scrape(searchTerm, productMeta);

          if (!result.ok) {
            errors += 1;
            console.error(
              `[${result.storeSlug}] ${searchTerm}: ${result.error ?? "Falló el scraper"}`,
            );
            continue;
          }

          for (const product of result.products) {
            try {
              await saveScrapedProduct(product);
              if (product.price !== null) savedPrices += 1;
            } catch (error) {
              errors += 1;
              console.error(
                `[${result.storeSlug}] No se pudo guardar ${product.externalName}:`,
                error,
              );
            }
          }
        } catch (error) {
          errors += 1;
          console.error(`Falló el procesamiento de "${searchTerm}":`, error);
        }
      }
    }
  }

  console.info({
    processedProducts,
    savedPrices,
    errors,
    totalTimeMs: Date.now() - startedAt,
  });
}

updatePrices().catch((error: unknown) => {
  console.error("El job terminó inesperadamente:", error);
  process.exitCode = 1;
});
