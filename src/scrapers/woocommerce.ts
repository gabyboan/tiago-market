import { z } from "zod";

const wooImageSchema = z.object({
  src: z.string().url(),
});

const wooPricesSchema = z.object({
  price: z.string().regex(/^\d+$/),
  regular_price: z.string().regex(/^\d+$/),
  sale_price: z.string().regex(/^\d+$/),
  currency_code: z.string().min(1),
  currency_minor_unit: z.coerce.number().int().nonnegative(),
});

const wooProductSchema = z.object({
  id: z.coerce.number().int().positive(),
  name: z.string().min(1),
  permalink: z.string().url(),
  sku: z.string(),
  short_description: z.string(),
  prices: wooPricesSchema,
  images: z.array(wooImageSchema).optional().default([]),
  categories: z
    .array(z.object({ name: z.string().min(1) }))
    .optional()
    .default([]),
  is_purchasable: z.boolean(),
  is_in_stock: z.boolean(),
});

export const wooStoreProductsSchema = z.array(wooProductSchema);
export type WooStoreProduct = z.infer<typeof wooProductSchema>;

export function wooPrice(product: WooStoreProduct): number {
  return (
    Number(product.prices.price) / 10 ** product.prices.currency_minor_unit
  );
}

export async function fetchWooStoreCatalogPage(
  host: string,
  page: number,
  pageSize = 100,
): Promise<{ requestUrl: string; products: WooStoreProduct[] }> {
  const url = new URL("/wp-json/wc/store/v1/products", `https://${host}`);
  url.searchParams.set("page", String(page));
  url.searchParams.set("per_page", String(pageSize));

  const requestUrl = url.toString();
  const response = await fetch(requestUrl, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`${host} respondió HTTP ${response.status}.`);
  }

  return {
    requestUrl,
    products: wooStoreProductsSchema.parse(await response.json()),
  };
}

export async function fetchWooStoreProducts(
  host: string,
  searchTerm: string,
  maximum = 20,
): Promise<{ requestUrl: string; products: WooStoreProduct[] }> {
  const url = new URL("/wp-json/wc/store/v1/products", `https://${host}`);
  url.searchParams.set("search", searchTerm);
  url.searchParams.set("per_page", String(maximum));

  const requestUrl = url.toString().replace(/\+/g, "%20");
  const response = await fetch(requestUrl, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`${host} respondió HTTP ${response.status}.`);
  }

  return {
    requestUrl,
    products: wooStoreProductsSchema.parse(await response.json()),
  };
}
