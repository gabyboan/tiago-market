import type { ProductMeta } from "../products/products-test.js";
import { createBrowserPage } from "./browser.js";
import type { ScraperResult } from "./types.js";

export type WalmartFamilyBrand = {
  storeSlug: "walmart-mx" | "bodega-aurrera-mx";
  storeName: "Walmart México" | "Bodega Aurrera";
  searchUrl: string;
};

const challengeMarkers = [
  "captcha",
  "access denied",
  "verify you are human",
  "unusual traffic",
  "robot check",
];

export function detectAccessChallenge(html: string): string | null {
  const normalized = html.toLowerCase();
  const marker = challengeMarkers.find((candidate) =>
    normalized.includes(candidate),
  );
  return marker === undefined
    ? null
    : `Public page returned an access challenge (${marker}).`;
}

export async function scrapeWalmartFamily(
  searchTerm: string,
  _productMeta: ProductMeta,
  brand: WalmartFamilyBrand,
): Promise<ScraperResult> {
  const { browser, page } = await createBrowserPage();

  try {
    const response = await page.goto(
      brand.searchUrl.replace("{query}", encodeURIComponent(searchTerm)),
      { waitUntil: "domcontentloaded" },
    );
    const html = await page.content();
    const challenge = detectAccessChallenge(html);

    if (challenge !== null) {
      return {
        ok: false,
        storeSlug: brand.storeSlug,
        searchTerm,
        products: [],
        error: `${brand.storeName}: ${challenge} HTTP ${response?.status() ?? "unknown"}.`,
      };
    }

    return {
      ok: false,
      storeSlug: brand.storeSlug,
      searchTerm,
      products: [],
      error:
        `${brand.storeName}: no validated product selectors or local-store ` +
        "evidence are available; source remains disabled.",
    };
  } catch (error) {
    return {
      ok: false,
      storeSlug: brand.storeSlug,
      searchTerm,
      products: [],
      error: error instanceof Error ? error.message : "Unknown error",
    };
  } finally {
    await browser.close();
  }
}
