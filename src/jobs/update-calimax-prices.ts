import { productsTest } from "../products/products-test.js";
import { scrapeCalimax } from "../scrapers/calimax.js";
import { updatePrices } from "./update-prices.js";

updatePrices({
  products: productsTest,
  scrapers: [scrapeCalimax],
}).catch((error: unknown) => {
  console.error("El job Calimax terminó inesperadamente:", error);
  process.exitCode = 1;
});
