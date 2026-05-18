"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getStaffName, saveStaffName } from "@/lib/storage";

export default function StaffPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    const saved = getStaffName();
    if (saved) {
      setName(saved);
    }
    setLoaded(true);
  }, []);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    saveStaffName(trimmed);
    router.push("/check");
  }

  if (!loaded) return null;

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-b from-blue-50 to-white px-6">
      <div className="w-full max-w-sm">
        <div className="text-center mb-10">
          <div className="text-5xl mb-4">🛒</div>
          <h1 className="text-2xl font-bold text-gray-800">仕入れ価格チェック</h1>
          <p className="text-gray-500 mt-2 text-sm">あなたの名前を入力してください</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              スタッフ名
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="例：山田"
              autoFocus
              className="w-full border-2 border-gray-300 rounded-xl px-4 py-4 text-xl focus:outline-none focus:border-blue-500 bg-white"
            />
          </div>

          <button
            type="submit"
            disabled={!name.trim()}
            className="w-full bg-blue-600 text-white text-xl font-bold py-4 rounded-xl disabled:opacity-40 active:bg-blue-700 transition-colors"
          >
            はじめる
          </button>
        </form>
      </div>
    </div>
  );
}
