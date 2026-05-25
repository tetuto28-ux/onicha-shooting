local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local overlay = gui:WaitForChild("RecordingOverlay")

overlay.Visible = true
overlay.Text = "この部屋の違和感、見つけられる？ (Rで撮影UI ON/OFF)"

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.R then
        overlay.Visible = not overlay.Visible
    end
end)
