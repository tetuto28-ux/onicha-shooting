# YouTube Shorts Factory

海外/国内のバズ構造を参考に、軸ジャンルのショート動画を半自動で量産するシステム。
**完全自動ではなく「人間レビュー必須」のセミ自動化**です。

---

## セットアップ手順

### 1. 依存パッケージのインストール

```bash
cd youtube-shorts-factory
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. 環境変数の設定

```bash
cp config/.env.example config/.env
# config/.env を編集して各APIキーを設定する
```

必要なAPIキー:
- **YouTube Data API v3** — トレンド収集・動画投稿
- **OpenAI API** — 企画生成(gpt-4o-mini)
- **Pexels API** — 無料CC0動画素材取得
- **VOICEVOX** — ローカルで起動しておく(`http://localhost:50021`)

### 3. ジャンル設定

`config/niche.yaml` を自分のチャンネルに合わせて編集します。

```yaml
primary: "あなたのジャンル"
audience: "ターゲット視聴者"
tone: "解説のトーン"
```

### 4. 動作確認

```bash
# フィルタのテスト
pytest tests/ -v

# トレンド収集
python -m src.crawler

# 企画生成
python -m src.ideator

# 人間レビュー
python -m src.reviewer_cli

# 制作
python -m src.producer

# 投稿(必ずprivateで投稿される)
python -m src.publisher
```

---

## ディレクトリ構成

```
youtube-shorts-factory/
├── config/
│   ├── settings.yaml              # ランタイム設定(投稿上限・間隔等)
│   ├── niche.yaml                 # ジャンル設定(ユーザーが編集)
│   ├── blocked_topics.yaml        # ブロックキーワード一覧
│   ├── reference_source_policy.yaml  # 参照元ルール定義
│   └── .env.example               # 環境変数テンプレート
├── src/
│   ├── safety_filter.py           # 安全性フィルタ(全企画が必ず通過)
│   ├── crawler.py                 # トレンド収集
│   ├── ideator.py                 # AI企画生成
│   ├── reviewer_cli.py            # 人間レビューCLI
│   ├── producer.py                # 動画制作パイプライン
│   ├── publisher.py               # YouTube投稿
│   └── analytics.py              # 分析・フィードバック
├── tests/
│   ├── test_safety_filter.py
│   ├── test_reference_check.py
│   └── test_producer.py
├── data/
│   ├── approved_queue/            # 企画JSON・承認済みJSONL
│   ├── output/                    # 生成動画・字幕・manifest
│   └── logs/                      # 投稿履歴・監査ログ
└── assets/
    └── bgm_licensed/              # ライセンス済みBGM
```

---

## 安全設計の原則

1. 全企画は `safety_filter.check_idea()` を通過すること
2. 人間承認なしで制作工程に進まないこと
3. 動画素材はCC0(Pexels等)または自家素材のみ
4. BGMはYouTube Audio Libraryまたは自家ライセンスのみ
5. 投稿は必ず `privacyStatus="private"` — 人間が最終確認後publicに切替
6. `containsSyntheticMedia=True` を全アップロードで強制
7. 1日の投稿上限と最小投稿間隔をコード側で物理的に強制
8. 元動画の内容は保存せず、抽象的な構造パターンのみDB化
9. 医療助言・投資助言・実在人物批評・センシティブ題材はブロック
10. 全中間データを残し、監査可能な状態を維持

---

## ⚠️ 海外参照コンテンツのリスクについて(必読)

### よくある誤解

> 「海外の動画を参考にすれば、言語が違うのでパクリにならない」

**これは誤りです。** 以下の理由から、海外コンテンツの参照は国内コンテンツと**同等のリスク**があります。

### 法的根拠

| リスク | 詳細 |
|--------|------|
| **ベルヌ条約** | 海外著作物は日本国内でも自動的に保護される |
| **翻訳権** | 原稿の翻訳権は原著作者に帰属(著作権法第27条) |
| **Content ID** | 映像・音声のContent IDは言語に関係なく動作する |
| **実質的類似性** | YouTubeの再利用コンテンツ判定は内容の類似性で判断する |

### 海外参照で「借用OK」な3レベルのみ

```
concept          → コンセプト・アイデア(著作権保護の対象外)
format_structure → 構造・フォーマット(3選形式、質問→答え形式等)
editing_style    → 演出スタイル(抽象レベルの編集手法)
```

### 絶対にNGな借用

```
translated_script → 原稿の直訳(翻訳権侵害)
visual_assets     → 映像素材の流用(Content ID対象)
audio_assets      → 音声・音楽の流用(Content ID対象)
exact_sequence    → 構成順序の完全コピー(再利用コンテンツ判定)
```

### 本システムの対応

- `reference_source_policy.yaml` に判定フローを定義
- `safety_filter.check_reference_safety()` が全企画に対して自動チェック
- `reviewer_cli.py` の人間レビューで参照元確認を必須化
- 海外参照・国内参照で**同一の判定基準**を適用

---

## 投稿フロー

```
トレンド収集(crawler) 
  → AI企画生成(ideator) 
  → 安全フィルタ(safety_filter) ← 自動ブロック
  → 人間レビュー(reviewer_cli)  ← 必須承認
  → 動画制作(producer) 
  → 公開前チェック(safety_filter) 
  → YouTube投稿・private(publisher) 
  → 人間が最終確認してpublicに切替
```

---

## ライセンス・免責事項

本システムは半自動化ツールです。生成されたコンテンツの法的責任はユーザーが負います。
使用前に各APIの利用規約・著作権法・YouTubeのポリシーを必ずご確認ください。
