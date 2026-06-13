import type { ProductMeta } from "../products/products-test.js";
import type { ScrapedProduct, ScraperResult } from "./types.js";
import {
  fetchWooStoreProducts,
  type WooStoreProduct,
  wooPrice,
} from "./woocommerce.js";

const SMART_FINAL_HOST = "www.smartnfinal.com.mx";

function textFromHtml(value: string): string {
  return value.replace(/<[^>]*>/g, " ").replace(/&nbsp;|&#160;/gi, " ");
}

function normalizeProduct(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\bkilogramos?\b/g, "kg")
    .replace(/\bgramos?\b/g, "g")
    .replace(/\blitros?|lts?\b/g, "l")
    .replace(/\bmililitros?\b/g, "ml")
    .replace(/\bpiezas?|pzas?\b/g, "pza")
    .replace(/(\d)([a-z])/g, "$1 $2")
    .replace(/([a-z])(\d)/g, "$1 $2")
    .replace(/[^a-z0-9.,]+/g, " ")
    .trim();
}

function presentationFromProduct(product: WooStoreProduct): string | null {
  return (
    textFromHtml(product.short_description).match(
      /\b\d+(?:[.,]\d+)?\s*(?:ml|l|lts?|g|kg|pzas?|piezas?|rollos?)\b/i,
    )?.[0] ?? null
  );
}

function normalizedPresentation(value: string): string | null {
  const match = normalizeProduct(value).match(
    /\b(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg|pza|rollos?)\b/,
  );
  if (!match) return null;
  const amountText = match[1];
  const unit = match[2];
  if (!amountText || !unit) return null;

  return `${Number(amountText.replace(",", "."))}:${unit}`;
}

function searchQuery(productMeta: ProductMeta): string {
  return normalizeProduct(productMeta.normalizedName)
    .split(" ")
    .filter(
      (term) =>
        !/^\d+(?:[.,]\d+)?$/.test(term) &&
        !["l", "ml", "g", "kg", "pza", "rollo", "rollos"].includes(term),
    )
    .join(" ");
}

export function smartFinalProductMatches(
  product: WooStoreProduct,
  productMeta: ProductMeta,
): boolean {
  const candidate = normalizeProduct(
    `${product.name} ${textFromHtml(product.short_description)}`,
  );
  const requested = normalizeProduct(productMeta.normalizedName);
  const requestedPresentation = normalizedPresentation(requested);
  const candidatePresentation = normalizedPresentation(candidate);

  if (
    requestedPresentation &&
    requestedPresentation !== candidatePresentation
  ) {
    return false;
  }

  const variantTerms = [
    "deslactosada",
    "organica",
    "fresca",
    "evaporada",
    "condensada",
    "polvo",
    "sabor",
  ];
  if (
    variantTerms.some(
      (term) => candidate.includes(term) && !requested.includes(term),
    )
  ) {
    return false;
  }

  const ignoredTerms = new Set([
    "de",
    "el",
    "la",
    "l",
    "ml",
    "g",
    "kg",
    "pza",
    "rollo",
    "rollos",
  ]);
  const meaningfulTerms = requested
    .split(" ")
    .filter((term) => term.length > 1 && !ignoredTerms.has(term));

  return meaningfulTerms.every((term) => candidate.includes(term));
}

export function smartFinalProductToScrapedProduct(
  product: WooStoreProduct,
  requestUrl: string,
  searchTerm: string,
  productMeta: ProductMeta,
): ScrapedProduct {
  return {
    storeSlug: "smart-final-mexico-online",
    storeName: "Smart & Final México online",
    storeEnabled: true,
    source: "smart-final-direct",
    sourceProductName: product.name,
    sourceStoreName: "Smart & Final México online",
    sourceBranchName: null,
    sourceBranchKey: null,
    sourceAddress: null,
    sourceNeighborhood: null,
    sourcePostalCode: null,
    sourceMunicipality: null,
    sourceState: null,
    sourceCityCode: null,
    sourceCityName: null,
    externalReference: requestUrl,
    rawPayload: {
      productId: product.id,
      sku: product.sku,
      regularPrice: product.prices.regular_price,
      salePrice: product.prices.sale_price,
      currencyMinorUnit: product.prices.currency_minor_unit,
      isPurchasable: product.is_purchasable,
      isInStock: product.is_in_stock,
    },
    searchTerm,
    internalProductName: productMeta.internalName,
    normalizedName: productMeta.normalizedName,
    category: productMeta.category,
    externalName: product.name,
    price: wooPrice(product),
    currency: "MXN",
    externalUrl: product.permalink,
    storeProductUrl: product.permalink,
    imageUrl: product.images[0]?.src ?? null,
    presentation: presentationFromProduct(product),
    available: product.is_in_stock,
    scrapedAt: new Date().toISOString(),
  };
}

export async function scrapeSmartFinal(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  try {
    const { requestUrl, products } = await fetchWooStoreProducts(
      SMART_FINAL_HOST,
      searchQuery(productMeta),
    );
    const selected = products
      .filter((product) => product.prices.currency_code === "MXN")
      .filter((product) => wooPrice(product) > 0)
      .filter((product) => product.is_in_stock)
      .filter((product) =>
        product.permalink.startsWith(`https://${SMART_FINAL_HOST}/`),
      )
      .filter((product) => smartFinalProductMatches(product, productMeta));

    return {
      ok: true,
      storeSlug: "smart-final-mexico-online",
      searchTerm,
      products: selected.map((product) =>
        smartFinalProductToScrapedProduct(
          product,
          requestUrl,
          searchTerm,
          productMeta,
        ),
      ),
    };
  } catch (error) {
    return {
      ok: false,
      storeSlug: "smart-final-mexico-online",
      searchTerm,
      products: [],
      error: error instanceof Error ? error.message : "Error desconocido",
    };
  }
}
