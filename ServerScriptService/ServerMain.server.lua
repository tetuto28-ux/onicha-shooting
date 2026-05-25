local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local serverClickHooked = {}
local serverTouchCooldown = {}

local function makePart(parent, name, position, size, color)
    local part = parent:FindFirstChild(name) or Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.Position = position
    part.Size = size
    part.Color = color
    part.Parent = parent
    return part
end

local function ensureDemoWorld()
    local rooms = Workspace:FindFirstChild("Rooms") or Instance.new("Folder")
    rooms.Name = "Rooms"
    rooms.Parent = Workspace

    local room = rooms:FindFirstChild("Room001") or Instance.new("Model")
    room.Name = "Room001"
    room.Parent = rooms

    makePart(room, "Room001Floor", Vector3.new(0, 0, -18), Vector3.new(42, 1, 42), Color3.fromRGB(82, 91, 110))
    makePart(room, "BackWall", Vector3.new(0, 8, -39), Vector3.new(42, 16, 1), Color3.fromRGB(155, 164, 184))
    makePart(room, "LeftWall", Vector3.new(-21, 8, -18), Vector3.new(1, 16, 42), Color3.fromRGB(135, 145, 165))
    makePart(room, "RightWall", Vector3.new(21, 8, -18), Vector3.new(1, 16, 42), Color3.fromRGB(135, 145, 165))

    local anomalies = {
        { name = "ReverseClock", position = Vector3.new(-10, 3, -18), color = Color3.fromRGB(255, 230, 90) },
        { name = "CeilingChair", position = Vector3.new(0, 6, -27), color = Color3.fromRGB(90, 180, 255) },
        { name = "MiniYatai", position = Vector3.new(10, 3, -18), color = Color3.fromRGB(255, 120, 120) },
    }

    for _, info in ipairs(anomalies) do
        local part = makePart(room, info.name, info.position, Vector3.new(4, 4, 4), info.color)
        part:SetAttribute("IsAnomaly", true)
        part:SetAttribute("RoomId", 1)
        part:SetAttribute("AnomalyName", info.name)
        part:SetAttribute("ServerClickHooked", nil)

        local click = part:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
        click.MaxActivationDistance = 100
        click.Parent = part
    end
end

ensureDemoWorld()

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

local modules = script.Parent:WaitForChild("Modules")
local CoinService = require(modules.CoinService)
local RoomService = require(modules.RoomService)
local AnomalyService = require(modules.AnomalyService)
local UpgradeService = require(modules.UpgradeService)
local SaveService = require(modules.SaveService)
local AntiExploitService = require(modules.AntiExploitService)

local function initPlayer(player)
    local save = SaveService:Load(player)
    if RunService:IsStudio() then
        save.currentRoom = 1
    end
    CoinService:InitPlayer(player, save.coins)
    RoomService:InitPlayer(player, save.currentRoom)
    UpgradeService:InitPlayer(player, save.upgrades)
    UIMessageEvent:FireClient(player, {kind = "RoomStart", text = "違和感を3つ探せ！", room = RoomService:GetCurrentRoom(player)})
end

Players.PlayerAdded:Connect(initPlayer)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(initPlayer, player)
end

local function awardAnomaly(player, roomId, anomalyName, anomalyInstance, skipDistanceCheck)
    if not RoomService.State[player] then
        initPlayer(player)
    end

    if not skipDistanceCheck and AntiExploitService:IsOnCooldown(player, "find") then return end
    if not AntiExploitService:ValidateAnomalyRequest(anomalyInstance) then return end
    if not skipDistanceCheck and not AntiExploitService:IsPlayerNearInstance(player, anomalyInstance, 35) then return end

    local canonicalRoomId = tonumber(anomalyInstance:GetAttribute("RoomId")) or 1
    local canonicalAnomalyName = anomalyInstance:GetAttribute("AnomalyName") or anomalyInstance.Name

    if canonicalRoomId ~= roomId then return end
    if canonicalAnomalyName ~= anomalyName then return end
    if not RoomService:IsCurrentRoom(player, roomId) then return end
    if not RoomService:IsValidAnomalyForRoom(player, roomId, canonicalAnomalyName) then return end

    local first, count = RoomService:MarkFound(player, roomId, canonicalAnomalyName)
    if not first then return end
    local reward, isRare = AnomalyService:GetReward(canonicalAnomalyName)
    CoinService:AddCoins(player, reward)
    anomalyInstance.Transparency = 0.45
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
end

AnomalyFoundEvent.OnServerEvent:Connect(function(player, roomId, anomalyName, anomalyInstance)
    awardAnomaly(player, roomId, anomalyName, anomalyInstance, false)
end)

local function hookServerAnomalyClick(instance)
    if not instance:IsA("BasePart") then return end
    if instance:GetAttribute("IsAnomaly") ~= true then return end
    if serverClickHooked[instance] then return end

    local click = instance:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
    click.MaxActivationDistance = 100
    click.Parent = instance
    serverClickHooked[instance] = true

    click.MouseClick:Connect(function(player)
        local roomId = instance:GetAttribute("RoomId") or 1
        local anomalyName = instance:GetAttribute("AnomalyName") or instance.Name
        awardAnomaly(player, roomId, anomalyName, instance, true)
    end)

    instance.Touched:Connect(function(hit)
        local character = hit.Parent
        local player = character and Players:GetPlayerFromCharacter(character)
        if not player then return end

        local key = player.UserId .. ":" .. instance.Name
        local now = os.clock()
        if serverTouchCooldown[key] and now - serverTouchCooldown[key] < 0.5 then
            return
        end
        serverTouchCooldown[key] = now

        local roomId = instance:GetAttribute("RoomId") or 1
        local anomalyName = instance:GetAttribute("AnomalyName") or instance.Name
        awardAnomaly(player, roomId, anomalyName, instance, true)
    end)
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
    hookServerAnomalyClick(descendant)
end

Workspace.DescendantAdded:Connect(hookServerAnomalyClick)

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
    RoomService:CleanupPlayer(player)
    UpgradeService:CleanupPlayer(player)
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        SaveService:Save(player, {
            coins = CoinService:GetCoins(player),
            currentRoom = RoomService:GetCurrentRoom(player),
            upgrades = UpgradeService.Purchased[player] or {},
        })
    end
end)
