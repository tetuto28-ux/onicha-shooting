"""src/safety_filter.py のユニットテスト"""
import pytest
from pathlib import Path

from src.safety_filter import SafetyFilter, SafetyResult

CONFIG_DIR = Path(__file__).parent.parent / "config"


@pytest.fixture
def sf():
    return SafetyFilter(config_dir=CONFIG_DIR)


# ==============================================================
# check_idea
# ==============================================================
class TestCheckIdea:
    def test_clean_content_passes(self, sf):
        result = sf.check_idea("深海魚の不思議な生態5選", "今回は深海に住む生き物を紹介します。")
        assert result.passed
        assert result.status == "ok"

    def test_medical_keyword_blocks(self, sf):
        result = sf.check_idea("この方法で病気が治る", "症状が効く薬の使い方を解説します。")
        assert not result.passed
        assert result.status == "block"
        assert any("治る" in r or "効く症状" in r or "薬" in r for r in result.reasons)

    def test_investment_keyword_blocks(self, sf):
        result = sf.check_idea("必ず儲かる投資術", "確実な投資で稼ぐ方法。")
        assert not result.passed
        assert result.status == "block"

    def test_privacy_keyword_blocks(self, sf):
        result = sf.check_idea("有名人の本名と住所", "実際の年収も紹介します。")
        assert not result.passed
        assert result.status == "block"

    def test_copyright_risk_blocks(self, sf):
        result = sf.check_idea("人気アニメ考察まとめ", "漫画ネタバレも含む映画解説です。")
        assert not result.passed
        assert result.status == "block"

    def test_exaggerated_expression_blocks(self, sf):
        result = sf.check_idea("絶対に痩せる方法", "必ず効果が出ます。")
        assert not result.passed
        assert result.status == "block"

    def test_soft_warning_passes_with_warning(self, sf):
        result = sf.check_idea("都市伝説5選", "怖い話を紹介します。")
        assert result.passed
        assert result.status == "warning"
        assert len(result.reasons) > 0

    def test_keyword_match_is_case_insensitive(self, sf):
        # ひらがな・全角は完全一致なのでこのケースは通過する(大文字小文字変換のみ)
        result = sf.check_idea("clean title", "clean script content here")
        assert result.passed

    def test_returns_safety_result_type(self, sf):
        result = sf.check_idea("タイトル", "スクリプト")
        assert isinstance(result, SafetyResult)
        assert isinstance(result.passed, bool)
        assert isinstance(result.status, str)
        assert isinstance(result.reasons, list)


# ==============================================================
# check_asset_license
# ==============================================================
class TestCheckAssetLicense:
    def test_pexels_video_allowed(self, sf):
        result = sf.check_asset_license("pexels", "video")
        assert result.passed
        assert result.status == "ok"

    def test_pixabay_video_allowed(self, sf):
        result = sf.check_asset_license("pixabay", "video")
        assert result.passed

    def test_self_generated_video_allowed(self, sf):
        result = sf.check_asset_license("self_generated", "video")
        assert result.passed

    def test_youtube_audio_library_allowed(self, sf):
        result = sf.check_asset_license("youtube_audio_library", "audio")
        assert result.passed

    def test_self_licensed_audio_allowed(self, sf):
        result = sf.check_asset_license("self_licensed", "audio")
        assert result.passed

    def test_unknown_video_source_blocked(self, sf):
        result = sf.check_asset_license("random_website", "video")
        assert not result.passed
        assert result.status == "block"

    def test_unknown_audio_source_blocked(self, sf):
        result = sf.check_asset_license("unknown_bgm_site", "audio")
        assert not result.passed
        assert result.status == "block"

    def test_invalid_kind_blocked(self, sf):
        result = sf.check_asset_license("pexels", "image")
        assert not result.passed
        assert result.status == "block"


# ==============================================================
# check_pre_publish
# ==============================================================
class TestCheckPrePublish:
    def _valid_manifest(self):
        return {
            "ai_disclosure": True,
            "human_approved": True,
            "reference_safety_passed": True,
            "duration_sec": 35,
            "assets": [
                {"source": "pexels", "kind": "video"},
                {"source": "youtube_audio_library", "kind": "audio"},
            ],
        }

    def test_valid_manifest_passes(self, sf):
        result = sf.check_pre_publish(self._valid_manifest())
        assert result.passed
        assert result.status == "ok"

    def test_missing_ai_disclosure_blocks(self, sf):
        m = self._valid_manifest()
        m["ai_disclosure"] = False
        result = sf.check_pre_publish(m)
        assert not result.passed
        assert any("ai_disclosure" in r for r in result.reasons)

    def test_missing_human_approved_blocks(self, sf):
        m = self._valid_manifest()
        m["human_approved"] = False
        result = sf.check_pre_publish(m)
        assert not result.passed
        assert any("human_approved" in r for r in result.reasons)

    def test_missing_reference_safety_blocks(self, sf):
        m = self._valid_manifest()
        m["reference_safety_passed"] = False
        result = sf.check_pre_publish(m)
        assert not result.passed
        assert any("reference_safety_passed" in r for r in result.reasons)

    def test_duration_too_short_blocks(self, sf):
        m = self._valid_manifest()
        m["duration_sec"] = 10
        result = sf.check_pre_publish(m)
        assert not result.passed
        assert any("動画尺" in r for r in result.reasons)

    def test_duration_too_long_blocks(self, sf):
        m = self._valid_manifest()
        m["duration_sec"] = 120
        result = sf.check_pre_publish(m)
        assert not result.passed
        assert any("動画尺" in r for r in result.reasons)

    def test_unlicensed_asset_blocks(self, sf):
        m = self._valid_manifest()
        m["assets"].append({"source": "unknown_site", "kind": "video"})
        result = sf.check_pre_publish(m)
        assert not result.passed

    def test_multiple_violations_reported(self, sf):
        m = self._valid_manifest()
        m["ai_disclosure"] = False
        m["human_approved"] = False
        result = sf.check_pre_publish(m)
        assert not result.passed
        assert len(result.reasons) >= 2
