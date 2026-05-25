param(
    [string]$ProjectFile = "default.project.json"
)

Write-Host "=== Rojo セットアップ補助 (Windows / PowerShell) ===" -ForegroundColor Cyan

if (-not (Test-Path $ProjectFile)) {
    Write-Host "[エラー] $ProjectFile が見つかりません。リポジトリのルートで実行してください。" -ForegroundColor Red
    exit 1
}

$rojo = Get-Command rojo -ErrorAction SilentlyContinue
if (-not $rojo) {
    Write-Host "[未検出] Rojo CLI がインストールされていません。" -ForegroundColor Yellow
    Write-Host "次の手順で手動インストールしてください:" -ForegroundColor Yellow
    Write-Host "  1) https://rojo.space/docs/ へアクセス" 
    Write-Host "  2) Windows向けインストール手順を実行" 
    Write-Host "  3) 新しいPowerShellを開き直してこのスクリプトを再実行" 
    exit 1
}

Write-Host "[OK] Rojo CLI を検出: $($rojo.Source)" -ForegroundColor Green

try {
    $version = rojo --version
    Write-Host "[OK] rojo --version => $version" -ForegroundColor Green
} catch {
    Write-Host "[エラー] rojo --version の実行に失敗しました。PATH設定を確認してください。" -ForegroundColor Red
    exit 1
}

Write-Host "\n--- 次にやること (手動) ---" -ForegroundColor Cyan
Write-Host "1) Roblox Studioで Rojo Plugin をインストール"
Write-Host "   - 推奨: Studio > Plugins > Manage Plugins から Rojo を追加"
Write-Host "   - 参考CLI: rojo plugin install"
Write-Host "2) このウィンドウで同期サーバーを起動"
Write-Host "   rojo serve $ProjectFile"
Write-Host "3) Studio側のRojoプラグインで localhost に接続"

Write-Host "\nRojoサーバーを起動します... (停止は Ctrl + C)" -ForegroundColor Cyan
rojo serve $ProjectFile
