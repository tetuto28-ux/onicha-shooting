# 違和感ホテル Tycoon MVP (Roblox Studio)

このリポジトリの Lua ファイルを Roblox Studio に配置して使います。

## 1) 作成スクリプト一覧
- `ReplicatedStorage/SharedModules/RoomData.lua`
- `ReplicatedStorage/SharedModules/AnomalyData.lua`
- `ReplicatedStorage/SharedModules/CommentIdeaData.lua`
- `ReplicatedStorage/SharedModules/UpgradeData.lua`
- `ServerScriptService/Modules/CoinService.lua`
- `ServerScriptService/Modules/RoomService.lua`
- `ServerScriptService/Modules/AnomalyService.lua`
- `ServerScriptService/Modules/UpgradeService.lua`
- `ServerScriptService/Modules/SaveService.lua`
- `ServerScriptService/Modules/AntiExploitService.lua`
- `ServerScriptService/ServerMain.lua`
- `StarterGui/LocalScripts/UIController.lua`
- `StarterGui/LocalScripts/RoomUIController.lua`
- `StarterGui/LocalScripts/RecordingModeController.lua`

## 2) 初心者向け配置手順
1. Studioで新規Baseplateを作成。
2. Explorerで同名のフォルダ/Script/ModuleScript/LocalScriptを作成。
3. 各ファイル内容をコピー。
4. `StarterGui/MainUI`配下に TextLabel を作成:
   - CoinDisplay / RoomDisplay / MessageDisplay / FoundCounter / RecordingOverlay
5. `Workspace/Rooms` に `Room001`～`Room005` を Model で作る。
6. 各違和感Partに属性を追加:
   - `IsAnomaly=true`, `RoomId=1..5`, `AnomalyName="ReverseClock"` など。
7. `Workspace/Lobby` に
   - 部屋入口Part
   - AI装置Part
   - 今週の採用コメントボードPart
   - 各アップグレード購入ボタンPart
   を配置。

## 3) テスト手順
- Play Soloで開始。
- Coin表示が0で出るか確認。
- 違和感Partクリックで +10 / レア +60 を確認。
- 3つ以上見つけて「クリア！」表示を確認。
- AI生成(Remote呼び出し)で3秒後に完了表示。
- 購入(Remote呼び出し)でコイン減少と重複購入不可を確認。

## 4) よく起きるバグと対処
- ClickDetectorが反応しない: 対象Partに `IsAnomaly=true` 属性を付与。
- UIが出ない: `MainUI` と TextLabel 名を一致させる。
- セーブ失敗警告: StudioのAPI設定未有効でも警告のみで進行可能。

## 5) 今後アップデート案
- 本物のDataStore自動保存/再接続処理。
- ボードの週替わり更新自動化。
- AI生成結果の3Dテンプレ差し替え。
- 難易度・部屋数・ランキング拡張。

## 6) Shorts撮影シーン案
- 開始1秒: 「違和感を3つ探せ！」
- 10秒以内に1つ目発見演出。
- クリア瞬間 + 次部屋予告。
- 「次の違和感コメント募集」をボード前で表示。
