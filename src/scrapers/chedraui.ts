import type { ProductMeta } from "../products/products-test.js";
import { presentationFromText } from "../products/normalize.js";
import type { ScrapedProduct } from "./types.js";
import type { VtexListing } from "./vtex.js";

export function chedrauiListingToScrapedProduct(
  listing: VtexListing,
  requestUrl: string,
  productMeta: ProductMeta,
): ScrapedProduct {
  return {
    storeSlug: "chedraui-online",
    storeName: "Chedraui online",
    storeEnabled: true,
    source: "chedraui-direct",
    sourceProductName: listing.productName,
    sourceStoreName: "Chedraui online",
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
      brand: listing.brand,
      category: listing.category,
      ean: listing.ean,
      sellerName: listing.sellerName,
      listPrice: listing.listPrice,
      availableQuantity: listing.availableQuantity,
    },
    searchTerm: productMeta.normalizedName,
    internalProductName: productMeta.internalName,
    normalizedName: productMeta.normalizedName,
    category: productMeta.category,
    externalName: listing.productName,
    price: listing.price,
    currency: "MXN",
    externalUrl: listing.productUrl,
    storeProductUrl: listing.productUrl,
    imageUrl: listing.imageUrl,
    presentation: presentationFromText(listing.productName),
    available: listing.availableQuantity > 0,
    scrapedAt: new Date().toISOString(),
  };
}
