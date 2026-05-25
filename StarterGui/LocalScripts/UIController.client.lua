local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:FindFirstChild("MainUI") or Instance.new("ScreenGui")
gui.Name = "MainUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function makeLabel(name, position, size, text, textSize)
    local label = gui:FindFirstChild(name) or Instance.new("TextLabel")
    label.Name = name
    label.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
    label.BackgroundTransparency = 0.12
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.Position = position
    label.Size = size
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = textSize or 28
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = gui
    return label
end

makeLabel("TitleDisplay", UDim2.new(0, 24, 0, 86), UDim2.new(0, 330, 0, 44), "Oddity Hunt", 30)
makeLabel("CoinDisplay", UDim2.new(0, 24, 0, 140), UDim2.new(0, 260, 0, 46), "Coins: 0", 32)
makeLabel("RoomDisplay", UDim2.new(0, 24, 0, 194), UDim2.new(0, 260, 0, 46), "Room: 001", 32)
makeLabel("FoundCounter", UDim2.new(0, 24, 0, 248), UDim2.new(0, 260, 0, 46), "Found: 0/3", 32)
makeLabel("HintDisplay", UDim2.new(0, 24, 1, -80), UDim2.new(0, 560, 0, 48), "Click or touch the glowing odd objects.", 22)

local message = makeLabel("MessageDisplay", UDim2.new(0.5, -260, 0, 112), UDim2.new(0, 520, 0, 56), "", 34)
message.TextXAlignment = Enum.TextXAlignment.Center
message.Visible = false

local overlay = makeLabel("RecordingOverlay", UDim2.new(1, -470, 0, 86), UDim2.new(0, 440, 0, 52), "Recording mode: find the odd things.", 22)
overlay.TextXAlignment = Enum.TextXAlignment.Center
overlay.Visible = false

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIMessageEvent = remotes:WaitForChild("UIMessageEvent")

local coinDisplay = gui:WaitForChild("CoinDisplay")
local roomDisplay = gui:WaitForChild("RoomDisplay")
local messageDisplay = gui:WaitForChild("MessageDisplay")
local foundCounter = gui:WaitForChild("FoundCounter")

local coinConnection

local function refreshCoins()
    local stats = player:FindFirstChild("leaderstats")
    local coins = stats and stats:FindFirstChild("Coins")
    if coins then
        coinDisplay.Text = "Coins: " .. tostring(coins.Value)
    end
end

local function hookLeaderstats(stats)
    local coins = stats:WaitForChild("Coins")
    if coinConnection then
        coinConnection:Disconnect()
    end
    coinConnection = coins:GetPropertyChangedSignal("Value"):Connect(refreshCoins)
    refreshCoins()
end

local existingStats = player:FindFirstChild("leaderstats")
if existingStats then
    hookLeaderstats(existingStats)
end

player.ChildAdded:Connect(function(child)
    if child.Name == "leaderstats" then
        hookLeaderstats(child)
    end
end)

UIMessageEvent.OnClientEvent:Connect(function(payload)
    if payload.room then
        roomDisplay.Text = string.format("Room: %03d", payload.room)
    end
    if payload.found then
        foundCounter.Text = "Found: " .. tostring(payload.found) .. "/3"
    end
    if payload.text then
        messageDisplay.Text = payload.text
        messageDisplay.Visible = true
        task.delay(2.0, function()
            if messageDisplay.Text == payload.text then
                messageDisplay.Visible = false
            end
        end)
    end
end)
