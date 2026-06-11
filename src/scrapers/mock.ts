import type { ProductMeta } from "../products/products-test.js";
import type { ScraperResult } from "./types.js";

const basePrices: Record<string, number> = {
  "coca cola 600 ml": 18.5,
  "leche entera 1 l": 29.9,
  "arroz 1 kg": 38.5,
  "azucar 1 kg": 34.9,
  "aceite vegetal 1 l": 47.5,
  "huevo blanco 12 piezas": 52.9,
  "pan blanco de caja": 49.5,
  "detergente liquido 1 l": 42.9,
  "papel higienico 4 rollos": 39.9,
  "cafe soluble 100 g": 74.5,
};

export async function scrapeMock(
  searchTerm: string,
  productMeta: ProductMeta,
): Promise<ScraperResult> {
  const price = basePrices[productMeta.normalizedName] ?? 50;
  const slug = productMeta.normalizedName.replaceAll(" ", "-");

  return {
    ok: true,
    storeSlug: "mock-market",
    searchTerm,
    products: [
      {
        storeSlug: "mock-market",
        searchTerm,
        internalProductName: productMeta.internalName,
        normalizedName: productMeta.normalizedName,
        category: productMeta.category,
        externalName: `${productMeta.internalName} Marca Ejemplo`,
        price,
        currency: "MXN",
        externalUrl: `https://example.com/productos/${slug}`,
        imageUrl: `https://placehold.co/600x600?text=${encodeURIComponent(productMeta.internalName)}`,
        presentation: productMeta.internalName.match(/\d.+$/)?.[0] ?? null,
        available: true,
        scrapedAt: new Date().toISOString(),
      },
    ],
  };
}
