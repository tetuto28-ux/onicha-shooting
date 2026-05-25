local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local AnomalyFoundEvent = remotes:WaitForChild("AnomalyFoundEvent")

local function hookAnomaly(instance)
    if not instance:IsA("BasePart") then return end
    if not instance:GetAttribute("IsAnomaly") then return end
    local click = instance:FindFirstChildOfClass("ClickDetector") or Instance.new("ClickDetector")
    click.Parent = instance
    click.MaxActivationDistance = 20
    click.MouseClick:Connect(function()
        local roomId = instance:GetAttribute("RoomId") or 1
        local anomalyName = instance:GetAttribute("AnomalyName") or instance.Name
        instance.Transparency = 0.45
        AnomalyFoundEvent:FireServer(roomId, anomalyName, instance)
    end)
end

for _, desc in ipairs(workspace:GetDescendants()) do
    hookAnomaly(desc)
end
workspace.DescendantAdded:Connect(hookAnomaly)
