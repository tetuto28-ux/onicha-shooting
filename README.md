# Onicha Shooting (Roblox + Rojo)

このリポジトリは **RojoでRoblox Studioに同期してテスト** できる構成です。

## 前提ツール
- Roblox Studio
- Rojo CLI (v7系推奨)
- Roblox Studio用 Rojo プラグイン

## 1. Rojo CLI をインストール

macOS (Homebrew):
```bash
brew install rojo-rbx/tap/rojo
```

Windows (Scoop):
```powershell
scoop bucket add rojo-rbx https://github.com/rojo-rbx/scoop-bucket.git
scoop install rojo
```

インストール確認:
```bash
rojo --version
```

## 2. Roblox Studio プラグインを導入
1. Roblox Studioを起動
2. Marketplace / Toolbox の Plugins で `Rojo` を検索
3. **Rojo (公式プラグイン)** をインストール
4. Studio再起動後、`Plugins` タブに Rojo が表示されることを確認

## 3. プロジェクト構成（Rojoマッピング）
`default.project.json` により以下をDataModelへ同期します。
- `ServerScriptService/` → `game.ServerScriptService`
- `ReplicatedStorage/` → `game.ReplicatedStorage`
- `StarterGui/` → `game.StarterGui`
- `Workspace/` → `game.Workspace`
- `ServerStorage/` → `game.ServerStorage`

## 4. 起動手順（はじめてでもOK）
1. このリポジトリを開く
2. ターミナルで以下を実行
```bash
rojo serve
```
3. Roblox Studioで空のBaseplateを開く
4. `Plugins` → `Rojo` → `Connect`
5. `localhost:34872`（デフォルト）へ接続
6. Explorerにスクリプトが同期されたら `Play` を押す

## 5. テストの進め方（MVP）
Play後、最低限以下を確認できます。

- ロビー/テスト部屋
  - `Workspace/MVPTestRig.server.lua` が `Rooms/Room001..005` と違和感Partを自動生成
- UI
  - `StarterGui/MainUI` から Coin/Room/Message/Found 表示
- クリック判定
  - 違和感Partをクリックするとサーバーへ通知
- コイン処理
  - 発見時に加算、レア違和感で追加報酬

## 6. 既存コードと配置パス整合性
- `ServerMain.lua` は `ServerScriptService` 直下前提で `script.Modules.*` を require
- クライアント側は `PlayerGui/MainUI` 前提
- 共有データは `ReplicatedStorage/SharedModules` 前提

このため、現在のフォルダ配置はRojoマッピングと整合しています。

## 7. よくある詰まりポイント
- Rojoで接続できない: `rojo serve` が起動しているか確認
- UIが出ない: Explorer で `StarterGui > MainUI` が同期されているか確認
- クリック反応しない: 対象Partの属性 `IsAnomaly=true`, `RoomId`, `AnomalyName` を確認
