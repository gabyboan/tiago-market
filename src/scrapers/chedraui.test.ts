import assert from "node:assert/strict";
import test from "node:test";
import { productMetaFromListing } from "../products/normalize.js";
import { chedrauiListingToScrapedProduct } from "./chedraui.js";

test("Chedraui conserva marca, categoría y enlace oficial", () => {
  const listing = {
    productId: "1",
    itemId: "2",
    productName: "Pantalla Samsung 55 pulgadas",
    brand: "Samsung",
    category: "Electrodomesticos y linea blanca",
    productReference: null,
    ean: "123",
    sellerName: "Chedraui",
    price: 9999,
    listPrice: 10999,
    availableQuantity: 3,
    productUrl: "https://www.chedraui.com.mx/pantalla-samsung/p",
    imageUrl: "https://www.chedraui.com.mx/pantalla.jpg",
  };
  const product = chedrauiListingToScrapedProduct(
    listing,
    "https://www.chedraui.com.mx/api/catalog_system/pub/products/search/",
    productMetaFromListing(listing.productName, listing.category),
  );

  assert.equal(product.category, "Electrodomesticos y linea blanca");
  assert.equal(product.storeProductUrl, listing.productUrl);
  assert.equal(product.rawPayload.brand, "Samsung");
});
