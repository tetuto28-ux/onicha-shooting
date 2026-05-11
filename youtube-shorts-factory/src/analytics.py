"""
YouTube Analytics API で投稿済み動画の統計を取得し、
次の企画生成にフィードバックするレポートを生成する。
"""
from __future__ import annotations

import json
import logging
import os
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone, timedelta
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)

_CONFIG_DIR  = Path(__file__).parent.parent / "config"
_DATA_DIR    = Path(__file__).parent.parent / "data"
_HISTORY_DB  = _DATA_DIR / "logs" / "publish_history.jsonl"
_PATTERNS_DB = _DATA_DIR / "patterns.jsonl"


# ------------------------------------------------------------------
# データモデル
# ------------------------------------------------------------------
@dataclass
class VideoStats:
    video_id:           str
    title:              str
    published_at:       str
    views:              int
    likes:              int
    avg_view_duration:  float   # 秒
    ctr:                float   # クリック率 (0.0〜1.0)
    retention_rate:     float   # 平均視聴維持率 (0.0〜1.0)
    idea_id:            str = ""


@dataclass
class AnalyticsReport:
    generated_at:        str
    period_days:         int
    total_videos:        int
    total_views:         int
    avg_ctr:             float
    avg_retention_rate:  float
    top_videos:          list[dict]          # VideoStats の asdict (上位3件)
    low_videos:          list[dict]          # VideoStats の asdict (下位3件)
    pattern_performance: dict[str, float]    # pattern_type → avg_retention
    recommendations:     list[str]           # 次回企画への推奨アクション
    mock:                bool = False


# ------------------------------------------------------------------
# Analytics
# ------------------------------------------------------------------
class Analytics:
    def __init__(
        self,
        config_dir:  Path | None = None,
        history_db:  Path | None = None,
    ) -> None:
        cfg_dir = config_dir or _CONFIG_DIR
        self._settings   = self._load_yaml(cfg_dir / "settings.yaml")
        self._history_db = history_db or _HISTORY_DB
        self._mock_mode  = not self._oauth_available()

        if self._mock_mode:
            logger.warning("YouTube OAuth 未設定 → モックモードで動作します")

    @staticmethod
    def _load_yaml(path: Path) -> dict:
        with path.open(encoding="utf-8") as f:
            return yaml.safe_load(f)

    @staticmethod
    def _oauth_available() -> bool:
        return bool(
            list(Path(".").glob("token.json"))
            or list(Path(".").glob("client_secret*.json"))
            or os.getenv("YOUTUBE_CLIENT_ID")
        )

    # ------------------------------------------------------------------
    # 投稿履歴の読み込み
    # ------------------------------------------------------------------
    def _load_publish_history(self) -> list[dict]:
        if not self._history_db.exists():
            return []
        records: list[dict] = []
        with self._history_db.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        r = json.loads(line)
                        if not r.get("mock"):   # 本番投稿のみ対象
                            records.append(r)
                    except json.JSONDecodeError:
                        pass
        return records

    # ------------------------------------------------------------------
    # 統計取得(API / モック)
    # ------------------------------------------------------------------
    def fetch_video_stats(self, video_id: str, title: str = "", idea_id: str = "") -> VideoStats:
        if self._mock_mode:
            return self._fetch_video_stats_mock(video_id, title, idea_id)
        return self._fetch_video_stats_api(video_id, title, idea_id)

    def _fetch_video_stats_api(self, video_id: str, title: str, idea_id: str) -> VideoStats:
        try:
            from googleapiclient.discovery import build       # type: ignore
            from google.oauth2.credentials import Credentials # type: ignore
        except ImportError:
            logger.error("google-api-python-client 未インストール")
            return self._fetch_video_stats_mock(video_id, title, idea_id)

        creds = Credentials.from_authorized_user_file(
            "token.json",
            scopes=[
                "https://www.googleapis.com/auth/youtube.readonly",
                "https://www.googleapis.com/auth/yt-analytics.readonly",
            ],
        )

        youtube  = build("youtube",         "v3",         credentials=creds)
        ytanalytics = build("youtubeAnalytics", "v2", credentials=creds)

        # 動画基本情報
        video_resp = youtube.videos().list(
            part="snippet,statistics",
            id=video_id,
        ).execute()
        items = video_resp.get("items", [])
        if not items:
            return self._fetch_video_stats_mock(video_id, title, idea_id)

        snippet    = items[0]["snippet"]
        statistics = items[0].get("statistics", {})
        title      = title or snippet.get("title", "")

        # Analytics (視聴維持率・CTR)
        end_date   = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        start_date = (datetime.now(timezone.utc) - timedelta(days=90)).strftime("%Y-%m-%d")

        try:
            ar = ytanalytics.reports().query(
                ids="channel==MINE",
                startDate=start_date,
                endDate=end_date,
                metrics="views,likes,averageViewDuration,annotationClickThroughRate",
                filters=f"video=={video_id}",
            ).execute()
            row = ar.get("rows", [[0, 0, 0.0, 0.0]])[0]
            views, likes, avg_dur, ctr = int(row[0]), int(row[1]), float(row[2]), float(row[3])
        except Exception as e:
            logger.warning("Analytics API エラー: %s", e)
            views, likes, avg_dur, ctr = (
                int(statistics.get("viewCount", 0)),
                int(statistics.get("likeCount", 0)),
                0.0, 0.0,
            )

        # 維持率の推定(尺が不明なのでビデオ情報から計算)
        content_resp = youtube.videos().list(part="contentDetails", id=video_id).execute()
        duration_iso = content_resp["items"][0]["contentDetails"].get("duration", "PT30S")
        from src.crawler import TrendCrawler  # type: ignore
        total_sec = TrendCrawler._parse_iso_duration(duration_iso) or 30
        retention = min(1.0, avg_dur / total_sec) if total_sec > 0 else 0.0

        return VideoStats(
            video_id=video_id,
            title=title,
            published_at=snippet.get("publishedAt", ""),
            views=views,
            likes=likes,
            avg_view_duration=avg_dur,
            ctr=ctr,
            retention_rate=round(retention, 3),
            idea_id=idea_id,
        )

    @staticmethod
    def _fetch_video_stats_mock(video_id: str, title: str, idea_id: str) -> VideoStats:
        """ダミー統計を返す(モック)。video_id のハッシュで値を分散させる。"""
        import hashlib
        seed = int(hashlib.md5(video_id.encode()).hexdigest()[:6], 16)
        views          = 1000 + (seed % 9000)
        likes          = int(views * (0.02 + (seed % 10) * 0.005))
        avg_view_dur   = 15.0 + (seed % 20)
        ctr            = round(0.04 + (seed % 8) * 0.005, 3)
        retention      = round(0.3 + (seed % 10) * 0.04, 3)

        return VideoStats(
            video_id=video_id,
            title=title or f"動画 {video_id[:8]}",
            published_at=datetime.now(timezone.utc).isoformat(),
            views=views,
            likes=likes,
            avg_view_duration=avg_view_dur,
            ctr=ctr,
            retention_rate=retention,
            idea_id=idea_id,
        )

    # ------------------------------------------------------------------
    # パターン性能の集計
    # ------------------------------------------------------------------
    def _pattern_performance(self, stats_list: list[VideoStats]) -> dict[str, float]:
        """
        publish_history の idea_id と patterns.jsonl を突き合わせ、
        pattern_type ごとの平均維持率を返す。
        """
        if not _PATTERNS_DB.exists():
            return {}

        # idea_id → pattern_type のマッピング(approved_queue から)
        idea_to_pattern: dict[str, str] = {}
        approved_db = _DATA_DIR / "approved_queue" / "approved.jsonl"
        if approved_db.exists():
            with approved_db.open(encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            r = json.loads(line)
                            ref = r.get("reference_source", {})
                            pt  = ref.get("borrow_level", "concept")
                            idea_to_pattern[r.get("idea_id", "")] = pt
                        except json.JSONDecodeError:
                            pass

        bucket: dict[str, list[float]] = {}
        for s in stats_list:
            pt = idea_to_pattern.get(s.idea_id, "unknown")
            bucket.setdefault(pt, []).append(s.retention_rate)

        return {pt: round(sum(v) / len(v), 3) for pt, v in bucket.items()}

    # ------------------------------------------------------------------
    # 推奨アクション生成
    # ------------------------------------------------------------------
    @staticmethod
    def _generate_recommendations(
        stats_list: list[VideoStats],
        pattern_perf: dict[str, float],
    ) -> list[str]:
        recs: list[str] = []

        if not stats_list:
            return ["投稿済み動画がないため推奨アクションを生成できません"]

        avg_ctr       = sum(s.ctr            for s in stats_list) / len(stats_list)
        avg_retention = sum(s.retention_rate for s in stats_list) / len(stats_list)

        if avg_ctr < 0.05:
            recs.append(
                f"平均CTR {avg_ctr:.1%} が低め(目標5%以上): "
                "サムネイルのキャッチコピーと色使いを見直す"
            )
        if avg_retention < 0.4:
            recs.append(
                f"平均視聴維持率 {avg_retention:.1%} が低め(目標40%以上): "
                "冒頭3秒のフックを強化する"
            )

        if pattern_perf:
            best_pt  = max(pattern_perf, key=pattern_perf.get)   # type: ignore
            worst_pt = min(pattern_perf, key=pattern_perf.get)    # type: ignore
            recs.append(
                f"維持率が高いパターン: '{best_pt}' ({pattern_perf[best_pt]:.1%}) "
                "→ 次の企画生成に優先的に採用"
            )
            if pattern_perf[worst_pt] < 0.3:
                recs.append(
                    f"維持率が低いパターン: '{worst_pt}' ({pattern_perf[worst_pt]:.1%}) "
                    "→ 企画の切り口を変える"
                )

        top = max(stats_list, key=lambda s: s.retention_rate)
        recs.append(
            f"最高維持率動画 '{top.title}' ({top.retention_rate:.1%}) の "
            "構成・尺・フックを分析して次回に活かす"
        )

        return recs

    # ------------------------------------------------------------------
    # PatternDB へのフィードバック
    # ------------------------------------------------------------------
    def feedback_to_ideator(self, report: AnalyticsReport) -> int:
        """
        高維持率(>= 0.5)のパターン種別を PatternDB に追記する。
        追加件数を返す。
        """
        from src.crawler import PatternDB, PatternRecord  # type: ignore

        db  = PatternDB()
        now = datetime.now(timezone.utc).isoformat()
        added = 0

        for pt, retention in report.pattern_performance.items():
            if retention >= 0.5 and pt not in ("unknown",):
                record = PatternRecord(
                    pattern_hash=f"analytics_{pt}_{int(retention*100)}",
                    pattern_type=pt,
                    format_tags=["high_retention_feedback"],
                    language="ja",
                    region="JP",
                    duration_category="short",
                    collected_at=now,
                )
                if db.save(record):
                    added += 1
                    logger.info("PatternDB フィードバック追記: %s (retention=%.1f%%)", pt, retention * 100)

        return added

    # ------------------------------------------------------------------
    # レポート生成
    # ------------------------------------------------------------------
    def generate_report(self, days: int = 28) -> AnalyticsReport:
        """投稿済み全動画の統計を集計してレポートを返す。"""
        history = self._load_publish_history()

        if not history:
            logger.info("投稿履歴なし → モックデータでレポートを生成")
            # モック用にダミー履歴を作成
            history = [
                {"video_id": f"DEMO_{i:04d}", "title": f"デモ動画{i}", "idea_id": f"idea_{i}"}
                for i in range(5)
            ]

        stats_list: list[VideoStats] = []
        for rec in history:
            vid   = rec.get("video_id", "")
            title = rec.get("title", "")
            iid   = rec.get("idea_id", "")
            if not vid:
                continue
            s = self.fetch_video_stats(vid, title, iid)
            stats_list.append(s)
            logger.info(
                "統計取得: %s | views=%d ctr=%.1f%% retention=%.1f%%",
                vid, s.views, s.ctr * 100, s.retention_rate * 100,
            )

        if not stats_list:
            stats_list = [self._fetch_video_stats_mock("dummy", "dummy", "")]

        total_views   = sum(s.views            for s in stats_list)
        avg_ctr       = sum(s.ctr              for s in stats_list) / len(stats_list)
        avg_retention = sum(s.retention_rate   for s in stats_list) / len(stats_list)

        sorted_stats  = sorted(stats_list, key=lambda s: s.retention_rate, reverse=True)
        top_videos    = [asdict(s) for s in sorted_stats[:3]]
        low_videos    = [asdict(s) for s in sorted_stats[-3:]]

        pattern_perf  = self._pattern_performance(stats_list)
        recommendations = self._generate_recommendations(stats_list, pattern_perf)

        return AnalyticsReport(
            generated_at=datetime.now(timezone.utc).isoformat(),
            period_days=days,
            total_videos=len(stats_list),
            total_views=total_views,
            avg_ctr=round(avg_ctr, 4),
            avg_retention_rate=round(avg_retention, 4),
            top_videos=top_videos,
            low_videos=low_videos,
            pattern_performance=pattern_perf,
            recommendations=recommendations,
            mock=self._mock_mode,
        )

    # ------------------------------------------------------------------
    # メインエントリ
    # ------------------------------------------------------------------
    def run(self, days: int = 28) -> AnalyticsReport:
        """統計取得 → レポート生成 → PatternDB フィードバック → ファイル保存。"""
        report = self.generate_report(days=days)

        # PatternDB へフィードバック
        added = self.feedback_to_ideator(report)
        logger.info("PatternDB フィードバック: %d件追記", added)

        # レポート保存
        log_dir = _DATA_DIR / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        ts       = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        out_path = log_dir / f"analytics_{ts}.json"
        with out_path.open("w", encoding="utf-8") as f:
            json.dump(asdict(report), f, ensure_ascii=False, indent=2)
        logger.info("レポート保存: %s", out_path.name)

        return report


# ------------------------------------------------------------------
# CLI エントリポイント
# ------------------------------------------------------------------
def main() -> None:
    import argparse
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="YouTube Analytics レポート生成")
    parser.add_argument("--days", type=int, default=28, help="集計期間(日数、デフォルト28)")
    args = parser.parse_args()

    analytics = Analytics()
    report    = analytics.run(days=args.days)

    print("\n=== Analytics レポート ===")
    print(f"  集計期間   : 直近 {report.period_days} 日")
    print(f"  総動画数   : {report.total_videos} 本")
    print(f"  総再生数   : {report.total_views:,}")
    print(f"  平均CTR    : {report.avg_ctr:.1%}")
    print(f"  平均維持率 : {report.avg_retention_rate:.1%}")

    if report.top_videos:
        print("\n[維持率トップ3]")
        for v in report.top_videos:
            print(f"  {v['title'][:30]:30s} | retention={v['retention_rate']:.1%} ctr={v['ctr']:.1%}")

    if report.pattern_performance:
        print("\n[パターン別維持率]")
        for pt, ret in sorted(report.pattern_performance.items(), key=lambda x: -x[1]):
            print(f"  {pt:25s} : {ret:.1%}")

    print("\n[推奨アクション]")
    for rec in report.recommendations:
        print(f"  → {rec}")

    print(f"\n  モード: {'mock' if report.mock else 'api'}")


if __name__ == "__main__":
    main()
