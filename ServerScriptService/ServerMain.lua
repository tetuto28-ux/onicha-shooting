local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensureRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
    remotes.Name = "Remotes"
    remotes.Parent = ReplicatedStorage
    local remote = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = remotes
    return remote
end

local AnomalyFoundEvent = ensureRemote("AnomalyFoundEvent")
local RoomClearedEvent = ensureRemote("RoomClearedEvent")
local GenerateAnomalyEvent = ensureRemote("GenerateAnomalyEvent")
local PurchaseUpgradeEvent = ensureRemote("PurchaseUpgradeEvent")
local UIMessageEvent = ensureRemote("UIMessageEvent")

local CoinService = require(script.Modules.CoinService)
local RoomService = require(script.Modules.RoomService)
local AnomalyService = require(script.Modules.AnomalyService)
local UpgradeService = require(script.Modules.UpgradeService)
local SaveService = require(script.Modules.SaveService)
local AntiExploitService = require(script.Modules.AntiExploitService)

Players.PlayerAdded:Connect(function(player)
    local save = SaveService:Load(player)
    CoinService:InitPlayer(player, save.coins)
    RoomService:InitPlayer(player, save.currentRoom)
    UpgradeService:InitPlayer(player, save.upgrades)
    UIMessageEvent:FireClient(player, {kind = "RoomStart", text = "違和感を3つ探せ！", room = RoomService:GetCurrentRoom(player)})
end)

AnomalyFoundEvent.OnServerEvent:Connect(function(player, roomId, anomalyName, anomalyInstance)
    if AntiExploitService:IsOnCooldown(player, "find") then return end
    if not AntiExploitService:ValidateAnomalyRequest(anomalyInstance) then return end
    local first, count = RoomService:MarkFound(player, roomId, anomalyName)
    if not first then return end
    local reward, isRare = AnomalyService:GetReward(anomalyName)
    CoinService:AddCoins(player, reward)
    UIMessageEvent:FireClient(player, {kind = "Found", text = "見つけた！ +" .. reward, found = count, isRare = isRare})
    if isRare then
        UIMessageEvent:FireClient(player, {kind = "Rare", text = "レア違和感発見！"})
    end
    if RoomService:IsRoomCleared(player, roomId) then
        CoinService:AddCoins(player, 50)
        local nextRoom = RoomService:AdvanceRoom(player)
        RoomClearedEvent:FireClient(player, roomId, nextRoom)
        UIMessageEvent:FireClient(player, {kind = "Clear", text = "クリア！ +50"})
    end
end)

GenerateAnomalyEvent.OnServerEvent:Connect(function(player)
    if AntiExploitService:IsOnCooldown(player, "generate") then return end
    if not CoinService:SpendCoins(player, 100) then
        UIMessageEvent:FireClient(player, {kind = "Warn", text = "コイン不足 (100必要)"})
        return
    end
    UIMessageEvent:FireClient(player, {kind = "Generating", text = "AIが違和感を生成中..."})
    task.wait(3)
    local currentRoom = RoomService:GetCurrentRoom(player)
    local candidates = {"TVStaff", "WalkingChair", "EmbeddedDoor", "SushiRail", "MiniHotel"}
    local selected = candidates[math.random(1, #candidates)]
    RoomService:AddGeneratedAnomaly(player, currentRoom, selected)
    UIMessageEvent:FireClient(player, {kind = "GenerateDone", text = "生成完了！ " .. selected})
end)

PurchaseUpgradeEvent.OnServerEvent:Connect(function(player, upgradeId)
    if AntiExploitService:IsOnCooldown(player, "upgrade") then return end
    local ok, info = UpgradeService:Purchase(player, upgradeId, CoinService)
    if not ok then
        UIMessageEvent:FireClient(player, {kind = "Warn", text = "購入失敗: " .. tostring(info)})
        return
    end
    UIMessageEvent:FireClient(player, {kind = "Upgrade", text = info.displayName .. " 購入！"})
end)

Players.PlayerRemoving:Connect(function(player)
    SaveService:Save(player, {
        coins = CoinService:GetCoins(player),
        currentRoom = RoomService:GetCurrentRoom(player),
        upgrades = UpgradeService.Purchased[player] or {},
    })
end)
