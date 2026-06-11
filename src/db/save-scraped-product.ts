import type { ScrapedProduct } from "../scrapers/types.js";
import { supabase } from "./supabase.js";

function assertNoError(error: { message: string } | null, operation: string) {
  if (error) {
    throw new Error(`${operation}: ${error.message}`);
  }
}

export function snapshotRecord(
  product: ScrapedProduct,
  storeProductId: string,
  branchId: string | null = null,
) {
  return {
    store_product_id: storeProductId,
    branch_id: branchId,
    price: product.price,
    currency: product.currency,
    available: product.available,
    scraped_at: product.scrapedAt,
    captured_at: product.scrapedAt,
    source: product.source,
    source_product_name: product.sourceProductName,
    source_store_name: product.sourceStoreName,
    source_branch_name: product.sourceBranchName,
    source_city_code: product.sourceCityCode,
    source_city_name: product.sourceCityName,
    external_reference: product.externalReference,
    raw_payload: product.rawPayload,
  };
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

  let branchId: string | null = null;
  if (product.sourceBranchName && product.sourceBranchKey) {
    const { data: branch, error: branchError } = await supabase
      .from("branches")
      .upsert(
        {
          store_id: store!.id,
          source: product.source,
          external_key: product.sourceBranchKey,
          name: product.sourceBranchName,
          address: product.sourceAddress,
          neighborhood: product.sourceNeighborhood,
          postal_code: product.sourcePostalCode,
          municipality: product.sourceMunicipality,
          state: product.sourceState,
          city_code: product.sourceCityCode,
          city_name: product.sourceCityName,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "source,external_key" },
      )
      .select("id")
      .single();
    assertNoError(branchError, "No se pudo buscar/crear la sucursal");
    branchId = branch!.id as string;
  }

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
        branch_id: branchId,
        store_product_url: product.storeProductUrl,
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
        branch_id: branchId,
        store_product_url: product.storeProductUrl,
      })
      .select("id")
      .single();
    assertNoError(error, "No se pudo crear el producto de tienda");
    storeProductId = data!.id as string;
  }

  if (product.price !== null) {
    const { error } = await supabase
      .from("price_snapshots")
      .insert(snapshotRecord(product, storeProductId, branchId));
    assertNoError(error, "No se pudo guardar el precio");
  }
}
