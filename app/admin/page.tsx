"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getProducts, addProduct, updateProduct, deleteProduct, getSettings } from "@/lib/storage";
import type { Product } from "@/lib/types";

// ---------- PIN認証 ----------

function PinScreen({ onSuccess }: { onSuccess: () => void }) {
  const [pin, setPin] = useState("");
  const [error, setError] = useState(false);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const settings = getSettings();
    if (pin === settings.manager_pin) {
      onSuccess();
    } else {
      setError(true);
      setPin("");
    }
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 px-6">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="text-5xl mb-4">🔒</div>
          <h1 className="text-2xl font-bold text-gray-800">店長メニュー</h1>
          <p className="text-gray-500 mt-2 text-sm">PINを入力してください</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="password"
            inputMode="numeric"
            value={pin}
            onChange={(e) => { setPin(e.target.value); setError(false); }}
            placeholder="PIN"
            className={`w-full border-2 rounded-xl px-4 py-4 text-center text-3xl tracking-widest focus:outline-none ${
              error ? "border-red-400 bg-red-50" : "border-gray-300 focus:border-blue-500"
            }`}
          />
          {error && <p className="text-red-600 text-sm text-center">PINが違います</p>}
          <button
            type="submit"
            disabled={!pin}
            className="w-full bg-gray-800 text-white text-xl font-bold py-4 rounded-xl disabled:opacity-40"
          >
            入力完了
          </button>
          <Link href="/check" className="block text-center text-blue-600 text-sm py-2">
            ← 戻る
          </Link>
        </form>
      </div>
    </div>
  );
}

// ---------- 商品フォーム ----------

const EMPTY_FORM = {
  name: "",
  aliases: "",
  normal_price: "",
  warning_price: "",
  memo: "",
};

function ProductForm({
  initial,
  onSave,
  onCancel,
}: {
  initial?: Product;
  onSave: (data: Omit<Product, "id" | "created_at" | "updated_at">) => void;
  onCancel: () => void;
}) {
  const [form, setForm] = useState(
    initial
      ? {
          name: initial.name,
          aliases: initial.aliases.join(", "),
          normal_price: String(initial.normal_price),
          warning_price: String(initial.warning_price),
          memo: initial.memo,
        }
      : EMPTY_FORM
  );

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const aliases = form.aliases
      .split(/[,、，\n]/)
      .map((s) => s.trim())
      .filter(Boolean);
    onSave({
      name: form.name.trim(),
      aliases,
      normal_price: Number(form.normal_price),
      warning_price: Number(form.warning_price),
      memo: form.memo.trim(),
    });
  }

  const isValid =
    form.name.trim() &&
    Number(form.normal_price) > 0 &&
    Number(form.warning_price) > 0;

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">商品名 *</label>
        <input
          type="text"
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="例：筍"
          className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-lg focus:outline-none focus:border-blue-500"
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">表記ゆれ（カンマ区切り）</label>
        <input
          type="text"
          value={form.aliases}
          onChange={(e) => setForm({ ...form, aliases: e.target.value })}
          placeholder="例：たけのこ, 竹の子, タケノコ"
          className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 focus:outline-none focus:border-blue-500"
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">通常価格（円） *</label>
          <input
            type="number"
            inputMode="numeric"
            value={form.normal_price}
            onChange={(e) => setForm({ ...form, normal_price: e.target.value })}
            placeholder="300"
            min={0}
            className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-lg focus:outline-none focus:border-blue-500"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">注意価格（円） *</label>
          <input
            type="number"
            inputMode="numeric"
            value={form.warning_price}
            onChange={(e) => setForm({ ...form, warning_price: e.target.value })}
            placeholder="450"
            min={0}
            className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-lg focus:outline-none focus:border-blue-500"
          />
        </div>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">メモ</label>
        <input
          type="text"
          value={form.memo}
          onChange={(e) => setForm({ ...form, memo: e.target.value })}
          placeholder="例：450円を超えたら店長確認"
          className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 focus:outline-none focus:border-blue-500"
        />
      </div>
      <div className="flex gap-3 pt-2">
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 border-2 border-gray-300 text-gray-600 py-3 rounded-xl font-bold"
        >
          キャンセル
        </button>
        <button
          type="submit"
          disabled={!isValid}
          className="flex-1 bg-blue-600 text-white py-3 rounded-xl font-bold disabled:opacity-40"
        >
          保存する
        </button>
      </div>
    </form>
  );
}

// ---------- 商品管理メイン ----------

export default function AdminPage() {
  const [authed, setAuthed] = useState(false);
  const [products, setProducts] = useState<Product[]>([]);
  const [mode, setMode] = useState<"list" | "add" | "edit">("list");
  const [editTarget, setEditTarget] = useState<Product | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);

  function load() {
    setProducts(getProducts());
  }

  useEffect(() => {
    if (authed) load();
  }, [authed]);

  function handleSave(data: Omit<Product, "id" | "created_at" | "updated_at">) {
    if (mode === "add") {
      addProduct(data);
    } else if (mode === "edit" && editTarget) {
      updateProduct(editTarget.id, data);
    }
    load();
    setMode("list");
    setEditTarget(null);
  }

  function handleDelete(id: string) {
    deleteProduct(id);
    setDeleteConfirm(null);
    load();
  }

  if (!authed) return <PinScreen onSuccess={() => setAuthed(true)} />;

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow-sm sticky top-0 z-10">
        <div className="flex items-center justify-between px-4 py-3 max-w-lg mx-auto">
          <Link href="/check" className="text-blue-600 font-medium text-sm">← 戻る</Link>
          <h1 className="text-lg font-bold text-gray-800">商品管理</h1>
          <button
            onClick={() => { setMode("add"); setEditTarget(null); }}
            className="text-blue-600 font-bold text-sm"
          >
            ＋ 追加
          </button>
        </div>
      </header>

      <main className="px-4 py-4 max-w-lg mx-auto">
        {(mode === "add" || mode === "edit") ? (
          <div className="bg-white rounded-2xl p-5 shadow-sm">
            <h2 className="text-lg font-bold text-gray-800 mb-4">
              {mode === "add" ? "商品を追加" : "商品を編集"}
            </h2>
            <ProductForm
              initial={editTarget ?? undefined}
              onSave={handleSave}
              onCancel={() => { setMode("list"); setEditTarget(null); }}
            />
          </div>
        ) : (
          <div className="space-y-3">
            {products.length === 0 ? (
              <div className="text-center py-16 text-gray-400">
                <p className="text-4xl mb-3">📦</p>
                <p>商品がありません</p>
                <button
                  onClick={() => setMode("add")}
                  className="mt-4 bg-blue-600 text-white px-6 py-3 rounded-xl font-bold"
                >
                  最初の商品を追加
                </button>
              </div>
            ) : (
              products.map((p) => (
                <div key={p.id} className="bg-white rounded-xl shadow-sm p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-gray-800 text-lg">{p.name}</p>
                      {p.aliases.length > 0 && (
                        <p className="text-xs text-gray-400 mt-0.5 truncate">{p.aliases.join(" / ")}</p>
                      )}
                      <div className="flex gap-4 mt-2">
                        <span className="text-sm text-gray-600">
                          通常 <span className="font-bold text-green-700">{p.normal_price.toLocaleString()}円</span>
                        </span>
                        <span className="text-sm text-gray-600">
                          注意 <span className="font-bold text-red-700">{p.warning_price.toLocaleString()}円</span>
                        </span>
                      </div>
                      {p.memo && <p className="text-xs text-gray-400 mt-1">{p.memo}</p>}
                    </div>
                    <div className="flex flex-col gap-2">
                      <button
                        onClick={() => { setEditTarget(p); setMode("edit"); }}
                        className="text-xs bg-gray-100 text-gray-700 px-3 py-1.5 rounded-lg font-medium"
                      >
                        編集
                      </button>
                      {deleteConfirm === p.id ? (
                        <button
                          onClick={() => handleDelete(p.id)}
                          className="text-xs bg-red-600 text-white px-3 py-1.5 rounded-lg font-medium"
                        >
                          確認削除
                        </button>
                      ) : (
                        <button
                          onClick={() => setDeleteConfirm(p.id)}
                          className="text-xs bg-red-50 text-red-600 px-3 py-1.5 rounded-lg font-medium"
                        >
                          削除
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </main>
    </div>
  );
}
