import { env } from "../config/env.js";
import { saveScrapedProduct } from "../db/save-scraped-product.js";
import {
  catalogPriceToScrapedProduct,
  fetchProfecoCatalogTerm,
  profecoCatalogTerms,
  selectLatestCatalogListings,
} from "../scrapers/profeco-catalog.js";
import type { ProfecoPrice } from "../scrapers/profeco.js";

const SAVE_CONCURRENCY = 20;

export async function importProfecoCatalog(): Promise<void> {
  const startedAt = Date.now();
  const prices: ProfecoPrice[] = [];
  let requestErrors = 0;

  for (const term of profecoCatalogTerms.slice(
    0,
    env.PROFECO_BULK_TERM_LIMIT,
  )) {
    try {
      const rows = await fetchProfecoCatalogTerm(term);
      prices.push(...rows);
      console.info({ term, observations: rows.length });
    } catch (error) {
      requestErrors += 1;
      console.error(`[profeco-catalog] ${term}:`, error);
    } finally {
      await new Promise((resolve) =>
        setTimeout(resolve, env.PROFECO_REQUEST_DELAY_MS),
      );
    }
  }

  const listings = selectLatestCatalogListings(
    prices,
    env.PROFECO_BULK_MAX_LISTINGS,
  );
  let savedPrices = 0;
  let saveErrors = 0;

  for (let index = 0; index < listings.length; index += SAVE_CONCURRENCY) {
    const batch = listings.slice(index, index + SAVE_CONCURRENCY);
    await Promise.all(
      batch.map(async (price) => {
        try {
          await saveScrapedProduct(
            catalogPriceToScrapedProduct(price, price.tipo_producto),
          );
          savedPrices += 1;
        } catch (error) {
          saveErrors += 1;
          console.error(
            `[profeco-catalog] No se pudo guardar ${price.producto}:`,
            error,
          );
        }
      }),
    );
  }

  console.info({
    terms: Math.min(env.PROFECO_BULK_TERM_LIMIT, profecoCatalogTerms.length),
    fetchedObservations: prices.length,
    uniqueLatestListings: listings.length,
    savedPrices,
    errors: requestErrors + saveErrors,
    totalTimeMs: Date.now() - startedAt,
  });
}

if (process.argv[1]?.endsWith("import-profeco-catalog.ts")) {
  importProfecoCatalog().catch((error: unknown) => {
    console.error(
      "La importación masiva PROFECO terminó inesperadamente:",
      error,
    );
    process.exitCode = 1;
  });
}
