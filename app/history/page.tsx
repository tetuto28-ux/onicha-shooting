"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getPriceChecks } from "@/lib/storage";
import type { PriceCheck } from "@/lib/types";

const RESULT_LABEL: Record<string, { label: string; bg: string; text: string }> = {
  ok: { label: "OK", bg: "bg-green-100", text: "text-green-700" },
  warning: { label: "要確認", bg: "bg-red-100", text: "text-red-700" },
  unregistered: { label: "未登録", bg: "bg-gray-100", text: "text-gray-600" },
};

function formatDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export default function HistoryPage() {
  const [checks, setChecks] = useState<PriceCheck[]>([]);
  const [filter, setFilter] = useState<"all" | "ok" | "warning" | "unregistered">("all");

  useEffect(() => {
    setChecks(getPriceChecks());
  }, []);

  const filtered = filter === "all" ? checks : checks.filter((c) => c.result === filter);

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow-sm sticky top-0 z-10">
        <div className="flex items-center justify-between px-4 py-3 max-w-lg mx-auto">
          <Link href="/check" className="text-blue-600 font-medium text-sm">← 戻る</Link>
          <h1 className="text-lg font-bold text-gray-800">チェック履歴</h1>
          <span className="text-sm text-gray-400">{filtered.length}件</span>
        </div>
      </header>

      <main className="px-4 py-4 max-w-lg mx-auto space-y-4">
        {/* フィルター */}
        <div className="flex gap-2 overflow-x-auto pb-1">
          {(["all", "ok", "warning", "unregistered"] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`flex-shrink-0 px-4 py-2 rounded-full text-sm font-medium transition-colors ${
                filter === f
                  ? "bg-blue-600 text-white"
                  : "bg-white text-gray-600 shadow-sm"
              }`}
            >
              {f === "all" ? "すべて" : f === "ok" ? "✅ OK" : f === "warning" ? "⚠️ 要確認" : "❓ 未登録"}
            </button>
          ))}
        </div>

        {/* リスト */}
        {filtered.length === 0 ? (
          <div className="text-center py-16 text-gray-400">
            <p className="text-4xl mb-3">📋</p>
            <p>履歴がありません</p>
          </div>
        ) : (
          <div className="space-y-3">
            {filtered.map((check) => {
              const style = RESULT_LABEL[check.result];
              return (
                <div key={check.id} className="bg-white rounded-xl shadow-sm p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${style.bg} ${style.text}`}>
                          {style.label}
                        </span>
                        <span className="text-xs text-gray-400">{formatDate(check.created_at)}</span>
                      </div>
                      <p className="font-bold text-gray-800 text-lg truncate">{check.input_name}</p>
                      <p className="text-gray-600 text-sm">
                        {check.input_price.toLocaleString()}円
                        {check.normal_price_at_check !== null && (
                          <span className="text-gray-400 ml-2">（通常: {check.normal_price_at_check.toLocaleString()}円）</span>
                        )}
                      </p>
                    </div>
                    <span className="text-xs text-gray-400 flex-shrink-0">{check.staff_name}</span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}
