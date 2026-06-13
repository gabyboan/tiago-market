import type { ProductMeta } from "./products-test.js";

export function normalizeProductName(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\bkilogramos?\b/g, "kg")
    .replace(/\bgramos?\b/g, "g")
    .replace(/\blitros?|lts?\b/g, "l")
    .replace(/\bmililitros?\b/g, "ml")
    .replace(/\bpiezas?|pzas?\b/g, "pza")
    .replace(/(\d)([a-z])/g, "$1 $2")
    .replace(/([a-z])(\d)/g, "$1 $2")
    .replace(/[^a-z0-9.,]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function presentationFromText(value: string): string | null {
  return (
    normalizeProductName(value).match(
      /\b\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg|pza|rollos?|gal)\b/i,
    )?.[0] ?? null
  );
}

export function normalizedPresentation(value: string): string | null {
  const normalized = normalizeProductName(value);
  const multipack = normalized.match(
    /\b(\d+)\s*(?:pza|pack|paquete)?\s*(?:de|x)\s*(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg)\b/,
  );
  if (multipack?.[1] && multipack[2] && multipack[3]) {
    const count = Number(multipack[1]);
    const amount = Number(multipack[2].replace(",", "."));
    const unit = multipack[3];
    const canonicalAmount =
      unit === "kg" || unit === "l" ? amount * 1000 : amount;
    const canonicalUnit = unit === "kg" ? "g" : unit === "l" ? "ml" : unit;
    return `${count}x${canonicalAmount}:${canonicalUnit}`;
  }

  const match = normalized.match(
    /\b(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg|pza|rollos?|gal)\b/,
  );
  const amountText = match?.[1];
  const unit = match?.[2];
  if (!amountText || !unit) return null;

  const amount = Number(amountText.replace(",", "."));
  if (unit === "kg") return `${amount * 1000}:g`;
  if (unit === "l") return `${amount * 1000}:ml`;
  if (unit === "gal") return `${Math.round(amount * 3785.41)}:ml`;
  if (unit === "rollo" || unit === "rollos") return `${amount}:rollos`;
  return `${amount}:${unit}`;
}

export function comparisonKey(name: string, presentation?: string | null) {
  const normalizedName = normalizeProductName(name);
  const normalizedPack =
    normalizedPresentation(presentation ?? "") ??
    normalizedPresentation(normalizedName);
  const baseName = normalizedName
    .replace(
      /\b\d+\s*(?:pza|pack|paquete)?\s*(?:de|x)\s*\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg)\b/g,
      " ",
    )
    .replace(/\b\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg|pza|rollos?|gal)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return normalizedPack ? `${baseName}|${normalizedPack}` : baseName;
}

export function productMetaFromListing(
  name: string,
  category: string | null,
): ProductMeta {
  const normalizedName = normalizeProductName(name);
  return {
    internalName: name.trim(),
    normalizedName,
    category: category ?? "Sin categoría",
    searchTerms: [normalizedName],
  };
}
