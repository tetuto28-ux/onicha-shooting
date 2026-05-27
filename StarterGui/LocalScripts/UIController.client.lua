-- Oddity Hunt - "declare" mode client.
-- Click objects you think are oddities to flag them, then press Confirm.
-- Flagging a normal object, or missing an oddity, costs a life.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ROOM_COUNT = 3
local ROOM_SPACING = 90
local ROOM_TIME = 60
local START_LIVES = 3
local MAX_HINTS = 3

local ROOM_ORIGINS = {}
for i = 1, ROOM_COUNT do
    ROOM_ORIGINS[i] = Vector3.new(ROOM_SPACING * (i - 1), 0, -18)
end

local PANEL_BG = Color3.fromRGB(16, 20, 32)
local ACCENT = Color3.fromRGB(120, 200, 255)
local GOLD = Color3.fromRGB(255, 216, 102)
local GREEN = Color3.fromRGB(120, 230, 150)
local RED = Color3.fromRGB(255, 110, 110)
local HINT_COLOR = Color3.fromRGB(232, 168, 56)

-- ---------------------------------------------------------------------------
-- UI scaffolding
-- ---------------------------------------------------------------------------
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
    label.TextSize = textSize or 26
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

makeLabel("TitleDisplay", UDim2.new(0, 24, 0, 36), UDim2.new(0, 300, 0, 46), "🔍 Oddity Hunt", 28, GOLD)
local livesDisplay = makeLabel("LivesDisplay", UDim2.new(0, 24, 0, 90), UDim2.new(0, 240, 0, 42), "Lives: ♥♥♥", 26, RED)
local roomDisplay = makeLabel("RoomDisplay", UDim2.new(0, 24, 0, 138), UDim2.new(0, 240, 0, 42), "Room: 1/3", 26, ACCENT)
local scoreDisplay = makeLabel("ScoreDisplay", UDim2.new(0, 24, 0, 186), UDim2.new(0, 240, 0, 42), "Score: 0", 26, GOLD)
local timeDisplay = makeLabel("TimeDisplay", UDim2.new(0, 24, 0, 234), UDim2.new(0, 240, 0, 42), "Time: 60", 26, Color3.fromRGB(220, 220, 235))
local flagDisplay = makeLabel("FlagDisplay", UDim2.new(0, 24, 0, 282), UDim2.new(0, 240, 0, 42), "Flagged: 0", 26, HINT_COLOR)

local hintText = makeLabel("HintDisplay", UDim2.new(0.5, -340, 1, -64), UDim2.new(0, 680, 0, 44), "Click anything that looks WRONG to flag it. Found them all? Press Confirm (F). Flagging a normal thing, or missing one, costs a life.", 19)
hintText.TextXAlignment = Enum.TextXAlignment.Center

local message = makeLabel("MessageDisplay", UDim2.new(0.5, -260, 0, 100), UDim2.new(0, 520, 0, 58), "", 32)
message.TextXAlignment = Enum.TextXAlignment.Center
message.BackgroundTransparency = 0.08
message.Visible = false
stroke(message, GOLD, 2, 0.3)

local overlay = makeLabel("RecordingOverlay", UDim2.new(1, -470, 0, 36), UDim2.new(0, 440, 0, 50), "Recording mode: find the odd things.", 22, RED)
overlay.TextXAlignment = Enum.TextXAlignment.Center
overlay.Visible = false

local confirmButton = gui:FindFirstChild("ConfirmButton") or Instance.new("TextButton")
confirmButton.Name = "ConfirmButton"
confirmButton.AnchorPoint = Vector2.new(0.5, 1)
confirmButton.Position = UDim2.new(0.5, -130, 1, -76)
confirmButton.Size = UDim2.new(0, 230, 0, 56)
confirmButton.BackgroundColor3 = Color3.fromRGB(46, 134, 222)
confirmButton.BorderSizePixel = 0
confirmButton.Font = Enum.Font.GothamBold
confirmButton.Text = "✓ Confirm (F)"
confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmButton.TextSize = 26
confirmButton.Parent = gui
round(confirmButton, 14)
stroke(confirmButton, Color3.fromRGB(255, 255, 255), 2, 0.3)

local hintButton = gui:FindFirstChild("HintButton") or Instance.new("TextButton")
hintButton.Name = "HintButton"
hintButton.AnchorPoint = Vector2.new(0.5, 1)
hintButton.Position = UDim2.new(0.5, 130, 1, -76)
hintButton.Size = UDim2.new(0, 200, 0, 56)
hintButton.BackgroundColor3 = HINT_COLOR
hintButton.BorderSizePixel = 0
hintButton.Font = Enum.Font.GothamBold
hintButton.Text = "💡 Hint x3 (H)"
hintButton.TextColor3 = Color3.fromRGB(30, 24, 12)
hintButton.TextSize = 24
hintButton.Parent = gui
round(hintButton, 14)
stroke(hintButton, Color3.fromRGB(255, 244, 210), 2, 0.25)

-- Result panel (win or game over).
local panel = gui:FindFirstChild("ResultPanel") or Instance.new("Frame")
panel.Name = "ResultPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 380, 0, 320)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
round(panel, 20)
stroke(panel, GOLD, 2.5, 0.2)

local panelLayout = panel:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
panelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
panelLayout.Padding = UDim.new(0, 14)
panelLayout.Parent = panel

local panelTitle = panel:FindFirstChild("PanelTitle") or Instance.new("TextLabel")
panelTitle.Name = "PanelTitle"
panelTitle.BackgroundTransparency = 1
panelTitle.Font = Enum.Font.GothamBlack
panelTitle.Size = UDim2.new(1, -30, 0, 56)
panelTitle.Text = ""
panelTitle.TextColor3 = GOLD
panelTitle.TextSize = 34
panelTitle.TextWrapped = true
panelTitle.LayoutOrder = 1
panelTitle.Parent = panel

local panelStats = panel:FindFirstChild("PanelStats") or Instance.new("TextLabel")
panelStats.Name = "PanelStats"
panelStats.BackgroundTransparency = 1
panelStats.Font = Enum.Font.GothamMedium
panelStats.Size = UDim2.new(1, -40, 0, 120)
panelStats.Text = ""
panelStats.TextColor3 = Color3.fromRGB(235, 238, 245)
panelStats.TextSize = 24
panelStats.LayoutOrder = 2
panelStats.Parent = panel

local playAgain = panel:FindFirstChild("PlayAgainButton") or Instance.new("TextButton")
playAgain.Name = "PlayAgainButton"
playAgain.BackgroundColor3 = Color3.fromRGB(46, 134, 222)
playAgain.BorderSizePixel = 0
playAgain.Font = Enum.Font.GothamBold
playAgain.Size = UDim2.new(0, 240, 0, 56)
playAgain.Text = "▶ Play Again"
playAgain.TextColor3 = Color3.fromRGB(255, 255, 255)
playAgain.TextSize = 28
playAgain.LayoutOrder = 3
playAgain.Parent = panel
round(playAgain, 16)
stroke(playAgain, Color3.fromRGB(255, 255, 255), 2, 0.3)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIMessageEvent = remotes:WaitForChild("UIMessageEvent")
local ReplayEvent = remotes:WaitForChild("ReplayEvent")

-- ---------------------------------------------------------------------------
-- Game state
-- ---------------------------------------------------------------------------
local lives = START_LIVES
local score = 0
local currentRoom = 1
local cleared = 0
local hintsLeft = MAX_HINTS
local roomEndTime = os.clock() + ROOM_TIME
local roomTimerId = 0
local active = false
local runStart = os.clock()
local bestScore = nil

local flagged = {} -- model -> true

local function roomsFolder()
    local demo = Workspace:FindFirstChild("OnichaShootingDemo")
    return demo and demo:FindFirstChild("Rooms")
end

local function currentRoomModel()
    local rooms = roomsFolder()
    return rooms and rooms:FindFirstChild(string.format("Room%03d", currentRoom))
end

local function inspectableModels(roomModel)
    local list = {}
    if not roomModel then
        return list
    end
    for _, child in ipairs(roomModel:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("Inspectable") then
            table.insert(list, child)
        end
    end
    return list
end

local function setFlagVisual(model, on)
    local existing = model:FindFirstChild("FlagMark")
    local existingQ = model:FindFirstChild("FlagQ")
    if on then
        if not existing then
            local hl = Instance.new("Highlight")
            hl.Name = "FlagMark"
            hl.FillColor = Color3.fromRGB(255, 140, 40)
            hl.FillTransparency = 0.45
            hl.OutlineColor = Color3.fromRGB(255, 80, 80)
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Adornee = model
            hl.Parent = model
        end
        if not existingQ and model.PrimaryPart then
            local bb = Instance.new("BillboardGui")
            bb.Name = "FlagQ"
            bb.AlwaysOnTop = true
            bb.Size = UDim2.new(0, 48, 0, 48)
            bb.StudsOffset = Vector3.new(0, 3, 0)
            bb.Adornee = model.PrimaryPart
            bb.Parent = model.PrimaryPart
            local t = Instance.new("TextLabel")
            t.BackgroundTransparency = 1
            t.Size = UDim2.fromScale(1, 1)
            t.Font = Enum.Font.GothamBlack
            t.Text = "❓"
            t.TextScaled = true
            t.TextColor3 = Color3.fromRGB(255, 200, 60)
            t.Parent = bb
        end
    else
        if existing then existing:Destroy() end
        if existingQ then existingQ:Destroy() end
    end
end

local function countFlaggedHere()
    local n = 0
    local roomModel = currentRoomModel()
    for model in pairs(flagged) do
        if model.Parent and roomModel and model:IsDescendantOf(roomModel) then
            n += 1
        end
    end
    return n
end

local function livesString()
    local s = ""
    for i = 1, START_LIVES do
        s = s .. (i <= lives and "♥" or "♡")
    end
    return s
end

local function updateHud()
    livesDisplay.Text = "Lives: " .. livesString()
    roomDisplay.Text = string.format("Room: %d/%d", math.min(currentRoom, ROOM_COUNT), ROOM_COUNT)
    scoreDisplay.Text = "Score: " .. tostring(score)
    flagDisplay.Text = "Flagged: " .. tostring(countFlaggedHere())
    hintButton.Text = string.format("💡 Hint x%d (H)", hintsLeft)
end

local function showMessage(text, color, seconds)
    message.TextColor3 = color or GOLD
    message.Text = text
    message.Visible = true
    task.delay(seconds or 2.0, function()
        if message.Text == text and not panel.Visible then
            message.Visible = false
        end
    end)
end

local function clearFlags()
    for model in pairs(flagged) do
        if model.Parent then
            setFlagVisual(model, false)
        end
    end
    flagged = {}
end

local function teleportTo(roomId)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart", 5)
    local origin = ROOM_ORIGINS[roomId]
    if hrp and origin then
        hrp.CFrame = CFrame.new(origin + Vector3.new(0, 5, 18), origin + Vector3.new(0, 4, -20))
    end
end

-- ---------------------------------------------------------------------------
-- Click / flag handling
-- ---------------------------------------------------------------------------
local function toggleFlag(model)
    if not active then
        return
    end
    if not model.Parent then
        return
    end
    local roomModel = currentRoomModel()
    if not roomModel or not model:IsDescendantOf(roomModel) then
        showMessage("Look around THIS room first.", ACCENT, 1.2)
        return
    end
    if flagged[model] then
        flagged[model] = nil
        setFlagVisual(model, false)
    else
        flagged[model] = true
        setFlagVisual(model, true)
    end
    updateHud()
end

local function hookModel(model)
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and not p:FindFirstChild("FlagClick") then
            local cd = Instance.new("ClickDetector")
            cd.Name = "FlagClick"
            cd.MaxActivationDistance = 64
            cd.Parent = p
            cd.MouseClick:Connect(function()
                toggleFlag(model)
            end)
        end
    end
end

local function hookAllRooms()
    local rooms = roomsFolder()
    if not rooms then
        return
    end
    for _, roomModel in ipairs(rooms:GetChildren()) do
        for _, m in ipairs(inspectableModels(roomModel)) do
            hookModel(m)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Round / result flow
-- ---------------------------------------------------------------------------
local startRoom

local function finishGame(victory)
    active = false
    roomTimerId += 1
    clearFlags()
    if bestScore == nil or score > bestScore then
        bestScore = score
    end
    panelTitle.Text = victory and "🎉 Escaped!" or "💀 Game Over"
    panelTitle.TextColor3 = victory and GOLD or RED
    panelStats.Text = string.format(
        "Score   %d\nBest    %d\nRooms   %d/%d\nTime    %s",
        score,
        bestScore,
        cleared,
        ROOM_COUNT,
        string.format("%d:%02d", math.floor((os.clock() - runStart) / 60), math.floor((os.clock() - runStart) % 60))
    )
    panel.Visible = true
end

local function revealAnswers()
    local roomModel = currentRoomModel()
    for _, m in ipairs(inspectableModels(roomModel)) do
        if m:GetAttribute("IsAnomaly") then
            local hint = m:FindFirstChild("HintMarker")
            if hint and hint:IsA("Highlight") then
                hint.Enabled = true
                task.delay(2.2, function()
                    if hint and hint.Parent then
                        hint.Enabled = false
                    end
                end)
            end
        end
    end
end

local function advanceRoom()
    clearFlags()
    currentRoom += 1
    if currentRoom > ROOM_COUNT then
        finishGame(cleared >= ROOM_COUNT)
        return
    end
    teleportTo(currentRoom)
    startRoom()
end

local function loseLife(reason)
    lives -= 1
    updateHud()
    showMessage(reason .. "  (Life -1)", RED, 1.8)
    if lives <= 0 then
        active = false
        task.delay(0.6, function()
            finishGame(false)
        end)
        return true
    end
    return false
end

local confirmCooldown = false

local function confirm()
    if not active or confirmCooldown then
        return
    end
    confirmCooldown = true
    task.delay(0.4, function()
        confirmCooldown = false
    end)

    local roomModel = currentRoomModel()
    local errors = 0
    for _, m in ipairs(inspectableModels(roomModel)) do
        local truth = m:GetAttribute("IsAnomaly") == true
        local isFlagged = flagged[m] == true
        if truth ~= isFlagged then
            errors += 1
        end
    end

    if errors == 0 then
        active = false
        cleared += 1
        local remaining = math.max(0, roomEndTime - os.clock())
        score += 10 + math.floor(remaining / 5)
        updateHud()
        showMessage("Correct! Next room...", GREEN, 1.6)
        task.delay(1.0, advanceRoom)
    else
        loseLife("Wrong!")
    end
end

local function doHint()
    if not active then
        return
    end
    if hintsLeft <= 0 then
        showMessage("No hints left.", HINT_COLOR, 1.4)
        return
    end
    local roomModel = currentRoomModel()
    local target
    for _, m in ipairs(inspectableModels(roomModel)) do
        if m:GetAttribute("IsAnomaly") and not flagged[m] then
            target = m
            break
        end
    end
    hintsLeft -= 1
    updateHud()
    if target then
        local hint = target:FindFirstChild("HintMarker")
        if hint and hint:IsA("Highlight") then
            hint.Enabled = true
            task.delay(2.0, function()
                if hint and hint.Parent then
                    hint.Enabled = false
                end
            end)
        end
        showMessage("Hint: something here is wrong!", HINT_COLOR, 2.0)
    else
        showMessage("Hint: maybe nothing is wrong here...", HINT_COLOR, 2.0)
    end
end

startRoom = function()
    roomTimerId += 1
    roomEndTime = os.clock() + ROOM_TIME
    active = true
    updateHud()
    showMessage(string.format("Room %d: spot the oddities!", currentRoom), GOLD, 2.0)
end

local function startGame()
    local rooms = roomsFolder()
    if not rooms then
        return
    end
    clearFlags()
    lives = START_LIVES
    score = 0
    cleared = 0
    currentRoom = 1
    hintsLeft = MAX_HINTS
    runStart = os.clock()
    panel.Visible = false
    message.Visible = false
    hookAllRooms()
    teleportTo(1)
    startRoom()
end

-- ---------------------------------------------------------------------------
-- Timer
-- ---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    if not active then
        return
    end
    local remaining = math.max(0, roomEndTime - os.clock())
    timeDisplay.Text = "Time: " .. tostring(math.ceil(remaining))
    timeDisplay.TextColor3 = remaining <= 10 and RED or Color3.fromRGB(220, 220, 235)
    if remaining <= 0 then
        active = false
        local myId = roomTimerId
        revealAnswers()
        local out = loseLife("Time up!")
        if not out then
            task.delay(2.2, function()
                if roomTimerId == myId then
                    advanceRoom()
                end
            end)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Inputs
-- ---------------------------------------------------------------------------
confirmButton.MouseButton1Click:Connect(confirm)
hintButton.MouseButton1Click:Connect(doHint)
playAgain.MouseButton1Click:Connect(function()
    panel.Visible = false
    ReplayEvent:FireServer()
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == Enum.KeyCode.F then
        confirm()
    elseif input.KeyCode == Enum.KeyCode.H then
        doHint()
    end
end)

-- ---------------------------------------------------------------------------
-- Server messages
-- ---------------------------------------------------------------------------
UIMessageEvent.OnClientEvent:Connect(function(payload)
    if payload.kind == "WorldReady" then
        task.wait(0.3)
        startGame()
    end
end)

-- Cold start in case the WorldReady message arrived before we connected.
task.spawn(function()
    local demo = Workspace:WaitForChild("OnichaShootingDemo", 15)
    if demo then
        demo:WaitForChild("Rooms", 5)
        task.wait(0.3)
        if not active and not panel.Visible then
            startGame()
        end
    end
end)
