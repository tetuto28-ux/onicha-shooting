# 仕入れ価格チェックアプリ

飲食店スタッフがスマホで仕入れ価格を素早くチェックできるWebアプリです。

## 機能

- **価格チェック** - 商品名と現在価格を入力すると OK / 要確認 / 未登録を即判定
- **表記ゆれ対応** - 「たけのこ」「タケノコ」「竹の子」などを同一商品として認識
- **チェック履歴** - いつ・誰が・いくらでチェックしたか記録
- **商品管理** - 商品の追加・編集・削除（PIN保護）
- **オフライン動作** - localStorage でデータ保存（インターネット不要）

## デフォルトPIN

```
1234
```

> **重要**: 本番環境では必ず PIN を変更してください。
> `.env.local` に `NEXT_PUBLIC_MANAGER_PIN=あなたのPIN` を設定してください。

## ローカル起動方法

```bash
# リポジトリをクローン
git clone https://github.com/tetuto28-ux/onicha-shooting.git
cd onicha-shooting

# 環境変数ファイルを作成
cp .env.local.example .env.local
# .env.local を編集してPINを変更

# パッケージインストール
npm install

# 開発サーバー起動
npm run dev
```

ブラウザで http://localhost:3000 を開きます。

## スマホで確認する方法

開発サーバーを起動したら、PCとスマホを同じWi-Fiに接続し、PCのIPアドレスでアクセスします。

```bash
# PCのIPアドレスを確認
ip addr show  # Linux
ipconfig      # Windows
ifconfig      # Mac

# スマホのブラウザで以下にアクセス
http://192.168.x.x:3000
```

## Vercelデプロイ方法

1. [Vercel](https://vercel.com) にログイン
2. 「New Project」でこのリポジトリをインポート
3. Environment Variables に以下を設定:
   - `NEXT_PUBLIC_MANAGER_PIN` = あなたのPIN
4. Deploy

## Supabaseへの移行

現在はlocalStorageで動作しますが、Supabaseに移行することでデータをクラウド保存できます。

### 1. Supabaseプロジェクト作成

[supabase.com](https://supabase.com) でプロジェクトを作成します。

### 2. SQLを実行

`supabase/schema.sql` の内容を Supabase の SQL Editor で実行します。

### 3. 環境変数を設定

`.env.local` に追加:

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

### 4. lib/storage.ts を差し替え

`lib/storage.ts` の各関数をSupabaseクライアントを使うよう書き換えます。
データアクセス層が分離されているため、関数のシグネチャを維持すれば他のコードは変更不要です。

## 判定ルール

| 条件 | 結果 |
|------|------|
| 入力価格 ≤ 注意価格 | ✅ OK |
| 入力価格 > 注意価格 | ⚠️ 要確認（店長確認） |
| 商品未登録 | ❓ 未登録（店長確認） |

## 今後追加予定の機能

- [ ] **PWA対応** - ホーム画面に追加してアプリのように使う
- [ ] **レシート画像アップロード** - カメラで撮影してそのまま入力
- [ ] **OCR** - 画像から商品名・価格を自動読み取り
- [ ] **LINE通知** - 要確認時に店長のLINEに通知
- [ ] **店長承認フロー** - 要確認商品に店長が承認/却下を記録
- [ ] **複数店舗対応** - 店舗ごとにデータを分けて管理
- [ ] **グラフ表示** - 価格推移をグラフで確認

## 技術スタック

- [Next.js 15](https://nextjs.org/) - Reactフレームワーク
- [TypeScript](https://www.typescriptlang.org/) - 型安全
- [Tailwind CSS](https://tailwindcss.com/) - スタイリング
- データ保存: localStorage（→ Supabase移行可能）
- デプロイ: Vercel推奨
