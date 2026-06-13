import { env } from "../config/env.js";
import { validateDirectProduct } from "../data-quality/direct-product.js";
import { saveScrapedProduct } from "../db/save-scraped-product.js";
import { productMetaFromListing } from "../products/normalize.js";
import { arteliListingToScrapedProduct } from "../scrapers/arteli.js";
import { chedrauiListingToScrapedProduct } from "../scrapers/chedraui.js";
import { hebListingToScrapedProduct } from "../scrapers/heb.js";
import { smartFinalProductToScrapedProduct } from "../scrapers/smart-final.js";
import { fetchVtexCatalogPage } from "../scrapers/vtex.js";
import { fetchWooStoreCatalogPage, wooPrice } from "../scrapers/woocommerce.js";
import type { ScrapedProduct } from "../scrapers/types.js";

const SAVE_CONCURRENCY = 5;

async function saveProducts(products: ScrapedProduct[]): Promise<number> {
  const uniqueProducts = [
    ...new Map(
      products.map((product) => [
        `${product.storeSlug}|${product.normalizedName}|${product.externalUrl ?? product.externalName}`,
        product,
      ]),
    ).values(),
  ];
  let saved = 0;
  for (let index = 0; index < uniqueProducts.length; index += SAVE_CONCURRENCY) {
    await Promise.all(
      uniqueProducts
        .slice(index, index + SAVE_CONCURRENCY)
        .map(async (product) => {
        if (!validateDirectProduct(product).accepted) return;
        await saveScrapedProduct(product);
        saved += 1;
        }),
    );
  }
  return saved;
}

async function importArteliPage(page: number): Promise<number> {
  const { requestUrl, listings } = await fetchVtexCatalogPage(
    "www.arteli.com.mx",
    page,
  );
  const products = listings
    .filter((listing) => listing.sellerName.toLowerCase() === "arteli")
    .filter((listing) => listing.price > 0 && listing.availableQuantity > 0)
    .map((listing) => {
      const meta = productMetaFromListing(listing.productName, listing.category);
      return arteliListingToScrapedProduct(
        listing,
        requestUrl,
        meta.normalizedName,
        meta,
      );
    });
  return saveProducts(products);
}

async function importSmartFinalPage(page: number): Promise<number> {
  const { requestUrl, products } = await fetchWooStoreCatalogPage(
    "www.smartnfinal.com.mx",
    page,
  );
  const scraped = products
    .filter((product) => product.prices.currency_code === "MXN")
    .filter((product) => wooPrice(product) > 0 && product.is_in_stock)
    .map((product) => {
      const meta = productMetaFromListing(
        `${product.name} ${product.short_description.replace(/<[^>]*>/g, " ")}`,
        product.categories[0]?.name ?? null,
      );
      return smartFinalProductToScrapedProduct(
        product,
        requestUrl,
        meta.normalizedName,
        meta,
      );
    });
  return saveProducts(scraped);
}

async function importChedrauiPage(page: number): Promise<number> {
  const { requestUrl, listings } = await fetchVtexCatalogPage(
    "www.chedraui.com.mx",
    page,
  );
  const products = listings
    .filter((listing) => listing.sellerName.toLowerCase() === "chedraui")
    .filter((listing) => listing.price > 0 && listing.availableQuantity > 0)
    .map((listing) => {
      const meta = productMetaFromListing(listing.productName, listing.category);
      return chedrauiListingToScrapedProduct(listing, requestUrl, meta);
    });
  return saveProducts(products);
}

async function importHebPage(page: number): Promise<number> {
  const { requestUrl, listings } = await fetchVtexCatalogPage(
    "www.heb.com.mx",
    page,
  );
  const products = listings
    .filter((listing) => listing.sellerName.toLowerCase() === "heb")
    .filter((listing) => listing.price > 0 && listing.availableQuantity > 0)
    .map((listing) => {
      const meta = productMetaFromListing(listing.productName, listing.category);
      return hebListingToScrapedProduct(listing, requestUrl, meta);
    });
  return saveProducts(products);
}

async function safeImport(
  source: string,
  page: number,
  importer: (page: number) => Promise<number>,
) {
  try {
    return await importer(page);
  } catch (error) {
    console.warn({ source, page, error: String(error) });
    return 0;
  }
}

async function importDirectCatalog(): Promise<void> {
  let saved = 0;
  const sources = new Set(
    env.DIRECT_CATALOG_SOURCES.split(",").map((source) => source.trim()),
  );
  const lastPage =
    env.DIRECT_CATALOG_START_PAGE + env.DIRECT_CATALOG_PAGE_LIMIT - 1;
  for (
    let page = env.DIRECT_CATALOG_START_PAGE;
    page <= Math.min(lastPage, 100);
    page += 1
  ) {
    const [arteli, smartFinal, chedraui, heb] = await Promise.all([
      sources.has("arteli") ? safeImport("arteli", page, importArteliPage) : 0,
      sources.has("smart-final")
        ? safeImport("smart-final", page, importSmartFinalPage)
        : 0,
      sources.has("chedraui")
        ? safeImport("chedraui", page, importChedrauiPage)
        : 0,
      sources.has("heb") ? safeImport("heb", page, importHebPage) : 0,
    ]);
    saved += arteli + smartFinal + chedraui + heb;
    console.info({ page, arteli, smartFinal, chedraui, heb, saved });
  }
}

importDirectCatalog().catch((error: unknown) => {
  console.error("La importación del catálogo directo falló:", error);
  process.exitCode = 1;
});
