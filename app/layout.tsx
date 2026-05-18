import type { Metadata, Viewport } from "next";
import "./globals.css";
import PWAInstaller from "@/app/components/PWAInstaller";

export const metadata: Metadata = {
  title: "仕入れ価格チェック",
  description: "飲食店向け仕入れ価格チェックアプリ",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "価格チェック",
  },
  icons: {
    apple: "/apple-touch-icon.png",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#2563eb",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ja">
      <body className="bg-gray-50 min-h-screen">
        {children}
        <PWAInstaller />
      </body>
    </html>
  );
}
