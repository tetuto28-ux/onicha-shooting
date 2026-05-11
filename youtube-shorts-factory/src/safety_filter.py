from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import List

import yaml


@dataclass
class SafetyResult:
    passed: bool
    status: str  # "ok" | "warning" | "block"
    reasons: List[str] = field(default_factory=list)


_CONFIG_DIR = Path(__file__).parent.parent / "config"


class SafetyFilter:
    def __init__(self, config_dir: Path | None = None) -> None:
        self._config_dir = config_dir or _CONFIG_DIR
        self._settings = self._load_yaml("settings.yaml")
        self._blocked = self._load_yaml("blocked_topics.yaml")

    def _load_yaml(self, filename: str) -> dict:
        path = self._config_dir / filename
        with path.open(encoding="utf-8") as f:
            return yaml.safe_load(f)

    # ------------------------------------------------------------------
    # 1. 企画コンテンツのキーワードチェック
    # ------------------------------------------------------------------
    def check_idea(self, title: str, script: str) -> SafetyResult:
        """タイトルとスクリプトに対してキーワードブロックチェックを行う。"""
        text = f"{title} {script}".lower()
        reasons: list[str] = []
        warnings: list[str] = []

        for rule in self._blocked.get("hard_blocks", []):
            for kw in rule.get("keyword", []):
                if kw.lower() in text:
                    reasons.append(
                        f"ハードブロック: '{kw}' — {rule.get('reason', '')}"
                    )

        if reasons:
            return SafetyResult(False, "block", reasons)

        for rule in self._blocked.get("soft_warnings", []):
            for kw in rule.get("keyword", []):
                if kw.lower() in text:
                    warnings.append(
                        f"ソフト警告: '{kw}' — {rule.get('note', '')}"
                    )

        if warnings:
            return SafetyResult(True, "warning", warnings)

        return SafetyResult(True, "ok", [])

    # ------------------------------------------------------------------
    # 2. 素材ライセンスチェック
    # ------------------------------------------------------------------
    def check_asset_license(self, source: str, kind: str) -> SafetyResult:
        """
        素材のソースとカテゴリ(video/audio)がポリシーに合致するか確認する。

        Args:
            source: 素材の取得元 (例: "pexels", "youtube_audio_library")
            kind:   素材の種類 ("video" または "audio")
        """
        safety_cfg = self._settings.get("safety", {})

        if kind == "video":
            allowed = safety_cfg.get("allowed_video_sources", [])
            label = "動画"
        elif kind == "audio":
            allowed = safety_cfg.get("allowed_audio_sources", [])
            label = "音声/BGM"
        else:
            return SafetyResult(
                False, "block", [f"不明な素材種別: '{kind}'"]
            )

        if source not in allowed:
            return SafetyResult(
                False,
                "block",
                [
                    f"{label}素材ソース '{source}' は許可リスト外 "
                    f"(許可: {allowed})"
                ],
            )

        return SafetyResult(True, "ok", [])

    # ------------------------------------------------------------------
    # 3. 公開前最終チェック
    # ------------------------------------------------------------------
    def check_pre_publish(self, manifest: dict) -> SafetyResult:
        """
        投稿直前にmanifestの全必須フィールドを検証する。
        1つでも失敗したら投稿を拒否する。
        """
        reasons: list[str] = []
        content_cfg = self._settings.get("content", {})

        # AI開示ラベル
        if not manifest.get("ai_disclosure"):
            reasons.append("ai_disclosure が True でない")

        # 人間承認
        if not manifest.get("human_approved"):
            reasons.append("human_approved が True でない")

        # 参照元安全チェック済み
        if not manifest.get("reference_safety_passed"):
            reasons.append("reference_safety_passed が True でない")

        # 素材ライセンス
        for asset in manifest.get("assets", []):
            result = self.check_asset_license(
                asset.get("source", ""), asset.get("kind", "")
            )
            if not result.passed:
                reasons.extend(result.reasons)

        # 動画尺
        duration = manifest.get("duration_sec")
        if duration is not None:
            min_sec = content_cfg.get("duration_min_sec", 25)
            max_sec = content_cfg.get("duration_max_sec", 50)
            if not (min_sec <= duration <= max_sec):
                reasons.append(
                    f"動画尺 {duration}秒 が範囲外 ({min_sec}〜{max_sec}秒)"
                )

        if reasons:
            return SafetyResult(False, "block", reasons)

        return SafetyResult(True, "ok", [])

    # ------------------------------------------------------------------
    # 4. 参照元コンテンツの安全性チェック
    # ------------------------------------------------------------------
    def check_reference_safety(self, idea: dict) -> SafetyResult:
        """
        参照元コンテンツの安全性チェック。
        海外/国内問わず同じ基準を適用する。
        """
        reasons: list[str] = []
        ref = idea.get("reference_source", {})

        if not ref:
            # 参照元情報なし = 完全オリジナルとみなしてOK
            return SafetyResult(True, "ok", [])

        # 1. 借用レベルチェック
        borrow_level = ref.get("borrow_level", "concept")
        forbidden_levels = {
            "translated_script",
            "visual_assets",
            "audio_assets",
            "exact_sequence",
        }
        if borrow_level in forbidden_levels:
            reasons.append(
                f"借用レベル '{borrow_level}' は禁止 "
                "(言語が違っても著作権・ポリシー違反)"
            )

        # 2. 構成順序の完全一致チェック(言語不問)
        if ref.get("sequence_identical") is True:
            reasons.append(
                "原典との構成順序完全一致は再利用コンテンツ判定リスク"
            )

        # 3. 翻訳パクリチェック
        if ref.get("is_translation") is True:
            reasons.append(
                "原典スクリプトの翻訳は翻訳権侵害の可能性"
            )

        # 4. オリジナリティ記載確認
        if not ref.get("originality_notes"):
            reasons.append(
                "オリジナリティ記載なし(どこを独自要素として変えたか不明)"
            )

        # 5. 海外参照時の追加チェック(誤った安心感への警告)
        source_lang = ref.get("source_language", "ja")
        if source_lang != "ja":
            safe_levels = {"concept", "format_structure", "editing_style"}
            if borrow_level not in safe_levels and borrow_level not in forbidden_levels:
                # forbidden はすでにステップ1でブロック済み
                # caution レベルは海外参照では追加警告
                reasons.append(
                    f"海外参照({source_lang})でも "
                    "concept/format_structure/editing_style 以外は同等リスク"
                )

        if reasons:
            return SafetyResult(False, "block", reasons)

        return SafetyResult(True, "ok", [])
