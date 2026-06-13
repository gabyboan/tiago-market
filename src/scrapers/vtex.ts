import { z } from "zod";

const vtexOfferSchema = z.object({
  Price: z.coerce.number().nonnegative(),
  ListPrice: z.coerce.number().nonnegative(),
  AvailableQuantity: z.coerce.number().int().nonnegative(),
});

const vtexSellerSchema = z.object({
  sellerName: z.string().min(1),
  commertialOffer: vtexOfferSchema,
});

const vtexItemSchema = z.object({
  itemId: z.string().min(1),
  name: z.string().optional(),
  ean: z.string().optional(),
  images: z
    .array(z.object({ imageUrl: z.string().url() }))
    .optional()
    .default([]),
  sellers: z.array(vtexSellerSchema).optional().default([]),
});

const vtexProductSchema = z.object({
  productId: z.string().min(1),
  productName: z.string().min(1),
  brand: z.string().optional(),
  categories: z.array(z.string()).optional().default([]),
  link: z.string().url(),
  productReference: z.string().optional(),
  items: z.array(vtexItemSchema).optional().default([]),
});

export const vtexSearchResponseSchema = z.array(vtexProductSchema);
export type VtexProduct = z.infer<typeof vtexProductSchema>;

export type VtexListing = {
  productId: string;
  itemId: string;
  productName: string;
  brand: string | null;
  category: string | null;
  productReference: string | null;
  ean: string | null;
  sellerName: string;
  price: number;
  listPrice: number;
  availableQuantity: number;
  productUrl: string;
  imageUrl: string | null;
};

export function flattenVtexProducts(products: VtexProduct[]): VtexListing[] {
  return products.flatMap((product) =>
    product.items.flatMap((item) =>
      item.sellers.map((seller) => ({
        productId: product.productId,
        itemId: item.itemId,
        productName: product.productName,
        brand: product.brand ?? null,
        category:
          product.categories
            .map((category) => category.replaceAll("/", "").trim())
            .filter(Boolean)
            .at(-1) ?? null,
        productReference: product.productReference ?? null,
        ean: item.ean || null,
        sellerName: seller.sellerName,
        price: seller.commertialOffer.Price,
        listPrice: seller.commertialOffer.ListPrice,
        availableQuantity: seller.commertialOffer.AvailableQuantity,
        productUrl: product.link,
        imageUrl: item.images[0]?.imageUrl ?? null,
      })),
    ),
  );
}

export async function fetchVtexListings(
  host: string,
  searchTerm: string,
  maximum = 20,
): Promise<{ requestUrl: string; listings: VtexListing[] }> {
  const url = new URL(
    "/api/catalog_system/pub/products/search/",
    `https://${host}`,
  );
  url.searchParams.set("ft", searchTerm);
  url.searchParams.set("_from", "0");
  url.searchParams.set("_to", String(Math.max(0, maximum - 1)));
  const requestUrl = url.toString().replace(/\+/g, "%20");

  const response = await fetch(requestUrl, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`${host} respondió HTTP ${response.status}.`);
  }

  const products = vtexSearchResponseSchema.parse(await response.json());
  return {
    requestUrl,
    listings: flattenVtexProducts(products),
  };
}

export async function fetchVtexCatalogPage(
  host: string,
  page: number,
  pageSize = 50,
): Promise<{ requestUrl: string; listings: VtexListing[] }> {
  const from = Math.max(0, page - 1) * pageSize;
  const url = new URL(
    "/api/catalog_system/pub/products/search/",
    `https://${host}`,
  );
  url.searchParams.set("_from", String(from));
  url.searchParams.set("_to", String(from + pageSize - 1));

  const requestUrl = url.toString();
  const response = await fetch(requestUrl, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`${host} respondió HTTP ${response.status}.`);
  }

  const products = vtexSearchResponseSchema.parse(await response.json());
  return {
    requestUrl,
    listings: flattenVtexProducts(products),
  };
}
