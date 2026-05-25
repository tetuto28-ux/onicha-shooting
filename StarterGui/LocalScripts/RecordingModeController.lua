local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local overlay = gui:WaitForChild("RecordingOverlay")

overlay.Visible = false
overlay.Text = "この部屋の違和感、見つけられる？ (Rで撮影UI ON/OFF)"

if overlay:IsA("TextLabel") then
    overlay.AnchorPoint = Vector2.new(1, 0)
    overlay.Position = UDim2.new(1, -20, 0, 20)
    overlay.Size = UDim2.new(0, 420, 0, 44)
    overlay.TextScaled = true
    overlay.TextWrapped = true
    overlay.BackgroundTransparency = 0.3
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.R then
        overlay.Visible = not overlay.Visible
    end
end)
