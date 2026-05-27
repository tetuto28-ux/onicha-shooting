-- Oddity Hunt - "declare" mode.
-- The server only builds the world: enclosed rooms full of normal props plus a
-- randomised set of oddities. Every inspectable object is a Model tagged with
-- "Inspectable", and oddities additionally carry "IsAnomaly". All of the game
-- logic (flagging, confirming, lives, timer, scoring) lives on the client, so
-- the server stays small and hard to break.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ROOM_SPACING = 90
local ROOM_WIDTH = 44
local ROOM_DEPTH = 54
local WALL_HEIGHT = 18
local ROOM_COUNT = 3

-- Each listed oddity appears with this probability, so the number of oddities
-- in a room (and whether there are any at all) changes every play.
local ANOMALY_PRESENCE_CHANCE = 0.6

local animatedUpdaters = {}

local roomConfigs = {
    {
        id = 1,
        title = "Room 001 - Strange Lobby",
        origin = Vector3.new(0, 0, -18),
        wallColor = Color3.fromRGB(78, 101, 138),
        floorColor = Color3.fromRGB(78, 88, 108),
        anomalies = {
            { name = "ReverseClock", label = "Reverse Clock", pos = Vector3.new(-12, 6, -31), color = Color3.fromRGB(255, 224, 92) },
            { name = "CeilingChair", label = "Ceiling Chair", pos = Vector3.new(0, 13, -22), color = Color3.fromRGB(77, 170, 255) },
            { name = "MiniYatai", label = "Tiny Food Stall", pos = Vector3.new(15, 3, -26), color = Color3.fromRGB(255, 127, 139) },
        },
    },
    {
        id = 2,
        title = "Room 002 - Kitchen Hotel",
        origin = Vector3.new(ROOM_SPACING, 0, -18),
        wallColor = Color3.fromRGB(92, 118, 101),
        floorColor = Color3.fromRGB(92, 89, 75),
        anomalies = {
            { name = "MiniSea", label = "Tiny Sea Fridge", pos = Vector3.new(ROOM_SPACING - 15, 4, -25), color = Color3.fromRGB(77, 206, 255) },
            { name = "StarSink", label = "Star Sink", pos = Vector3.new(ROOM_SPACING + 2, 3, -30), color = Color3.fromRGB(255, 241, 90) },
            { name = "MiniHotel", label = "Mini Hotel", pos = Vector3.new(ROOM_SPACING + 15, 4, -24), color = Color3.fromRGB(185, 120, 255) },
        },
    },
    {
        id = 3,
        title = "Room 003 - Mirror Hall",
        origin = Vector3.new(ROOM_SPACING * 2, 0, -18),
        wallColor = Color3.fromRGB(106, 91, 126),
        floorColor = Color3.fromRGB(83, 81, 105),
        anomalies = {
            { name = "MirrorArt", label = "Wrong Mirror Art", pos = Vector3.new(ROOM_SPACING * 2 - 14, 6, -31), color = Color3.fromRGB(167, 230, 255) },
            { name = "MovingCurtainShadow", label = "Moving Shadow", pos = Vector3.new(ROOM_SPACING * 2 + 2, 5, -29), color = Color3.fromRGB(33, 36, 46) },
            { name = "MiniElevator", label = "Mini Elevator", pos = Vector3.new(ROOM_SPACING * 2 + 15, 5, -31), color = Color3.fromRGB(145, 168, 188) },
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

local UIMessageEvent = ensureRemote("UIMessageEvent")
local ReplayEvent = ensureRemote("ReplayEvent")

-- Generic builder used for every part.
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

-- Collidable scenery part (walls, floor) parented straight to the room.
local function scenery(parent, name, position, size, color, material)
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

-- ---------------------------------------------------------------------------
-- Oddity model builders. Each returns the model's primary (anchor) part.
-- ---------------------------------------------------------------------------

local function buildReverseClock(model, info)
    local c = info.pos
    local cream = Color3.fromRGB(244, 240, 226)

    build(model, { name = "Rim", pos = c - Vector3.new(0, 0, 0.2), size = Vector3.new(0.4, 4.6, 4.6), color = Color3.fromRGB(60, 60, 70), material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })
    local face = build(model, { name = "Face", pos = c, size = Vector3.new(0.4, 4, 4), color = cream, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })

    for _, off in ipairs({ Vector3.new(0, 1.6, 0), Vector3.new(1.6, 0, 0), Vector3.new(0, -1.6, 0), Vector3.new(-1.6, 0, 0) }) do
        build(model, { name = "Tick", pos = c + off + Vector3.new(0, 0, 0.3), size = Vector3.new(0.3, 0.3, 0.18), color = Color3.fromRGB(40, 40, 50) })
    end

    build(model, { name = "Hub", pos = c + Vector3.new(0, 0, 0.32), size = Vector3.new(0.5, 0.5, 0.3), color = Color3.fromRGB(40, 40, 50), shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 90, 0) })

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

    local seat = build(model, { name = "Seat", pos = c, size = Vector3.new(3, 0.5, 3), color = wood, material = Enum.Material.Wood })
    for _, dx in ipairs({ -1.2, 1.2 }) do
        for _, dz in ipairs({ -1.2, 1.2 }) do
            build(model, { name = "Leg", pos = c + Vector3.new(dx, 1.5, dz), size = Vector3.new(0.4, 3, 0.4), color = wood, material = Enum.Material.Wood })
        end
    end
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
    build(model, { name = "Roof", pos = c + Vector3.new(0, 5.3, 0), size = Vector3.new(6, 0.5, 3.4), color = Color3.fromRGB(210, 70, 78), material = Enum.Material.Fabric })
    build(model, { name = "RoofStripe", pos = c + Vector3.new(0, 5.55, 0), size = Vector3.new(6.1, 0.2, 1.1), color = Color3.fromRGB(245, 245, 245), material = Enum.Material.Fabric })
    build(model, { name = "Lantern", pos = c + Vector3.new(1.6, 4.4, 1.2), size = Vector3.new(1, 1.2, 1), color = Color3.fromRGB(220, 60, 50), material = Enum.Material.Neon, shape = Enum.PartType.Ball })

    return counter
end

local function buildMiniSea(model, info)
    local c = info.pos
    local white = Color3.fromRGB(236, 238, 240)

    local body = build(model, { name = "FridgeBody", pos = c, size = Vector3.new(3.4, 5.4, 3), color = white, material = Enum.Material.SmoothPlastic })
    build(model, { name = "Door", pos = CFrame.new(c + Vector3.new(-2.4, 0, 1.4)) * CFrame.Angles(0, math.rad(60), 0), size = Vector3.new(0.3, 5.2, 2.8), color = white, material = Enum.Material.SmoothPlastic })
    build(model, { name = "Handle", pos = CFrame.new(c + Vector3.new(-2.4, 0, 2.4)) * CFrame.Angles(0, math.rad(60), 0), size = Vector3.new(0.2, 2, 0.2), color = Color3.fromRGB(150, 150, 160), material = Enum.Material.Metal })
    build(model, { name = "Water", pos = c + Vector3.new(0, -0.4, 0.2), size = Vector3.new(2.6, 3.2, 2.2), color = Color3.fromRGB(40, 130, 210), material = Enum.Material.Glass, transparency = 0.25 })
    build(model, { name = "Foam", pos = c + Vector3.new(0, 1.1, 0.2), size = Vector3.new(2.6, 0.4, 2.2), color = Color3.fromRGB(220, 240, 255), material = Enum.Material.Foil, transparency = 0.15 })

    return body
end

local function buildStarSink(model, info)
    local c = info.pos
    local steel = Color3.fromRGB(190, 196, 204)

    local counter = build(model, { name = "Counter", pos = c, size = Vector3.new(5, 1.2, 3), color = Color3.fromRGB(210, 205, 195), material = Enum.Material.Marble })
    build(model, { name = "Basin", pos = c + Vector3.new(0, 0.5, 0), size = Vector3.new(0.6, 2.6, 2.6), color = steel, material = Enum.Material.Metal, shape = Enum.PartType.Cylinder, orient = Vector3.new(0, 0, 90) })
    for i = 0, 4 do
        local a = math.rad(i * 72)
        local off = Vector3.new(math.sin(a) * 1.5, 0.75, math.cos(a) * 1.5)
        build(model, { name = "StarPoint", pos = CFrame.new(c + off) * CFrame.Angles(0, a, 0), size = Vector3.new(0.4, 0.2, 1.6), color = info.color, material = Enum.Material.Neon })
    end
    build(model, { name = "FaucetBase", pos = c + Vector3.new(0, 1.4, -1), size = Vector3.new(0.4, 2, 0.4), color = steel, material = Enum.Material.Metal })
    build(model, { name = "FaucetSpout", pos = c + Vector3.new(0, 2.4, -0.4), size = Vector3.new(0.4, 0.4, 1.6), color = steel, material = Enum.Material.Metal })

    return counter
end

local function buildMiniHotel(model, info)
    local c = info.pos
    local wall = Color3.fromRGB(214, 200, 170)

    build(model, { name = "TableTop", pos = c + Vector3.new(0, -2.6, 0), size = Vector3.new(6, 0.4, 4), color = Color3.fromRGB(90, 64, 44), material = Enum.Material.Wood })

    local tower = build(model, { name = "Tower", pos = c, size = Vector3.new(4, 6, 3), color = wall, material = Enum.Material.Concrete })
    build(model, { name = "Roof", pos = c + Vector3.new(0, 3.2, 0), size = Vector3.new(4.4, 0.6, 3.4), color = Color3.fromRGB(120, 70, 60), material = Enum.Material.Slate })

    for floor = -1, 1 do
        for col = -1, 1 do
            build(model, { name = "Window", pos = c + Vector3.new(col * 1.1, floor * 1.6, 1.55), size = Vector3.new(0.7, 1, 0.1), color = Color3.fromRGB(255, 226, 130), material = Enum.Material.Neon })
        end
    end
    build(model, { name = "Door", pos = c + Vector3.new(0, -2.5, 1.55), size = Vector3.new(1, 1.4, 0.1), color = Color3.fromRGB(80, 50, 40), material = Enum.Material.Wood })
    local sign = build(model, { name = "HotelSign", pos = c + Vector3.new(0, 3.9, 1), size = Vector3.new(3, 0.9, 0.3), color = info.color, material = Enum.Material.Neon })
    labelBillboard(sign, "HOTEL", 1.4)

    return tower
end

local function buildMirrorArt(model, info)
    local c = info.pos

    build(model, { name = "ArtFrame", pos = c + Vector3.new(-2.4, 0, 0), size = Vector3.new(0.4, 5, 3.2), color = Color3.fromRGB(60, 44, 30), material = Enum.Material.Wood })
    build(model, { name = "ArtCanvas", pos = c + Vector3.new(-2.2, 0, 0), size = Vector3.new(0.2, 4.2, 2.6), color = Color3.fromRGB(90, 150, 120), material = Enum.Material.SmoothPlastic })

    build(model, { name = "MirrorFrame", pos = c + Vector3.new(2.4, 0, 0), size = Vector3.new(0.4, 5, 3.2), color = Color3.fromRGB(60, 44, 30), material = Enum.Material.Wood })
    local glass = build(model, { name = "MirrorGlass", pos = c + Vector3.new(2.2, 0, 0), size = Vector3.new(0.2, 4.4, 2.8), color = Color3.fromRGB(205, 225, 235), material = Enum.Material.Glass, transparency = 0.2, reflectance = 0.5 })
    build(model, { name = "WrongReflection", pos = c + Vector3.new(2.05, 0, 0), size = Vector3.new(0.15, 3.4, 2), color = Color3.fromRGB(210, 90, 150), material = Enum.Material.SmoothPlastic })

    return glass
end

local function buildMovingCurtainShadow(model, info)
    local c = info.pos

    build(model, { name = "Curtain", pos = c + Vector3.new(0, 0, -0.6), size = Vector3.new(6, 8, 0.4), color = Color3.fromRGB(120, 70, 90), material = Enum.Material.Fabric })
    build(model, { name = "Rail", pos = c + Vector3.new(0, 4.2, -0.6), size = Vector3.new(6.4, 0.4, 0.6), color = Color3.fromRGB(80, 80, 90), material = Enum.Material.Metal })

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

    build(model, { name = "CallButton", pos = c + Vector3.new(2.3, 0.5, 0.3), size = Vector3.new(0.4, 0.6, 0.4), color = Color3.fromRGB(120, 255, 140), material = Enum.Material.Neon })

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

-- ---------------------------------------------------------------------------
-- Normal decoy props. They look ordinary; flagging one is a mistake.
-- ---------------------------------------------------------------------------

local function newInspectable(parent, name, isAnomaly)
    local model = Instance.new("Model")
    model.Name = name
    model:SetAttribute("Inspectable", true)
    model:SetAttribute("IsAnomaly", isAnomaly == true)
    model.Parent = parent
    return model
end

local function buildDecoy(room, name, pos)
    local model = newInspectable(room, name, false)
    local primary

    if name == "Desk" then
        primary = build(model, { name = "Top", pos = pos + Vector3.new(0, 2.4, 0), size = Vector3.new(8, 0.6, 4), color = Color3.fromRGB(120, 82, 52), material = Enum.Material.Wood })
        build(model, { name = "Body", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(7.4, 2, 3.4), color = Color3.fromRGB(104, 70, 44), material = Enum.Material.Wood })
    elseif name == "Sofa" then
        primary = build(model, { name = "Base", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(8, 1.6, 3.5), color = Color3.fromRGB(96, 110, 150), material = Enum.Material.Fabric })
        build(model, { name = "Back", pos = pos + Vector3.new(0, 2.4, -1.4), size = Vector3.new(8, 2, 0.8), color = Color3.fromRGB(96, 110, 150), material = Enum.Material.Fabric })
    elseif name == "Lamp" then
        primary = build(model, { name = "Pole", pos = pos + Vector3.new(0, 2.5, 0), size = Vector3.new(0.6, 5, 0.6), color = Color3.fromRGB(60, 60, 70), material = Enum.Material.Metal })
        build(model, { name = "Shade", pos = pos + Vector3.new(0, 5.2, 0), size = Vector3.new(2.6, 1.6, 2.6), color = Color3.fromRGB(255, 236, 170), material = Enum.Material.Neon })
    elseif name == "Plant" then
        primary = build(model, { name = "Pot", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(2, 2, 2), color = Color3.fromRGB(150, 92, 60), material = Enum.Material.Slate })
        build(model, { name = "Leaves", pos = pos + Vector3.new(0, 3.2, 0), size = Vector3.new(4, 4, 4), color = Color3.fromRGB(72, 140, 70), material = Enum.Material.Grass, shape = Enum.PartType.Ball })
    elseif name == "Painting" then
        primary = build(model, { name = "Frame", pos = pos, size = Vector3.new(5, 4, 0.5), color = Color3.fromRGB(60, 44, 30), material = Enum.Material.Wood })
        build(model, { name = "Canvas", pos = pos + Vector3.new(0, 0, 0.2), size = Vector3.new(4.2, 3.2, 0.2), color = Color3.fromRGB(150, 180, 210), material = Enum.Material.SmoothPlastic })
    elseif name == "Crate" then
        primary = build(model, { name = "Box", pos = pos + Vector3.new(0, 1.5, 0), size = Vector3.new(3, 3, 3), color = Color3.fromRGB(168, 130, 84), material = Enum.Material.WoodPlanks })
    else -- "TV"
        primary = build(model, { name = "Screen", pos = pos + Vector3.new(0, 3, 0), size = Vector3.new(5, 3, 0.5), color = Color3.fromRGB(28, 30, 38), material = Enum.Material.Glass })
        build(model, { name = "Stand", pos = pos + Vector3.new(0, 1, 0), size = Vector3.new(1, 2, 1), color = Color3.fromRGB(40, 42, 50), material = Enum.Material.Metal })
    end

    model.PrimaryPart = primary
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end
    return model
end

local function createAnomaly(room, config, info)
    local model = newInspectable(room, info.name, true)

    local builder = anomalyBuilders[info.name]
    local primary
    if builder then
        primary = builder(model, info)
    else
        primary = build(model, { name = info.name, pos = info.pos, size = Vector3.new(4, 4, 4), color = info.color, material = Enum.Material.Neon })
    end
    model.PrimaryPart = primary

    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end

    -- Hidden outline used only by the client Hint feature.
    local hint = Instance.new("Highlight")
    hint.Name = "HintMarker"
    hint.Enabled = false
    hint.FillColor = info.color
    hint.FillTransparency = 0.45
    hint.OutlineColor = Color3.fromRGB(255, 255, 255)
    hint.OutlineTransparency = 0
    hint.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hint.Adornee = model
    hint.Parent = model

    return model
end

local DECOY_SLOTS = {
    { name = "Desk", off = Vector3.new(-14, 0, 8) },
    { name = "Sofa", off = Vector3.new(0, 0, 14) },
    { name = "Lamp", off = Vector3.new(15, 0, 8) },
    { name = "Plant", off = Vector3.new(-17, 0, -6) },
    { name = "Painting", off = Vector3.new(8, 9, -ROOM_DEPTH / 2 + 0.9) },
    { name = "Crate", off = Vector3.new(16, 0, -2) },
    { name = "TV", off = Vector3.new(-9, 0, -10) },
}

local function decorateRoom(room, config)
    local origin = config.origin

    -- Scenery (not inspectable).
    scenery(room, "Floor", origin, Vector3.new(ROOM_WIDTH, 1, ROOM_DEPTH), config.floorColor, Enum.Material.Plastic)
    scenery(room, "BackWall", origin + Vector3.new(0, WALL_HEIGHT / 2, -ROOM_DEPTH / 2), Vector3.new(ROOM_WIDTH, WALL_HEIGHT, 1), config.wallColor)
    scenery(room, "FrontWall", origin + Vector3.new(0, WALL_HEIGHT / 2, ROOM_DEPTH / 2), Vector3.new(ROOM_WIDTH, WALL_HEIGHT, 1), config.wallColor)
    scenery(room, "LeftWall", origin + Vector3.new(-ROOM_WIDTH / 2, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, ROOM_DEPTH), config.wallColor)
    scenery(room, "RightWall", origin + Vector3.new(ROOM_WIDTH / 2, WALL_HEIGHT / 2, 0), Vector3.new(1, WALL_HEIGHT, ROOM_DEPTH), config.wallColor:Lerp(Color3.new(1, 1, 1), 0.25))
    scenery(room, "Rug", origin + Vector3.new(0, 0.55, 2), Vector3.new(20, 0.1, 16), config.wallColor:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)

    local sign = scenery(room, "RoomSign", origin + Vector3.new(0, 14, -ROOM_DEPTH / 2 + 0.7), Vector3.new(18, 5, 0.5), Color3.fromRGB(24, 29, 40))
    labelBillboard(sign, config.title, 4)

    -- Normal decoy objects (inspectable, but flagging them is a mistake).
    for _, slot in ipairs(DECOY_SLOTS) do
        buildDecoy(room, slot.name, origin + slot.off)
    end
end

local function buildWorld()
    local okLight = pcall(function()
        Lighting.ClockTime = 14
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(120, 128, 150)
        Lighting.OutdoorAmbient = Color3.fromRGB(95, 105, 130)
        Lighting.EnvironmentDiffuseScale = 0.45
        Lighting.FogEnd = 400

        local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
        atmosphere.Density = 0.28
        atmosphere.Haze = 1.2
        atmosphere.Color = Color3.fromRGB(199, 205, 220)
        atmosphere.Parent = Lighting
    end)
    if not okLight then
        warn("[buildWorld] lighting setup skipped")
    end

    local oldDemo = Workspace:FindFirstChild("OnichaShootingDemo")
    if oldDemo then
        oldDemo:Destroy()
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

        local okDecor, errDecor = pcall(decorateRoom, room, config)
        if not okDecor then
            warn(string.format("[buildWorld] decorateRoom failed for room %d: %s", config.id, tostring(errDecor)))
        end

        for _, info in ipairs(config.anomalies) do
            if math.random() < ANOMALY_PRESENCE_CHANCE then
                local okAnomaly, errAnomaly = pcall(createAnomaly, room, config, info)
                if not okAnomaly then
                    warn(string.format("[buildWorld] createAnomaly failed for %s: %s", tostring(info.name), tostring(errAnomaly)))
                end
            end
        end
    end
end

local function spawnForRoom(roomId)
    local index = math.clamp(tonumber(roomId) or 1, 1, ROOM_COUNT)
    local origin = roomConfigs[index].origin
    return CFrame.new(origin + Vector3.new(0, 5, 18), origin + Vector3.new(0, 4, -20))
end

local function moveCharacterToRoom(player, roomId)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.CFrame = spawnForRoom(roomId)
    end
end

local function initPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.3)
        moveCharacterToRoom(player, 1)
    end)
    if player.Character then
        moveCharacterToRoom(player, 1)
    end
    UIMessageEvent:FireClient(player, { kind = "WorldReady", rooms = ROOM_COUNT })
end

local okWorld, errWorld = pcall(buildWorld)
if not okWorld then
    warn("[ServerMain] buildWorld error (players will still init): " .. tostring(errWorld))
end

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

ReplayEvent.OnServerEvent:Connect(function(player)
    pcall(buildWorld)
    for _, p in ipairs(Players:GetPlayers()) do
        moveCharacterToRoom(p, 1)
        UIMessageEvent:FireClient(p, { kind = "WorldReady", rooms = ROOM_COUNT })
    end
end)
