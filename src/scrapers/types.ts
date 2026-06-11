import type { ProductMeta } from "../products/products-test.js";

export type ScrapedProduct = {
  storeSlug: string;
  storeName?: string;
  storeEnabled?: boolean;
  source: string;
  sourceProductName: string;
  sourceStoreName: string;
  sourceBranchName: string | null;
  sourceBranchKey: string | null;
  sourceAddress: string | null;
  sourceNeighborhood: string | null;
  sourcePostalCode: string | null;
  sourceMunicipality: string | null;
  sourceState: string | null;
  sourceCityCode: string | null;
  sourceCityName: string | null;
  externalReference: string | null;
  rawPayload: Record<string, unknown>;
  searchTerm: string;
  internalProductName: string;
  normalizedName: string;
  category: string | null;
  externalName: string;
  price: number | null;
  currency: "MXN";
  externalUrl: string | null;
  storeProductUrl: string | null;
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
