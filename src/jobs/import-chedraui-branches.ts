import { z } from "zod";
import { supabase } from "../db/supabase.js";

const pickupResponseSchema = z.object({
  paging: z.object({
    page: z.coerce.number().int().positive(),
    pages: z.coerce.number().int().nonnegative(),
  }),
  items: z.array(
    z.object({
      pickupPoint: z.object({
        id: z.string().min(1),
        friendlyName: z.string().min(1),
        isActive: z.boolean(),
        address: z.object({
          postalCode: z.string().nullable(),
          city: z.string().nullable(),
          state: z.string().nullable(),
          street: z.string().nullable(),
          number: z.string().nullable(),
          neighborhood: z.string().nullable(),
          geoCoordinates: z.tuple([z.number(), z.number()]),
        }),
      }),
    }),
  ),
});

const seedCoordinates = [
  [-99.1332, 19.4326],
  [-103.3496, 20.6597],
  [-100.3161, 25.6866],
  [-96.1342, 19.1738],
  [-98.2063, 19.0414],
  [-86.8515, 21.1619],
  [-92.9475, 17.9895],
  [-96.7266, 17.0732],
  [-101.194, 19.706],
] as const;

async function fetchPickups(longitude: number, latitude: number, page: number) {
  const url = new URL(
    "/api/checkout/pub/pickup-points",
    "https://www.chedraui.com.mx",
  );
  url.searchParams.set("geoCoordinates", `${longitude};${latitude}`);
  url.searchParams.set("page", String(page));
  url.searchParams.set("pageSize", "100");
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`Chedraui respondió HTTP ${response.status}`);
  return pickupResponseSchema.parse(await response.json());
}

async function importBranches() {
  const { data: store, error: storeError } = await supabase
    .from("stores")
    .upsert(
      { slug: "chedraui-online", name: "Chedraui online", enabled: true },
      { onConflict: "slug" },
    )
    .select("id")
    .single();
  if (storeError) throw storeError;

  const branches = new Map<string, Record<string, unknown>>();
  for (const [longitude, latitude] of seedCoordinates) {
    const first = await fetchPickups(longitude, latitude, 1);
    for (let page = 1; page <= Math.max(1, first.paging.pages); page += 1) {
      const result = page === 1 ? first : await fetchPickups(longitude, latitude, page);
      for (const { pickupPoint } of result.items) {
        if (!pickupPoint.isActive) continue;
        const address = pickupPoint.address;
        branches.set(pickupPoint.id, {
          store_id: store.id,
          source: "chedraui-pickup-directory",
          external_key: pickupPoint.id,
          name: pickupPoint.friendlyName.trim(),
          address: [address.street, address.number].filter(Boolean).join(" "),
          neighborhood: address.neighborhood,
          postal_code: address.postalCode,
          municipality: address.city,
          state: address.state,
          city_name: address.city,
          longitude: address.geoCoordinates[0],
          latitude: address.geoCoordinates[1],
          geocoding_status: "manual",
          geocoded_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });
      }
    }
  }

  const { error } = await supabase.from("branches").upsert([...branches.values()], {
    onConflict: "source,external_key",
  });
  if (error) throw error;
  console.info({ importedChedrauiBranches: branches.size });
}

importBranches().catch((error: unknown) => {
  console.error("No se pudieron importar sucursales de Chedraui:", error);
  process.exitCode = 1;
});
