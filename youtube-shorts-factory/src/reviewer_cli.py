"""
人間レビューCLI — rich + click ベースの対話型企画承認UI。
承認済み企画のみ data/approved_queue/approved.jsonl に追記する。
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

import click
from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.table import Table
from rich.text import Text

_DATA_DIR    = Path(__file__).parent.parent / "data"
_QUEUE_DIR   = _DATA_DIR / "approved_queue"
_APPROVED_DB = _QUEUE_DIR / "approved.jsonl"

console = Console()


# ------------------------------------------------------------------
# ユーティリティ
# ------------------------------------------------------------------
def _load_ideas(queue_dir: Path) -> list[dict]:
    """ideas_*.json を新しい順に読み込み、全企画を返す。"""
    ideas: list[dict] = []
    for path in sorted(queue_dir.glob("ideas_*.json"), reverse=True):
        with path.open(encoding="utf-8") as f:
            ideas.extend(json.load(f))
    return ideas


def _already_reviewed_ids(approved_db: Path) -> set[str]:
    """approved.jsonl に記録済みの idea_id セットを返す。"""
    if not approved_db.exists():
        return set()
    ids: set[str] = set()
    with approved_db.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    ids.add(json.loads(line)["idea_id"])
                except (json.JSONDecodeError, KeyError):
                    pass
    return ids


def _append_approved(idea: dict, approved_db: Path) -> None:
    """承認済みレコードを approved.jsonl に追記する。"""
    approved_db.parent.mkdir(parents=True, exist_ok=True)
    record = {
        **idea,
        "human_approved": True,
        "approved_at": datetime.now(timezone.utc).isoformat(),
    }
    with approved_db.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


# ------------------------------------------------------------------
# 表示
# ------------------------------------------------------------------
def _display_idea(idea: dict, index: int, total: int) -> None:
    """企画内容をリッチ表示する。"""
    ref = idea.get("reference_source") or {}
    has_ref = bool(ref) and ref.get("source_language", "none") != "none"

    # ヘッダ
    console.rule(
        f"[bold cyan]企画 {index}/{total}  ID: {idea.get('idea_id', '?')}[/bold cyan]"
    )

    # メイン情報
    table = Table(show_header=False, box=None, padding=(0, 1))
    table.add_column("key",   style="bold yellow", width=16)
    table.add_column("value", style="white")
    table.add_row("タイトル",   idea.get("title", ""))
    table.add_row("ジャンル",   idea.get("niche", ""))
    table.add_row("構成概要",   idea.get("script_outline", ""))
    console.print(table)

    # 参照元情報
    if has_ref:
        ref_table = Table(show_header=False, box=None, padding=(0, 1))
        ref_table.add_column("key",   style="bold magenta", width=16)
        ref_table.add_column("value", style="white")
        ref_table.add_row("言語",         ref.get("source_language", ""))
        ref_table.add_row("借用レベル",   ref.get("borrow_level", ""))
        ref_table.add_row("構成順序同一", str(ref.get("sequence_identical", "")))
        ref_table.add_row("翻訳",         str(ref.get("is_translation", "")))
        ref_table.add_row("独自要素",     ref.get("originality_notes", ""))
        console.print(
            Panel(ref_table, title="[magenta]参照元情報[/magenta]", border_style="magenta")
        )
    else:
        console.print("[dim]参照元: 完全オリジナル[/dim]")

    console.print()


# ------------------------------------------------------------------
# 承認フロー
# ------------------------------------------------------------------
def _ask_fact_check() -> bool:
    """ファクト確認。Falseを返したら即却下。"""
    console.print("[bold]── ファクト確認 ──[/bold]")
    return Confirm.ask("  ファクトを確認しましたか?（信頼できる情報源で検証済み）")


def _ask_reference_checks(ref: dict) -> bool:
    """
    参照元がある企画の追加確認(4項目)。
    1つでも No なら False を返す。
    """
    source_lang = ref.get("source_language", "none")
    if not ref or source_lang == "none":
        return True

    console.print()
    console.print(
        Panel(
            f"[bold]言語:[/bold] {source_lang}  "
            f"[bold]借用レベル:[/bold] {ref.get('borrow_level', '')}  \n"
            f"[bold]独自要素:[/bold] {ref.get('originality_notes', '')}",
            title="[magenta]参照元情報の最終確認[/magenta]",
            border_style="magenta",
        )
    )
    console.print("[bold]以下を全て確認してください (全YESでなければ却下):[/bold]")

    checks = [
        "原典の映像・音声を一切使用していない",
        "原典の構成順序と異なる順序にしている",
        "原典の固有名詞・具体例を引き継いでいない",
        "翻訳ではなく独自構成になっている",
    ]
    for check in checks:
        if not Confirm.ask(f"  {check}"):
            console.print("[red]  → 確認NGのため却下します[/red]")
            return False
    return True


def _run_approval(idea: dict) -> str:
    """
    承認フローを実行する。
    Returns: "approved" | "rejected"
    """
    ref = idea.get("reference_source") or {}

    if not _ask_fact_check():
        console.print("[red]ファクト確認NGのため却下します[/red]")
        return "rejected"

    if not _ask_reference_checks(ref):
        return "rejected"

    console.print("[green bold]✓ 承認しました[/green bold]")
    return "approved"


# ------------------------------------------------------------------
# 編集
# ------------------------------------------------------------------
def _edit_idea(idea: dict) -> dict:
    """タイトル・構成概要をインライン編集する。"""
    console.print("[bold]── 編集モード ──[/bold]")
    new_title = Prompt.ask("  タイトル", default=idea.get("title", ""))
    new_script = Prompt.ask("  構成概要", default=idea.get("script_outline", ""))
    idea = {**idea, "title": new_title, "script_outline": new_script}
    console.print("[cyan]編集を保存しました。もう一度この企画をレビューします。[/cyan]")
    return idea


# ------------------------------------------------------------------
# メインレビューループ
# ------------------------------------------------------------------
def _action_menu() -> str:
    """
    アクション選択メニュー。
    Returns: "approve" | "reject" | "edit" | "skip" | "quit"
    """
    console.print(
        "[bold cyan][A][/bold cyan]承認  "
        "[bold red][R][/bold red]却下  "
        "[bold yellow][E][/bold yellow]編集  "
        "[bold dim][S][/bold dim]スキップ  "
        "[bold dim][Q][/bold dim]終了"
    )
    choice = Prompt.ask("  選択", choices=["a", "r", "e", "s", "q"], default="s").lower()
    return {
        "a": "approve",
        "r": "reject",
        "e": "edit",
        "s": "skip",
        "q": "quit",
    }[choice]


def _review_loop(
    ideas: list[dict],
    approved_db: Path,
) -> dict:
    """企画を1件ずつレビューし、承認/却下/スキップを処理する。"""
    approved_count = 0
    rejected_count = 0
    skipped_count  = 0

    i = 0
    while i < len(ideas):
        idea = ideas[i]

        _display_idea(idea, index=i + 1, total=len(ideas))
        action = _action_menu()
        console.print()

        if action == "quit":
            console.print("[dim]レビューを中断しました[/dim]")
            break

        if action == "skip":
            skipped_count += 1
            i += 1
            continue

        if action == "edit":
            ideas[i] = _edit_idea(idea)
            # 編集後に同じ企画を再表示するためインデックスを進めない
            continue

        if action == "reject":
            console.print("[red]✗ 却下しました[/red]\n")
            rejected_count += 1
            i += 1
            continue

        if action == "approve":
            result = _run_approval(idea)
            if result == "approved":
                _append_approved(ideas[i], approved_db)
                approved_count += 1
            else:
                rejected_count += 1
            console.print()
            i += 1
            continue

    return {
        "approved": approved_count,
        "rejected": rejected_count,
        "skipped":  skipped_count,
    }


# ------------------------------------------------------------------
# CLI エントリポイント
# ------------------------------------------------------------------
@click.command()
@click.option(
    "--queue-dir",
    type=click.Path(path_type=Path),
    default=None,
    help="企画キューディレクトリ (デフォルト: data/approved_queue/)",
)
@click.option(
    "--approved-db",
    type=click.Path(path_type=Path),
    default=None,
    help="承認済み JSONL パス (デフォルト: data/approved_queue/approved.jsonl)",
)
@click.option("--all", "show_all", is_flag=True, help="承認済み企画も含めて表示")
def main(
    queue_dir: Path | None,
    approved_db: Path | None,
    show_all: bool,
) -> None:
    """人間レビューCLI — 企画を1件ずつ確認して承認/却下する。"""
    queue_dir   = queue_dir   or _QUEUE_DIR
    approved_db = approved_db or _APPROVED_DB

    console.print(
        Panel(
            "[bold green]YouTube Shorts Factory — 人間レビューCLI[/bold green]\n"
            "企画を1件ずつ確認し、承認/却下してください。\n"
            "[dim]承認された企画のみ制作工程に進みます。[/dim]",
            border_style="green",
        )
    )

    ideas = _load_ideas(queue_dir)
    if not ideas:
        console.print("[yellow]レビュー対象の企画が見つかりません。[/yellow]")
        console.print(f"[dim]先に python -m src.ideator を実行してください[/dim]")
        sys.exit(0)

    if not show_all:
        reviewed_ids = _already_reviewed_ids(approved_db)
        ideas = [i for i in ideas if i.get("idea_id") not in reviewed_ids]

    if not ideas:
        console.print("[green]未レビューの企画はありません。[/green]")
        sys.exit(0)

    console.print(f"[cyan]レビュー対象: {len(ideas)} 件[/cyan]\n")

    summary = _review_loop(ideas, approved_db)

    console.rule("[bold]レビュー完了[/bold]")
    console.print(
        f"  承認: [green]{summary['approved']}[/green]  "
        f"却下: [red]{summary['rejected']}[/red]  "
        f"スキップ: [dim]{summary['skipped']}[/dim]"
    )
    if summary["approved"] > 0:
        console.print(
            "\n[bold yellow]⚠  YouTube Studio で最終確認後、手動で public に切り替えてください[/bold yellow]"
        )


if __name__ == "__main__":
    main()
