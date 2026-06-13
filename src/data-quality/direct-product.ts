import type { ScrapedProduct } from "../scrapers/types.js";

export type DirectProductQuality = {
  accepted: boolean;
  issues: string[];
};

export function validateDirectProduct(
  product: ScrapedProduct,
): DirectProductQuality {
  const issues: string[] = [];

  if (!product.source.endsWith("-direct")) issues.push("source_not_direct");
  if (product.price === null || product.price <= 0)
    issues.push("invalid_price");
  if (product.price !== null && product.price > 100_000)
    issues.push("implausible_price");
  if (!product.storeProductUrl) issues.push("missing_official_link");
  if (!product.imageUrl) issues.push("missing_image");
  if (!product.available) issues.push("not_available");

  return { accepted: issues.length === 0, issues };
}
