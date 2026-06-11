import type { ScrapedProduct } from "../scrapers/types.js";
import { supabase } from "./supabase.js";

function assertNoError(error: { message: string } | null, operation: string) {
  if (error) {
    throw new Error(`${operation}: ${error.message}`);
  }
}

export async function saveScrapedProduct(
  product: ScrapedProduct,
): Promise<void> {
  const { data: store, error: storeError } = await supabase
    .from("stores")
    .upsert(
      {
        name: product.storeName ?? product.storeSlug,
        slug: product.storeSlug,
        enabled: product.storeEnabled ?? true,
      },
      { onConflict: "slug" },
    )
    .select("id")
    .single();
  assertNoError(storeError, "No se pudo buscar/crear la tienda");

  const { data: internalProduct, error: productError } = await supabase
    .from("products")
    .upsert(
      {
        name: product.internalProductName,
        normalized_name: product.normalizedName,
        category: product.category,
      },
      { onConflict: "normalized_name" },
    )
    .select("id")
    .single();
  assertNoError(productError, "No se pudo buscar/crear el producto");

  let storeProductQuery = supabase
    .from("store_products")
    .select("id")
    .eq("store_id", store!.id)
    .eq("product_id", internalProduct!.id);

  storeProductQuery = product.externalUrl
    ? storeProductQuery.eq("external_url", product.externalUrl)
    : storeProductQuery
        .is("external_url", null)
        .eq("external_name", product.externalName);

  const { data: existingStoreProduct, error: lookupError } =
    await storeProductQuery.maybeSingle();
  assertNoError(lookupError, "No se pudo buscar el producto de tienda");

  let storeProductId = existingStoreProduct?.id as string | undefined;

  if (storeProductId) {
    const { error } = await supabase
      .from("store_products")
      .update({
        external_name: product.externalName,
        image_url: product.imageUrl,
        presentation: product.presentation,
        source: product.source,
        available: product.available,
        last_seen_at: product.scrapedAt,
      })
      .eq("id", storeProductId);
    assertNoError(error, "No se pudo actualizar el producto de tienda");
  } else {
    const { data, error } = await supabase
      .from("store_products")
      .insert({
        store_id: store!.id,
        product_id: internalProduct!.id,
        external_name: product.externalName,
        external_url: product.externalUrl,
        image_url: product.imageUrl,
        presentation: product.presentation,
        source: product.source,
        available: product.available,
        last_seen_at: product.scrapedAt,
      })
      .select("id")
      .single();
    assertNoError(error, "No se pudo crear el producto de tienda");
    storeProductId = data!.id as string;
  }

  if (product.price !== null) {
    const { error } = await supabase.from("price_snapshots").insert({
      store_product_id: storeProductId,
      price: product.price,
      currency: product.currency,
      available: product.available,
      scraped_at: product.scrapedAt,
    });
    assertNoError(error, "No se pudo guardar el precio");
  }
}
