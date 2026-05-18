"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getStaffName } from "@/lib/storage";
import { getProducts, addPriceCheck } from "@/lib/storage";
import { findProduct } from "@/lib/normalize";
import type { CheckResult, Product } from "@/lib/types";

interface ResultState {
  result: CheckResult;
  product: Product | null;
  inputName: string;
  inputPrice: number;
}

export default function CheckPage() {
  const router = useRouter();
  const [staffName, setStaffName] = useState("");
  const [inputName, setInputName] = useState("");
  const [inputPrice, setInputPrice] = useState("");
  const [resultState, setResultState] = useState<ResultState | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const name = getStaffName();
    if (!name) {
      router.replace("/");
      return;
    }
    setStaffName(name);
  }, [router]);

  function handleCheck(e: React.FormEvent) {
    e.preventDefault();
    const price = Number(inputPrice);
    if (!inputName.trim() || !price) return;

    setLoading(true);

    const products = getProducts();
    const product = findProduct(inputName.trim(), products);

    let result: CheckResult;
    if (!product) {
      result = "unregistered";
    } else if (price <= product.warning_price) {
      result = "ok";
    } else {
      result = "warning";
    }

    addPriceCheck({
      product_id: product?.id ?? null,
      input_name: inputName.trim(),
      input_price: price,
      normal_price_at_check: product?.normal_price ?? null,
      warning_price_at_check: product?.warning_price ?? null,
      result,
      staff_name: staffName,
      note: "",
    });

    setResultState({ result, product, inputName: inputName.trim(), inputPrice: price });
    setLoading(false);
  }

  function handleReset() {
    setInputName("");
    setInputPrice("");
    setResultState(null);
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* ヘッダー */}
      <header className="bg-white shadow-sm sticky top-0 z-10">
        <div className="flex items-center justify-between px-4 py-3 max-w-lg mx-auto">
          <h1 className="text-lg font-bold text-gray-800">価格チェック</h1>
          <span className="text-sm text-gray-500">{staffName}</span>
        </div>
      </header>

      <main className="px-4 py-6 max-w-lg mx-auto space-y-4">
        {/* 入力フォーム */}
        <form onSubmit={handleCheck} className="bg-white rounded-2xl p-5 shadow-sm space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              商品名
            </label>
            <input
              type="text"
              value={inputName}
              onChange={(e) => setInputName(e.target.value)}
              placeholder="例：筍、たけのこ"
              className="w-full border-2 border-gray-200 rounded-xl px-4 py-4 text-xl focus:outline-none focus:border-blue-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              現在の価格（円）
            </label>
            <input
              type="number"
              inputMode="numeric"
              value={inputPrice}
              onChange={(e) => setInputPrice(e.target.value)}
              placeholder="例：700"
              min={0}
              className="w-full border-2 border-gray-200 rounded-xl px-4 py-4 text-2xl font-bold focus:outline-none focus:border-blue-500"
            />
          </div>

          <button
            type="submit"
            disabled={!inputName.trim() || !inputPrice || loading}
            className="w-full bg-blue-600 text-white text-xl font-bold py-4 rounded-xl disabled:opacity-40 active:bg-blue-700 transition-colors"
          >
            チェックする
          </button>
        </form>

        {/* 結果表示 */}
        {resultState && (
          <ResultCard state={resultState} onReset={handleReset} />
        )}

        {/* ナビゲーション */}
        <nav className="grid grid-cols-3 gap-3 pt-2">
          <Link
            href="/history"
            className="bg-white rounded-xl p-3 shadow-sm text-center text-sm font-medium text-gray-600 active:bg-gray-100"
          >
            📋 履歴
          </Link>
          <Link
            href="/admin"
            className="bg-white rounded-xl p-3 shadow-sm text-center text-sm font-medium text-gray-600 active:bg-gray-100"
          >
            🔒 商品管理
          </Link>
          <Link
            href="/"
            className="bg-white rounded-xl p-3 shadow-sm text-center text-sm font-medium text-gray-600 active:bg-gray-100"
          >
            👤 名前変更
          </Link>
        </nav>
      </main>
    </div>
  );
}

function ResultCard({ state, onReset }: { state: ResultState; onReset: () => void }) {
  const { result, product, inputName, inputPrice } = state;

  if (result === "unregistered") {
    return (
      <div className="bg-gray-100 border-2 border-gray-400 rounded-2xl p-6 space-y-3">
        <div className="text-4xl text-center">❓</div>
        <p className="text-2xl font-bold text-center text-gray-700">商品が登録されていません</p>
        <p className="text-center text-gray-600">「{inputName}」は未登録です</p>
        <p className="text-center text-gray-600 font-bold">店長に確認してください</p>
        <button onClick={onReset} className="w-full mt-4 bg-gray-600 text-white py-3 rounded-xl font-bold text-lg active:bg-gray-700">
          もう一度チェック
        </button>
      </div>
    );
  }

  if (result === "ok") {
    return (
      <div className="bg-green-50 border-2 border-green-400 rounded-2xl p-6 space-y-3">
        <div className="text-4xl text-center">✅</div>
        <p className="text-3xl font-bold text-center text-green-700">OKです</p>
        <p className="text-center text-gray-700">
          {product!.name}の通常価格は約<span className="font-bold">{product!.normal_price.toLocaleString()}円</span>です
        </p>
        <p className="text-center text-gray-700">
          今回の価格は<span className="font-bold text-lg">{inputPrice.toLocaleString()}円</span>です
        </p>
        <button onClick={onReset} className="w-full mt-4 bg-green-600 text-white py-3 rounded-xl font-bold text-lg active:bg-green-700">
          次の商品をチェック
        </button>
      </div>
    );
  }

  const ratio = (inputPrice / product!.normal_price).toFixed(1);
  return (
    <div className="bg-red-50 border-2 border-red-400 rounded-2xl p-6 space-y-3">
      <div className="text-4xl text-center">⚠️</div>
      <p className="text-3xl font-bold text-center text-red-700">高いです</p>
      <p className="text-center text-gray-700">
        {product!.name}の通常価格は約<span className="font-bold">{product!.normal_price.toLocaleString()}円</span>です
      </p>
      <p className="text-center text-gray-700">
        今回の<span className="font-bold text-lg text-red-600">{inputPrice.toLocaleString()}円</span>は通常価格の約<span className="font-bold text-red-600">{ratio}倍</span>です
      </p>
      <p className="text-center text-red-700 font-bold text-lg">購入前に店長確認してください</p>
      <button onClick={onReset} className="w-full mt-4 bg-red-600 text-white py-3 rounded-xl font-bold text-lg active:bg-red-700">
        次の商品をチェック
      </button>
    </div>
  );
}
