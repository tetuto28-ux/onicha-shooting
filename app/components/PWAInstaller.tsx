"use client";

import { useEffect, useState } from "react";

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

export default function PWAInstaller() {
  const [installEvent, setInstallEvent] = useState<BeforeInstallPromptEvent | null>(null);
  const [isIOS, setIsIOS] = useState(false);
  const [showIOSGuide, setShowIOSGuide] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Service Worker 登録
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }

    // iOS判定（スタンドアロンでない場合のみガイド表示）
    const ios =
      /iphone|ipad|ipod/i.test(navigator.userAgent) &&
      !("standalone" in navigator && (navigator as { standalone?: boolean }).standalone);
    setIsIOS(ios);

    // Chrome/Android インストールイベント
    const handler = (e: Event) => {
      e.preventDefault();
      setInstallEvent(e as BeforeInstallPromptEvent);
    };
    window.addEventListener("beforeinstallprompt", handler);

    // dismissed状態をsessionStorageで管理
    setDismissed(sessionStorage.getItem("pwa-dismissed") === "1");

    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, []);

  function dismiss() {
    sessionStorage.setItem("pwa-dismissed", "1");
    setDismissed(true);
    setInstallEvent(null);
    setShowIOSGuide(false);
  }

  async function handleInstall() {
    if (!installEvent) return;
    await installEvent.prompt();
    const { outcome } = await installEvent.userChoice;
    if (outcome === "accepted") setInstallEvent(null);
  }

  if (dismissed) return null;

  // Android/Chrome: ネイティブインストールプロンプト
  if (installEvent) {
    return (
      <div className="fixed bottom-0 left-0 right-0 z-50 p-4">
        <div className="bg-blue-600 text-white rounded-2xl p-4 shadow-xl max-w-lg mx-auto flex items-center gap-3">
          <span className="text-2xl">📱</span>
          <div className="flex-1 min-w-0">
            <p className="font-bold text-sm">ホーム画面に追加</p>
            <p className="text-xs text-blue-100">アプリとして使えるようになります</p>
          </div>
          <div className="flex gap-2 flex-shrink-0">
            <button onClick={dismiss} className="text-blue-200 text-sm px-2">あとで</button>
            <button
              onClick={handleInstall}
              className="bg-white text-blue-600 font-bold text-sm px-4 py-2 rounded-xl"
            >
              追加
            </button>
          </div>
        </div>
      </div>
    );
  }

  // iOS Safari: 手動手順ガイド
  if (isIOS && !showIOSGuide) {
    return (
      <div className="fixed bottom-0 left-0 right-0 z-50 p-4">
        <div className="bg-gray-800 text-white rounded-2xl p-4 shadow-xl max-w-lg mx-auto flex items-center gap-3">
          <span className="text-2xl">📱</span>
          <div className="flex-1 min-w-0">
            <p className="font-bold text-sm">ホーム画面に追加できます</p>
            <p className="text-xs text-gray-300">iPhoneでアプリとして使う</p>
          </div>
          <div className="flex gap-2 flex-shrink-0">
            <button onClick={dismiss} className="text-gray-400 text-sm px-2">×</button>
            <button
              onClick={() => setShowIOSGuide(true)}
              className="bg-blue-500 text-white font-bold text-sm px-3 py-2 rounded-xl"
            >
              方法を見る
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (isIOS && showIOSGuide) {
    return (
      <div className="fixed inset-0 z-50 bg-black/60 flex items-end">
        <div className="bg-white rounded-t-3xl p-6 w-full max-w-lg mx-auto space-y-4">
          <h2 className="text-xl font-bold text-gray-800 text-center">
            📱 ホーム画面に追加する方法
          </h2>
          <ol className="space-y-3 text-gray-700">
            <li className="flex gap-3 items-start">
              <span className="bg-blue-600 text-white rounded-full w-7 h-7 flex items-center justify-center font-bold flex-shrink-0">1</span>
              <div>
                <p className="font-medium">Safari下部の「共有」ボタンをタップ</p>
                <p className="text-sm text-gray-500">□↑ このマークです</p>
              </div>
            </li>
            <li className="flex gap-3 items-start">
              <span className="bg-blue-600 text-white rounded-full w-7 h-7 flex items-center justify-center font-bold flex-shrink-0">2</span>
              <div>
                <p className="font-medium">「ホーム画面に追加」を選ぶ</p>
                <p className="text-sm text-gray-500">スクロールすると見つかります</p>
              </div>
            </li>
            <li className="flex gap-3 items-start">
              <span className="bg-blue-600 text-white rounded-full w-7 h-7 flex items-center justify-center font-bold flex-shrink-0">3</span>
              <div>
                <p className="font-medium">「追加」をタップして完了</p>
              </div>
            </li>
          </ol>
          <button
            onClick={dismiss}
            className="w-full bg-gray-100 text-gray-700 font-bold py-3 rounded-xl"
          >
            閉じる
          </button>
        </div>
      </div>
    );
  }

  return null;
}
