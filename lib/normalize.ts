import type { Product } from "./types";

function normalizeText(text: string): string {
  return text
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "")
    // 全角英数字 → 半角
    .replace(/[Ａ-Ｚａ-ｚ０-９]/g, (c) =>
      String.fromCharCode(c.charCodeAt(0) - 0xfee0)
    )
    // カタカナ → ひらがな
    .replace(/[ァ-ヶ]/g, (c) =>
      String.fromCharCode(c.charCodeAt(0) - 0x60)
    );
}

export function findProduct(
  inputName: string,
  products: Product[]
): Product | null {
  const normalized = normalizeText(inputName);

  for (const product of products) {
    if (normalizeText(product.name) === normalized) return product;
    for (const alias of product.aliases) {
      if (normalizeText(alias) === normalized) return product;
    }
  }
  return null;
}
