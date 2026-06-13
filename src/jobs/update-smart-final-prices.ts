import { productsTest } from "../products/products-test.js";
import { scrapeSmartFinal } from "../scrapers/smart-final.js";
import { updatePrices } from "./update-prices.js";

updatePrices({
  products: productsTest,
  scrapers: [scrapeSmartFinal],
}).catch((error: unknown) => {
  console.error("El job Smart & Final terminó inesperadamente:", error);
  process.exitCode = 1;
});
