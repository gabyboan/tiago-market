import assert from "node:assert/strict";
import test from "node:test";
import type { ProductMeta } from "../products/products-test.js";
import {
  arteliListingMatches,
  arteliListingToScrapedProduct,
} from "./arteli.js";
import type { VtexListing } from "./vtex.js";

const productMeta: ProductMeta = {
  internalName: "Leche entera 1 L",
  normalizedName: "leche entera 1 l",
  category: "Lácteos",
  searchTerms: ["leche entera 1 l"],
};

const listing: VtexListing = {
  productId: "3718256",
  itemId: "3718256",
  productName: "Leche Lala Entera 1L",
  brand: "Lala",
  category: "Supermercado",
  productReference: "3718256",
  ean: "7501020513943",
  sellerName: "Arteli",
  price: 33,
  listPrice: 33,
  availableQuantity: 99999,
  productUrl: "https://www.arteli.com.mx/leche-lala-entera-1l-3718256/p",
  imageUrl: "https://example.com/leche.jpg",
};

test("Arteli conserva precio y ficha oficial verificable", () => {
  const product = arteliListingToScrapedProduct(
    listing,
    "https://www.arteli.com.mx/api/catalog_system/pub/products/search/?ft=leche",
    "leche entera 1 l",
    productMeta,
  );

  assert.equal(product.price, 33);
  assert.equal(product.storeProductUrl, listing.productUrl);
  assert.equal(product.source, "arteli-direct");
  assert.equal(product.sourceBranchName, null);
  assert.equal(product.presentation, "1L");
});

test("Arteli evita presentaciones y variantes no comparables", () => {
  assert.equal(
    arteliListingMatches(
      { ...listing, productName: "Leche Lala Entera 6 pack de 1L" },
      productMeta,
    ),
    false,
  );
  assert.equal(
    arteliListingMatches(
      { ...listing, productName: "Leche Lala Entera 1.5L" },
      productMeta,
    ),
    false,
  );
  assert.equal(
    arteliListingMatches(
      { ...listing, productName: "Leche Lala Entera Deslactosada 1L" },
      productMeta,
    ),
    false,
  );
});
