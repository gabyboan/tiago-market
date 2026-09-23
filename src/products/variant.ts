export type ParsedVariant = {
  variantLabel: string | null;
  netQuantity: number | null;
  unit: string | null;
  packCount: number | null;
  canonicalVariantKey: string;
};

function normalize(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9.]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function numberValue(value: string): number {
  return Number(value.replace(",", "."));
}

export function parseProductVariant(productName: string): ParsedVariant {
  const normalized = normalize(productName);
  const quantityMatch = normalized.match(
    /(^|\s)(\d+(?:\.\d+)?)\s*(kg|kilo|kilos|g|gramos?|mg|l|litros?|ml|mililitros?)(?=\s|$)/,
  );
  const packMatch = normalized.match(
    /(^|\s)(\d+)\s*(pza|pzas|pieza|piezas|rollo|rollos|pack|paquete|paquetes)(?=\s|$)/,
  );

  const unit = quantityMatch?.[3]
    ? {
        kilo: "kg",
        kilos: "kg",
        kg: "kg",
        g: "g",
        gramos: "g",
        mg: "mg",
        l: "l",
        litro: "l",
        litros: "l",
        ml: "ml",
        mililitro: "ml",
        mililitros: "ml",
      }[quantityMatch[3]] ?? null
    : null;
  const netQuantity = quantityMatch?.[2]
    ? numberValue(quantityMatch[2])
    : null;
  const packCount = packMatch?.[2] ? Number(packMatch[2]) : null;
  const variantLabel = normalized
    .replace(quantityMatch?.[0] ?? "", " ")
    .replace(packMatch?.[0] ?? "", " ")
    .replace(/\s+/g, " ")
    .trim();

  const canonicalVariantKey = [
    variantLabel || normalized,
    netQuantity === null || unit === null
      ? null
      : `qty=${netQuantity}${unit}`,
    packCount === null ? null : `pack=${packCount}`,
  ]
    .filter((part): part is string => part !== null)
    .join("|");

  return {
    variantLabel: variantLabel || null,
    netQuantity,
    unit,
    packCount,
    canonicalVariantKey,
  };
}