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

-- Parts whose CFrame is updated every frame for a touch of life.
-- Each entry is a function(now) that moves something.
local animatedUpdaters = {}

local roomConfigs = {
    {
        id = 1,
        title = "Room 001 - Strange Lobby",
        origin = Vector3.new(0, 0, -18),
        wallColor = Color3.fromRGB(78, 101, 138),
        floorColor = Color3.fromRGB(78, 88, 108),
        anomalies = {
            { name = "ReverseClock", label = "Reverse Clock", pos = Vector3.new(-12, 6, -31), color = Color3.fromRGB(255, 224, 92), reward = 10 },
            { name = "CeilingChair", label = "Ceiling Chair", pos = Vector3.new(0, 12, -22), color = Color3.fromRGB(77, 170, 255), reward = 10 },
            { name = "MiniYatai", label = "Tiny Food Stall", pos = Vector3.new(13, 3, -16), color = Color3.fromRGB(255, 127, 139), reward = 10 },
        },
    },
    {
        id = 2,
        title = "Room 002 - Kitchen Hotel",
        origin = Vector3.new(ROOM_SPACING, 0, -18),
        wallColor = Color3.fromRGB(92, 118, 101),
        floorColor = Color3.fromRGB(92, 89, 75),
        anomalies = {
            { name = "MiniSea", label = "Tiny Sea Fridge", pos = Vector3.new(ROOM_SPACING - 13, 4, -19), color = Color3.fromRGB(77, 206, 255), reward = 10 },
            { name = "StarSink", label = "Star Sink", pos = Vector3.new(ROOM_SPACING, 3, -30), color = Color3.fromRGB(255, 241, 90), reward = 10 },
            { name = "MiniHotel", label = "Mini Hotel", pos = Vector3.new(ROOM_SPACING + 13, 4, -16), color = Color3.fromRGB(185, 120, 255), reward = 60 },
        },
    },
    {
        id = 3,
        title = "Room 003 - Mirror Hall",
        origin = Vector3.new(ROOM_SPACING * 2, 0, -18),
        wallColor = Color3.fromRGB(106, 91, 126),
        floorColor = Color3.fromRGB(83, 81, 105),
        anomalies = {
            { name = "MirrorArt", label = "Wrong Mirror Art", pos = Vector3.new(ROOM_SPACING * 2 - 13, 6, -31), color = Color3.fromRGB(167, 230, 255), reward = 10 },
            { name = "MovingCurtainShadow", label = "Moving Shadow", pos = Vector3.new(ROOM_SPACING * 2, 5, -29), color = Color3.fromRGB(33, 36, 46), reward = 10 },
            { name = "MiniElevator", label = "Mini Elevator", pos = Vector3.new(ROOM_SPACING * 2 + 13, 5, -31), color = Color3.fromRGB(145, 168, 188), reward = 10 },
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
local ReplayEvent = ensureRemote("ReplayEvent")

local modules = script.Parent:WaitForChild("Modules")
local CoinService = require(modules.CoinService)
local RoomService = require(modules.RoomService)
local AnomalyService = require(modules.AnomalyService)
local UpgradeService = require(modules.UpgradeService)
local SaveService = require(modules.SaveService)
local AntiExploitService = require(modules.AntiExploitService)

-- Generic builder used for every decorative / anomaly sub-part.
local function build(parent, def)
    local p = Instance.new("Part")
    p.Name = def.name or "Part"
    p.Anchored = true
    p.CanCollide = def.canCollide == true
    p.Size = def.size
    p.Color = def.color or Color3.fromRGB(200, 200, 200)
    p.Material = def.material or Enum.Material.SmoothPlastic
    p.Transparency = def.transparency or 0
    p.Reflectance = def.reflectance or 0
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

-- Decorative collidable part for room furniture.
local function part(parent, name, position, size, color, material)
    return build(parent, {
        name = name,
        pos = position,
        size = size,
        color = color,
        material = material or Enum.Material.SmoothPlastic,
        canCollide = true,
    })
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

-- A hidden "Found!" badge that pops up once the anomaly is discovered.
local function foundBadge(parent, text)
    local gui = Instance.new("BillboardGui")
    gui.Name = "FoundLabel"
    gui.AlwaysOnTop = true
    gui.Enabled = false
    gui.Size = UDim2.new(0, 180, 0, 46)
    gui.StudsOffset = Vector3.new(0, 3.2, 0)
    gui.Parent = parent

    local label = Instance.new("TextLabel")
    label.BackgroundColor3 = Color3.fromRGB(34, 153, 84)
    label.BackgroundTransparency = 0.1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.Size = UDim2.fromScale(1, 1)
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = label
    return gui
end

local function decorateRoom(model, config)
    local origin = config.origin

    part(model, "Floor", origin, Vector3.new(ROOM_WIDTH, 1, ROOM_DEPTH), config.floorColor, Enum.Material.Plastic)
    part(model, "BackWall", origin + Vector3.new(0, WALL_HEIGHT / 2, -ROOM_DEPTH / 2), Vector3.new(ROOM_WIDTH, WALL_HEIGHT, 1), config.wallColor)
    part(model, "LeftWall", origin + Vector3.new(-ROOM_WIDTH / 2, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, ROOM_DEPTH), config.wallColor)
    part(model, "RightWall", origin + Vector3.new(ROOM_WIDTH / 2, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, ROOM_DEPTH), config.wallColor:Lerp(Color3.new(1, 1, 1), 0.25))
    part(model, "EntryPad", origin + Vector3.new(0, 0.65, 18), Vector3.new(12, 0.3, 8), Color3.fromRGB(225, 231, 245), Enum.Material.Neon)

    -- A rug so the floor reads as a furnished room rather than a flat slab.
    part(model, "Rug", origin + Vector3.new(0, 0.55, 2), Vector3.new(20, 0.1, 16), config.wallColor:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)

    local sign = part(model, "RoomSign", origin + Vector3.new(0, 8, -ROOM_DEPTH / 2 + 0.7), Vector3.new(18, 5, 0.5), Color3.fromRGB(24, 29, 40))
    labelBillboard(sign, config.title, 4)

    -- Normal furniture for context.
    part(model, "Desk", origin + Vector3.new(-13, 2, 6), Vector3.new(10, 3, 4), Color3.fromRGB(116, 78, 49), Enum.Material.Wood)
    part(model, "Table", origin + Vector3.new(10, 1.5, 3), Vector3.new(8, 2, 5), Color3.fromRGB(71, 54, 48), Enum.Material.Wood)
    part(model, "Lamp", origin + Vector3.new(14, 4, 3), Vector3.new(1.4, 4, 1.4), Color3.fromRGB(255, 235, 126), Enum.Material.Neon)

    -- A potted plant.
    part(model, "PlantPot", origin + Vector3.new(-16, 1.5, -6), Vector3.new(2, 3, 2), Color3.fromRGB(120, 72, 48), Enum.Material.Slate)
    part(model, "PlantLeaves", origin + Vector3.new(-16, 4, -6), Vector3.new(4, 4, 4), Color3.fromRGB(72, 140, 70), Enum.Material.Grass)

    -- A simple framed picture on the back wall (a "normal" object near the odd one).
    part(model, "PictureFrame", origin + Vector3.new(8, 9, -ROOM_DEPTH / 2 + 0.9), Vector3.new(6, 4.5, 0.4), Color3.fromRGB(40, 30, 22), Enum.Material.Wood)
    part(model, "PictureArt", origin + Vector3.new(8, 9, -ROOM_DEPTH / 2 + 1.1), Vector3.new(5, 3.6, 0.2), Color3.fromRGB(150, 180, 210), Enum.Material.SmoothPlastic)
end

-- ---------------------------------------------------------------------------
-- Anomaly model builders. Each returns the model's primary (anchor) part.
-- All sub-parts are tagged afterwards, so any part of the model is clickable.
-- ---------------------------------------------------------------------------

local function buildReverseClock(model, info)
    local c = info.pos
    local cream = Color3.fromRGB(244, 240, 226)

    local rim = build(model, { name = "Rim", pos = c - Vector3.new(0, 0, 0.2), size = Vector3.new(0.4, 4.6, 4.6), color = Color3.fromRGB(60, 60, 70), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })
    local face = build(model, { name = "Face", pos = c, size = Vector3.new(0.4, 4, 4), color = cream, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })

    -- Hour ticks at 12 / 3 / 6 / 9.
    for _, off in ipairs({ Vector3.new(0, 1.6, 0), Vector3.new(1.6, 0, 0), Vector3.new(0, -1.6, 0), Vector3.new(-1.6, 0, 0) }) do
        build(model, { name = "Tick", pos = c + off + Vector3.new(0, 0, 0.3), size = Vector3.new(0.3, 0.3, 0.18), color = Color3.fromRGB(40, 40, 50) })
    end

    build(model, { name = "Hub", pos = c + Vector3.new(0, 0, 0.32), size = Vector3.new(0.5, 0.5, 0.3), color = Color3.fromRGB(40, 40, 50), shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })

    -- The two hands pivot about the clock centre and sweep BACKWARDS.
    local centre = CFrame.new(c.X, c.Y, c.Z + 0.4)
    local minuteHand = build(model, { name = "MinuteHand", pos = centre * CFrame.new(0, 0.8, 0), size = Vector3.new(0.18, 1.7, 0.12), color = Color3.fromRGB(30, 30, 40) })
    local secondHand = build(model, { name = "SecondHand", pos = centre * CFrame.new(0, 1.0, 0), size = Vector3.new(0.1, 2.1, 0.1), color = Color3.fromRGB(200, 60, 60) })

    table.insert(animatedUpdaters, function(now)
        minuteHand.CFrame = centre * CFrame.Angles(0, 0, math.rad(20) * now) * CFrame.new(0, 0.8, 0)
        secondHand.CFrame = centre * CFrame.Angles(0, 0, math.rad(80) * now) * CFrame.new(0, 1.0, 0)
    end)

    return face
end

local function buildCeilingChair(model, info)
    local c = info.pos
    local wood = Color3.fromRGB(150, 96, 56)

    -- Built upside-down: the seat is up high, legs point toward the ceiling.
    local seat = build(model, { name = "Seat", pos = c, size = Vector3.new(3, 0.5, 3), color = wood, material = Enum.Material.Wood })
    for _, dx in ipairs({ -1.2, 1.2 }) do
        for _, dz in ipairs({ -1.2, 1.2 }) do
            build(model, { name = "Leg", pos = c + Vector3.new(dx, 1.5, dz), size = Vector3.new(0.4, 3, 0.4), color = wood, material = Enum.Material.Wood })
        end
    end
    -- Backrest hangs downward because the chair is flipped.
    build(model, { name = "Back", pos = c + Vector3.new(0, -1.8, -1.3), size = Vector3.new(3, 3, 0.4), color = wood, material = Enum.Material.Wood })

    local basePivot = CFrame.new(c)
    table.insert(animatedUpdaters, function(now)
        model:PivotTo(basePivot * CFrame.new(0, math.sin(now * 1.6) * 0.4, 0) * CFrame.Angles(0, 0, math.rad(math.sin(now) * 5)))
    end)

    return seat
end

local function buildMiniYatai(model, info)
    local c = info.pos

    local counter = build(model, { name = "Counter", pos = c, size = Vector3.new(5, 2.4, 2.4), color = Color3.fromRGB(150, 92, 56), material = Enum.Material.Wood })
    build(model, { name = "CounterTop", pos = c + Vector3.new(0, 1.4, 0), size = Vector3.new(5.4, 0.4, 2.8), color = Color3.fromRGB(196, 150, 100), material = Enum.Material.WoodPlanks })
    build(model, { name = "PostL", pos = c + Vector3.new(-2.2, 3.2, 0), size = Vector3.new(0.3, 4, 0.3), color = Color3.fromRGB(90, 60, 40), material = Enum.Material.Wood })
    build(model, { name = "PostR", pos = c + Vector3.new(2.2, 3.2, 0), size = Vector3.new(0.3, 4, 0.3), color = Color3.fromRGB(90, 60, 40), material = Enum.Material.Wood })
    -- Striped roof.
    build(model, { name = "Roof", pos = c + Vector3.new(0, 5.3, 0), size = Vector3.new(6, 0.5, 3.4), color = Color3.fromRGB(210, 70, 78), material = Enum.Material.Fabric })
    build(model, { name = "RoofStripe", pos = c + Vector3.new(0, 5.55, 0), size = Vector3.new(6.1, 0.2, 1.1), color = Color3.fromRGB(245, 245, 245), material = Enum.Material.Fabric })
    -- Red paper lantern.
    build(model, { name = "Lantern", pos = c + Vector3.new(1.6, 4.4, 1.2), size = Vector3.new(1, 1.2, 1), color = Color3.fromRGB(220, 60, 50), material = Enum.Material.Neon, shape = Enum.PartType.Ball })

    return counter
end

local function buildMiniSea(model, info)
    local c = info.pos
    local white = Color3.fromRGB(236, 238, 240)

    local body = build(model, { name = "FridgeBody", pos = c, size = Vector3.new(3.4, 5.4, 3), color = white, material = Enum.Material.SmoothPlastic })
    -- Door swung open to the side.
    build(model, { name = "Door", pos = CFrame.new(c + Vector3.new(-2.4, 0, 1.4)) * CFrame.Angles(0, math.rad(60), 0), size = Vector3.new(0.3, 5.2, 2.8), color = white, material = Enum.Material.SmoothPlastic })
    build(model, { name = "Handle", pos = CFrame.new(c + Vector3.new(-2.4, 0, 2.4)) * CFrame.Angles(0, math.rad(60), 0), size = Vector3.new(0.2, 2, 0.2), color = Color3.fromRGB(150, 150, 160), material = Enum.Material.Metal })
    -- The little sea inside.
    build(model, { name = "Water", pos = c + Vector3.new(0, -0.4, 0.2), size = Vector3.new(2.6, 3.2, 2.2), color = Color3.fromRGB(40, 130, 210), material = Enum.Material.Glass, transparency = 0.25 })
    build(model, { name = "Foam", pos = c + Vector3.new(0, 1.1, 0.2), size = Vector3.new(2.6, 0.4, 2.2), color = Color3.fromRGB(220, 240, 255), material = Enum.Material.Foil, transparency = 0.15 })

    return body
end

local function buildStarSink(model, info)
    local c = info.pos
    local steel = Color3.fromRGB(190, 196, 204)

    local counter = build(model, { name = "Counter", pos = c, size = Vector3.new(5, 1.2, 3), color = Color3.fromRGB(210, 205, 195), material = Enum.Material.Marble })
    -- Basin.
    build(model, { name = "Basin", pos = c + Vector3.new(0, 0.5, 0), size = Vector3.new(0.6, 2.6, 2.6), color = steel, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 0, 90) })
    -- Five points suggesting a star around the rim.
    for i = 0, 4 do
        local a = math.rad(i * 72)
        local off = Vector3.new(math.sin(a) * 1.5, 0.75, math.cos(a) * 1.5)
        build(model, { name = "StarPoint", pos = CFrame.new(c + off) * CFrame.Angles(0, a, 0), size = Vector3.new(0.4, 0.2, 1.6), color = info.color, material = Enum.Material.Neon })
    end
    -- Faucet.
    build(model, { name = "FaucetBase", pos = c + Vector3.new(0, 1.4, -1), size = Vector3.new(0.4, 2, 0.4), color = steel, material = Enum.Material.Metal })
    build(model, { name = "FaucetSpout", pos = c + Vector3.new(0, 2.4, -0.4), size = Vector3.new(0.4, 0.4, 1.6), color = steel, material = Enum.Material.Metal })

    return counter
end

local function buildMiniHotel(model, info)
    local c = info.pos
    local wall = Color3.fromRGB(214, 200, 170)

    -- Tabletop the little hotel sits on.
    build(model, { name = "TableTop", pos = c + Vector3.new(0, -2.6, 0), size = Vector3.new(6, 0.4, 4), color = Color3.fromRGB(90, 64, 44), material = Enum.Material.Wood })

    local tower = build(model, { name = "Tower", pos = c, size = Vector3.new(4, 6, 3), color = wall, material = Enum.Material.Concrete })
    build(model, { name = "Roof", pos = c + Vector3.new(0, 3.2, 0), size = Vector3.new(4.4, 0.6, 3.4), color = Color3.fromRGB(120, 70, 60), material = Enum.Material.Slate })

    -- Window grid.
    for floor = -1, 1 do
        for col = -1, 1 do
            build(model, { name = "Window", pos = c + Vector3.new(col * 1.1, floor * 1.6, 1.55), size = Vector3.new(0.7, 1, 0.1), color = Color3.fromRGB(255, 226, 130), material = Enum.Material.Neon })
        end
    end
    -- Door + glowing sign (it is the rare one, so make it pop).
    build(model, { name = "Door", pos = c + Vector3.new(0, -2.5, 1.55), size = Vector3.new(1, 1.4, 0.1), color = Color3.fromRGB(80, 50, 40), material = Enum.Material.Wood })
    local sign = build(model, { name = "HotelSign", pos = c + Vector3.new(0, 3.9, 1), size = Vector3.new(3, 0.9, 0.3), color = info.color, material = Enum.Material.Neon })
    labelBillboard(sign, "HOTEL", 1.4)

    return tower
end

local function buildMirrorArt(model, info)
    local c = info.pos

    -- A real painting on the left, a mirror on the right.
    build(model, { name = "ArtFrame", pos = c + Vector3.new(-2.4, 0, 0), size = Vector3.new(0.4, 5, 3.2), color = Color3.fromRGB(60, 44, 30), material = Enum.Material.Wood })
    build(model, { name = "ArtCanvas", pos = c + Vector3.new(-2.2, 0, 0), size = Vector3.new(0.2, 4.2, 2.6), color = Color3.fromRGB(90, 150, 120), material = Enum.Material.SmoothPlastic })

    build(model, { name = "MirrorFrame", pos = c + Vector3.new(2.4, 0, 0), size = Vector3.new(0.4, 5, 3.2), color = Color3.fromRGB(60, 44, 30), material = Enum.Material.Wood })
    local glass = build(model, { name = "MirrorGlass", pos = c + Vector3.new(2.2, 0, 0), size = Vector3.new(0.2, 4.4, 2.8), color = Color3.fromRGB(205, 225, 235), material = Enum.Material.Glass, transparency = 0.2, reflectance = 0.5 })
    -- The reflected art is the WRONG colour: that is the oddity.
    build(model, { name = "WrongReflection", pos = c + Vector3.new(2.05, 0, 0), size = Vector3.new(0.15, 3.4, 2), color = Color3.fromRGB(210, 90, 150), material = Enum.Material.SmoothPlastic })

    return glass
end

local function buildMovingCurtainShadow(model, info)
    local c = info.pos

    -- Curtain behind the shadow.
    build(model, { name = "Curtain", pos = c + Vector3.new(0, 0, -0.6), size = Vector3.new(6, 8, 0.4), color = Color3.fromRGB(120, 70, 90), material = Enum.Material.Fabric })
    build(model, { name = "Rail", pos = c + Vector3.new(0, 4.2, -0.6), size = Vector3.new(6.4, 0.4, 0.6), color = Color3.fromRGB(80, 80, 90), material = Enum.Material.Metal })

    -- A dark human-like silhouette.
    local bodyShadow = build(model, { name = "ShadowBody", pos = c, size = Vector3.new(1.8, 4.6, 0.6), color = Color3.fromRGB(18, 18, 24), material = Enum.Material.SmoothPlastic, transparency = 0.15 })
    build(model, { name = "ShadowHead", pos = c + Vector3.new(0, 3, 0), size = Vector3.new(1.4, 1.4, 0.6), color = Color3.fromRGB(18, 18, 24), material = Enum.Material.SmoothPlastic, transparency = 0.15, shape = Enum.PartType.Ball })

    local basePivot = CFrame.new(c)
    table.insert(animatedUpdaters, function(now)
        model:PivotTo(basePivot * CFrame.new(math.sin(now * 0.9) * 1.6, 0, 0))
    end)

    return bodyShadow
end

local function buildMiniElevator(model, info)
    local c = info.pos
    local steel = Color3.fromRGB(150, 158, 170)

    build(model, { name = "Frame", pos = c, size = Vector3.new(4, 7, 0.6), color = steel, material = Enum.Material.Metal })
    build(model, { name = "ShaftL", pos = c + Vector3.new(-1.7, 0, 0.3), size = Vector3.new(0.4, 7, 0.6), color = Color3.fromRGB(110, 116, 128), material = Enum.Material.Metal })
    build(model, { name = "ShaftR", pos = c + Vector3.new(1.7, 0, 0.3), size = Vector3.new(0.4, 7, 0.6), color = Color3.fromRGB(110, 116, 128), material = Enum.Material.Metal })
    build(model, { name = "ShaftTop", pos = c + Vector3.new(0, 3.5, 0.3), size = Vector3.new(4, 0.5, 0.6), color = Color3.fromRGB(110, 116, 128), material = Enum.Material.Metal })

    -- Call button / floor indicator.
    build(model, { name = "CallButton", pos = c + Vector3.new(2.3, 0.5, 0.3), size = Vector3.new(0.4, 0.6, 0.4), color = Color3.fromRGB(120, 255, 140), material = Enum.Material.Neon })

    -- The cab rides up and down inside the shaft.
    local cab = build(model, { name = "Cab", pos = c + Vector3.new(0, -1.5, 0.45), size = Vector3.new(2.8, 3, 0.5), color = Color3.fromRGB(220, 224, 232), material = Enum.Material.SmoothPlastic })
    local cabBase = cab.CFrame
    table.insert(animatedUpdaters, function(now)
        cab.CFrame = cabBase + Vector3.new(0, (math.sin(now * 1.1) + 1) * 1.6, 0)
    end)

    return cab
end

local anomalyBuilders = {
    ReverseClock = buildReverseClock,
    CeilingChair = buildCeilingChair,
    MiniYatai = buildMiniYatai,
    MiniSea = buildMiniSea,
    StarSink = buildStarSink,
    MiniHotel = buildMiniHotel,
    MirrorArt = buildMirrorArt,
    MovingCurtainShadow = buildMovingCurtainShadow,
    MiniElevator = buildMiniElevator,
}

local function createAnomaly(room, config, info)
    local model = Instance.new("Model")
    model.Name = info.name
    model.Parent = room

    local builder = anomalyBuilders[info.name]
    local primary
    if builder then
        primary = builder(model, info)
    else
        primary = build(model, { name = info.name, pos = info.pos, size = Vector3.new(4, 4, 4), color = info.color, material = Enum.Material.Neon })
    end
    model.PrimaryPart = primary

    -- Tag every part so a click/touch anywhere on the model counts.
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
            p:SetAttribute("IsAnomaly", true)
            p:SetAttribute("RoomId", config.id)
            p:SetAttribute("AnomalyName", info.name)
            p:SetAttribute("DisplayName", info.label)
            p:SetAttribute("Reward", info.reward)
            p:SetAttribute("Found", false)
            p:SetAttribute("BaseTransparency", p.Transparency)
        end
    end

    -- A soft outline used ONLY by the Hint system. Off by default so the
    -- player has to actually search for the oddities.
    local highlight = Instance.new("Highlight")
    highlight.Name = "Marker"
    highlight.Enabled = false
    highlight.FillColor = info.color
    highlight.FillTransparency = 0.6
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = model
    highlight.Parent = model

    -- Sparkle burst played when the oddity is discovered.
    local sparkles = Instance.new("ParticleEmitter")
    sparkles.Name = "FoundSparkles"
    sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparkles.Rate = 0
    sparkles.Enabled = false
    sparkles.Lifetime = NumberRange.new(0.45, 0.9)
    sparkles.Speed = NumberRange.new(7, 14)
    sparkles.SpreadAngle = Vector2.new(180, 180)
    sparkles.Color = ColorSequence.new(info.color)
    sparkles.LightEmission = 0.7
    sparkles.Size = NumberSequence.new(1.4, 0)
    sparkles.Parent = primary

    foundBadge(primary, "Found! +" .. tostring(info.reward))
    return primary
end

local function buildWorld()
    Lighting.ClockTime = 15
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(120, 128, 150)
    Lighting.OutdoorAmbient = Color3.fromRGB(90, 100, 125)
    Lighting.EnvironmentDiffuseScale = 0.4
    Lighting.FogEnd = 320
    Lighting.FogColor = Color3.fromRGB(150, 160, 185)

    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
    atmosphere.Density = 0.32
    atmosphere.Offset = 0.1
    atmosphere.Haze = 1.4
    atmosphere.Glare = 0.1
    atmosphere.Color = Color3.fromRGB(199, 205, 220)
    atmosphere.Decay = Color3.fromRGB(106, 112, 135)
    atmosphere.Parent = Lighting

    local oldDemo = Workspace:FindFirstChild("OnichaShootingDemo")
    if oldDemo then
        oldDemo:Destroy()
    end

    local oldRooms = Workspace:FindFirstChild("Rooms")
    if oldRooms then
        oldRooms:Destroy()
    end

    table.clear(animatedUpdaters)

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

-- Dim a whole anomaly model and reveal its "Found!" badge.
local function markModelFound(model)
    if not model then
        return
    end
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and p:GetAttribute("IsAnomaly") then
            local base = p:GetAttribute("BaseTransparency") or 0
            p.Transparency = math.clamp(base + 0.45, 0, 0.85)
            p:SetAttribute("Found", true)
        end
    end
    local highlight = model:FindFirstChild("Marker")
    if highlight and highlight:IsA("Highlight") then
        highlight.Enabled = false
    end
    if model.PrimaryPart then
        local sparkles = model.PrimaryPart:FindFirstChild("FoundSparkles")
        if sparkles and sparkles:IsA("ParticleEmitter") then
            sparkles:Emit(26)
        end
        local badge = model.PrimaryPart:FindFirstChild("FoundLabel")
        if badge then
            badge.Enabled = true
        end
    end
end

local function resetAllAnomalies()
    local root = Workspace:FindFirstChild("OnichaShootingDemo")
    if not root then
        return
    end
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("BasePart") and inst:GetAttribute("IsAnomaly") then
            inst.Transparency = inst:GetAttribute("BaseTransparency") or 0
            inst:SetAttribute("Found", false)
        elseif inst:IsA("Highlight") and inst.Name == "Marker" then
            inst.Enabled = false
        elseif inst:IsA("BillboardGui") and inst.Name == "FoundLabel" then
            inst.Enabled = false
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
    markModelFound(anomalyInstance:FindFirstAncestorOfClass("Model"))

    UIMessageEvent:FireClient(player, {
        kind = "Found",
        text = "Found! +" .. tostring(reward),
        found = count,
        isRare = isRare,
    })

    if RoomService:IsRoomCleared(player, roomId) then
        if roomId >= #roomConfigs then
            CoinService:AddCoins(player, 100)
            UIMessageEvent:FireClient(player, {
                kind = "GameComplete",
                text = "All rooms clear! +100",
            })
        else
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

if not RunService:IsRunning() then
    return
end

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    for _, fn in ipairs(animatedUpdaters) do
        fn(now)
    end
end)

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

ReplayEvent.OnServerEvent:Connect(function(player)
    if AntiExploitService:IsOnCooldown(player, "replay") then
        return
    end
    RoomService:ResetPlayer(player)
    resetAllAnomalies()
    moveCharacterToRoom(player, 1)
    UIMessageEvent:FireClient(player, {
        kind = "Replay",
        text = "New hunt! Find 3 odd things.",
        room = 1,
    })
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
