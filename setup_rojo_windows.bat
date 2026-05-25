@echo off
setlocal
set PROJECT_FILE=default.project.json

echo === Rojo セットアップ補助 (Windows / cmd) ===

if not exist "%PROJECT_FILE%" (
  echo [エラー] %PROJECT_FILE% が見つかりません。リポジトリのルートで実行してください。
  exit /b 1
)

where rojo >nul 2>nul
if errorlevel 1 (
  echo [未検出] Rojo CLI がインストールされていません。
  echo 次の手順で手動インストールしてください:
  echo   1^) https://rojo.space/docs/ へアクセス
  echo   2^) Windows向けインストール手順を実行
  echo   3^) 新しいコマンドプロンプトを開き直してこのスクリプトを再実行
  exit /b 1
)

echo [OK] Rojo CLI を検出しました。
rojo --version
if errorlevel 1 (
  echo [エラー] rojo --version の実行に失敗しました。PATH設定を確認してください。
  exit /b 1
)

echo.
echo --- 次にやること (手動) ---
echo 1^) Roblox Studioで Rojo Plugin をインストール
echo    - 推奨: Studio ^> Plugins ^> Manage Plugins から Rojo を追加
echo    - 参考CLI: rojo plugin install
echo 2^) このウィンドウで同期サーバーを起動
echo    rojo serve %PROJECT_FILE%
echo 3^) Studio側のRojoプラグインで localhost に接続

echo.
echo Rojoサーバーを起動します... ^(停止は Ctrl + C^)
rojo serve %PROJECT_FILE%

endlocal
