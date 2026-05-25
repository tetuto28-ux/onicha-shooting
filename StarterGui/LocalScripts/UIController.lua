local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:FindFirstChild("MainUI")

if not gui then
    gui = Instance.new("ScreenGui")
    gui.Name = "MainUI"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui
end

local function ensureLabel(name, position, size, text)
    local label = gui:FindFirstChild(name)
    if not label then
        label = Instance.new("TextLabel")
        label.Name = name
        label.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
        label.BackgroundTransparency = 0.15
        label.BorderSizePixel = 0
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextScaled = true
        label.Parent = gui
    end
    label.Position = position
    label.Size = size
    label.Text = label.Text ~= "" and label.Text or text
    return label
end

ensureLabel("CoinDisplay", UDim2.new(0, 16, 0, 16), UDim2.new(0, 170, 0, 36), "Coins: 0")
ensureLabel("RoomDisplay", UDim2.new(0, 16, 0, 58), UDim2.new(0, 170, 0, 36), "Room: 001")
ensureLabel("FoundCounter", UDim2.new(0, 16, 0, 100), UDim2.new(0, 170, 0, 36), "Found: 0/3")
local message = ensureLabel("MessageDisplay", UDim2.new(0.5, -220, 0, 16), UDim2.new(0, 440, 0, 44), "")
message.Visible = false
ensureLabel("RecordingOverlay", UDim2.new(1, -440, 0, 16), UDim2.new(0, 420, 0, 44), "")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIMessageEvent = remotes:WaitForChild("UIMessageEvent")

local coinDisplay = gui:WaitForChild("CoinDisplay")
local roomDisplay = gui:WaitForChild("RoomDisplay")
local messageDisplay = gui:WaitForChild("MessageDisplay")
local foundCounter = gui:WaitForChild("FoundCounter")

local function refreshCoins()
    local stats = player:FindFirstChild("leaderstats")
    local coins = stats and stats:FindFirstChild("Coins")
    coinDisplay.Text = "Coins: " .. tostring(coins and coins.Value or 0)
end

player.ChildAdded:Connect(function(child)
    if child.Name == "leaderstats" then
        child:WaitForChild("Coins"):GetPropertyChangedSignal("Value"):Connect(refreshCoins)
        refreshCoins()
    end
end)

UIMessageEvent.OnClientEvent:Connect(function(payload)
    if payload.room then
        roomDisplay.Text = string.format("Room: %03d", payload.room)
    end
    if payload.found then
        foundCounter.Text = "Found: " .. tostring(payload.found) .. "/3+"
    end
    if payload.text then
        messageDisplay.Text = payload.text
        messageDisplay.Visible = true
        task.delay(1.8, function()
            if messageDisplay.Text == payload.text then
                messageDisplay.Visible = false
            end
        end)
    end
end)

refreshCoins()
