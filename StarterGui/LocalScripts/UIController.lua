local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
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
