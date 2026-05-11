"""
YouTube トレンド動画から「構造パターン」だけを抽出して保存する。
元動画のID・タイトル原文・説明文は一切保存しない。
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

import yaml

logger = logging.getLogger(__name__)

_CONFIG_DIR = Path(__file__).parent.parent / "config"
_DATA_DIR = Path(__file__).parent.parent / "data"

# ------------------------------------------------------------------
# パターン種別と分類キーワード(言語別)
# ------------------------------------------------------------------
_KEYWORDS: dict[str, dict[str, list[str]]] = {
    "ja": {
        "ranking":       [r"\d+位", r"\d+選", r"ランキング", r"top\s*\d+"],
        "curiosity_hook":[r"なぜ", r"なぜ?", r"知ってた", r"衝撃", r"驚き"],
        "how_to":        [r"やり方", r"方法", r"手順", r"コツ", r"テクニック"],
        "experiment":    [r"試してみた", r"やってみた", r"検証", r"実験"],
        "fact_reveal":   [r"実は", r"本当は", r"真相", r"事実"],
        "comparison":    [r"\bvs\b", r"比較", r"どっちが", r"違い"],
        "mystery":       [r"都市伝説", r"謎", r"不思議"],
        "list_format":   [r"\d+つ", r"\d+個"],
    },
    "en": {
        "ranking":       [r"top\s*\d+", r"ranking", r"best\s+\d+", r"worst\s+\d+"],
        "curiosity_hook":[r"\bwhy\b", r"did you know", r"shocking", r"amazing", r"secret"],
        "how_to":        [r"how to", r"tutorial", r"\btips\b", r"tricks"],
        "experiment":    [r"i tried", r"\btested\b", r"experiment", r"challenge"],
        "fact_reveal":   [r"the truth", r"\bactually\b", r"revealed", r"exposed"],
        "comparison":    [r"\bvs\b", r"versus", r"comparison", r"which is better"],
        "mystery":       [r"mystery", r"unsolved", r"hidden"],
        "list_format":   [r"\d+\s+things", r"\d+\s+ways", r"\d+\s+reasons"],
    },
    "ko": {
        "ranking":       [r"\d+위", r"\d+선", r"순위", r"top\s*\d+"],
        "curiosity_hook":[r"왜", r"알고", r"충격", r"놀라운"],
        "how_to":        [r"방법", r"하는법", r"팁", r"노하우"],
        "experiment":    [r"해봤", r"실험", r"도전"],
        "fact_reveal":   [r"사실", r"실제로", r"진실"],
        "comparison":    [r"\bvs\b", r"비교", r"차이"],
        "mystery":       [r"미스터리", r"비밀"],
        "list_format":   [r"\d+가지", r"\d+개"],
    },
}

_REGION_TO_LANG = {"JP": "ja", "US": "en", "KR": "ko"}

_MOCK_PATTERNS = [
    ("ranking",        ["list_format", "number_in_title"],     "short"),
    ("curiosity_hook", ["question_hook"],                       "short"),
    ("how_to",         ["step_by_step"],                        "medium"),
    ("experiment",     ["challenge_format"],                    "short"),
    ("fact_reveal",    ["surprise_opening"],                    "short"),
    ("comparison",     ["dual_structure"],                      "short"),
    ("list_format",    ["number_in_title", "list_format"],      "short"),
]


# ------------------------------------------------------------------
# データモデル
# ------------------------------------------------------------------
@dataclass
class PatternRecord:
    """
    保存するのは「抽象パターン」のみ。
    元動画ID・タイトル原文・説明文は含まない。
    """
    pattern_hash: str
    pattern_type: str
    format_tags: list[str]
    language: str
    region: str
    duration_category: str    # "short" | "medium" | "long"
    collected_at: str         # ISO 8601


# ------------------------------------------------------------------
# パターンDB(JSONLファイルベース)
# ------------------------------------------------------------------
class PatternDB:
    def __init__(self, db_path: Path | None = None) -> None:
        self._path = db_path or (_DATA_DIR / "patterns.jsonl")
        self._path.parent.mkdir(parents=True, exist_ok=True)

    def _existing_hashes(self) -> set[str]:
        if not self._path.exists():
            return set()
        hashes: set[str] = set()
        with self._path.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        hashes.add(json.loads(line)["pattern_hash"])
                    except (json.JSONDecodeError, KeyError):
                        pass
        return hashes

    def save(self, record: PatternRecord) -> bool:
        """重複ハッシュを除いて追記。保存した場合 True を返す。"""
        if record.pattern_hash in self._existing_hashes():
            return False
        with self._path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(asdict(record), ensure_ascii=False) + "\n")
        return True

    def load_all(self) -> list[PatternRecord]:
        if not self._path.exists():
            return []
        records: list[PatternRecord] = []
        with self._path.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        records.append(PatternRecord(**json.loads(line)))
                    except (json.JSONDecodeError, TypeError):
                        pass
        return records

    def count_by_region(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for r in self.load_all():
            counts[r.region] = counts.get(r.region, 0) + 1
        return counts


# ------------------------------------------------------------------
# クローラ本体
# ------------------------------------------------------------------
class TrendCrawler:
    def __init__(
        self,
        api_key: str | None = None,
        config_dir: Path | None = None,
        db: PatternDB | None = None,
    ) -> None:
        cfg_dir = config_dir or _CONFIG_DIR
        with (cfg_dir / "settings.yaml").open(encoding="utf-8") as f:
            self._settings = yaml.safe_load(f)

        self._api_key = api_key or os.getenv("YOUTUBE_API_KEY", "")
        self._mock_mode = not bool(self._api_key)
        self._db = db or PatternDB()

        if self._mock_mode:
            logger.warning("YOUTUBE_API_KEY が未設定のためモックモードで動作します")

    # ------------------------------------------------------------------
    # 内部ユーティリティ
    # ------------------------------------------------------------------
    def _detect_language(self, region: str) -> str:
        return _REGION_TO_LANG.get(region, "en")

    def _classify_pattern(self, title: str, description: str, language: str) -> str:
        """タイトル+説明の構造的特徴からパターン種別を判定する。"""
        text = (title + " " + description).lower()
        kw_map = _KEYWORDS.get(language, _KEYWORDS["en"])
        for pattern_type, patterns in kw_map.items():
            for pat in patterns:
                if re.search(pat, text, re.IGNORECASE):
                    return pattern_type
        return "other"

    def _extract_format_tags(self, title: str, description: str, language: str) -> list[str]:
        """フォーマット特徴タグを抽出する。"""
        tags: list[str] = []
        text = title + " " + description

        if re.search(r"\d+", title):
            tags.append("number_in_title")
        if re.search(r"[?？]", title):
            tags.append("question_hook")
        if re.search(r"\d+\s*(選|つ|個|位|things|ways|reasons|가지|개)", text, re.IGNORECASE):
            tags.append("list_format")
        if re.search(r"(step|手順|ステップ|순서)", text, re.IGNORECASE):
            tags.append("step_by_step")
        if re.search(r"(vs|versus|比較|비교)", text, re.IGNORECASE):
            tags.append("dual_structure")
        if re.search(r"(challenge|チャレンジ|도전)", text, re.IGNORECASE):
            tags.append("challenge_format")
        if re.search(r"(実は|actually|사실)", text, re.IGNORECASE):
            tags.append("surprise_opening")
        if not tags:
            tags.append("freeform")

        return tags

    @staticmethod
    def _parse_iso_duration(duration: str) -> int:
        """ISO 8601 duration (PT1M30S) を秒数に変換する。"""
        m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", duration or "")
        if not m:
            return 0
        h = int(m.group(1) or 0)
        mn = int(m.group(2) or 0)
        s = int(m.group(3) or 0)
        return h * 3600 + mn * 60 + s

    @staticmethod
    def _duration_category(seconds: int) -> str:
        if seconds <= 60:
            return "short"
        if seconds <= 300:
            return "medium"
        return "long"

    @staticmethod
    def _make_pattern_hash(pattern_type: str, format_tags: list[str], language: str) -> str:
        """元動画情報を含まないパターンのSHA256ハッシュを生成する。"""
        payload = json.dumps(
            {"t": pattern_type, "f": sorted(format_tags), "l": language},
            sort_keys=True,
            ensure_ascii=False,
        )
        return hashlib.sha256(payload.encode()).hexdigest()[:16]

    # ------------------------------------------------------------------
    # モードごとの取得処理
    # ------------------------------------------------------------------
    def _fetch_region_mock(self, region: str, max_results: int) -> list[PatternRecord]:
        """APIキーなしのモック動作: ダミーパターンを生成する。"""
        lang = self._detect_language(region)
        now = datetime.now(timezone.utc).isoformat()
        records: list[PatternRecord] = []

        for i, (ptype, tags, dur_cat) in enumerate(_MOCK_PATTERNS[:max_results]):
            p_hash = self._make_pattern_hash(ptype, tags, lang)
            records.append(PatternRecord(
                pattern_hash=p_hash,
                pattern_type=ptype,
                format_tags=tags,
                language=lang,
                region=region,
                duration_category=dur_cat,
                collected_at=now,
            ))
        return records

    def _fetch_region_api(self, region: str, max_results: int) -> list[PatternRecord]:
        """YouTube Data API v3 からトレンドを取得しパターンを抽出する。"""
        try:
            from googleapiclient.discovery import build  # type: ignore
        except ImportError:
            logger.error("google-api-python-client が未インストールです")
            return []

        lang = self._detect_language(region)
        now = datetime.now(timezone.utc).isoformat()
        records: list[PatternRecord] = []

        youtube = build("youtube", "v3", developerKey=self._api_key)
        response = (
            youtube.videos()
            .list(
                part="snippet,contentDetails",
                chart="mostPopular",
                regionCode=region,
                maxResults=min(max_results, 50),
                hl=lang,
            )
            .execute()
        )

        for item in response.get("items", []):
            snippet = item.get("snippet", {})
            content = item.get("contentDetails", {})

            # タイトル・説明は分類にのみ使い、直後に破棄(保存しない)
            title: str = snippet.get("title", "")
            description: str = snippet.get("description", "")
            duration_str: str = content.get("duration", "PT0S")

            pattern_type = self._classify_pattern(title, description, lang)
            format_tags = self._extract_format_tags(title, description, lang)
            duration_sec = self._parse_iso_duration(duration_str)
            dur_cat = self._duration_category(duration_sec)
            p_hash = self._make_pattern_hash(pattern_type, format_tags, lang)

            # title / description / video ID はここで破棄 — 保存しない
            records.append(PatternRecord(
                pattern_hash=p_hash,
                pattern_type=pattern_type,
                format_tags=format_tags,
                language=lang,
                region=region,
                duration_category=dur_cat,
                collected_at=now,
            ))

        return records

    def fetch_region(self, region: str, max_results: int) -> list[PatternRecord]:
        """指定リージョンのトレンドパターンを取得する。"""
        logger.info("取得中: region=%s max=%d mock=%s", region, max_results, self._mock_mode)
        if self._mock_mode:
            return self._fetch_region_mock(region, max_results)
        return self._fetch_region_api(region, max_results)

    # ------------------------------------------------------------------
    # メインエントリ
    # ------------------------------------------------------------------
    def run(
        self,
        regions: list[str] | None = None,
        per_region_limit: int | None = None,
    ) -> dict:
        """全リージョンを処理してDBに保存し、サマリを返す。"""
        crawler_cfg = self._settings.get("crawler", {})
        regions = regions or crawler_cfg.get("target_regions", ["JP", "US", "KR"])
        per_region_limit = per_region_limit or crawler_cfg.get("per_region_limit", 20)

        total_fetched = 0
        total_saved = 0
        region_summary: dict[str, dict] = {}

        for region in regions:
            records = self.fetch_region(region, per_region_limit)
            saved = sum(1 for r in records if self._db.save(r))
            total_fetched += len(records)
            total_saved += saved
            region_summary[region] = {"fetched": len(records), "saved": saved}
            logger.info("  %s: %d件取得 / %d件保存", region, len(records), saved)

        summary = {
            "mode": "mock" if self._mock_mode else "api",
            "regions": region_summary,
            "total_fetched": total_fetched,
            "total_saved": total_saved,
            "db_total": len(self._db.load_all()),
        }
        return summary


# ------------------------------------------------------------------
# CLI エントリポイント
# ------------------------------------------------------------------
def main() -> None:
    import argparse

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="YouTube トレンドパターン収集")
    parser.add_argument("--regions", nargs="+", default=None, help="対象リージョン (例: JP US KR)")
    parser.add_argument("--limit", type=int, default=None, help="リージョンあたりの取得件数")
    args = parser.parse_args()

    crawler = TrendCrawler()
    summary = crawler.run(regions=args.regions, per_region_limit=args.limit)

    print("\n=== 収集完了 ===")
    for region, stat in summary["regions"].items():
        print(f"  {region}: 取得 {stat['fetched']}件 / 新規保存 {stat['saved']}件")
    print(f"  合計保存: {summary['total_saved']}件 / DB総数: {summary['db_total']}件")
    print(f"  モード: {summary['mode']}")


if __name__ == "__main__":
    main()
