import type { ProductMeta } from "../products/products-test.js";
import type { ScrapedProduct, ScraperResult } from "./types.js";
import { fetchVtexListings, type VtexListing } from "./vtex.js";

const ARTELI_HOST = "www.arteli.com.mx";

function normalizeProduct(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\bkilogramos?\b/g, "kg")
    .replace(/\bgramos?\b/g, "g")
    .replace(/\blitros?\b/g, "l")
    .replace(/\bmililitros?\b/g, "ml")
    .replace(/(\d)([a-z])/g, "$1 $2")
    .replace(/([a-z])(\d)/g, "$1 $2")
    .replace(/[^a-z0-9.,]+/g, " ")
    .trim();
}

function presentationFromName(productName: string): string | null {
  return (
    productName.match(/\b\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg|pzas?)\b/i)?.[0] ?? null
  );
}

function normalizedPresentation(value: string): string | null {
  const match = normalizeProduct(value).match(
    /\b(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg|pzas?|piezas?|rollos?)\b/,
  );
  if (!match) return null;
  const amountText = match[1];
  const unitText = match[2];
  if (!amountText || !unitText) return null;

  const amount = Number(amountText.replace(",", "."));
  const unit = unitText.replace(/^piezas?$/, "pza").replace(/^pzas?$/, "pza");
  return `${amount}:${unit}`;
}

function searchQuery(productMeta: ProductMeta): string {
  return normalizeProduct(productMeta.normalizedName)
    .split(" ")
    .filter(
      (term) =>
        !/^\d+(?:[.,]\d+)?$/.test(term) &&
        ![
          "l",
          "ml",
          "g",
          "kg",
          "pza",
          "pzas",
          "pieza",
          "piezas",
          "rollo",
          "rollos",
        ].includes(term),
    )
    .join(" ");
}

export function arteliListingMatches(
  listing: VtexListing,
  productMeta: ProductMeta,
): boolean {
  const product = normalizeProduct(listing.productName);
  const requested = normalizeProduct(productMeta.normalizedName);
  const requestedPresentation = normalizedPresentation(requested);
  const listingPresentation = normalizedPresentation(product);

  if (requestedPresentation && requestedPresentation !== listingPresentation) {
    return false;
  }
  if (
    !/\b(?:pack|paquete)\b/.test(requested) &&
    /\b(?:pack|paquete)\b/.test(product)
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
      (term) => product.includes(term) && !requested.includes(term),
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
    "pzas",
    "pieza",
    "piezas",
    "rollo",
    "rollos",
  ]);
  const meaningfulTerms = requested
    .split(" ")
    .filter((term) => term.length > 1 && !ignoredTerms.has(term));

  return meaningfulTerms.every((term) => product.includes(term));
}

export function arteliListingToScrapedProduct(
  listing: VtexListing,
  requestUrl: string,
  searchTerm: string,
  productMeta: ProductMeta,
): ScrapedProduct {
  return {
    storeSlug: "arteli-online",
    storeName: "Arteli online",
    storeEnabled: true,
    source: "arteli-direct",
    sourceProductName: listing.productName,
    sourceStoreName: "Arteli online",
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
      productId: listing.productId,
      itemId: listing.itemId,
      productReference: listing.productReference,
      ean: listing.ean,
      brand: listing.brand,
      category: listing.category,
      sellerName: listing.sellerName,
      listPrice: listing.listPrice,
      availableQuantity: listing.availableQuantity,
    },
    searchTerm,
    internalProductName: productMeta.internalName,
    normalizedName: productMeta.normalizedName,
    category: productMeta.category,
    externalName: listing.productName,
    price: listing.price,
    currency: "MXN",
    externalUrl: listing.productUrl,
    storeProductUrl: listing.productUrl,
    imageUrl: listing.imageUrl,
    presentation: presentationFromName(listing.productName),
    available: listing.availableQuantity > 0,
    scrapedAt: new Date().toISOString(),
  };
}

export async function scrapeArteli(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  try {
    const { requestUrl, listings } = await fetchVtexListings(
      ARTELI_HOST,
      searchQuery(productMeta),
    );
    const selected = listings
      .filter((listing) => listing.sellerName.toLowerCase() === "arteli")
      .filter((listing) => listing.price > 0 && listing.availableQuantity > 0)
      .filter((listing) =>
        listing.productUrl.startsWith(`https://${ARTELI_HOST}/`),
      )
      .filter((listing) => arteliListingMatches(listing, productMeta));

    return {
      ok: true,
      storeSlug: "arteli-online",
      searchTerm,
      products: selected.map((listing) =>
        arteliListingToScrapedProduct(
          listing,
          requestUrl,
          searchTerm,
          productMeta,
        ),
      ),
    };
  } catch (error) {
    return {
      ok: false,
      storeSlug: "arteli-online",
      searchTerm,
      products: [],
      error: error instanceof Error ? error.message : "Error desconocido",
    };
  }
}
