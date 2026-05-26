local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PANEL_BG = Color3.fromRGB(16, 20, 32)
local ACCENT = Color3.fromRGB(120, 200, 255)
local GOLD = Color3.fromRGB(255, 216, 102)
local GREEN = Color3.fromRGB(120, 230, 150)

local gui = playerGui:FindFirstChild("MainUI") or Instance.new("ScreenGui")
gui.Name = "MainUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function round(instance, radius)
    local corner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 12)
    corner.Parent = instance
end

local function stroke(instance, color, thickness, transparency)
    local s = instance:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(255, 255, 255)
    s.Thickness = thickness or 1.5
    s.Transparency = transparency or 0.55
    s.Parent = instance
end

local function makeLabel(name, position, size, text, textSize, textColor)
    local label = gui:FindFirstChild(name) or Instance.new("TextLabel")
    label.Name = name
    label.BackgroundColor3 = PANEL_BG
    label.BackgroundTransparency = 0.18
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.Position = position
    label.Size = size
    label.Text = text
    label.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
    label.TextSize = textSize or 28
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = gui

    round(label, 12)
    stroke(label, Color3.fromRGB(120, 140, 180), 1.5, 0.6)

    local pad = label:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = label
    return label
end

makeLabel("TitleDisplay", UDim2.new(0, 24, 0, 40), UDim2.new(0, 300, 0, 48), "🔍 Oddity Hunt", 30, GOLD)
makeLabel("CoinDisplay", UDim2.new(0, 24, 0, 98), UDim2.new(0, 240, 0, 46), "Coins: 0", 30, GOLD)
makeLabel("RoomDisplay", UDim2.new(0, 24, 0, 152), UDim2.new(0, 240, 0, 46), "Room: 001", 30, ACCENT)
makeLabel("FoundCounter", UDim2.new(0, 24, 0, 206), UDim2.new(0, 240, 0, 46), "Found: 0/3", 30, GREEN)

local hint = makeLabel("HintDisplay", UDim2.new(0.5, -300, 1, -70), UDim2.new(0, 600, 0, 48), "Walk up to the glowing odd objects and click or touch them.", 22)
hint.TextXAlignment = Enum.TextXAlignment.Center

local message = makeLabel("MessageDisplay", UDim2.new(0.5, -260, 0, 110), UDim2.new(0, 520, 0, 60), "", 34)
message.TextXAlignment = Enum.TextXAlignment.Center
message.BackgroundTransparency = 0.08
message.Visible = false
stroke(message, GOLD, 2, 0.3)

local overlay = makeLabel("RecordingOverlay", UDim2.new(1, -470, 0, 40), UDim2.new(0, 440, 0, 52), "Recording mode: find the odd things.", 22, Color3.fromRGB(255, 120, 120))
overlay.TextXAlignment = Enum.TextXAlignment.Center
overlay.Visible = false

-- Play Again button, shown only after every room is cleared.
local playAgain = gui:FindFirstChild("PlayAgainButton") or Instance.new("TextButton")
playAgain.Name = "PlayAgainButton"
playAgain.BackgroundColor3 = Color3.fromRGB(46, 134, 222)
playAgain.BorderSizePixel = 0
playAgain.Font = Enum.Font.GothamBold
playAgain.Position = UDim2.new(0.5, -130, 0.5, 20)
playAgain.Size = UDim2.new(0, 260, 0, 60)
playAgain.Text = "▶ Play Again"
playAgain.TextColor3 = Color3.fromRGB(255, 255, 255)
playAgain.TextSize = 30
playAgain.AutoButtonColor = true
playAgain.Visible = false
playAgain.Parent = gui
round(playAgain, 16)
stroke(playAgain, Color3.fromRGB(255, 255, 255), 2, 0.3)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIMessageEvent = remotes:WaitForChild("UIMessageEvent")
local ReplayEvent = remotes:WaitForChild("ReplayEvent")

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

playAgain.MouseButton1Click:Connect(function()
    playAgain.Visible = false
    ReplayEvent:FireServer()
end)

UIMessageEvent.OnClientEvent:Connect(function(payload)
    if payload.room then
        roomDisplay.Text = string.format("Room: %03d", payload.room)
    end
    if payload.found then
        foundCounter.Text = "Found: " .. tostring(payload.found) .. "/3"
    end

    if payload.kind == "GameComplete" then
        playAgain.Visible = true
    elseif payload.kind == "Replay" then
        playAgain.Visible = false
        foundCounter.Text = "Found: 0/3"
        roomDisplay.Text = "Room: 001"
    end

    if payload.text then
        local color = GOLD
        if payload.kind == "Found" then
            color = payload.isRare and Color3.fromRGB(255, 170, 90) or GREEN
        elseif payload.kind == "Warn" then
            color = Color3.fromRGB(255, 120, 120)
        end
        messageDisplay.TextColor3 = color
        messageDisplay.Text = payload.text
        messageDisplay.Visible = true
        task.delay(2.0, function()
            if messageDisplay.Text == payload.text and not playAgain.Visible then
                messageDisplay.Visible = false
            end
        end)
    end
end)
