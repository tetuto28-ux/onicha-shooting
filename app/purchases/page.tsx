"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  getReceipts,
  getReceiptItems,
  deleteReceipt,
} from "@/lib/receipt-storage";
import type { Receipt, ReceiptItem } from "@/lib/types";

type Tab = "list" | "monthly";

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

function monthKey(dateStr: string): string {
  const [y, m] = dateStr.split("-");
  return `${y}-${m}`;
}

function monthLabel(key: string): string {
  const [y, m] = key.split("-");
  return `${y}年${Number(m)}月`;
}

// ---------------------------------------------------------------------------
// 月次集計データ構造
// ---------------------------------------------------------------------------

interface MonthSummary {
  key: string;
  label: string;
  total: number;
  receiptCount: number;
  topItems: { name: string; amount: number }[];
}

function buildMonthlySummaries(
  receipts: Receipt[],
  allItems: ReceiptItem[]
): MonthSummary[] {
  const map = new Map<string, { total: number; receiptCount: number; itemAmounts: Map<string, number> }>();

  for (const r of receipts) {
    const key = monthKey(r.purchased_at);
    if (!map.has(key)) {
      map.set(key, { total: 0, receiptCount: 0, itemAmounts: new Map() });
    }
    const entry = map.get(key)!;
    const items = allItems.filter((i) => i.receipt_id === r.id);
    const receiptTotal = items.reduce((s, i) => s + i.unit_price * i.quantity, 0);
    entry.total += receiptTotal;
    entry.receiptCount += 1;
    for (const item of items) {
      const amt = item.unit_price * item.quantity;
      entry.itemAmounts.set(item.product_name, (entry.itemAmounts.get(item.product_name) ?? 0) + amt);
    }
  }

  return Array.from(map.entries())
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([key, val]) => ({
      key,
      label: monthLabel(key),
      total: val.total,
      receiptCount: val.receiptCount,
      topItems: Array.from(val.itemAmounts.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([name, amount]) => ({ name, amount })),
    }));
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
  const [tab, setTab] = useState<Tab>("list");

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

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return receipts;
    return receipts.filter((r) => {
      if (r.supplier_name.toLowerCase().includes(q)) return true;
      const items = allItems.filter((i) => i.receipt_id === r.id);
      return items.some((i) => i.product_name.toLowerCase().includes(q));
    });
  }, [receipts, allItems, search]);

  const monthlySummaries = useMemo(
    () => buildMonthlySummaries(receipts, allItems),
    [receipts, allItems]
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
          <h1 className="text-lg font-bold text-gray-800">仕入れ履歴</h1>
          <Link href="/receipts" className="text-blue-600 font-bold text-sm">
            ＋ 登録
          </Link>
        </div>
        {/* タブ */}
        <div className="flex border-t border-gray-100 max-w-lg mx-auto">
          {(["list", "monthly"] as Tab[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={`flex-1 py-2 text-sm font-medium transition-colors ${
                tab === t
                  ? "text-blue-600 border-b-2 border-blue-600"
                  : "text-gray-400"
              }`}
            >
              {t === "list" ? "📋 一覧" : "📊 月次集計"}
            </button>
          ))}
        </div>
      </header>

      <main className="px-4 py-4 max-w-lg mx-auto">
        {tab === "list" ? (
          <ListTab
            filtered={filtered}
            allItems={allItems}
            search={search}
            setSearch={setSearch}
            expanded={expanded}
            toggleExpand={toggleExpand}
            deleteTarget={deleteTarget}
            setDeleteTarget={setDeleteTarget}
            handleDelete={handleDelete}
          />
        ) : (
          <MonthlyTab summaries={monthlySummaries} />
        )}
      </main>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 一覧タブ
// ---------------------------------------------------------------------------

interface ListTabProps {
  filtered: Receipt[];
  allItems: ReceiptItem[];
  search: string;
  setSearch: (s: string) => void;
  expanded: Set<string>;
  toggleExpand: (id: string) => void;
  deleteTarget: string | null;
  setDeleteTarget: (id: string | null) => void;
  handleDelete: (id: string) => void;
}

function ListTab({
  filtered, allItems, search, setSearch,
  expanded, toggleExpand, deleteTarget, setDeleteTarget, handleDelete,
}: ListTabProps) {
  return (
    <div className="space-y-4">
      {/* 検索 */}
      <div className="relative">
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="仕入れ先・商品名で絞り込む"
          className="w-full border-2 border-gray-200 rounded-xl pl-10 pr-4 py-3 focus:outline-none focus:border-blue-500 bg-white"
        />
        <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">🔍</span>
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

      <p className="text-sm text-gray-400 text-right">{filtered.length} 件</p>

      {filtered.length === 0 ? (
        <EmptyState hasSearch={!!search} />
      ) : (
        <div className="space-y-3">
          {filtered.map((receipt) => {
            const items = allItems.filter((i) => i.receipt_id === receipt.id);
            const isExpanded = expanded.has(receipt.id);
            const isDeleting = deleteTarget === receipt.id;

            return (
              <div key={receipt.id} className="bg-white rounded-2xl shadow-sm overflow-hidden">
                <button
                  type="button"
                  onClick={() => toggleExpand(receipt.id)}
                  className="w-full text-left px-4 py-4"
                >
                  <div className="flex items-start gap-3">
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
                      {!isExpanded && items.length > 0 && (
                        <p className="text-xs text-gray-500 mt-1 truncate">
                          {items.map((i) => i.product_name).join("、")}
                        </p>
                      )}
                    </div>
                  </div>
                </button>

                {isExpanded && (
                  <div className="border-t border-gray-100 px-4 py-3 space-y-3">
                    {receipt.image_data && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={receipt.image_data}
                        alt="レシート"
                        className="w-full rounded-xl object-contain max-h-56 bg-gray-100"
                      />
                    )}
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
                                <span className="block text-xs text-gray-400">{item.memo}</span>
                              )}
                            </td>
                            <td className="py-2 text-right text-gray-700">
                              {item.unit_price.toLocaleString()}円
                            </td>
                            <td className="py-2 text-right text-gray-700">{item.quantity}</td>
                            <td className="py-2 text-right font-medium text-gray-800">
                              {(item.unit_price * item.quantity).toLocaleString()}円
                            </td>
                          </tr>
                        ))}
                      </tbody>
                      <tfoot>
                        <tr>
                          <td colSpan={3} className="pt-2 text-xs text-gray-400 font-medium">合計</td>
                          <td className="pt-2 text-right font-bold text-gray-800">
                            {items.reduce((s, i) => s + i.unit_price * i.quantity, 0).toLocaleString()}円
                          </td>
                        </tr>
                      </tfoot>
                    </table>
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
    </div>
  );
}

// ---------------------------------------------------------------------------
// 月次集計タブ
// ---------------------------------------------------------------------------

function MonthlyTab({ summaries }: { summaries: MonthSummary[] }) {
  if (summaries.length === 0) {
    return (
      <div className="text-center py-16 text-gray-400">
        <p className="text-4xl mb-3">📊</p>
        <p>まだ仕入れデータがありません</p>
        <Link
          href="/receipts"
          className="mt-4 inline-block bg-blue-600 text-white px-6 py-3 rounded-xl font-bold"
        >
          レシートを登録する
        </Link>
      </div>
    );
  }

  const current = summaries[0];
  const previous = summaries[1];
  const diff = previous ? current.total - previous.total : null;
  const diffPct = previous && previous.total > 0
    ? Math.round((diff! / previous.total) * 100)
    : null;

  return (
    <div className="space-y-4">
      {/* 今月サマリーカード */}
      <div className="bg-blue-600 text-white rounded-2xl p-5">
        <p className="text-sm opacity-80">{current.label}の仕入れ合計</p>
        <p className="text-4xl font-bold mt-1">
          ¥{current.total.toLocaleString()}
        </p>
        <div className="flex items-center gap-3 mt-2 text-sm opacity-80">
          <span>{current.receiptCount} 伝票</span>
          {diff !== null && diffPct !== null && (
            <span className={diff > 0 ? "text-red-200" : "text-green-200"}>
              {diff > 0 ? "▲" : "▼"} 前月比 {Math.abs(diffPct)}%
              （{diff > 0 ? "+" : ""}{diff.toLocaleString()}円）
            </span>
          )}
        </div>
      </div>

      {/* 今月のTop品目 */}
      {current.topItems.length > 0 && (
        <div className="bg-white rounded-2xl shadow-sm p-4">
          <h2 className="text-sm font-bold text-gray-600 mb-3">
            {current.label} 仕入れ上位品目
          </h2>
          <div className="space-y-2">
            {current.topItems.map((item, i) => {
              const pct = current.total > 0
                ? Math.round((item.amount / current.total) * 100)
                : 0;
              return (
                <div key={item.name}>
                  <div className="flex justify-between text-sm mb-1">
                    <span className="text-gray-700">
                      <span className="text-gray-400 mr-1">{i + 1}.</span>
                      {item.name}
                    </span>
                    <span className="font-medium text-gray-800">
                      ¥{item.amount.toLocaleString()}
                      <span className="text-xs text-gray-400 ml-1">({pct}%)</span>
                    </span>
                  </div>
                  <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-blue-500 rounded-full"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 月別一覧 */}
      <div className="space-y-3">
        {summaries.map((s, idx) => {
          const prev = summaries[idx + 1];
          const d = prev ? s.total - prev.total : null;
          const p = prev && prev.total > 0 ? Math.round((d! / prev.total) * 100) : null;
          return (
            <div key={s.key} className="bg-white rounded-2xl shadow-sm p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-bold text-gray-800">{s.label}</p>
                  <p className="text-xs text-gray-400 mt-0.5">{s.receiptCount} 伝票</p>
                </div>
                <div className="text-right">
                  <p className="text-xl font-bold text-gray-800">
                    ¥{s.total.toLocaleString()}
                  </p>
                  {d !== null && p !== null && (
                    <p className={`text-xs mt-0.5 ${d > 0 ? "text-red-500" : "text-green-600"}`}>
                      {d > 0 ? "▲" : "▼"} 前月比 {Math.abs(p)}%
                    </p>
                  )}
                </div>
              </div>
              {s.topItems.length > 0 && (
                <p className="text-xs text-gray-400 mt-2 truncate">
                  上位: {s.topItems.slice(0, 3).map((i) => i.name).join("、")}
                </p>
              )}
            </div>
          );
        })}
      </div>
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
