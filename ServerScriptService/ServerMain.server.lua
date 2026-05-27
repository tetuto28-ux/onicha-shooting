-- Spot-the-difference ("Machigai-sagashi").
-- The server only builds the world: one wide, walkable, enclosed map with
-- interior dividers (so a single screenshot can't capture everything) and a set
-- of ordinary furniture objects. Every object is a Model tagged "Inspectable".
-- The baseline (types + colours) is randomised, and re-randomised on replay.
-- All game logic (study, per-round change, finding, lives, score) is on the
-- client, so the server stays small and robust.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MAP_HALF_X = 50
local MAP_HALF_Z = 38
local WALL_HEIGHT = 17

local function ensureRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
    remotes.Name = "Remotes"
    remotes.Parent = ReplicatedStorage

    local remote = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = remotes
    return remote
end

local UIMessageEvent = ensureRemote("UIMessageEvent")
local ReplayEvent = ensureRemote("ReplayEvent")

local function build(parent, def)
    local p = Instance.new("Part")
    p.Name = def.name or "Part"
    p.Anchored = true
    p.CanCollide = def.canCollide == true
    p.Size = def.size
    p.Color = def.color or Color3.fromRGB(200, 200, 200)
    p.Material = def.material or Enum.Material.SmoothPlastic
    p.Transparency = def.transparency or 0
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    if def.shape then
        p.Shape = def.shape
    end
    if typeof(def.pos) == "CFrame" then
        p.CFrame = def.pos
    else
        p.CFrame = CFrame.new(def.pos or Vector3.new())
    end
    if def.orient then
        p.CFrame = p.CFrame * CFrame.Angles(math.rad(def.orient.X), math.rad(def.orient.Y), math.rad(def.orient.Z))
    end
    p.Parent = parent
    return p
end

local function scenery(parent, name, position, size, color, material)
    return build(parent, { name = name, pos = position, size = size, color = color, material = material or Enum.Material.SmoothPlastic, canCollide = true })
end

-- ---------------------------------------------------------------------------
-- Ordinary furniture objects. `color` tints the main body so the baseline
-- differs each play. Each object returns its primary (anchor) part.
-- ---------------------------------------------------------------------------
local DECOY_TYPES = { "Sofa", "Desk", "Lamp", "Plant", "Painting", "Crate", "TV", "Chair", "Vase", "Bookshelf", "Barrel", "Statue", "Clock", "Bench" }

local function darken(color, amount)
    return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function buildDecoy(parent, name, pos, color)
    local model = Instance.new("Model")
    model.Name = name
    model:SetAttribute("Inspectable", true)
    model.Parent = parent

    local primary

    if name == "Sofa" then
        primary = build(model, { name = "Base", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(7, 1.6, 3.2), color = color, material = Enum.Material.Fabric })
        build(model, { name = "Back", pos = pos + Vector3.new(0, 2.3, -1.3), size = Vector3.new(7, 2, 0.8), color = color, material = Enum.Material.Fabric })
    elseif name == "Desk" then
        primary = build(model, { name = "Top", pos = pos + Vector3.new(0, 2.4, 0), size = Vector3.new(7, 0.5, 4), color = color, material = Enum.Material.Wood })
        build(model, { name = "Body", pos = pos + Vector3.new(0, 1.1, 0), size = Vector3.new(6.4, 2.2, 3.4), color = darken(color, 0.2), material = Enum.Material.Wood })
    elseif name == "Lamp" then
        primary = build(model, { name = "Pole", pos = pos + Vector3.new(0, 2.6, 0), size = Vector3.new(0.6, 5.2, 0.6), color = darken(color, 0.4), material = Enum.Material.Metal })
        build(model, { name = "Shade", pos = pos + Vector3.new(0, 5.4, 0), size = Vector3.new(2.6, 1.6, 2.6), color = color, material = Enum.Material.Neon })
    elseif name == "Plant" then
        primary = build(model, { name = "Pot", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(2, 2, 2), color = color, material = Enum.Material.Slate })
        build(model, { name = "Leaves", pos = pos + Vector3.new(0, 3.2, 0), size = Vector3.new(4, 4, 4), color = Color3.fromRGB(72, 140, 70), material = Enum.Material.Grass, shape = Enum.PartType.Ball })
    elseif name == "Painting" then
        primary = build(model, { name = "Frame", pos = pos + Vector3.new(0, 5, 0), size = Vector3.new(5, 4, 0.5), color = darken(color, 0.5), material = Enum.Material.Wood })
        build(model, { name = "Canvas", pos = pos + Vector3.new(0, 5, 0.2), size = Vector3.new(4.2, 3.2, 0.2), color = color, material = Enum.Material.SmoothPlastic })
    elseif name == "Crate" then
        primary = build(model, { name = "Box", pos = pos + Vector3.new(0, 1.6, 0), size = Vector3.new(3.2, 3.2, 3.2), color = color, material = Enum.Material.WoodPlanks })
    elseif name == "TV" then
        primary = build(model, { name = "Screen", pos = pos + Vector3.new(0, 3.4, 0), size = Vector3.new(5.2, 3, 0.5), color = darken(color, 0.6), material = Enum.Material.Glass })
        build(model, { name = "Stand", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(1, 2.4, 1), color = darken(color, 0.4), material = Enum.Material.Metal })
    elseif name == "Chair" then
        primary = build(model, { name = "Seat", pos = pos + Vector3.new(0, 1.8, 0), size = Vector3.new(2.6, 0.5, 2.6), color = color, material = Enum.Material.Wood })
        build(model, { name = "Back", pos = pos + Vector3.new(0, 3, -1.05), size = Vector3.new(2.6, 2.4, 0.4), color = color, material = Enum.Material.Wood })
    elseif name == "Vase" then
        primary = build(model, { name = "Body", pos = pos + Vector3.new(0, 1.8, 0), size = Vector3.new(2, 3.6, 2), color = color, material = Enum.Material.Marble })
        build(model, { name = "Neck", pos = pos + Vector3.new(0, 3.8, 0), size = Vector3.new(1, 0.8, 1), color = darken(color, 0.2), material = Enum.Material.Marble })
    elseif name == "Bookshelf" then
        primary = build(model, { name = "Body", pos = pos + Vector3.new(0, 3, 0), size = Vector3.new(5, 6, 1.6), color = color, material = Enum.Material.Wood })
        build(model, { name = "Books1", pos = pos + Vector3.new(0, 2, 0.3), size = Vector3.new(4.4, 1, 1.2), color = Color3.fromRGB(180, 90, 80), material = Enum.Material.SmoothPlastic })
        build(model, { name = "Books2", pos = pos + Vector3.new(0, 4, 0.3), size = Vector3.new(4.4, 1, 1.2), color = Color3.fromRGB(90, 130, 180), material = Enum.Material.SmoothPlastic })
    elseif name == "Barrel" then
        primary = build(model, { name = "Body", pos = pos + Vector3.new(0, 2, 0), size = Vector3.new(3, 4, 3), color = color, material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 0, 90) })
    elseif name == "Statue" then
        primary = build(model, { name = "Pedestal", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(2.4, 2, 2.4), color = darken(color, 0.3), material = Enum.Material.Marble })
        build(model, { name = "Figure", pos = pos + Vector3.new(0, 3.6, 0), size = Vector3.new(1.6, 3.2, 1.6), color = color, material = Enum.Material.Marble })
        build(model, { name = "Head", pos = pos + Vector3.new(0, 5.6, 0), size = Vector3.new(1.4, 1.4, 1.4), color = color, material = Enum.Material.Marble, shape = Enum.PartType.Ball })
    elseif name == "Clock" then
        primary = build(model, { name = "Frame", pos = pos + Vector3.new(0, 5, 0), size = Vector3.new(0.5, 3.6, 3.6), color = darken(color, 0.4), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })
        build(model, { name = "Face", pos = pos + Vector3.new(0, 5, 0.1), size = Vector3.new(0.5, 3, 3), color = color, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })
    else -- "Bench"
        primary = build(model, { name = "Seat", pos = pos + Vector3.new(0, 1.4, 0), size = Vector3.new(6, 0.5, 2), color = color, material = Enum.Material.Wood })
        build(model, { name = "LegL", pos = pos + Vector3.new(-2.4, 0.7, 0), size = Vector3.new(0.6, 1.4, 1.8), color = darken(color, 0.3), material = Enum.Material.Wood })
        build(model, { name = "LegR", pos = pos + Vector3.new(2.4, 0.7, 0), size = Vector3.new(0.6, 1.4, 1.8), color = darken(color, 0.3), material = Enum.Material.Wood })
    end

    model.PrimaryPart = primary
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end
    return model
end

-- Slots spread across the four quadrants so the player must walk to see them.
local SLOTS = {
    Vector3.new(-40, 0, -28), Vector3.new(-26, 0, -30), Vector3.new(-12, 0, -26),
    Vector3.new(12, 0, -30), Vector3.new(26, 0, -28), Vector3.new(42, 0, -26),
    Vector3.new(-42, 0, -8), Vector3.new(-28, 0, -12), Vector3.new(40, 0, -10), Vector3.new(28, 0, -6),
    Vector3.new(-40, 0, 26), Vector3.new(-26, 0, 30), Vector3.new(-10, 0, 28),
    Vector3.new(12, 0, 30), Vector3.new(28, 0, 28), Vector3.new(42, 0, 26),
    Vector3.new(0, 0, 12), Vector3.new(40, 0, 8),
}

local PALETTE = {
    Color3.fromRGB(196, 116, 92), Color3.fromRGB(110, 142, 196), Color3.fromRGB(120, 176, 120),
    Color3.fromRGB(206, 178, 96), Color3.fromRGB(170, 120, 196), Color3.fromRGB(206, 132, 150),
    Color3.fromRGB(120, 188, 196), Color3.fromRGB(176, 176, 188), Color3.fromRGB(150, 110, 88),
    Color3.fromRGB(214, 150, 90),
}

local function shuffled(list)
    local copy = table.clone(list)
    for i = #copy, 2, -1 do
        local j = math.random(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

local function buildMap(root)
    local floorColor = Color3.fromRGB(96, 100, 116)
    local wallColor = Color3.fromRGB(116, 122, 142)

    scenery(root, "Floor", Vector3.new(0, 0, 0), Vector3.new(MAP_HALF_X * 2, 1, MAP_HALF_Z * 2), floorColor, Enum.Material.WoodPlanks)
    scenery(root, "WallN", Vector3.new(0, WALL_HEIGHT / 2, -MAP_HALF_Z), Vector3.new(MAP_HALF_X * 2, WALL_HEIGHT, 1), wallColor)
    scenery(root, "WallS", Vector3.new(0, WALL_HEIGHT / 2, MAP_HALF_Z), Vector3.new(MAP_HALF_X * 2, WALL_HEIGHT, 1), wallColor)
    scenery(root, "WallW", Vector3.new(-MAP_HALF_X, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, MAP_HALF_Z * 2), wallColor)
    scenery(root, "WallE", Vector3.new(MAP_HALF_X, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, MAP_HALF_Z * 2), wallColor)

    -- Interior dividers (with gaps) break sight lines so one screenshot is not enough.
    scenery(root, "DivA", Vector3.new(0, WALL_HEIGHT / 2, -22), Vector3.new(1, WALL_HEIGHT, 32), darken(wallColor, 0.1))
    scenery(root, "DivB", Vector3.new(22, WALL_HEIGHT / 2, 6), Vector3.new(44, WALL_HEIGHT, 1), darken(wallColor, 0.1))
    scenery(root, "DivC", Vector3.new(-26, WALL_HEIGHT / 2, 8), Vector3.new(34, WALL_HEIGHT, 1), darken(wallColor, 0.1))
end

local function populate(root)
    local types = shuffled(DECOY_TYPES)
    for i, slot in ipairs(SLOTS) do
        local typeName = types[((i - 1) % #types) + 1]
        local color = PALETTE[math.random(1, #PALETTE)]
        buildDecoy(root, typeName, slot, color)
    end
end

local function buildWorld()
    pcall(function()
        Lighting.ClockTime = 14
        Lighting.Brightness = 2.2
        Lighting.Ambient = Color3.fromRGB(140, 146, 160)
        Lighting.OutdoorAmbient = Color3.fromRGB(120, 128, 150)
        Lighting.FogEnd = 600
    end)

    local oldDemo = Workspace:FindFirstChild("OnichaShootingDemo")
    if oldDemo then
        oldDemo:Destroy()
    end

    local root = Instance.new("Folder")
    root.Name = "OnichaShootingDemo"
    root.Parent = Workspace

    local mapFolder = Instance.new("Folder")
    mapFolder.Name = "Map"
    mapFolder.Parent = root

    local objectsFolder = Instance.new("Folder")
    objectsFolder.Name = "Objects"
    objectsFolder.Parent = root

    local okMap, errMap = pcall(buildMap, mapFolder)
    if not okMap then
        warn("[buildWorld] map failed: " .. tostring(errMap))
    end
    local okObj, errObj = pcall(populate, objectsFolder)
    if not okObj then
        warn("[buildWorld] objects failed: " .. tostring(errObj))
    end
end

local function spawnCFrame()
    return CFrame.new(Vector3.new(0, 5, 30), Vector3.new(0, 4, 0))
end

local function teleport(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.CFrame = spawnCFrame()
    end
end

local function initPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.3)
        teleport(player)
    end)
    if player.Character then
        teleport(player)
    end
    UIMessageEvent:FireClient(player, { kind = "WorldReady" })
end

local okWorld, errWorld = pcall(buildWorld)
if not okWorld then
    warn("[ServerMain] buildWorld error: " .. tostring(errWorld))
end

if not RunService:IsRunning() then
    return
end

Players.PlayerAdded:Connect(initPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(initPlayer, player)
end

ReplayEvent.OnServerEvent:Connect(function(player)
    pcall(buildWorld)
    for _, p in ipairs(Players:GetPlayers()) do
        teleport(p)
        UIMessageEvent:FireClient(p, { kind = "WorldReady" })
    end
end)
