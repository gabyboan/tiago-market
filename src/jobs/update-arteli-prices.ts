import { productsTest } from "../products/products-test.js";
import { scrapeArteli } from "../scrapers/arteli.js";
import { updatePrices } from "./update-prices.js";

updatePrices({
  products: productsTest,
  scrapers: [scrapeArteli],
}).catch((error: unknown) => {
  console.error("El job Arteli terminó inesperadamente:", error);
  process.exitCode = 1;
});
