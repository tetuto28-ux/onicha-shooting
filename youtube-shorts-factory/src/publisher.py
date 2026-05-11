"""
YouTube 投稿モジュール。
6つの前提条件を全て満たさなければ投稿を拒否する。
投稿は必ず privacyStatus="private" で行い、人間が最終確認後 public に切り替える。
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, date, timezone, timedelta
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)

_CONFIG_DIR = Path(__file__).parent.parent / "config"
_DATA_DIR   = Path(__file__).parent.parent / "data"
_HISTORY_DB = _DATA_DIR / "logs" / "publish_history.jsonl"


# ------------------------------------------------------------------
# カスタム例外
# ------------------------------------------------------------------
class PublishError(Exception):
    """投稿前提条件の違反を表す例外。"""


# ------------------------------------------------------------------
# 履歴ユーティリティ
# ------------------------------------------------------------------
def _load_history(history_db: Path) -> list[dict]:
    if not history_db.exists():
        return []
    records: list[dict] = []
    with history_db.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return records


def _count_today(history: list[dict], tz_name: str = "Asia/Tokyo") -> int:
    """本日(設定タイムゾーン)の投稿数を返す。ISO タイムスタンプをパースして比較する。"""
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(tz_name)
    except Exception:
        tz = timezone(timedelta(hours=9))
    today = datetime.now(tz).date()
    count = 0
    for r in history:
        at = r.get("published_at", "")
        if not at:
            continue
        try:
            dt = datetime.fromisoformat(at)
            if dt.astimezone(tz).date() == today:
                count += 1
        except (ValueError, TypeError):
            pass
    return count


def _minutes_since_last(history: list[dict]) -> float | None:
    """前回投稿からの経過分数を返す。履歴がなければ None。"""
    if not history:
        return None
    last_at = history[-1].get("published_at", "")
    if not last_at:
        return None
    try:
        last_dt = datetime.fromisoformat(last_at)
        elapsed = (datetime.now(timezone.utc) - last_dt).total_seconds() / 60
        return elapsed
    except ValueError:
        return None


# ------------------------------------------------------------------
# Publisher
# ------------------------------------------------------------------
class Publisher:
    def __init__(
        self,
        config_dir:  Path | None = None,
        history_db:  Path | None = None,
    ) -> None:
        cfg_dir = config_dir or _CONFIG_DIR
        self._settings   = self._load_yaml(cfg_dir / "settings.yaml")
        self._history_db = history_db or _HISTORY_DB
        self._history_db.parent.mkdir(parents=True, exist_ok=True)

        # OAuth クライアントが使えるか確認
        self._mock_mode = not self._oauth_available()
        if self._mock_mode:
            logger.warning(
                "YouTube OAuth 未設定(token.json / client_secret*.json 不在) "
                "→ モードモードで動作します"
            )

    @staticmethod
    def _load_yaml(path: Path) -> dict:
        with path.open(encoding="utf-8") as f:
            return yaml.safe_load(f)

    @staticmethod
    def _oauth_available() -> bool:
        """token.json または client_secret*.json があれば True。"""
        cwd = Path(".")
        return bool(
            list(cwd.glob("token.json"))
            or list(cwd.glob("client_secret*.json"))
            or os.getenv("YOUTUBE_CLIENT_ID")
        )

    # ------------------------------------------------------------------
    # Manifest 読み込み
    # ------------------------------------------------------------------
    @staticmethod
    def _load_manifest(output_dir: Path) -> dict:
        path = output_dir / "manifest.json"
        if not path.exists():
            raise PublishError(f"manifest.json が見つかりません: {path}")
        with path.open(encoding="utf-8") as f:
            return json.load(f)

    # ------------------------------------------------------------------
    # 前提条件チェック(6条件、1つでも失敗なら PublishError)
    # ------------------------------------------------------------------
    def _check_upload_preconditions(self, manifest: dict, final_mp4: Path) -> None:
        runtime = self._settings.get("runtime", {})
        max_per_day  = int(runtime.get("max_videos_per_day", 3))
        min_interval = int(runtime.get("min_interval_minutes", 180))

        errors: list[str] = []

        # 1. 人間承認済み
        if not manifest.get("human_approved"):
            errors.append("human_approved が True でない(reviewer_cli で承認が必要)")

        # 2. AI開示ラベル
        if not manifest.get("ai_disclosure"):
            errors.append("ai_disclosure が True でない")

        # 3. 公開前チェック通過
        pre = manifest.get("pre_publish_check", {})
        if not pre.get("passed"):
            failures = pre.get("failures", [])
            errors.append(
                "pre_publish_check が未通過: " + "; ".join(failures)
            )

        # 4. final.mp4 の存在
        if not final_mp4.exists() or final_mp4.stat().st_size == 0:
            errors.append(f"final.mp4 が存在しないか空: {final_mp4}")

        # 5. 本日の投稿数上限
        history = _load_history(self._history_db)
        today_count = _count_today(history)
        if today_count >= max_per_day:
            errors.append(
                f"本日の投稿数上限に達しています "
                f"({today_count}/{max_per_day}件)"
            )

        # 6. 最小投稿間隔
        elapsed = _minutes_since_last(history)
        if elapsed is not None and elapsed < min_interval:
            remaining = int(min_interval - elapsed)
            errors.append(
                f"前回投稿から {int(elapsed)}分しか経過していません "
                f"(最小間隔: {min_interval}分 / あと約{remaining}分)"
            )

        if errors:
            raise PublishError(
                "投稿前提条件チェック失敗:\n" + "\n".join(f"  - {e}" for e in errors)
            )

        logger.info(
            "前提条件チェック OK — 本日%d件目 / 前回から%.0f分経過",
            today_count + 1,
            elapsed if elapsed is not None else float("inf"),
        )

    # ------------------------------------------------------------------
    # アップロード(API / モック)
    # ------------------------------------------------------------------
    def _upload_video_api(self, manifest: dict, final_mp4: Path) -> str:
        """YouTube Data API v3 でアップロードする。"""
        try:
            from googleapiclient.discovery import build          # type: ignore
            from googleapiclient.http import MediaFileUpload     # type: ignore
            from google.oauth2.credentials import Credentials    # type: ignore
            from google.auth.transport.requests import Request   # type: ignore
            import google_auth_oauthlib.flow as flow_mod         # type: ignore
        except ImportError:
            raise PublishError(
                "google-api-python-client / google-auth-oauthlib が未インストールです"
            )

        # 認証
        creds = None
        token_path = Path("token.json")
        if token_path.exists():
            creds = Credentials.from_authorized_user_file(
                str(token_path),
                scopes=["https://www.googleapis.com/auth/youtube.upload"],
            )
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                secret_files = list(Path(".").glob("client_secret*.json"))
                if not secret_files:
                    raise PublishError("client_secret*.json が見つかりません")
                fl = flow_mod.InstalledAppFlow.from_client_secrets_file(
                    str(secret_files[0]),
                    scopes=["https://www.googleapis.com/auth/youtube.upload"],
                )
                creds = fl.run_local_server(port=0)
            token_path.write_text(creds.to_json())

        youtube = build("youtube", "v3", credentials=creds)

        body = {
            "snippet": {
                "title":       manifest.get("title", ""),
                "description": (
                    f"#Shorts\n\n"
                    f"※ この動画はAIを活用して制作しています。\n"
                    f"ジャンル: {manifest.get('niche', '')}"
                ),
                "tags":        ["Shorts", manifest.get("niche", "")],
                "categoryId":  "22",  # People & Blogs
            },
            "status": {
                "privacyStatus":          "private",        # 必ず private
                "selfDeclaredMadeForKids": False,
                "containsSyntheticMedia":  True,            # AI開示
            },
        }

        media = MediaFileUpload(
            str(final_mp4),
            mimetype="video/mp4",
            resumable=True,
            chunksize=1024 * 1024,
        )

        request = youtube.videos().insert(
            part=",".join(body.keys()),
            body=body,
            media_body=media,
        )

        response = None
        while response is None:
            status, response = request.next_chunk()
            if status:
                logger.info("アップロード進捗: %d%%", int(status.progress() * 100))

        video_id: str = response["id"]
        logger.info("アップロード完了: https://youtu.be/%s (private)", video_id)
        return video_id

    def _upload_video_mock(self, manifest: dict, final_mp4: Path) -> str:
        """モックアップロード(実際には送信しない)。"""
        dummy_id = f"MOCK_{manifest.get('idea_id', 'xxx')[:8]}"
        logger.info("モックアップロード: video_id=%s (実際には送信していません)", dummy_id)
        return dummy_id

    def _upload_video(self, manifest: dict, final_mp4: Path) -> str:
        if self._mock_mode:
            return self._upload_video_mock(manifest, final_mp4)
        return self._upload_video_api(manifest, final_mp4)

    # ------------------------------------------------------------------
    # 履歴記録
    # ------------------------------------------------------------------
    def _record_history(self, manifest: dict, video_id: str) -> None:
        record = {
            "video_id":       video_id,
            "idea_id":        manifest.get("idea_id"),
            "title":          manifest.get("title"),
            "privacy_status": "private",
            "published_at":   datetime.now(timezone.utc).isoformat(),
            "mock":           self._mock_mode,
        }
        with self._history_db.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        logger.info("履歴記録: %s", self._history_db.name)

    # ------------------------------------------------------------------
    # メインエントリ
    # ------------------------------------------------------------------
    def publish(self, output_dir: Path) -> dict:
        """
        manifest を検証し、前提条件を全て満たした場合のみ YouTube に投稿する。
        投稿は必ず privacyStatus="private"。

        Returns:
            {"video_id": str, "mock": bool}
        """
        manifest = self._load_manifest(output_dir)
        final_mp4 = output_dir / "final.mp4"

        # 前提条件チェック(1つでも失敗で PublishError)
        self._check_upload_preconditions(manifest, final_mp4)

        # アップロード
        logger.info("投稿開始: [%s] %s", manifest.get("idea_id"), manifest.get("title"))
        video_id = self._upload_video(manifest, final_mp4)

        # 履歴記録
        self._record_history(manifest, video_id)

        return {"video_id": video_id, "mock": self._mock_mode}


# ------------------------------------------------------------------
# CLI エントリポイント
# ------------------------------------------------------------------
def main() -> None:
    import argparse
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="YouTube 投稿")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="制作出力ディレクトリ (省略時は data/output/ の最新)",
    )
    args = parser.parse_args()

    output_dir = args.output_dir
    if output_dir is None:
        candidates = sorted((_DATA_DIR / "output").iterdir()) if (_DATA_DIR / "output").exists() else []
        candidates = [d for d in candidates if d.is_dir()]
        if not candidates:
            print("data/output/ に制作済みディレクトリがありません。先に producer を実行してください。")
            return
        output_dir = candidates[-1]

    print(f"投稿対象: {output_dir}")

    publisher = Publisher()
    try:
        result = publisher.publish(output_dir)
    except PublishError as e:
        print(f"\n[投稿拒否]\n{e}")
        return

    print("\n=== 投稿完了 ===")
    print(f"  video_id : {result['video_id']}")
    print(f"  公開設定 : private (モック: {result['mock']})")
    print()
    print("=" * 60)
    print("  ⚠  YouTube Studio で最終確認後、手動で public に切替")
    print("     https://studio.youtube.com/")
    print("=" * 60)


if __name__ == "__main__":
    main()
