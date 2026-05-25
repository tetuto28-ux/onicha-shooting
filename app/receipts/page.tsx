"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getStaffName } from "@/lib/storage";
import { saveReceiptWithItems } from "@/lib/receipt-storage";
import { compressImage } from "@/lib/image-utils";
import type { ReceiptItem } from "@/lib/types";

// ---------------------------------------------------------------------------
// 型
// ---------------------------------------------------------------------------

type ItemForm = {
  key: number; // リスト用ローカルキー
  product_name: string;
  unit_price: string;
  quantity: string;
  memo: string;
};

function emptyItem(key: number): ItemForm {
  return { key, product_name: "", unit_price: "", quantity: "1", memo: "" };
}

// ---------------------------------------------------------------------------
// メインページ
// ---------------------------------------------------------------------------

export default function ReceiptsPage() {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);

  const [staffName, setStaffName] = useState("");
  const [imageData, setImageData] = useState<string | null>(null);
  const [imageLoading, setImageLoading] = useState(false);
  const [supplierName, setSupplierName] = useState("");
  const [purchasedAt, setPurchasedAt] = useState(
    () => new Date().toISOString().slice(0, 10)
  );
  const [items, setItems] = useState<ItemForm[]>([emptyItem(0)]);
  const [nextKey, setNextKey] = useState(1);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const name = getStaffName();
    if (!name) {
      router.replace("/");
      return;
    }
    setStaffName(name);
  }, [router]);

  // ---- 画像選択 ----
  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageLoading(true);
    setError("");
    try {
      const compressed = await compressImage(file);
      setImageData(compressed);
      // --- OCR 差し替えポイント ---
      // const ocrItems = await extractItemsFromImage(compressed);
      // ocrItems で items を初期値として設定する
    } catch {
      setError("画像の読み込みに失敗しました");
    } finally {
      setImageLoading(false);
    }
  }

  // ---- 明細操作 ----
  function addItem() {
    setItems((prev) => [...prev, emptyItem(nextKey)]);
    setNextKey((k) => k + 1);
  }

  function removeItem(key: number) {
    setItems((prev) => prev.filter((i) => i.key !== key));
  }

  function updateItem(key: number, field: keyof Omit<ItemForm, "key">, value: string) {
    setItems((prev) =>
      prev.map((i) => (i.key === key ? { ...i, [field]: value } : i))
    );
  }

  // ---- 保存 ----
  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    const validItems = items.filter(
      (i) => i.product_name.trim() && Number(i.unit_price) > 0
    );
    if (validItems.length === 0) {
      setError("商品名と単価が入力された明細を 1 件以上追加してください");
      return;
    }

    setSaving(true);
    try {
      const itemsData: Omit<ReceiptItem, "id" | "receipt_id">[] = validItems.map(
        (i) => ({
          product_name: i.product_name.trim(),
          unit_price: Number(i.unit_price),
          quantity: Number(i.quantity) || 1,
          memo: i.memo.trim(),
        })
      );

      saveReceiptWithItems(
        {
          image_data: imageData,
          supplier_name: supplierName.trim(),
          purchased_at: purchasedAt,
          created_by: staffName,
        },
        itemsData
      );

      router.push("/purchases");
    } catch {
      setError("保存に失敗しました。もう一度試してください。");
      setSaving(false);
    }
  }

  const canSave = items.some(
    (i) => i.product_name.trim() && Number(i.unit_price) > 0
  );

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  return (
    <div className="min-h-screen bg-gray-50 pb-8">
      {/* ヘッダー */}
      <header className="bg-white shadow-sm sticky top-0 z-10">
        <div className="flex items-center justify-between px-4 py-3 max-w-lg mx-auto">
          <Link href="/check" className="text-blue-600 font-medium text-sm">
            ← 戻る
          </Link>
          <h1 className="text-lg font-bold text-gray-800">レシート登録</h1>
          <span className="text-sm text-gray-500">{staffName}</span>
        </div>
      </header>

      <form onSubmit={handleSave} className="px-4 py-4 max-w-lg mx-auto space-y-4">
        {/* 画像アップロード */}
        <section className="bg-white rounded-2xl p-5 shadow-sm space-y-3">
          <h2 className="font-bold text-gray-700 text-sm">レシート画像（任意）</h2>

          {imageLoading && (
            <div className="flex items-center justify-center h-36 bg-gray-50 rounded-xl">
              <span className="text-gray-400 animate-pulse">読み込み中…</span>
            </div>
          )}

          {!imageLoading && imageData && (
            <div className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={imageData}
                alt="レシートプレビュー"
                className="w-full rounded-xl object-contain max-h-64 bg-gray-100"
              />
              <button
                type="button"
                onClick={() => { setImageData(null); if (fileRef.current) fileRef.current.value = ""; }}
                className="absolute top-2 right-2 bg-black/50 text-white text-xs px-2 py-1 rounded-lg"
              >
                削除
              </button>
              {/* OCR 差し替えポイント: 将来ここに「OCRで読み取る」ボタンを追加 */}
            </div>
          )}

          {!imageLoading && !imageData && (
            <button
              type="button"
              onClick={() => fileRef.current?.click()}
              className="w-full h-36 border-2 border-dashed border-gray-300 rounded-xl flex flex-col items-center justify-center gap-2 text-gray-400 active:bg-gray-50"
            >
              <span className="text-4xl">📷</span>
              <span className="text-sm">タップして画像を選択</span>
            </button>
          )}

          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            capture="environment"
            onChange={handleFileChange}
            className="hidden"
          />

          {imageData && (
            <button
              type="button"
              onClick={() => fileRef.current?.click()}
              className="w-full text-sm text-blue-600 py-2"
            >
              画像を撮り直す
            </button>
          )}
        </section>

        {/* 基本情報 */}
        <section className="bg-white rounded-2xl p-5 shadow-sm space-y-4">
          <h2 className="font-bold text-gray-700 text-sm">基本情報</h2>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              仕入れ先
            </label>
            <input
              type="text"
              value={supplierName}
              onChange={(e) => setSupplierName(e.target.value)}
              placeholder="例：市場、○○商店"
              className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-lg focus:outline-none focus:border-blue-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              購入日
            </label>
            <input
              type="date"
              value={purchasedAt}
              onChange={(e) => setPurchasedAt(e.target.value)}
              className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-lg focus:outline-none focus:border-blue-500"
            />
          </div>
        </section>

        {/* 明細 */}
        <section className="bg-white rounded-2xl p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="font-bold text-gray-700 text-sm">明細</h2>
            <button
              type="button"
              onClick={addItem}
              className="text-blue-600 text-sm font-bold"
            >
              ＋ 追加
            </button>
          </div>

          {items.map((item, idx) => (
            <ItemRow
              key={item.key}
              item={item}
              index={idx}
              total={items.length}
              onChange={(field, val) => updateItem(item.key, field, val)}
              onRemove={() => removeItem(item.key)}
            />
          ))}
        </section>

        {error && (
          <p className="text-red-600 text-sm text-center bg-red-50 rounded-xl py-3 px-4">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={!canSave || saving}
          className="w-full bg-blue-600 text-white text-xl font-bold py-4 rounded-xl disabled:opacity-40 active:bg-blue-700 transition-colors"
        >
          {saving ? "保存中…" : "保存する"}
        </button>
      </form>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 明細行コンポーネント
// ---------------------------------------------------------------------------

function ItemRow({
  item,
  index,
  total,
  onChange,
  onRemove,
}: {
  item: ItemForm;
  index: number;
  total: number;
  onChange: (field: keyof Omit<ItemForm, "key">, value: string) => void;
  onRemove: () => void;
}) {
  return (
    <div className="border border-gray-100 rounded-xl p-4 space-y-3 bg-gray-50">
      <div className="flex items-center justify-between">
        <span className="text-xs font-bold text-gray-400">明細 {index + 1}</span>
        {total > 1 && (
          <button
            type="button"
            onClick={onRemove}
            className="text-red-400 text-xs"
          >
            削除
          </button>
        )}
      </div>

      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          商品名 *
        </label>
        <input
          type="text"
          value={item.product_name}
          onChange={(e) => onChange("product_name", e.target.value)}
          placeholder="例：筍"
          className="w-full border-2 border-gray-200 rounded-xl px-3 py-2 text-base bg-white focus:outline-none focus:border-blue-500"
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">
            単価（円） *
          </label>
          <input
            type="number"
            inputMode="numeric"
            value={item.unit_price}
            onChange={(e) => onChange("unit_price", e.target.value)}
            placeholder="0"
            min={0}
            className="w-full border-2 border-gray-200 rounded-xl px-3 py-2 text-base bg-white focus:outline-none focus:border-blue-500"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">
            数量
          </label>
          <input
            type="number"
            inputMode="numeric"
            value={item.quantity}
            onChange={(e) => onChange("quantity", e.target.value)}
            placeholder="1"
            min={1}
            className="w-full border-2 border-gray-200 rounded-xl px-3 py-2 text-base bg-white focus:outline-none focus:border-blue-500"
          />
        </div>
      </div>

      <div>
        <label className="block text-xs font-medium text-gray-600 mb-1">
          メモ
        </label>
        <input
          type="text"
          value={item.memo}
          onChange={(e) => onChange("memo", e.target.value)}
          placeholder="任意メモ"
          className="w-full border-2 border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:border-blue-500"
        />
      </div>
    </div>
  );
}
