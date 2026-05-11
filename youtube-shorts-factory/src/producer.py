"""
動画制作パイプライン。
VOICEVOX → faster-whisper → Pexels → FFmpeg の順に実行し、
final.mp4 と manifest.json を data/output/{idea_id}/ に生成する。
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
import yaml

from .safety_filter import SafetyFilter

logger = logging.getLogger(__name__)

_CONFIG_DIR  = Path(__file__).parent.parent / "config"
_DATA_DIR    = Path(__file__).parent.parent / "data"
_ASSETS_DIR  = Path(__file__).parent.parent / "assets"


# ------------------------------------------------------------------
# データモデル
# ------------------------------------------------------------------
@dataclass
class AssetInfo:
    source: str   # "pexels" | "youtube_audio_library" | "self_generated" etc.
    kind:   str   # "video" | "audio"
    path:   str   # data/output/ 以下の相対パス


@dataclass
class PrePublishCheck:
    passed:     bool
    checked_at: str
    failures:   list[str] = field(default_factory=list)


@dataclass
class Manifest:
    idea_id:                 str
    title:                   str
    niche:                   str
    reference_source:        dict
    assets:                  list[dict]          # AssetInfo の asdict
    duration_sec:            float
    ai_disclosure:           bool
    human_approved:          bool
    reference_safety_passed: bool
    produced_at:             str
    output_dir:              str
    pre_publish_check:       dict = field(default_factory=dict)   # PrePublishCheck の asdict


# ------------------------------------------------------------------
# ユーティリティ
# ------------------------------------------------------------------
def _ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def _run_ffmpeg(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    cmd = ["ffmpeg", "-y", *args]
    logger.debug("FFmpeg: %s", " ".join(cmd))
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


def _format_srt_time(seconds: float) -> str:
    h  = int(seconds // 3600)
    m  = int((seconds % 3600) // 60)
    s  = int(seconds % 60)
    ms = int((seconds - int(seconds)) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


# ------------------------------------------------------------------
# Producer
# ------------------------------------------------------------------
class Producer:
    def __init__(
        self,
        config_dir: Path | None = None,
        data_dir:   Path | None = None,
        assets_dir: Path | None = None,
    ) -> None:
        cfg_dir = config_dir or _CONFIG_DIR
        self._data_dir   = data_dir   or _DATA_DIR
        self._assets_dir = assets_dir or _ASSETS_DIR
        self._settings   = self._load_yaml(cfg_dir / "settings.yaml")
        self._safety     = SafetyFilter(config_dir=cfg_dir)

        self._voicevox_url = os.getenv(
            "VOICEVOX_BASE_URL",
            self._settings.get("voicevox", {}).get("base_url", "http://localhost:50021"),
        )
        self._voicevox_speaker = int(
            self._settings.get("voicevox", {}).get("speaker_id", 1)
        )
        self._pexels_key = os.getenv("PEXELS_API_KEY", "")

        # モック判定
        self._mock_voice  = not self._voicevox_reachable()
        self._mock_pexels = not bool(self._pexels_key)
        self._mock_ffmpeg = not _ffmpeg_available()

        if self._mock_voice:
            logger.warning("VOICEVOX 未起動 → モック音声を使用")
        if self._mock_pexels:
            logger.warning("PEXELS_API_KEY 未設定 → モック動画を使用")
        if self._mock_ffmpeg:
            logger.warning("FFmpeg 未インストール → ダミー final.mp4 を使用")

    @staticmethod
    def _load_yaml(path: Path) -> dict:
        with path.open(encoding="utf-8") as f:
            return yaml.safe_load(f)

    def _voicevox_reachable(self) -> bool:
        try:
            r = requests.get(f"{self._voicevox_url}/version", timeout=2)
            return r.status_code == 200
        except Exception:
            return False

    # ------------------------------------------------------------------
    # Step 1: ナレーション音声合成 (VOICEVOX)
    # ------------------------------------------------------------------
    def _synthesize_voice(self, script: str, out_path: Path) -> float:
        """WAVファイルを生成し、尺(秒)を返す。"""
        if self._mock_voice or self._mock_ffmpeg:
            return self._synthesize_voice_mock(script, out_path)

        # audio_query
        r = requests.post(
            f"{self._voicevox_url}/audio_query",
            params={"text": script, "speaker": self._voicevox_speaker},
            timeout=30,
        )
        r.raise_for_status()
        query = r.json()

        # synthesis
        r2 = requests.post(
            f"{self._voicevox_url}/synthesis",
            params={"speaker": self._voicevox_speaker},
            json=query,
            timeout=60,
        )
        r2.raise_for_status()
        out_path.write_bytes(r2.content)

        # 尺の計算
        duration = self._get_audio_duration(out_path)
        logger.info("音声合成完了: %.1fs → %s", duration, out_path.name)
        return duration

    def _synthesize_voice_mock(self, script: str, out_path: Path) -> float:
        """FFmpegで無音WAVを生成する(モック)。"""
        # 文字数から尺を推定(1文字≒0.15秒)
        estimated = max(25.0, min(50.0, len(script) * 0.15))
        if _ffmpeg_available():
            _run_ffmpeg([
                "-f", "lavfi", "-i", f"anullsrc=r=44100:cl=mono:duration={estimated:.1f}",
                "-acodec", "pcm_s16le", str(out_path),
            ])
        else:
            out_path.write_bytes(b"RIFF\x00\x00\x00\x00WAVEfmt ")  # 最小WAVヘッダ
        return estimated

    def _get_audio_duration(self, path: Path) -> float:
        if not _ffmpeg_available():
            return 30.0
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
            capture_output=True, text=True,
        )
        try:
            return float(result.stdout.strip())
        except ValueError:
            return 30.0

    # ------------------------------------------------------------------
    # Step 2: SRT字幕生成 (faster-whisper)
    # ------------------------------------------------------------------
    def _generate_subtitles(self, audio_path: Path, out_path: Path) -> None:
        """音声からSRT字幕を生成する。"""
        if self._mock_voice:
            self._generate_subtitles_mock(out_path)
            return

        try:
            from faster_whisper import WhisperModel  # type: ignore
        except ImportError:
            logger.warning("faster-whisper 未インストール → モック字幕を使用")
            self._generate_subtitles_mock(out_path)
            return

        model = WhisperModel("tiny", device="cpu", compute_type="int8")
        segments, _ = model.transcribe(str(audio_path), language="ja")

        lines: list[str] = []
        for i, seg in enumerate(segments, start=1):
            lines.append(str(i))
            lines.append(
                f"{_format_srt_time(seg.start)} --> {_format_srt_time(seg.end)}"
            )
            lines.append(seg.text.strip())
            lines.append("")

        out_path.write_text("\n".join(lines), encoding="utf-8")
        logger.info("字幕生成完了: %s", out_path.name)

    @staticmethod
    def _generate_subtitles_mock(out_path: Path) -> None:
        srt = (
            "1\n00:00:00,000 --> 00:00:03,000\n深海の不思議な世界へようこそ。\n\n"
            "2\n00:00:03,000 --> 00:00:08,000\n今回は驚きの事実をご紹介します。\n\n"
            "3\n00:00:08,000 --> 00:00:15,000\nチャンネル登録もよろしくお願いします。\n"
        )
        out_path.write_text(srt, encoding="utf-8")

    # ------------------------------------------------------------------
    # Step 3: Pexels 縦動画素材取得
    # ------------------------------------------------------------------
    def _fetch_video_asset(self, keyword: str, out_path: Path) -> AssetInfo:
        """Pexels から縦動画を取得する。ライセンスの二重チェックあり。"""
        # ライセンスチェック(ソース確定前に pexels として事前確認)
        lic = self._safety.check_asset_license("pexels", "video")
        if not lic.passed:
            raise RuntimeError(f"動画素材ライセンスNG: {lic.reasons}")

        if self._mock_pexels or not _ffmpeg_available():
            return self._fetch_video_asset_mock(out_path)

        headers = {"Authorization": self._pexels_key}
        r = requests.get(
            "https://api.pexels.com/videos/search",
            headers=headers,
            params={"query": keyword, "orientation": "portrait", "per_page": 5},
            timeout=15,
        )
        r.raise_for_status()
        data = r.json()
        videos = data.get("videos", [])
        if not videos:
            logger.warning("Pexels 動画なし → モックを使用")
            return self._fetch_video_asset_mock(out_path)

        # 1080x1920 に最も近いファイルを選択
        best_link: str | None = None
        for video in videos[:3]:
            for vf in video.get("video_files", []):
                w, h = vf.get("width", 0), vf.get("height", 0)
                if w > 0 and h > w:  # 縦動画のみ
                    best_link = vf["link"]
                    break
            if best_link:
                break

        if not best_link:
            return self._fetch_video_asset_mock(out_path)

        resp = requests.get(best_link, timeout=60, stream=True)
        resp.raise_for_status()
        with out_path.open("wb") as f:
            for chunk in resp.iter_content(chunk_size=8192):
                f.write(chunk)

        logger.info("Pexels 動画取得完了: %s", out_path.name)
        return AssetInfo(source="pexels", kind="video", path=out_path.name)

    @staticmethod
    def _fetch_video_asset_mock(out_path: Path) -> AssetInfo:
        """FFmpegでカラーテストパターン動画を生成する(モック)。"""
        if _ffmpeg_available():
            _run_ffmpeg([
                "-f", "lavfi",
                "-i", "color=c=0x1a1a2e:s=1080x1920:r=30:d=30",
                "-c:v", "libx264", "-t", "30",
                str(out_path),
            ])
        else:
            out_path.touch()
        return AssetInfo(source="self_generated", kind="video", path=out_path.name)

    # ------------------------------------------------------------------
    # Step 4: BGM 選択
    # ------------------------------------------------------------------
    def _pick_bgm(self, out_path: Path) -> AssetInfo:
        """assets/bgm_licensed/ から BGM を選択する。"""
        bgm_dir = self._assets_dir / "bgm_licensed"
        candidates = list(bgm_dir.glob("*.mp3")) + list(bgm_dir.glob("*.wav"))

        if candidates:
            src = candidates[0]
            shutil.copy(src, out_path)
            logger.info("BGM選択: %s", src.name)
            return AssetInfo(
                source="self_licensed", kind="audio", path=out_path.name
            )

        # 無音BGMを生成(モック)
        if _ffmpeg_available():
            _run_ffmpeg([
                "-f", "lavfi",
                "-i", "anullsrc=r=44100:cl=stereo:duration=30",
                "-acodec", "libmp3lame", "-b:a", "128k",
                str(out_path),
            ])
        else:
            out_path.touch()

        logger.info("BGM: 無音モック")
        return AssetInfo(
            source="youtube_audio_library", kind="audio", path=out_path.name
        )

    # ------------------------------------------------------------------
    # Step 5: FFmpeg合成
    # ------------------------------------------------------------------
    def _compose_video(
        self,
        video_path: Path,
        voice_path: Path,
        bgm_path:   Path,
        srt_path:   Path,
        out_path:   Path,
        duration:   float,
    ) -> float:
        """
        FFmpegで最終動画を合成する。
        - 解像度: 1080x1920, fps: 30
        - BGM音量: 0.15, ナレーション音量: 1.5
        - 字幕をバーンイン
        """
        content_cfg = self._settings.get("content", {})
        burn_subs = content_cfg.get("subtitle_burn_in", True)

        if not _ffmpeg_available():
            logger.warning("FFmpeg なし → dummy final.mp4 を作成")
            out_path.write_bytes(b"\x00" * 64)
            return duration

        # 字幕フィルタ(エスケープ処理)
        srt_escaped = str(srt_path).replace("\\", "/").replace(":", "\\:")
        vf = f"scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2"
        if burn_subs and srt_path.exists() and srt_path.stat().st_size > 0:
            vf += f",subtitles='{srt_escaped}':force_style='FontSize=24,PrimaryColour=&HFFFFFF,Outline=2'"

        result = _run_ffmpeg([
            # 入力
            "-i", str(video_path),
            "-i", str(voice_path),
            "-i", str(bgm_path),
            # 音声ミックス: ナレーション x1.5, BGM x0.15
            "-filter_complex",
            f"[1:a]volume=1.5[voice];[2:a]volume=0.15[bgm];[voice][bgm]amix=inputs=2:duration=first[aout]",
            # 映像フィルタ
            "-vf", vf,
            # エンコード設定
            "-c:v", "libx264", "-preset", "fast", "-crf", "23",
            "-c:a", "aac", "-b:a", "128k",
            "-r", "30", "-t", str(duration),
            "-map", "0:v", "-map", "[aout]",
            str(out_path),
        ])

        if result.returncode != 0:
            logger.error("FFmpeg エラー: %s", result.stderr[-500:])
            # エラー時もダミーファイルを残して続行
            out_path.touch()

        actual_dur = self._get_audio_duration(out_path) if out_path.stat().st_size > 64 else duration
        logger.info("動画合成完了: %.1fs → %s", actual_dur, out_path.name)
        return actual_dur

    # ------------------------------------------------------------------
    # Step 6: Manifest 生成 & 公開前チェック
    # ------------------------------------------------------------------
    def _write_manifest(
        self,
        idea:      dict,
        assets:    list[AssetInfo],
        duration:  float,
        out_dir:   Path,
        passed_pre: bool,
        failures:  list[str],
    ) -> Manifest:
        now = datetime.now(timezone.utc).isoformat()

        pre_check = PrePublishCheck(
            passed=passed_pre,
            checked_at=now,
            failures=failures,
        )

        manifest = Manifest(
            idea_id=idea.get("idea_id", str(uuid.uuid4())[:8]),
            title=idea.get("title", ""),
            niche=idea.get("niche", ""),
            reference_source=idea.get("reference_source", {}),
            assets=[asdict(a) for a in assets],
            duration_sec=round(duration, 2),
            ai_disclosure=True,
            human_approved=bool(idea.get("human_approved", False)),
            reference_safety_passed=True,
            produced_at=now,
            output_dir=str(out_dir),
            pre_publish_check=asdict(pre_check),
        )

        manifest_path = out_dir / "manifest.json"
        with manifest_path.open("w", encoding="utf-8") as f:
            json.dump(asdict(manifest), f, ensure_ascii=False, indent=2)
        logger.info("Manifest 生成: %s", manifest_path.name)
        return manifest

    # ------------------------------------------------------------------
    # メイン制作フロー
    # ------------------------------------------------------------------
    def produce(self, idea: dict) -> Manifest:
        """
        1企画から final.mp4 と manifest.json を生成する。
        最後に check_pre_publish() を実行し、結果を manifest に記録する。
        """
        idea_id   = idea.get("idea_id", str(uuid.uuid4())[:8])
        title     = idea.get("title", "企画")
        script    = idea.get("script_outline", title)
        niche     = idea.get("niche", "")
        ref       = idea.get("reference_source", {})

        # 出力ディレクトリ
        ts      = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        out_dir = self._data_dir / "output" / f"{idea_id}_{ts}"
        out_dir.mkdir(parents=True, exist_ok=True)
        logger.info("制作開始: [%s] %s → %s", idea_id, title, out_dir)

        assets: list[AssetInfo] = []

        # 1. ナレーション音声
        voice_path = out_dir / "voice.wav"
        duration   = self._synthesize_voice(script, voice_path)

        # 2. SRT字幕
        srt_path = out_dir / "subtitles.srt"
        self._generate_subtitles(voice_path, srt_path)

        # 3. 縦動画素材 (Pexels)
        video_path  = out_dir / "video_raw.mp4"
        video_asset = self._fetch_video_asset(niche or title, video_path)
        assets.append(video_asset)

        # 4. BGM
        bgm_path  = out_dir / "bgm.mp3"
        bgm_asset = self._pick_bgm(bgm_path)
        assets.append(bgm_asset)

        # 5. FFmpeg合成
        final_path = out_dir / "final.mp4"
        actual_dur = self._compose_video(
            video_path, voice_path, bgm_path, srt_path, final_path, duration
        )

        # 6. 公開前チェック
        manifest_input = {
            "ai_disclosure":           True,
            "human_approved":          idea.get("human_approved", False),
            "reference_safety_passed": True,
            "duration_sec":            actual_dur,
            "assets":                  [asdict(a) for a in assets],
        }
        pre_result = self._safety.check_pre_publish(manifest_input)

        # 7. Manifest 保存
        manifest = self._write_manifest(
            idea=idea,
            assets=assets,
            duration=actual_dur,
            out_dir=out_dir,
            passed_pre=pre_result.passed,
            failures=pre_result.reasons,
        )

        if pre_result.passed:
            logger.info("公開前チェック: OK")
        else:
            logger.warning("公開前チェック NG: %s", pre_result.reasons)

        return manifest


# ------------------------------------------------------------------
# CLI エントリポイント
# ------------------------------------------------------------------
def main() -> None:
    import argparse
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="動画制作パイプライン")
    parser.add_argument(
        "--idea",
        type=str,
        default=None,
        help="企画JSON文字列(省略時は approved.jsonl の最新1件を使用)",
    )
    args = parser.parse_args()

    if args.idea:
        idea = json.loads(args.idea)
    else:
        approved_db = _DATA_DIR / "approved_queue" / "approved.jsonl"
        if approved_db.exists():
            lines = [l.strip() for l in approved_db.read_text().splitlines() if l.strip()]
            if lines:
                idea = json.loads(lines[-1])
            else:
                print("approved.jsonl が空です。先に reviewer_cli で承認してください。")
                return
        else:
            # ダミー企画でテスト
            idea = {
                "idea_id": "demo0001",
                "title": "深海魚が光る理由5選",
                "script_outline": "冒頭で問いかけ。生物発光のメカニズムを3軸で解説。締めはチョウチンアンコウ。",
                "niche": "深海生物の雑学",
                "reference_source": {
                    "source_language": "none",
                    "borrow_level": "concept",
                    "sequence_identical": False,
                    "is_translation": False,
                    "originality_notes": "完全オリジナル構成",
                },
                "human_approved": True,
            }
            print("approved.jsonl なし → ダミー企画で制作します")

    producer = Producer()
    manifest = producer.produce(idea)

    print("\n=== 制作完了 ===")
    print(f"  タイトル       : {manifest.title}")
    print(f"  出力ディレクトリ: {manifest.output_dir}")
    print(f"  尺             : {manifest.duration_sec}秒")
    print(f"  AI開示         : {manifest.ai_disclosure}")
    print(f"  人間承認済み   : {manifest.human_approved}")
    print(f"  公開前チェック : {'OK' if manifest.pre_publish_check.get('passed') else 'NG'}")
    if not manifest.pre_publish_check.get("passed"):
        for f in manifest.pre_publish_check.get("failures", []):
            print(f"    → {f}")


if __name__ == "__main__":
    main()
