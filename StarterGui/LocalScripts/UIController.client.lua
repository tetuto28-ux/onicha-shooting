local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ROOM_SPACING = 90
local ROOM_COUNT = 3
local PER_ROOM = 3
local TOTAL_ODDITIES = ROOM_COUNT * PER_ROOM
local HINT_COOLDOWN = 5

local PANEL_BG = Color3.fromRGB(16, 20, 32)
local ACCENT = Color3.fromRGB(120, 200, 255)
local GOLD = Color3.fromRGB(255, 216, 102)
local GREEN = Color3.fromRGB(120, 230, 150)
local HINT_COLOR = Color3.fromRGB(232, 168, 56)

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
makeLabel("CoinDisplay", UDim2.new(0, 24, 0, 98), UDim2.new(0, 240, 0, 44), "Coins: 0", 28, GOLD)
makeLabel("RoomDisplay", UDim2.new(0, 24, 0, 150), UDim2.new(0, 240, 0, 44), "Room: 001", 28, ACCENT)
makeLabel("FoundCounter", UDim2.new(0, 24, 0, 202), UDim2.new(0, 240, 0, 44), "Found: 0/3", 28, GREEN)
local timeDisplay = makeLabel("TimeDisplay", UDim2.new(0, 24, 0, 254), UDim2.new(0, 240, 0, 44), "Time: 0:00", 28, Color3.fromRGB(220, 220, 235))

local hint = makeLabel("HintDisplay", UDim2.new(0.5, -320, 1, -70), UDim2.new(0, 640, 0, 48), "Look for the odd object in each room, then click or touch it. Stuck? Press H for a hint.", 21)
hint.TextXAlignment = Enum.TextXAlignment.Center

local message = makeLabel("MessageDisplay", UDim2.new(0.5, -260, 0, 110), UDim2.new(0, 520, 0, 60), "", 34)
message.TextXAlignment = Enum.TextXAlignment.Center
message.BackgroundTransparency = 0.08
message.Visible = false
stroke(message, GOLD, 2, 0.3)

local overlay = makeLabel("RecordingOverlay", UDim2.new(1, -470, 0, 40), UDim2.new(0, 440, 0, 52), "Recording mode: find the odd things.", 22, Color3.fromRGB(255, 120, 120))
overlay.TextXAlignment = Enum.TextXAlignment.Center
overlay.Visible = false

-- Hint button (bottom-right).
local hintButton = gui:FindFirstChild("HintButton") or Instance.new("TextButton")
hintButton.Name = "HintButton"
hintButton.BackgroundColor3 = HINT_COLOR
hintButton.BorderSizePixel = 0
hintButton.Font = Enum.Font.GothamBold
hintButton.AnchorPoint = Vector2.new(1, 1)
hintButton.Position = UDim2.new(1, -24, 1, -24)
hintButton.Size = UDim2.new(0, 200, 0, 54)
hintButton.Text = "💡 Hint (H)"
hintButton.TextColor3 = Color3.fromRGB(30, 24, 12)
hintButton.TextSize = 26
hintButton.AutoButtonColor = true
hintButton.Parent = gui
round(hintButton, 14)
stroke(hintButton, Color3.fromRGB(255, 244, 210), 2, 0.2)

-- A big title card shown briefly at the start of a run.
local titleCard = gui:FindFirstChild("TitleCard") or Instance.new("TextLabel")
titleCard.Name = "TitleCard"
titleCard.BackgroundTransparency = 1
titleCard.Font = Enum.Font.GothamBlack
titleCard.AnchorPoint = Vector2.new(0.5, 0.5)
titleCard.Position = UDim2.new(0.5, 0, 0.32, 0)
titleCard.Size = UDim2.new(0, 700, 0, 90)
titleCard.Text = "🔍 ODDITY HUNT"
titleCard.TextColor3 = Color3.fromRGB(255, 255, 255)
titleCard.TextSize = 64
titleCard.TextTransparency = 1
titleCard.Visible = true
titleCard.Parent = gui
stroke(titleCard, Color3.fromRGB(0, 0, 0), 3, 0.2)

-- Win panel (centered, hidden until all rooms cleared).
local winPanel = gui:FindFirstChild("WinPanel") or Instance.new("Frame")
winPanel.Name = "WinPanel"
winPanel.AnchorPoint = Vector2.new(0.5, 0.5)
winPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
winPanel.Size = UDim2.new(0, 380, 0, 320)
winPanel.BackgroundColor3 = PANEL_BG
winPanel.BackgroundTransparency = 0.05
winPanel.BorderSizePixel = 0
winPanel.Visible = false
winPanel.Parent = gui
round(winPanel, 20)
stroke(winPanel, GOLD, 2.5, 0.2)

local winLayout = winPanel:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
winLayout.FillDirection = Enum.FillDirection.Vertical
winLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
winLayout.VerticalAlignment = Enum.VerticalAlignment.Center
winLayout.Padding = UDim.new(0, 12)
winLayout.Parent = winPanel

local winTitle = winPanel:FindFirstChild("WinTitle") or Instance.new("TextLabel")
winTitle.Name = "WinTitle"
winTitle.BackgroundTransparency = 1
winTitle.Font = Enum.Font.GothamBlack
winTitle.Size = UDim2.new(1, -30, 0, 54)
winTitle.Text = "🎉 All Rooms Clear!"
winTitle.TextColor3 = GOLD
winTitle.TextSize = 32
winTitle.TextWrapped = true
winTitle.LayoutOrder = 1
winTitle.Parent = winPanel

local winStats = winPanel:FindFirstChild("WinStats") or Instance.new("TextLabel")
winStats.Name = "WinStats"
winStats.BackgroundTransparency = 1
winStats.Font = Enum.Font.GothamMedium
winStats.Size = UDim2.new(1, -40, 0, 130)
winStats.Text = ""
winStats.TextColor3 = Color3.fromRGB(235, 238, 245)
winStats.TextSize = 24
winStats.LayoutOrder = 2
winStats.Parent = winPanel

local playAgain = winPanel:FindFirstChild("PlayAgainButton") or Instance.new("TextButton")
playAgain.Name = "PlayAgainButton"
playAgain.BackgroundColor3 = Color3.fromRGB(46, 134, 222)
playAgain.BorderSizePixel = 0
playAgain.Font = Enum.Font.GothamBold
playAgain.Size = UDim2.new(0, 240, 0, 58)
playAgain.Text = "▶ Play Again"
playAgain.TextColor3 = Color3.fromRGB(255, 255, 255)
playAgain.TextSize = 28
playAgain.AutoButtonColor = true
playAgain.LayoutOrder = 3
playAgain.Parent = winPanel
round(playAgain, 16)
stroke(playAgain, Color3.fromRGB(255, 255, 255), 2, 0.3)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIMessageEvent = remotes:WaitForChild("UIMessageEvent")
local ReplayEvent = remotes:WaitForChild("ReplayEvent")

local coinDisplay = gui:WaitForChild("CoinDisplay")
local roomDisplay = gui:WaitForChild("RoomDisplay")
local messageDisplay = gui:WaitForChild("MessageDisplay")
local foundCounter = gui:WaitForChild("FoundCounter")

-- ---------------------------------------------------------------------------
-- Coins
-- ---------------------------------------------------------------------------
local coinConnection

local function getCoins()
    local stats = player:FindFirstChild("leaderstats")
    local coins = stats and stats:FindFirstChild("Coins")
    return coins and coins.Value or 0
end

local function refreshCoins()
    coinDisplay.Text = "Coins: " .. tostring(getCoins())
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

-- ---------------------------------------------------------------------------
-- Timer
-- ---------------------------------------------------------------------------
local startTime = os.clock()
local running = true
local bestTime = nil

local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function elapsed()
    return os.clock() - startTime
end

local function restartTimer()
    startTime = os.clock()
    running = true
end

RunService.Heartbeat:Connect(function()
    if running then
        timeDisplay.Text = "Time: " .. formatTime(elapsed())
    end
end)

-- ---------------------------------------------------------------------------
-- Title card
-- ---------------------------------------------------------------------------
local function showTitleCard()
    titleCard.TextTransparency = 0
    local stroked = titleCard:FindFirstChildOfClass("UIStroke")
    if stroked then
        stroked.Transparency = 0.2
    end
    task.delay(2.0, function()
        local fade = TweenService:Create(titleCard, TweenInfo.new(1.0), { TextTransparency = 1 })
        fade:Play()
        if stroked then
            TweenService:Create(stroked, TweenInfo.new(1.0), { Transparency = 1 }):Play()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Hint system
-- ---------------------------------------------------------------------------
local lastHint = -math.huge

local function currentRoomIndex()
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return 1
    end
    return math.clamp(math.floor(hrp.Position.X / ROOM_SPACING + 0.5) + 1, 1, ROOM_COUNT)
end

local function showToast(text, color, seconds)
    messageDisplay.TextColor3 = color or GOLD
    messageDisplay.Text = text
    messageDisplay.Visible = true
    task.delay(seconds or 1.6, function()
        if messageDisplay.Text == text and not winPanel.Visible then
            messageDisplay.Visible = false
        end
    end)
end

local function startHintCooldown()
    task.spawn(function()
        hintButton.Active = false
        hintButton.AutoButtonColor = false
        local remaining = HINT_COOLDOWN
        while remaining > 0 do
            hintButton.Text = "Hint  " .. tostring(math.ceil(remaining)) .. "s"
            hintButton.BackgroundColor3 = Color3.fromRGB(78, 86, 104)
            task.wait(0.25)
            remaining -= 0.25
        end
        hintButton.Text = "💡 Hint (H)"
        hintButton.BackgroundColor3 = HINT_COLOR
        hintButton.Active = true
        hintButton.AutoButtonColor = true
    end)
end

local function doHint()
    if winPanel.Visible then
        return
    end
    local now = os.clock()
    if now - lastHint < HINT_COOLDOWN then
        return
    end

    local demo = Workspace:FindFirstChild("OnichaShootingDemo")
    local rooms = demo and demo:FindFirstChild("Rooms")
    local roomModel = rooms and rooms:FindFirstChild(string.format("Room%03d", currentRoomIndex()))
    if not roomModel then
        return
    end

    local revealed = 0
    for _, m in ipairs(roomModel:GetChildren()) do
        if m:IsA("Model") and m.PrimaryPart and m.PrimaryPart:GetAttribute("IsAnomaly") and not m.PrimaryPart:GetAttribute("Found") then
            local marker = m:FindFirstChild("Marker")
            if marker and marker:IsA("Highlight") then
                marker.Enabled = true
                revealed += 1
                local target = m
                task.delay(2.4, function()
                    if target.PrimaryPart and not target.PrimaryPart:GetAttribute("Found") then
                        marker.Enabled = false
                    end
                end)
            end
        end
    end

    lastHint = now
    startHintCooldown()
    if revealed > 0 then
        showToast("Hint! Look at the outlined object.", HINT_COLOR, 2.2)
    else
        showToast("Nothing left to find here.", HINT_COLOR, 1.6)
    end
end

hintButton.MouseButton1Click:Connect(doHint)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == Enum.KeyCode.H then
        doHint()
    end
end)

-- ---------------------------------------------------------------------------
-- Win panel
-- ---------------------------------------------------------------------------
local function showWin()
    running = false
    local finalTime = elapsed()
    if bestTime == nil or finalTime < bestTime then
        bestTime = finalTime
    end
    winStats.Text = string.format(
        "Time   %s\nBest   %s\nCoins   %d\nFound   %d/%d",
        formatTime(finalTime),
        formatTime(bestTime),
        getCoins(),
        TOTAL_ODDITIES,
        TOTAL_ODDITIES
    )
    winPanel.Visible = true
end

playAgain.MouseButton1Click:Connect(function()
    winPanel.Visible = false
    messageDisplay.Visible = false
    restartTimer()
    ReplayEvent:FireServer()
    showTitleCard()
end)

-- ---------------------------------------------------------------------------
-- Server messages
-- ---------------------------------------------------------------------------
UIMessageEvent.OnClientEvent:Connect(function(payload)
    if payload.room then
        roomDisplay.Text = string.format("Room: %03d", payload.room)
    end
    if payload.found then
        foundCounter.Text = "Found: " .. tostring(payload.found) .. "/" .. tostring(PER_ROOM)
    end

    if payload.kind == "GameComplete" then
        showWin()
    elseif payload.kind == "Replay" then
        winPanel.Visible = false
        foundCounter.Text = "Found: 0/" .. tostring(PER_ROOM)
        roomDisplay.Text = "Room: 001"
        restartTimer()
    elseif payload.kind == "RoomStart" then
        restartTimer()
        showTitleCard()
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
            if messageDisplay.Text == payload.text and not winPanel.Visible then
                messageDisplay.Visible = false
            end
        end)
    end
end)

refreshCoins()
showTitleCard()
