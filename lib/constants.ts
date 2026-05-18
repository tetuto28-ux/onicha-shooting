import type { Product, Settings } from "./types";

export const DEFAULT_MANAGER_PIN =
  process.env.NEXT_PUBLIC_MANAGER_PIN ?? "1234";

export const INITIAL_PRODUCTS: Product[] = [
  {
    id: "1",
    name: "筍",
    aliases: ["たけのこ", "竹の子", "タケノコ", "たけのこ"],
    normal_price: 300,
    warning_price: 450,
    memo: "450円を超えたら店長確認",
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  },
];

export const DEFAULT_SETTINGS: Settings = {
  id: "1",
  manager_pin: DEFAULT_MANAGER_PIN,
};

export const STORAGE_KEYS = {
  PRODUCTS: "price_check_products",
  PRICE_CHECKS: "price_check_history",
  SETTINGS: "price_check_settings",
  STAFF_NAME: "price_check_staff_name",
  RECEIPTS: "price_check_receipts",
  RECEIPT_ITEMS: "price_check_receipt_items",
} as const;
