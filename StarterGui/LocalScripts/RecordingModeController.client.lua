local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI", 10)
if not gui then
    return
end

local overlay = gui:FindFirstChild("RecordingOverlay")
if not overlay then
    return
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == Enum.KeyCode.R then
        overlay.Visible = not overlay.Visible
    end
end)
