"use client";

import type { Receipt, ReceiptItem } from "./types";
import { STORAGE_KEYS } from "./constants";

// ---------------------------------------------------------------------------
// OCR 差し替えポイント
// ---------------------------------------------------------------------------
// OCR を実装するときは、この関数を差し替えるだけでよい。
// 例: Google Cloud Vision API、Tesseract.js など。
//
// 引数: imageData — base64 JPEG 文字列（または Supabase Storage の公開 URL）
// 戻り値: OCR で読み取った明細の配列（部分的でもよい）
// ---------------------------------------------------------------------------
export async function extractItemsFromImage(
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _imageData: string
): Promise<Partial<ReceiptItem>[]> {
  // TODO: OCR 実装に差し替える
  return [];
}

// ---------------------------------------------------------------------------
// localStorage ヘルパー
// ---------------------------------------------------------------------------

function loadJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function saveJson<T>(key: string, value: T): void {
  if (typeof window === "undefined") return;
  localStorage.setItem(key, JSON.stringify(value));
}

// ---------------------------------------------------------------------------
// Receipts
// ---------------------------------------------------------------------------

export function getReceipts(): Receipt[] {
  return loadJson<Receipt[]>(STORAGE_KEYS.RECEIPTS, []);
}

export function addReceipt(
  data: Omit<Receipt, "id" | "created_at">
): Receipt {
  const receipts = getReceipts();
  const newReceipt: Receipt = {
    ...data,
    id: crypto.randomUUID(),
    created_at: new Date().toISOString(),
  };
  // 最新 500 件のみ保持
  saveJson(STORAGE_KEYS.RECEIPTS, [newReceipt, ...receipts].slice(0, 500));
  return newReceipt;
}

export function deleteReceipt(id: string): void {
  saveJson(
    STORAGE_KEYS.RECEIPTS,
    getReceipts().filter((r) => r.id !== id)
  );
  // 関連明細も削除
  saveJson(
    STORAGE_KEYS.RECEIPT_ITEMS,
    getReceiptItems().filter((item) => item.receipt_id !== id)
  );
}

// ---------------------------------------------------------------------------
// ReceiptItems
// ---------------------------------------------------------------------------

export function getReceiptItems(): ReceiptItem[] {
  return loadJson<ReceiptItem[]>(STORAGE_KEYS.RECEIPT_ITEMS, []);
}

export function getItemsByReceiptId(receiptId: string): ReceiptItem[] {
  return getReceiptItems().filter((item) => item.receipt_id === receiptId);
}

export function addReceiptItems(
  items: Omit<ReceiptItem, "id">[]
): ReceiptItem[] {
  const existing = getReceiptItems();
  const newItems: ReceiptItem[] = items.map((item) => ({
    ...item,
    id: crypto.randomUUID(),
  }));
  saveJson(STORAGE_KEYS.RECEIPT_ITEMS, [...existing, ...newItems]);
  return newItems;
}

/** レシートと明細をまとめて保存して ID を返す */
export function saveReceiptWithItems(
  receiptData: Omit<Receipt, "id" | "created_at">,
  itemsData: Omit<ReceiptItem, "id" | "receipt_id">[]
): Receipt {
  const receipt = addReceipt(receiptData);
  addReceiptItems(
    itemsData.map((item) => ({ ...item, receipt_id: receipt.id }))
  );
  return receipt;
}
