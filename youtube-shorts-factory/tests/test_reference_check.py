"""
参照元コンテンツチェック専用テスト (check_reference_safety)

検証項目:
  - 海外参照で borrow_level=translated_script はブロックされること
  - 海外参照で sequence_identical=True はブロックされること
  - 海外参照で borrow_level=concept は通過すること
  - 国内参照と海外参照で判定基準が同等であること
"""
import pytest
from pathlib import Path

from src.safety_filter import SafetyFilter

CONFIG_DIR = Path(__file__).parent.parent / "config"


@pytest.fixture
def sf():
    return SafetyFilter(config_dir=CONFIG_DIR)


def _idea(ref: dict) -> dict:
    return {"title": "テスト企画", "reference_source": ref}


def _base_ref(**kwargs) -> dict:
    """有効な最小参照元情報のベース。キーワード引数で上書き可能。"""
    base = {
        "source_language": "en",
        "borrow_level": "concept",
        "sequence_identical": False,
        "is_translation": False,
        "originality_notes": "日本の深海事例に完全リビルド",
    }
    base.update(kwargs)
    return base


# ==============================================================
# ケース1: 参照元なし = 完全オリジナル
# ==============================================================
class TestNoReference:
    def test_no_reference_source_passes(self, sf):
        result = sf.check_reference_safety({"title": "完全オリジナル企画"})
        assert result.passed
        assert result.status == "ok"

    def test_empty_reference_source_passes(self, sf):
        result = sf.check_reference_safety(_idea({}))
        # 空dictは「参照元情報なし」と同義
        assert result.passed


# ==============================================================
# ケース2: 海外参照での禁止借用レベル
# ==============================================================
class TestForeignReferenceForbiddenBorrowLevels:
    @pytest.mark.parametrize("level", [
        "translated_script",
        "visual_assets",
        "audio_assets",
        "exact_sequence",
    ])
    def test_forbidden_borrow_level_blocks(self, sf, level):
        """禁止借用レベルはすべてブロックされること(海外参照)"""
        ref = _base_ref(source_language="en", borrow_level=level)
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed
        assert result.status == "block"
        assert any(level in r for r in result.reasons)

    def test_translated_script_blocked_with_reason(self, sf):
        """translated_script のブロック理由に著作権への言及があること"""
        ref = _base_ref(borrow_level="translated_script")
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed
        assert any("翻訳権" in r or "著作権" in r or "ポリシー" in r for r in result.reasons)


# ==============================================================
# ケース3: 海外参照での sequence_identical=True
# ==============================================================
class TestForeignReferenceSequenceIdentical:
    def test_sequence_identical_true_blocks(self, sf):
        """海外参照で sequence_identical=True はブロックされること"""
        ref = _base_ref(source_language="en", sequence_identical=True)
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed
        assert result.status == "block"
        assert any("構成順序" in r for r in result.reasons)

    def test_sequence_identical_false_passes(self, sf):
        """sequence_identical=False は問題なし"""
        ref = _base_ref(source_language="en", sequence_identical=False)
        result = sf.check_reference_safety(_idea(ref))
        assert result.passed


# ==============================================================
# ケース4: 海外参照での翻訳フラグ
# ==============================================================
class TestForeignReferenceTranslation:
    def test_is_translation_true_blocks(self, sf):
        """is_translation=True はブロックされること"""
        ref = _base_ref(source_language="en", is_translation=True)
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed
        assert any("翻訳" in r for r in result.reasons)

    def test_is_translation_false_passes(self, sf):
        """is_translation=False は問題なし"""
        ref = _base_ref(source_language="en", is_translation=False)
        result = sf.check_reference_safety(_idea(ref))
        assert result.passed


# ==============================================================
# ケース5: 海外参照での安全な借用レベル
# ==============================================================
class TestForeignReferenceSafeBorrowLevels:
    @pytest.mark.parametrize("level", [
        "concept",
        "format_structure",
        "editing_style",
    ])
    def test_safe_borrow_level_passes(self, sf, level):
        """海外参照で safe な借用レベルは通過すること"""
        ref = _base_ref(source_language="en", borrow_level=level)
        result = sf.check_reference_safety(_idea(ref))
        assert result.passed, f"level={level} が通過するべきだが blocked: {result.reasons}"
        assert result.status == "ok"

    def test_concept_from_us_passes(self, sf):
        """英語(US)のconceptレベル参照は通過"""
        ref = _base_ref(source_language="en", borrow_level="concept")
        assert sf.check_reference_safety(_idea(ref)).passed

    def test_format_structure_from_kr_passes(self, sf):
        """韓国語のformat_structureレベル参照は通過"""
        ref = _base_ref(source_language="ko", borrow_level="format_structure")
        assert sf.check_reference_safety(_idea(ref)).passed


# ==============================================================
# ケース6: 国内参照と海外参照で判定基準が同等であること
# ==============================================================
class TestEquivalentStandardsDomesticVsForeign:
    """
    設計原則11: 海外参照でも国内参照と同等のリスク基準を適用する。
    同じ違反(translated_script, sequence_identical, is_translation)は
    言語に関わらず同様にブロックされなければならない。
    """

    @pytest.mark.parametrize("lang", ["ja", "en", "ko", "zh"])
    def test_translated_script_blocked_regardless_of_language(self, sf, lang):
        """翻訳パクリは言語に関わらずブロックされること"""
        ref = _base_ref(source_language=lang, borrow_level="translated_script")
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed, f"lang={lang} で translated_script がブロックされるべき"

    @pytest.mark.parametrize("lang", ["ja", "en", "ko", "zh"])
    def test_sequence_identical_blocked_regardless_of_language(self, sf, lang):
        """構成順序の完全コピーは言語に関わらずブロックされること"""
        ref = _base_ref(source_language=lang, sequence_identical=True)
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed, f"lang={lang} で sequence_identical=True がブロックされるべき"

    @pytest.mark.parametrize("lang", ["ja", "en", "ko", "zh"])
    def test_is_translation_blocked_regardless_of_language(self, sf, lang):
        """翻訳フラグは言語に関わらずブロックされること"""
        ref = _base_ref(source_language=lang, is_translation=True)
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed, f"lang={lang} で is_translation=True がブロックされるべき"

    @pytest.mark.parametrize("lang", ["ja", "en", "ko", "zh"])
    def test_concept_level_passes_regardless_of_language(self, sf, lang):
        """conceptレベルの借用は言語に関わらず通過すること"""
        ref = _base_ref(source_language=lang, borrow_level="concept")
        result = sf.check_reference_safety(_idea(ref))
        assert result.passed, f"lang={lang} で concept が通過するべき: {result.reasons}"

    def test_domestic_and_foreign_same_block_outcome_for_translated_script(self, sf):
        """国内(ja)と海外(en)で translated_script の判定結果が同じであること"""
        ja_ref = _base_ref(source_language="ja", borrow_level="translated_script")
        en_ref = _base_ref(source_language="en", borrow_level="translated_script")
        ja_result = sf.check_reference_safety(_idea(ja_ref))
        en_result = sf.check_reference_safety(_idea(en_ref))
        assert ja_result.passed == en_result.passed
        assert ja_result.status == en_result.status

    def test_domestic_and_foreign_same_block_outcome_for_sequence(self, sf):
        """国内(ja)と海外(en)で sequence_identical=True の判定結果が同じであること"""
        ja_ref = _base_ref(source_language="ja", sequence_identical=True)
        en_ref = _base_ref(source_language="en", sequence_identical=True)
        ja_result = sf.check_reference_safety(_idea(ja_ref))
        en_result = sf.check_reference_safety(_idea(en_ref))
        assert ja_result.passed == en_result.passed


# ==============================================================
# ケース7: オリジナリティ記載
# ==============================================================
class TestOriginalityNotes:
    def test_missing_originality_notes_blocks(self, sf):
        """originality_notes が空の場合はブロックされること"""
        ref = _base_ref(originality_notes="")
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed
        assert any("オリジナリティ" in r for r in result.reasons)

    def test_none_originality_notes_blocks(self, sf):
        ref = _base_ref(originality_notes=None)
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed

    def test_valid_originality_notes_passes(self, sf):
        ref = _base_ref(originality_notes="日本固有の事例に完全置き換え済み")
        result = sf.check_reference_safety(_idea(ref))
        assert result.passed


# ==============================================================
# ケース8: 複合違反
# ==============================================================
class TestMultipleViolations:
    def test_multiple_violations_all_reported(self, sf):
        """複数の違反がある場合、すべての理由が報告されること"""
        ref = _base_ref(
            borrow_level="translated_script",
            sequence_identical=True,
            is_translation=True,
            originality_notes="",
        )
        result = sf.check_reference_safety(_idea(ref))
        assert not result.passed
        assert len(result.reasons) >= 3
