"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  getReceipts,
  getReceiptItems,
  deleteReceipt,
} from "@/lib/receipt-storage";
import type { Receipt, ReceiptItem } from "@/lib/types";

// ---------------------------------------------------------------------------
// ユーティリティ
// ---------------------------------------------------------------------------

function formatDate(dateStr: string): string {
  const [y, m, d] = dateStr.split("-");
  return `${y}年${Number(m)}月${Number(d)}日`;
}

function formatDatetime(iso: string): string {
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// メインページ
// ---------------------------------------------------------------------------

export default function PurchasesPage() {
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [allItems, setAllItems] = useState<ReceiptItem[]>([]);
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);

  function load() {
    setReceipts(getReceipts());
    setAllItems(getReceiptItems());
  }

  useEffect(() => {
    load();
  }, []);

  function toggleExpand(id: string) {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) { next.delete(id); } else { next.add(id); }
      return next;
    });
  }

  function handleDelete(id: string) {
    deleteReceipt(id);
    setDeleteTarget(null);
    load();
  }

  // 検索フィルター（仕入れ先名 or 商品名）
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return receipts;
    return receipts.filter((r) => {
      if (r.supplier_name.toLowerCase().includes(q)) return true;
      const items = allItems.filter((i) => i.receipt_id === r.id);
      return items.some((i) => i.product_name.toLowerCase().includes(q));
    });
  }, [receipts, allItems, search]);

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
          <h1 className="text-lg font-bold text-gray-800">仕入れ履歴</h1>
          <Link
            href="/receipts"
            className="text-blue-600 font-bold text-sm"
          >
            ＋ 登録
          </Link>
        </div>
      </header>

      <main className="px-4 py-4 max-w-lg mx-auto space-y-4">
        {/* 検索 */}
        <div className="relative">
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="仕入れ先・商品名で絞り込む"
            className="w-full border-2 border-gray-200 rounded-xl pl-10 pr-4 py-3 focus:outline-none focus:border-blue-500 bg-white"
          />
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">
            🔍
          </span>
          {search && (
            <button
              type="button"
              onClick={() => setSearch("")}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 text-lg"
            >
              ×
            </button>
          )}
        </div>

        {/* 件数 */}
        <p className="text-sm text-gray-400 text-right">
          {filtered.length} 件
        </p>

        {/* リスト */}
        {filtered.length === 0 ? (
          <EmptyState hasSearch={!!search} />
        ) : (
          <div className="space-y-3">
            {filtered.map((receipt) => {
              const items = allItems.filter(
                (i) => i.receipt_id === receipt.id
              );
              const isExpanded = expanded.has(receipt.id);
              const isDeleting = deleteTarget === receipt.id;

              return (
                <div
                  key={receipt.id}
                  className="bg-white rounded-2xl shadow-sm overflow-hidden"
                >
                  {/* サマリー行 */}
                  <button
                    type="button"
                    onClick={() => toggleExpand(receipt.id)}
                    className="w-full text-left px-4 py-4"
                  >
                    <div className="flex items-start gap-3">
                      {/* サムネイル */}
                      {receipt.image_data ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={receipt.image_data}
                          alt="レシート"
                          className="w-14 h-14 rounded-lg object-cover bg-gray-100 flex-shrink-0"
                        />
                      ) : (
                        <div className="w-14 h-14 rounded-lg bg-gray-100 flex items-center justify-center text-2xl flex-shrink-0">
                          🧾
                        </div>
                      )}

                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="font-bold text-gray-800 truncate">
                            {receipt.supplier_name || "仕入れ先未入力"}
                          </p>
                          <span className="text-gray-400 text-xs flex-shrink-0">
                            {isExpanded ? "▲" : "▼"}
                          </span>
                        </div>
                        <p className="text-sm text-gray-500 mt-0.5">
                          {formatDate(receipt.purchased_at)}
                        </p>
                        <p className="text-xs text-gray-400 mt-0.5">
                          {items.length} 品目　{receipt.created_by}　{formatDatetime(receipt.created_at)}登録
                        </p>
                        {/* 商品名プレビュー（折りたたみ時） */}
                        {!isExpanded && items.length > 0 && (
                          <p className="text-xs text-gray-500 mt-1 truncate">
                            {items.map((i) => i.product_name).join("、")}
                          </p>
                        )}
                      </div>
                    </div>
                  </button>

                  {/* 展開: 明細 */}
                  {isExpanded && (
                    <div className="border-t border-gray-100 px-4 py-3 space-y-3">
                      {/* 画像（大きく表示） */}
                      {receipt.image_data && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={receipt.image_data}
                          alt="レシート"
                          className="w-full rounded-xl object-contain max-h-56 bg-gray-100"
                        />
                      )}

                      {/* 明細テーブル */}
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="text-xs text-gray-400 border-b border-gray-100">
                            <th className="text-left pb-1 font-medium">商品名</th>
                            <th className="text-right pb-1 font-medium">単価</th>
                            <th className="text-right pb-1 font-medium">数量</th>
                            <th className="text-right pb-1 font-medium">小計</th>
                          </tr>
                        </thead>
                        <tbody>
                          {items.map((item) => (
                            <tr key={item.id} className="border-b border-gray-50">
                              <td className="py-2 text-gray-800">
                                {item.product_name}
                                {item.memo && (
                                  <span className="block text-xs text-gray-400">
                                    {item.memo}
                                  </span>
                                )}
                              </td>
                              <td className="py-2 text-right text-gray-700">
                                {item.unit_price.toLocaleString()}円
                              </td>
                              <td className="py-2 text-right text-gray-700">
                                {item.quantity}
                              </td>
                              <td className="py-2 text-right font-medium text-gray-800">
                                {(item.unit_price * item.quantity).toLocaleString()}円
                              </td>
                            </tr>
                          ))}
                        </tbody>
                        <tfoot>
                          <tr>
                            <td
                              colSpan={3}
                              className="pt-2 text-xs text-gray-400 font-medium"
                            >
                              合計
                            </td>
                            <td className="pt-2 text-right font-bold text-gray-800">
                              {items
                                .reduce(
                                  (sum, i) => sum + i.unit_price * i.quantity,
                                  0
                                )
                                .toLocaleString()}
                              円
                            </td>
                          </tr>
                        </tfoot>
                      </table>

                      {/* 削除ボタン */}
                      <div className="flex justify-end pt-1">
                        {isDeleting ? (
                          <div className="flex gap-3">
                            <button
                              type="button"
                              onClick={() => setDeleteTarget(null)}
                              className="text-sm text-gray-500 px-4 py-2"
                            >
                              キャンセル
                            </button>
                            <button
                              type="button"
                              onClick={() => handleDelete(receipt.id)}
                              className="text-sm bg-red-600 text-white px-4 py-2 rounded-xl font-bold"
                            >
                              削除する
                            </button>
                          </div>
                        ) : (
                          <button
                            type="button"
                            onClick={() => setDeleteTarget(receipt.id)}
                            className="text-xs text-red-400 px-3 py-1"
                          >
                            このレシートを削除
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 空状態コンポーネント
// ---------------------------------------------------------------------------

function EmptyState({ hasSearch }: { hasSearch: boolean }) {
  return (
    <div className="text-center py-16 text-gray-400">
      <p className="text-4xl mb-3">{hasSearch ? "🔍" : "🧾"}</p>
      {hasSearch ? (
        <p>一致する仕入れ履歴が見つかりません</p>
      ) : (
        <>
          <p>まだ仕入れ履歴がありません</p>
          <Link
            href="/receipts"
            className="mt-4 inline-block bg-blue-600 text-white px-6 py-3 rounded-xl font-bold"
          >
            レシートを登録する
          </Link>
        </>
      )}
    </div>
  );
}
