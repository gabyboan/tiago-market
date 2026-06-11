export type ProductMeta = {
  internalName: string;
  normalizedName: string;
  category: string;
  searchTerms: string[];
};

export const productsTest: ProductMeta[] = [
  {
    internalName: "Coca Cola 600 ml",
    normalizedName: "coca cola 600 ml",
    category: "Bebidas",
    searchTerms: ["coca cola 600 ml"],
  },
  {
    internalName: "Leche entera 1L",
    normalizedName: "leche entera 1 l",
    category: "Lácteos",
    searchTerms: ["leche entera 1 litro"],
  },
  {
    internalName: "Arroz 1 kg",
    normalizedName: "arroz 1 kg",
    category: "Despensa",
    searchTerms: ["arroz 1 kg"],
  },
  {
    internalName: "Azúcar 1 kg",
    normalizedName: "azucar 1 kg",
    category: "Despensa",
    searchTerms: ["azucar 1 kg"],
  },
  {
    internalName: "Aceite vegetal 1L",
    normalizedName: "aceite vegetal 1 l",
    category: "Despensa",
    searchTerms: ["aceite vegetal 1 litro"],
  },
  {
    internalName: "Huevo blanco 12 piezas",
    normalizedName: "huevo blanco 12 piezas",
    category: "Frescos",
    searchTerms: ["huevo blanco 12 piezas"],
  },
  {
    internalName: "Pan blanco de caja",
    normalizedName: "pan blanco de caja",
    category: "Panadería",
    searchTerms: ["pan blanco de caja"],
  },
  {
    internalName: "Detergente líquido 1L",
    normalizedName: "detergente liquido 1 l",
    category: "Limpieza",
    searchTerms: ["detergente liquido 1 litro"],
  },
  {
    internalName: "Papel higiénico 4 rollos",
    normalizedName: "papel higienico 4 rollos",
    category: "Higiene",
    searchTerms: ["papel higienico 4 rollos"],
  },
  {
    internalName: "Café soluble 100g",
    normalizedName: "cafe soluble 100 g",
    category: "Despensa",
    searchTerms: ["cafe soluble 100 g"],
  },
];
