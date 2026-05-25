local Workspace = game:GetService("Workspace")

local function ensureFolder(name)
    local f = Workspace:FindFirstChild(name)
    if not f then
        f = Instance.new("Folder")
        f.Name = name
        f.Parent = Workspace
    end
    return f
end

local rooms = ensureFolder("Rooms")

local roomAnomalies = {
    [1] = {"ReverseClock", "CeilingChair", "MiniYatai"},
    [2] = {"MiniSea", "StarSink", "MiniHotel"},
    [3] = {"MirrorArt", "MovingCurtainShadow", "MiniElevator"},
    [4] = {"ToyReception", "MiniRail", "GiantPudding"},
    [5] = {"SushiRail", "EmbeddedDoor", "WalkingChair"},
}

for roomId, anomalies in pairs(roomAnomalies) do
    local model = rooms:FindFirstChild(string.format("Room%03d", roomId))
    if not model then
        model = Instance.new("Model")
        model.Name = string.format("Room%03d", roomId)
        model.Parent = rooms
    end

    for i, anomalyName in ipairs(anomalies) do
        local part = model:FindFirstChild(anomalyName)
        if not part then
            part = Instance.new("Part")
            part.Name = anomalyName
            part.Size = Vector3.new(3, 3, 3)
            part.Position = Vector3.new((roomId - 1) * 35 + i * 5, 4, i * 8)
            part.Anchored = true
            part.Parent = model
        end
        part:SetAttribute("IsAnomaly", true)
        part:SetAttribute("RoomId", roomId)
        part:SetAttribute("AnomalyName", anomalyName)
    end
end
