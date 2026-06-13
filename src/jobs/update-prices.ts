import { saveScrapedProduct } from "../db/save-scraped-product.js";
import { validateDirectProduct } from "../data-quality/direct-product.js";
import { productsTest } from "../products/products-test.js";
import { scrapeMock } from "../scrapers/mock.js";
import type { StoreScraper } from "../scrapers/types.js";

type UpdatePricesOptions = {
  products?: typeof productsTest;
  scrapers?: StoreScraper[];
};

const SAVE_CONCURRENCY = 5;

export async function updatePrices({
  products = productsTest,
  scrapers = [scrapeMock],
}: UpdatePricesOptions = {}): Promise<void> {
  const startedAt = Date.now();
  let processedProducts = 0;
  let savedPrices = 0;
  let errors = 0;
  let rejectedProducts = 0;

  for (const productMeta of products) {
    for (const searchTerm of productMeta.searchTerms) {
      for (const scrape of scrapers) {
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

          if (result.products.length === 0) {
            console.warn(`[${result.storeSlug}] Sin resultados: ${searchTerm}`);
          }

          for (
            let index = 0;
            index < result.products.length;
            index += SAVE_CONCURRENCY
          ) {
            const batch = result.products.slice(
              index,
              index + SAVE_CONCURRENCY,
            );

            await Promise.all(
              batch.map(async (product) => {
                try {
                  const quality = validateDirectProduct(product);
                  if (!quality.accepted) {
                    rejectedProducts += 1;
                    console.warn(
                      `[${result.storeSlug}] Rechazado ${product.externalName}: ${quality.issues.join(", ")}`,
                    );
                    return;
                  }
                  await saveScrapedProduct(product);
                  if (product.price !== null) savedPrices += 1;
                } catch (error) {
                  errors += 1;
                  console.error(
                    `[${result.storeSlug}] No se pudo guardar ${product.externalName}:`,
                    error,
                  );
                }
              }),
            );
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
    rejectedProducts,
    totalTimeMs: Date.now() - startedAt,
  });
}

if (process.argv[1]?.endsWith("update-prices.ts")) {
  updatePrices().catch((error: unknown) => {
    console.error("El job terminó inesperadamente:", error);
    process.exitCode = 1;
  });
}
