local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ROOM_SPACING = 90
local ROOM_WIDTH = 44
local ROOM_DEPTH = 54
local WALL_HEIGHT = 18

local serverClickHooked = setmetatable({}, { __mode = "k" })
local serverTouchCooldown = {}

local roomConfigs = {
    {
        id = 1,
        title = "Room 001 - Strange Lobby",
        origin = Vector3.new(0, 0, -18),
        wallColor = Color3.fromRGB(78, 101, 138),
        floorColor = Color3.fromRGB(78, 88, 108),
        anomalies = {
            { name = "ReverseClock", label = "Reverse Clock", pos = Vector3.new(-12, 4, -31), size = Vector3.new(4, 4, 1), color = Color3.fromRGB(255, 224, 92), reward = 10, shape = "Cylinder" },
            { name = "CeilingChair", label = "Ceiling Chair", pos = Vector3.new(0, 9, -22), size = Vector3.new(4, 2, 4), color = Color3.fromRGB(77, 170, 255), reward = 10 },
            { name = "MiniYatai", label = "Tiny Food Stall", pos = Vector3.new(12, 3, -18), size = Vector3.new(5, 4, 4), color = Color3.fromRGB(255, 127, 139), reward = 10 },
        },
    },
    {
        id = 2,
        title = "Room 002 - Kitchen Hotel",
        origin = Vector3.new(ROOM_SPACING, 0, -18),
        wallColor = Color3.fromRGB(92, 118, 101),
        floorColor = Color3.fromRGB(92, 89, 75),
        anomalies = {
            { name = "MiniSea", label = "Tiny Sea Fridge", pos = Vector3.new(ROOM_SPACING - 12, 3, -19), size = Vector3.new(5, 4, 4), color = Color3.fromRGB(77, 206, 255), reward = 10 },
            { name = "StarSink", label = "Star Sink", pos = Vector3.new(ROOM_SPACING, 3, -31), size = Vector3.new(5, 3, 2), color = Color3.fromRGB(255, 241, 90), reward = 10 },
            { name = "MiniHotel", label = "Mini Hotel", pos = Vector3.new(ROOM_SPACING + 12, 4, -17), size = Vector3.new(5, 6, 4), color = Color3.fromRGB(185, 120, 255), reward = 60 },
        },
    },
    {
        id = 3,
        title = "Room 003 - Mirror Hall",
        origin = Vector3.new(ROOM_SPACING * 2, 0, -18),
        wallColor = Color3.fromRGB(106, 91, 126),
        floorColor = Color3.fromRGB(83, 81, 105),
        anomalies = {
            { name = "MirrorArt", label = "Wrong Mirror Art", pos = Vector3.new(ROOM_SPACING * 2 - 12, 4, -31), size = Vector3.new(5, 5, 1), color = Color3.fromRGB(167, 230, 255), reward = 10 },
            { name = "MovingCurtainShadow", label = "Moving Shadow", pos = Vector3.new(ROOM_SPACING * 2, 3, -17), size = Vector3.new(4, 5, 2), color = Color3.fromRGB(33, 36, 46), reward = 10 },
            { name = "MiniElevator", label = "Mini Elevator", pos = Vector3.new(ROOM_SPACING * 2 + 12, 4, -31), size = Vector3.new(5, 6, 2), color = Color3.fromRGB(145, 168, 188), reward = 10 },
        },
    },
}

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

local function part(parent, name, position, size, color, material)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.Position = position
    p.Size = size
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local function labelBillboard(parent, text, height)
    local gui = Instance.new("BillboardGui")
    gui.Name = "Label"
    gui.AlwaysOnTop = true
    gui.Size = UDim2.new(0, 220, 0, 52)
    gui.StudsOffset = Vector3.new(0, height or 4, 0)
    gui.Parent = parent

    local label = Instance.new("TextLabel")
    label.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
    label.BackgroundTransparency = 0.15
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.Size = UDim2.fromScale(1, 1)
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Parent = gui
    return gui
end

local function decorateRoom(model, config)
    local origin = config.origin

    part(model, "Floor", origin, Vector3.new(ROOM_WIDTH, 1, ROOM_DEPTH), config.floorColor, Enum.Material.Plastic)
    part(model, "BackWall", origin + Vector3.new(0, WALL_HEIGHT / 2, -ROOM_DEPTH / 2), Vector3.new(ROOM_WIDTH, WALL_HEIGHT, 1), config.wallColor)
    part(model, "LeftWall", origin + Vector3.new(-ROOM_WIDTH / 2, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, ROOM_DEPTH), config.wallColor)
    part(model, "RightWall", origin + Vector3.new(ROOM_WIDTH / 2, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, ROOM_DEPTH), config.wallColor:Lerp(Color3.new(1, 1, 1), 0.25))
    part(model, "EntryPad", origin + Vector3.new(0, 0.65, 18), Vector3.new(12, 0.3, 8), Color3.fromRGB(225, 231, 245), Enum.Material.Neon)

    local sign = part(model, "RoomSign", origin + Vector3.new(0, 8, -ROOM_DEPTH / 2 + 0.7), Vector3.new(18, 5, 0.5), Color3.fromRGB(24, 29, 40))
    labelBillboard(sign, config.title, 4)

    part(model, "Desk", origin + Vector3.new(-13, 2, 6), Vector3.new(10, 3, 4), Color3.fromRGB(116, 78, 49), Enum.Material.Wood)
    part(model, "Table", origin + Vector3.new(10, 1.5, 3), Vector3.new(8, 2, 5), Color3.fromRGB(71, 54, 48), Enum.Material.Wood)
    part(model, "Lamp", origin + Vector3.new(14, 4, 3), Vector3.new(1.4, 4, 1.4), Color3.fromRGB(255, 235, 126), Enum.Material.Neon)
end

local function createAnomaly(room, config, info)
    local p = part(room, info.name, info.pos, info.size, info.color, Enum.Material.Neon)
    if info.shape == "Cylinder" then
        p.Shape = Enum.PartType.Cylinder
        p.Orientation = Vector3.new(0, 0, 90)
    end

    p:SetAttribute("IsAnomaly", true)
    p:SetAttribute("RoomId", config.id)
    p:SetAttribute("AnomalyName", info.name)
    p:SetAttribute("DisplayName", info.label)
    p:SetAttribute("Reward", info.reward)
    p:SetAttribute("Found", false)

    local click = Instance.new("ClickDetector")
    click.MaxActivationDistance = 120
    click.Parent = p

    local light = Instance.new("PointLight")
    light.Color = info.color
    light.Brightness = 1.5
    light.Range = 12
    light.Parent = p

    labelBillboard(p, info.label .. "\nClick or touch", math.max(info.size.Y + 1, 4))
    return p
end

local function buildWorld()
    Lighting.ClockTime = 15
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(130, 140, 160)

    local oldDemo = Workspace:FindFirstChild("OnichaShootingDemo")
    if oldDemo then
        oldDemo:Destroy()
    end

    local oldRooms = Workspace:FindFirstChild("Rooms")
    if oldRooms then
        oldRooms:Destroy()
    end

    local root = Instance.new("Folder")
    root.Name = "OnichaShootingDemo"
    root.Parent = Workspace

    local roomsFolder = Instance.new("Folder")
    roomsFolder.Name = "Rooms"
    roomsFolder.Parent = root

    for _, config in ipairs(roomConfigs) do
        local room = Instance.new("Model")
        room.Name = string.format("Room%03d", config.id)
        room.Parent = roomsFolder

        decorateRoom(room, config)
        for _, info in ipairs(config.anomalies) do
            createAnomaly(room, config, info)
        end
    end
end

local function spawnForRoom(roomId)
    local index = math.clamp(tonumber(roomId) or 1, 1, #roomConfigs)
    local origin = roomConfigs[index].origin
    return CFrame.new(origin + Vector3.new(0, 5, 20), origin + Vector3.new(0, 3, -20))
end

local function moveCharacterToRoom(player, roomId)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.CFrame = spawnForRoom(roomId)
    end
end

local function initPlayer(player)
    local save = SaveService:Load(player)
    if RunService:IsStudio() then
        save.currentRoom = 1
    end

    CoinService:InitPlayer(player, save.coins)
    RoomService:InitPlayer(player, save.currentRoom)
    UpgradeService:InitPlayer(player, save.upgrades)

    player.CharacterAdded:Connect(function()
        task.wait(0.25)
        moveCharacterToRoom(player, RoomService:GetCurrentRoom(player))
    end)

    UIMessageEvent:FireClient(player, {
        kind = "RoomStart",
        text = "Find 3 odd things.",
        room = RoomService:GetCurrentRoom(player),
    })
end

local function awardAnomaly(player, roomId, anomalyName, anomalyInstance, skipDistanceCheck)
    if not RoomService.State[player] then
        initPlayer(player)
    end

    if not skipDistanceCheck and AntiExploitService:IsOnCooldown(player, "find") then
        return
    end
    if not AntiExploitService:ValidateAnomalyRequest(anomalyInstance) then
        return
    end
    if not skipDistanceCheck and not AntiExploitService:IsPlayerNearInstance(player, anomalyInstance, 120) then
        return
    end

    local canonicalRoomId = tonumber(anomalyInstance:GetAttribute("RoomId")) or 1
    local canonicalAnomalyName = anomalyInstance:GetAttribute("AnomalyName") or anomalyInstance.Name
    if canonicalRoomId ~= roomId or canonicalAnomalyName ~= anomalyName then
        return
    end

    local first, count = RoomService:MarkFound(player, roomId, canonicalAnomalyName)
    if not first then
        return
    end

    local reward, isRare = AnomalyService:GetReward(canonicalAnomalyName)
    CoinService:AddCoins(player, reward)
    anomalyInstance.Transparency = 0.55
    anomalyInstance:SetAttribute("Found", true)

    UIMessageEvent:FireClient(player, {
        kind = "Found",
        text = "Found! +" .. tostring(reward),
        found = count,
        isRare = isRare,
    })

    if RoomService:IsRoomCleared(player, roomId) then
        CoinService:AddCoins(player, 50)
        local nextRoom = RoomService:AdvanceRoom(player)
        RoomClearedEvent:FireClient(player, roomId, nextRoom)
        UIMessageEvent:FireClient(player, {
            kind = "Clear",
            text = "Room clear! +50",
            room = nextRoom,
        })
        task.delay(1.0, function()
            moveCharacterToRoom(player, nextRoom)
        end)
    end
end

local function hookServerAnomalyClick(instance)
    if not instance:IsA("BasePart") then
        return
    end
    if instance:GetAttribute("IsAnomaly") ~= true then
        return
    end
    if serverClickHooked[instance] then
        return
    end

    local click = instance:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
    click.MaxActivationDistance = 120
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
        if not player then
            return
        end

        local key = tostring(player.UserId) .. ":" .. instance:GetFullName()
        local now = os.clock()
        if serverTouchCooldown[key] and now - serverTouchCooldown[key] < 0.6 then
            return
        end
        serverTouchCooldown[key] = now

        local roomId = instance:GetAttribute("RoomId") or 1
        local anomalyName = instance:GetAttribute("AnomalyName") or instance.Name
        awardAnomaly(player, roomId, anomalyName, instance, true)
    end)
end

buildWorld()

Players.PlayerAdded:Connect(initPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(initPlayer, player)
end

AnomalyFoundEvent.OnServerEvent:Connect(function(player, roomId, anomalyName, anomalyInstance)
    awardAnomaly(player, roomId, anomalyName, anomalyInstance, false)
end)

for _, descendant in ipairs(Workspace:GetDescendants()) do
    hookServerAnomalyClick(descendant)
end
Workspace.DescendantAdded:Connect(hookServerAnomalyClick)

GenerateAnomalyEvent.OnServerEvent:Connect(function(player)
    if AntiExploitService:IsOnCooldown(player, "generate") then
        return
    end
    UIMessageEvent:FireClient(player, { kind = "Warn", text = "Generator coming soon." })
end)

PurchaseUpgradeEvent.OnServerEvent:Connect(function(player, upgradeId)
    if AntiExploitService:IsOnCooldown(player, "upgrade") then
        return
    end
    local ok, info = UpgradeService:Purchase(player, upgradeId, CoinService)
    UIMessageEvent:FireClient(player, {
        kind = ok and "Upgrade" or "Warn",
        text = ok and (info.displayName .. " purchased!") or ("Purchase failed: " .. tostring(info)),
    })
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
