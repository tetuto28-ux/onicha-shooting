"""
OpenAI API (gpt-4o-mini) でショート動画企画を生成し、
safety_filter を通過した案のみ保存する。
"""
from __future__ import annotations

import json
import logging
import os
import re
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

from .safety_filter import SafetyFilter

logger = logging.getLogger(__name__)

_CONFIG_DIR = Path(__file__).parent.parent / "config"
_DATA_DIR   = Path(__file__).parent.parent / "data"

_SAFE_BORROW_LEVELS = {"concept", "format_structure", "editing_style"}


# ------------------------------------------------------------------
# データモデル
# ------------------------------------------------------------------
@dataclass
class IdeaRecord:
    idea_id: str
    title: str
    script_outline: str
    niche: str
    reference_source: dict
    generated_at: str
    safety_status: str        # "passed" | "blocked"
    safety_reasons: list[str] = field(default_factory=list)


# ------------------------------------------------------------------
# モック企画(APIキーなし時)
# ------------------------------------------------------------------
_MOCK_IDEAS: list[dict] = [
    {
        "title": "深海魚が光る理由5選",
        "script_outline": "冒頭で「なぜ深海魚は光るの?」と問いかけ、生物発光のメカニズムをアニメ解説。捕食・コミュニケーション・擬態の3軸で展開し、チョウチンアンコウの事例で締める。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "concept",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "完全オリジナル構成。光る理由を3軸に整理する切り口は独自。"
        }
    },
    {
        "title": "水圧1000気圧に耐える深海生物の秘密",
        "script_outline": "1000気圧のリアリティを日常比喩(象何頭分?)で体感させ、深海魚の骨格・細胞膜の適応を解説。NHK映像ではなくCG図解で展開。",
        "reference_source": {
            "source_language": "en",
            "borrow_level": "format_structure",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "海外動画の「比喩→メカニズム解説」フォーマットを借用。数値・事例・ナレーションは完全に日本語オリジナルで再構成。"
        }
    },
    {
        "title": "深海で発見された謎の生物TOP3",
        "script_outline": "ランキング形式で3位から発表。各生物について「発見の状況→外見の特徴→科学的な意義」の3ステップで30秒以内に収める。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "format_structure",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "ランキング形式は汎用フォーマット。取り上げる生物・解説内容はオリジナルリサーチ。"
        }
    },
    {
        "title": "深海1万メートルの世界を30秒で体験",
        "script_outline": "深度を時間軸に変換(1秒=1000m)し、各深度で出会う生物をテンポよく紹介。最後にマリアナ海溝底でのサプライズ事実で締める。",
        "reference_source": {
            "source_language": "ko",
            "borrow_level": "editing_style",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "韓国動画のテンポ演出スタイルを参考。深度→時間変換のアイデアと事例は完全オリジナル。"
        }
    },
    {
        "title": "深海生物が怖い本当の理由",
        "script_outline": "「見た目が怖い」ではなく「生物学的に理解不能な部分が怖い」という切り口で再定義。認知的不気味の谷の概念を噛み砕いて解説。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "concept",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "怖さを再定義する独自アプローチ。認知科学との接続もオリジナル。"
        }
    },
    {
        "title": "深海魚を食べてみたら意外すぎた",
        "script_outline": "食用深海魚(アブラボウズ・ムツ等)を紹介。「深海=食べられない」という誤解を崩す構成。栄養価データも提示。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "concept",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "日本固有の食文化・魚種に特化したオリジナル企画。"
        }
    },
    {
        "title": "深海の暗闇で進化した目の話",
        "script_outline": "光のない環境での視覚進化を3パターン(巨大化・消失・赤外線対応)に分類。最後に人間の目との比較で視聴者に「自分ごと化」させる。",
        "reference_source": {
            "source_language": "en",
            "borrow_level": "format_structure",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "3分類フレームは独自整理。英語圏の進化解説動画の「比較締め」手法をフォーマットとして参考にしたが内容は完全再構成。"
        }
    },
    {
        "title": "深海で生きる魚の1日のスケジュール",
        "script_outline": "擬人化せずにファクトベースで深海魚の行動リズムを再現。日周垂直移動という概念を中心に据え、なぜ毎日数百m移動するかを解説。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "concept",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "日周垂直移動という専門概念を一般向けに噛み砕く独自企画。"
        }
    },
    {
        "title": "深海魚の求愛方法が想像を超えていた",
        "script_outline": "チョウチンアンコウの雄が雌に融合する繁殖戦略をメインに、3種の奇妙な求愛行動を紹介。科学的正確さを保ちながらエンタメ調で展開。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "concept",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "完全オリジナル選定・構成。センシティブ表現は使わず科学的事実のみ。"
        }
    },
    {
        "title": "深海探査ロボットが撮った衝撃映像の裏側",
        "script_outline": "ROV映像そのものは使わず、「どうやって深海映像を撮るか」という技術解説に軸を置く。探査技術の進歩を年表形式で30秒に圧縮。",
        "reference_source": {
            "source_language": "none",
            "borrow_level": "format_structure",
            "sequence_identical": False,
            "is_translation": False,
            "originality_notes": "映像流用なし。技術解説×年表フォーマットは独自構成。"
        }
    },
]


# ------------------------------------------------------------------
# Ideator
# ------------------------------------------------------------------
class Ideator:
    def __init__(
        self,
        api_key: str | None = None,
        config_dir: Path | None = None,
    ) -> None:
        cfg_dir = config_dir or _CONFIG_DIR
        self._settings   = self._load_yaml(cfg_dir / "settings.yaml")
        self._niche      = self._load_yaml(cfg_dir / "niche.yaml")
        self._api_key    = api_key or os.getenv("OPENAI_API_KEY", "")
        self._mock_mode  = not bool(self._api_key)
        self._safety     = SafetyFilter(config_dir=cfg_dir)

        if self._mock_mode:
            logger.warning("OPENAI_API_KEY が未設定のためモックモードで動作します")

    @staticmethod
    def _load_yaml(path: Path) -> dict:
        with path.open(encoding="utf-8") as f:
            return yaml.safe_load(f)

    # ------------------------------------------------------------------
    # プロンプト構築
    # ------------------------------------------------------------------
    def _build_system_prompt(self) -> str:
        niche   = self._niche.get("primary", "雑学")
        tone    = self._niche.get("tone", "落ち着いた解説調")
        ng_list = "\n".join(f"  - {ng}" for ng in self._niche.get("ng", []))

        return f"""あなたはYouTubeショート動画の企画ディレクターです。
ジャンル「{niche}」について、25〜50秒の縦型ショート動画企画を生成してください。
トーン: {tone}

【絶対遵守の禁止事項】
- 誇大表現禁止(絶対/必ず/治る/儲かる/100%/確実に等)
- 著作物(アニメ・漫画・映画・ゲーム等)の二次解説禁止
- 実在人物の声・容姿模倣禁止
- 検証不能・出典不明な情報禁止
- 医療助言・投資助言・政治攻撃・センシティブ題材禁止
- NG題材: {ng_list if ng_list else "なし"}

【出力形式】
以下のJSONスキーマの配列を返してください。マークダウンや説明文は不要です。
JSONのみを返すこと。

[
  {{
    "title": "動画タイトル(30文字以内)",
    "script_outline": "構成概要(100〜200文字。冒頭フック・中盤展開・締めを含む)",
    "reference_source": {{
      "source_language": "none | en | ja | ko | zh",
      "borrow_level": "concept | format_structure | editing_style",
      "sequence_identical": false,
      "is_translation": false,
      "originality_notes": "どこをオリジナル要素として変えたかの具体的な説明(必須・空文字不可)"
    }}
  }}
]

【参照元コンテンツに関する厳格ルール】
海外または国内の既存バズ動画を参考にする場合でも:
- borrow_level は concept / format_structure / editing_style の3種のみ
- sequence_identical は必ず false(構成順序の完全コピー禁止)
- is_translation は必ず false(翻訳パクリ禁止)
- originality_notes に「どこをオリジナルとして変えたか」を必ず記載

【海外参照時の追加注意】
- 原典の具体例・固有名詞・数値をそのまま引き継がないこと
- 日本文脈・日本の事例で完全リビルドすること
- 言語が違っても翻訳は翻訳権侵害になり得る(著作権法27条)
"""

    def _build_user_prompt(self, patterns: list[dict] | None, n: int) -> str:
        niche = self._niche.get("primary", "雑学")
        pattern_hint = ""
        if patterns:
            types = list({p.get("pattern_type", "") for p in patterns[:10] if p.get("pattern_type")})
            pattern_hint = f"\n参考パターン種別(トレンドDB): {', '.join(types)}"
        return (
            f"「{niche}」について、視聴維持率が高そうなショート動画企画を{n}案生成してください。"
            f"{pattern_hint}\n"
            "バリエーションを持たせ、同じ pattern_type に偏らないようにしてください。"
        )

    # ------------------------------------------------------------------
    # スキーマバリデーション
    # ------------------------------------------------------------------
    def _validate_schema(self, raw: Any) -> tuple[bool, list[str]]:
        errors: list[str] = []
        if not isinstance(raw, dict):
            return False, ["企画がdictでない"]

        for key in ("title", "script_outline", "reference_source"):
            if not raw.get(key):
                errors.append(f"必須フィールド '{key}' が欠損または空")

        ref = raw.get("reference_source")
        if isinstance(ref, dict):
            if ref.get("sequence_identical") is not False:
                errors.append("reference_source.sequence_identical が false でない")
            if ref.get("is_translation") is not False:
                errors.append("reference_source.is_translation が false でない")
            if ref.get("borrow_level") not in _SAFE_BORROW_LEVELS:
                errors.append(
                    f"reference_source.borrow_level '{ref.get('borrow_level')}' "
                    "は concept/format_structure/editing_style のいずれかでなければならない"
                )
            if not ref.get("originality_notes"):
                errors.append("reference_source.originality_notes が空")
        else:
            errors.append("reference_source がdictでない")

        return len(errors) == 0, errors

    # ------------------------------------------------------------------
    # 生成(API / モック)
    # ------------------------------------------------------------------
    def _generate_mock(self, n: int) -> list[dict]:
        return _MOCK_IDEAS[:n]

    def _generate_api(self, n: int, patterns: list[dict] | None) -> list[dict]:
        try:
            from openai import OpenAI  # type: ignore
        except ImportError:
            logger.error("openai パッケージが未インストールです")
            return []

        client = OpenAI(api_key=self._api_key)
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system",  "content": self._build_system_prompt()},
                {"role": "user",    "content": self._build_user_prompt(patterns, n)},
            ],
            temperature=0.9,
            max_tokens=4096,
        )
        raw_text = response.choices[0].message.content or ""

        # マークダウンコードブロックを除去
        raw_text = re.sub(r"```(?:json)?\s*", "", raw_text).strip()

        try:
            ideas = json.loads(raw_text)
        except json.JSONDecodeError as e:
            logger.error("JSON解析失敗: %s\nraw: %s", e, raw_text[:200])
            return []

        if not isinstance(ideas, list):
            ideas = [ideas]
        return ideas

    def generate(self, n: int = 10, patterns: list[dict] | None = None) -> list[dict]:
        """n案生成する。OPENAI_API_KEY未設定時はモックを返す。"""
        if self._mock_mode:
            return self._generate_mock(n)
        return self._generate_api(n, patterns)

    # ------------------------------------------------------------------
    # フィルタ & 保存
    # ------------------------------------------------------------------
    def filter_and_save(self, raw_ideas: list[dict]) -> tuple[list[IdeaRecord], list[IdeaRecord]]:
        """
        スキーマ検証 → check_idea() → check_reference_safety() の順に全案を検査し、
        通過した案を data/approved_queue/ideas_*.json に保存する。

        Returns:
            (passed_records, blocked_records)
        """
        niche = self._niche.get("primary", "未設定")
        now   = datetime.now(timezone.utc).isoformat()
        passed:  list[IdeaRecord] = []
        blocked: list[IdeaRecord] = []

        for raw in raw_ideas:
            idea_id = str(uuid.uuid4())[:8]
            title   = raw.get("title", "")
            script  = raw.get("script_outline", "")
            ref     = raw.get("reference_source", {})

            # 1. スキーマバリデーション
            schema_ok, schema_errors = self._validate_schema(raw)
            if not schema_ok:
                blocked.append(IdeaRecord(
                    idea_id=idea_id, title=title, script_outline=script,
                    niche=niche, reference_source=ref,
                    generated_at=now, safety_status="blocked",
                    safety_reasons=[f"[schema] {e}" for e in schema_errors],
                ))
                logger.debug("スキーマNG: %s → %s", title, schema_errors)
                continue

            # 2. コンテンツキーワードチェック
            idea_result = self._safety.check_idea(title, script)
            if not idea_result.passed:
                blocked.append(IdeaRecord(
                    idea_id=idea_id, title=title, script_outline=script,
                    niche=niche, reference_source=ref,
                    generated_at=now, safety_status="blocked",
                    safety_reasons=[f"[keyword] {r}" for r in idea_result.reasons],
                ))
                logger.debug("キーワードNG: %s → %s", title, idea_result.reasons)
                continue

            # 3. 参照元安全チェック
            ref_result = self._safety.check_reference_safety({"reference_source": ref})
            if not ref_result.passed:
                blocked.append(IdeaRecord(
                    idea_id=idea_id, title=title, script_outline=script,
                    niche=niche, reference_source=ref,
                    generated_at=now, safety_status="blocked",
                    safety_reasons=[f"[reference] {r}" for r in ref_result.reasons],
                ))
                logger.debug("参照元NG: %s → %s", title, ref_result.reasons)
                continue

            passed.append(IdeaRecord(
                idea_id=idea_id, title=title, script_outline=script,
                niche=niche, reference_source=ref,
                generated_at=now, safety_status="passed",
            ))

        # 通過した案を保存
        if passed:
            out_dir = _DATA_DIR / "approved_queue"
            out_dir.mkdir(parents=True, exist_ok=True)
            ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            out_path = out_dir / f"ideas_{ts}.json"
            with out_path.open("w", encoding="utf-8") as f:
                json.dump([asdict(r) for r in passed], f, ensure_ascii=False, indent=2)
            logger.info("企画保存: %s (%d件)", out_path.name, len(passed))

        return passed, blocked

    # ------------------------------------------------------------------
    # メインエントリ
    # ------------------------------------------------------------------
    def run(self, n: int = 10) -> dict:
        """パターンDB参照 → 生成 → フィルタ → 保存 → サマリ返却。"""
        from .crawler import PatternDB
        patterns = [vars(r) if not isinstance(r, dict) else r
                    for r in PatternDB().load_all()]

        raw_ideas = self.generate(n=n, patterns=patterns or None)
        logger.info("生成完了: %d案", len(raw_ideas))

        passed, blocked = self.filter_and_save(raw_ideas)

        summary = {
            "mode":          "mock" if self._mock_mode else "api",
            "generated":     len(raw_ideas),
            "passed":        len(passed),
            "blocked":       len(blocked),
            "passed_titles": [r.title for r in passed],
            "blocked_titles": [
                {"title": r.title, "reasons": r.safety_reasons} for r in blocked
            ],
        }
        return summary


# ------------------------------------------------------------------
# CLI エントリポイント
# ------------------------------------------------------------------
def main() -> None:
    import argparse
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="ショート動画企画生成")
    parser.add_argument("--n", type=int, default=10, help="生成案数(デフォルト10)")
    args = parser.parse_args()

    ideator = Ideator()
    summary = ideator.run(n=args.n)

    print("\n=== 企画生成完了 ===")
    print(f"  モード   : {summary['mode']}")
    print(f"  生成数   : {summary['generated']}")
    print(f"  通過数   : {summary['passed']}")
    print(f"  ブロック : {summary['blocked']}")
    if summary["passed_titles"]:
        print("\n[通過した企画]")
        for t in summary["passed_titles"]:
            print(f"  ✓ {t}")
    if summary["blocked_titles"]:
        print("\n[ブロックされた企画]")
        for b in summary["blocked_titles"]:
            print(f"  ✗ {b['title']}")
            for r in b["reasons"]:
                print(f"      → {r}")


if __name__ == "__main__":
    main()
