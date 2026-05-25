local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AnomalyFoundEvent = remotes:WaitForChild("AnomalyFoundEvent")

local roomOrigins = {
    [1] = Vector3.new(0, 0, -18),
    [2] = Vector3.new(90, 0, -18),
    [3] = Vector3.new(180, 0, -18),
}

local foundByRoom = {}
local hooked = {}
local currentRoom = 1
local coins = 0
local totalFound = 0
local finalRoom = 3

local function mainUi()
    local playerGui = player:FindFirstChild("PlayerGui")
    return playerGui and playerGui:FindFirstChild("MainUI")
end

local function setText(name, text)
    local gui = mainUi()
    local label = gui and gui:FindFirstChild(name)
    if label then
        label.Text = text
    end
end

local function showMessage(text, seconds)
    local gui = mainUi()
    local label = gui and gui:FindFirstChild("MessageDisplay")
    if not label then
        return
    end
    label.Text = text
    label.Visible = true
    task.delay(seconds or 2.0, function()
        if label.Text == text then
            label.Visible = false
        end
    end)
end

local function updateUi()
    local roomFound = foundByRoom[currentRoom] or {}
    local count = 0
    for _ in pairs(roomFound) do
        count += 1
    end

    setText("CoinDisplay", "Coins: " .. tostring(coins))
    setText("RoomDisplay", string.format("Room: %03d", currentRoom))
    setText("FoundCounter", "Found: " .. tostring(count) .. "/3")
end

local function teleportToRoom(roomId)
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart", 5)
    local origin = roomOrigins[roomId]
    if root and origin then
        root.CFrame = CFrame.new(origin + Vector3.new(0, 5, 20), origin + Vector3.new(0, 3, -20))
    end
end

local function clearRoomIfReady(roomId)
    local roomFound = foundByRoom[roomId] or {}
    local count = 0
    for _ in pairs(roomFound) do
        count += 1
    end

    if count < 3 then
        return
    end

    if roomId >= finalRoom then
        showMessage("Demo clear! Total found: " .. tostring(totalFound), 5)
        return
    end

    showMessage("Room clear! Moving to next room...", 2)
    task.delay(1.5, function()
        currentRoom = roomId + 1
        updateUi()
        teleportToRoom(currentRoom)
        showMessage("Room " .. string.format("%03d", currentRoom) .. ": find 3 odd things.", 3)
    end)
end

local function markFound(instance)
    local roomId = instance:GetAttribute("RoomId") or 1
    local anomalyName = instance:GetAttribute("AnomalyName") or instance.Name

    if roomId ~= currentRoom then
        showMessage("Clear the current room first.", 1.4)
        return
    end

    foundByRoom[roomId] = foundByRoom[roomId] or {}
    if foundByRoom[roomId][anomalyName] then
        return
    end

    foundByRoom[roomId][anomalyName] = true
    totalFound += 1

    local reward = instance:GetAttribute("Reward") or 10
    coins += reward
    instance.Transparency = 0.55
    instance.Material = Enum.Material.Neon
    instance:SetAttribute("Found", true)

    updateUi()
    showMessage("Found! +" .. tostring(reward), 1.5)
    AnomalyFoundEvent:FireServer(roomId, anomalyName, instance)
    clearRoomIfReady(roomId)
end

local function hookAnomaly(instance)
    if not instance:IsA("BasePart") then
        return
    end
    if instance:GetAttribute("IsAnomaly") ~= true then
        return
    end
    if hooked[instance] then
        return
    end
    hooked[instance] = true

    local click = instance:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
    click.MaxActivationDistance = 120
    click.Parent = instance

    click.MouseClick:Connect(function()
        markFound(instance)
    end)

    instance.Touched:Connect(function(hit)
        local character = player.Character
        if character and hit:IsDescendantOf(character) then
            markFound(instance)
        end
    end)
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
    hookAnomaly(descendant)
end

Workspace.DescendantAdded:Connect(hookAnomaly)
player.CharacterAdded:Connect(function()
    task.wait(0.4)
    teleportToRoom(currentRoom)
    updateUi()
end)

task.defer(function()
    task.wait(0.5)
    teleportToRoom(currentRoom)
    updateUi()
    showMessage("Find 3 odd things in each room.", 3)
end)
