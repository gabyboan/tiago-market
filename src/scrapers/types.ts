import type { ProductMeta } from "../products/products-test.js";

export type ScrapedProduct = {
  storeSlug: string;
  storeName?: string;
  storeEnabled?: boolean;
  source: string;
  searchTerm: string;
  internalProductName: string;
  normalizedName: string;
  category: string | null;
  externalName: string;
  price: number | null;
  currency: "MXN";
  externalUrl: string | null;
  imageUrl: string | null;
  presentation: string | null;
  available: boolean;
  scrapedAt: string;
};

export type ScraperResult = {
  ok: boolean;
  storeSlug: string;
  searchTerm: string;
  products: ScrapedProduct[];
  error?: string;
};

export type StoreScraper = (
  searchTerm: string,
  productMeta: ProductMeta,
) => Promise<ScraperResult>;
