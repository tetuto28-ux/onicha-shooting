local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local AnomalyFoundEvent = remotes:WaitForChild("AnomalyFoundEvent")
local localFound = {}
local localCoins = 0
local localFoundCount = 0

local function updateDemoUi(reward)
    local player = game:GetService("Players").LocalPlayer
    local gui = player:FindFirstChild("PlayerGui")
    local mainUi = gui and gui:FindFirstChild("MainUI")
    if not mainUi then return end

    localCoins += reward
    localFoundCount += 1

    local coinDisplay = mainUi:FindFirstChild("CoinDisplay")
    if coinDisplay then
        coinDisplay.Text = "Coins: " .. tostring(localCoins)
    end

    local foundCounter = mainUi:FindFirstChild("FoundCounter")
    if foundCounter then
        foundCounter.Text = "Found: " .. tostring(localFoundCount) .. "/3"
    end

    local messageDisplay = mainUi:FindFirstChild("MessageDisplay")
    if messageDisplay then
        messageDisplay.Text = "Found! +" .. tostring(reward)
        messageDisplay.Visible = true
    end
end

local function hookAnomaly(instance)
    if not instance:IsA("BasePart") then return end
    if not instance:GetAttribute("IsAnomaly") then return end
    local click = instance:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
    click.Parent = instance
    click.MaxActivationDistance = 100
    click.MouseClick:Connect(function()
        local roomId = instance:GetAttribute("RoomId") or 1
        local anomalyName = instance:GetAttribute("AnomalyName") or instance.Name
        if localFound[anomalyName] then
            return
        end

        localFound[anomalyName] = true
        instance.Transparency = 0.45
        updateDemoUi(instance:GetAttribute("Reward") or 10)
        AnomalyFoundEvent:FireServer(roomId, anomalyName, instance)
    end)
end

for _, desc in ipairs(workspace:GetDescendants()) do
    hookAnomaly(desc)
end
workspace.DescendantAdded:Connect(hookAnomaly)
