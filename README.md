# Roblox Studio 起動ガイド（Rojo同期・初心者向け）

このリポジトリは、Rojo を使って **GitHub上のLuauコードをRoblox Studioへ同期** し、Playテストできるようにしています。

---

## 0. まず最初に（mainを最新版にする）

1. GitHub Desktop / VS Code / ターミナルでこのリポジトリを開く。
2. `main` ブランチをチェックアウト。
3. 最新を取得（Pull）する。

例（ターミナル）:

```bash
git checkout main
git pull origin main
```

---

## 1. Rojo CLIをインストールする

Rojo公式ドキュメント: https://rojo.space/docs/

Windows向け補助スクリプトを用意しています:

- `setup_rojo_windows.ps1`
- `setup_rojo_windows.bat`

### PowerShell版（推奨）

```powershell
./setup_rojo_windows.ps1
```

### cmd版

```bat
setup_rojo_windows.bat
```

このスクリプトがやること:
- `rojo` コマンドがあるか確認
- `rojo --version` を実行
- 未インストール時は、次の手順を日本語で案内
- 最後に `rojo serve default.project.json` を起動

---

## 2. Roblox StudioにRojo Pluginを入れる

> CodexだけではPCのStudioプラグインを完全自動インストールできないため、ここは手動です。

1. Roblox Studioを開く
2. **Plugins** タブを開く
3. **Manage Plugins**（またはMarketplace）から **Rojo** をインストール

補足:
- CLI側の参考コマンドとして `rojo plugin install` があります（環境によって挙動が異なるため、まずはStudio内インストール推奨）。

---

## 3. ターミナルでRojoサーバーを起動する

リポジトリ直下で実行:

```bash
rojo serve default.project.json
```

`Serving project 'default.project.json'` のような表示が出ればOKです。

---

## 4. Roblox Studioで接続する

1. Studioでプロジェクトを開く（Baseplate等）
2. Rojoプラグインを開く
3. `localhost` のサーバーに接続
4. Explorerに `ServerScriptService` などが同期されることを確認

---

## 5. Playボタンでテストする

- Studio上部の **Play** を押して実行
- 期待動作は `TESTING_ROBLOX_STUDIO.md` のチェックリストに沿って確認

---

## 6. エラーが出たときに見る場所

### Outputウィンドウの開き方

1. Studio上部の **View** タブ
2. **Output** をクリック
3. 赤いエラー、黄色い警告を確認

### あわせて見る場所

- Explorer のスクリプト配置
- Rojoプラグインの接続状態
- ターミナルの `rojo serve` ログ

---

## 7. よくある失敗と対処法

### 失敗1: `rojo` が見つからない
- 症状: `rojo is not recognized...`
- 対処: Rojo CLIを再インストールし、PowerShell/cmdを開き直す

### 失敗2: Studio側で接続先が出ない
- 症状: Rojoプラグインにlocalhostが表示されない
- 対処:
  - ターミナルで `rojo serve default.project.json` が起動中か確認
  - ファイアウォール設定を確認

### 失敗3: スクリプトが同期されない
- 症状: Explorerにフォルダが反映されない
- 対処:
  - `default.project.json` の場所がリポジトリ直下か確認
  - `ServerScriptService`, `ReplicatedStorage`, `StarterGui` などのフォルダ名が一致しているか確認

### 失敗4: PlayするとUIや挙動が出ない
- 症状: CoinUI非表示、クリック反応なし等
- 対処:
  - `StarterGui/LocalScripts` や `ServerScriptService/Modules` の同期状況を確認
  - Outputエラーを先に潰す

---

## 8. 補足

- Rojoマッピング定義: `default.project.json`
- 初期構築向け資料: `README_MVP_SETUP.md`
- テスト手順: `TESTING_ROBLOX_STUDIO.md`
- 作業ログ: `DEVELOPMENT_LOG.md`
