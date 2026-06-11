import { env } from "../config/env.js";
import { productsTest } from "../products/products-test.js";
import { scrapeProfeco } from "../scrapers/profeco.js";
import { updatePrices } from "./update-prices.js";

updatePrices({
  products: productsTest.slice(0, env.PROFECO_PRODUCT_LIMIT),
  scrapers: [scrapeProfeco],
}).catch((error: unknown) => {
  console.error("El job Profeco terminó inesperadamente:", error);
  process.exitCode = 1;
});
