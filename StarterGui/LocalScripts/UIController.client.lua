-- Spot-the-difference client.
-- Memorize the wide map once, then each round one object changes (move / rotate
-- / recolour) -- or, rarely, nothing changes. Walk around, click the thing that
-- changed, or press "No change". Wrong answers cost a life; the find timer
-- shrinks every round, so a run always ends eventually. Score = rounds survived.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STUDY_TIME = 25
local MAX_MISSES = 3
local MAX_HINTS = 3
local NO_CHANGE_CHANCE = 0.12
local TRANSITION_TIME = 1.2

local PANEL_BG = Color3.fromRGB(16, 20, 32)
local ACCENT = Color3.fromRGB(120, 200, 255)
local GOLD = Color3.fromRGB(255, 216, 102)
local GREEN = Color3.fromRGB(120, 230, 150)
local RED = Color3.fromRGB(255, 110, 110)
local HINT_COLOR = Color3.fromRGB(232, 168, 56)

local RECOLOR_TARGETS = {
    Color3.fromRGB(230, 90, 90), Color3.fromRGB(90, 160, 230), Color3.fromRGB(110, 210, 120),
    Color3.fromRGB(240, 200, 80), Color3.fromRGB(200, 110, 220), Color3.fromRGB(240, 150, 90),
}

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

makeLabel("TitleDisplay", UDim2.new(0, 24, 0, 32), UDim2.new(0, 300, 0, 44), "🔍 Spot the Difference", 24, GOLD)
local roundDisplay = makeLabel("RoundDisplay", UDim2.new(0, 24, 0, 84), UDim2.new(0, 230, 0, 42), "Round: -", 26, ACCENT)
local scoreDisplay = makeLabel("ScoreDisplay", UDim2.new(0, 24, 0, 130), UDim2.new(0, 230, 0, 42), "Score: 0", 26, GOLD)
local missDisplay = makeLabel("MissDisplay", UDim2.new(0, 24, 0, 176), UDim2.new(0, 230, 0, 42), "Lives: ♥♥♥", 26, RED)
local timeDisplay = makeLabel("TimeDisplay", UDim2.new(0, 24, 0, 222), UDim2.new(0, 230, 0, 42), "Time: --", 26, Color3.fromRGB(220, 220, 235))
local hintDisplay = makeLabel("HintCountDisplay", UDim2.new(0, 24, 0, 268), UDim2.new(0, 230, 0, 42), "Hints: 3", 26, HINT_COLOR)

local banner = makeLabel("Banner", UDim2.new(0.5, -300, 0, 92), UDim2.new(0, 600, 0, 58), "", 32)
banner.TextXAlignment = Enum.TextXAlignment.Center
banner.BackgroundTransparency = 0.08
banner.Visible = false
banner.ZIndex = 55
stroke(banner, GOLD, 2, 0.3)

local overlay = makeLabel("RecordingOverlay", UDim2.new(1, -470, 0, 32), UDim2.new(0, 440, 0, 48), "Recording mode.", 22, RED)
overlay.TextXAlignment = Enum.TextXAlignment.Center
overlay.Visible = false

local function makeButton(name, anchorX, posX, text, bg, fg)
    local b = gui:FindFirstChild(name) or Instance.new("TextButton")
    b.Name = name
    b.AnchorPoint = Vector2.new(anchorX, 1)
    b.Position = UDim2.new(0.5, posX, 1, -64)
    b.Size = UDim2.new(0, 210, 0, 54)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.TextColor3 = fg
    b.TextSize = 24
    b.Visible = false
    b.Parent = gui
    round(b, 14)
    stroke(b, Color3.fromRGB(255, 255, 255), 2, 0.3)
    return b
end

local startButton = makeButton("StartButton", 0.5, -105, "▶ Start (Space)", Color3.fromRGB(46, 134, 222), Color3.fromRGB(255, 255, 255))
local noChangeButton = makeButton("NoChangeButton", 1, -12, "No Change (G)", Color3.fromRGB(90, 96, 116), Color3.fromRGB(255, 255, 255))
local hintBtn = makeButton("HintButton", 0, 12, "💡 Hint (H)", HINT_COLOR, Color3.fromRGB(30, 24, 12))

-- Dim overlay used to hide the moment of change between rounds.
local dim = gui:FindFirstChild("DimOverlay") or Instance.new("Frame")
dim.Name = "DimOverlay"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.ZIndex = 50
dim.Visible = false
dim.Parent = gui

-- Result panel
local panel = gui:FindFirstChild("ResultPanel") or Instance.new("Frame")
panel.Name = "ResultPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 380, 0, 300)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.ZIndex = 60
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
panelTitle.Size = UDim2.new(1, -30, 0, 54)
panelTitle.Text = "Game Over"
panelTitle.TextColor3 = RED
panelTitle.TextSize = 34
panelTitle.ZIndex = 61
panelTitle.LayoutOrder = 1
panelTitle.Parent = panel

local panelStats = panel:FindFirstChild("PanelStats") or Instance.new("TextLabel")
panelStats.Name = "PanelStats"
panelStats.BackgroundTransparency = 1
panelStats.Font = Enum.Font.GothamMedium
panelStats.Size = UDim2.new(1, -40, 0, 110)
panelStats.Text = ""
panelStats.TextColor3 = Color3.fromRGB(235, 238, 245)
panelStats.TextSize = 24
panelStats.ZIndex = 61
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
playAgain.ZIndex = 61
playAgain.LayoutOrder = 3
playAgain.Parent = panel
round(playAgain, 16)
stroke(playAgain, Color3.fromRGB(255, 255, 255), 2, 0.3)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UIMessageEvent = remotes:WaitForChild("UIMessageEvent")
local ReplayEvent = remotes:WaitForChild("ReplayEvent")

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local phase = "idle" -- idle | study | transition | find | resolved | over
local roundNum = 0
local score = 0
local missesLeft = MAX_MISSES
local hintsLeft = MAX_HINTS
local bestScore = 0
local studyEnd = 0
local findEnd = 0

local objects = {}
local originals = {} -- model -> { pivot = CFrame, colors = {part -> Color3} }
local answerModel = nil
local prevAnswer = nil
local isNoChange = false
local hintedThisRound = false

local beginRound
local gameOver

-- ---------------------------------------------------------------------------
-- World helpers
-- ---------------------------------------------------------------------------
local function objectsFolder()
    local demo = Workspace:FindFirstChild("OnichaShootingDemo")
    return demo and demo:FindFirstChild("Objects")
end

local function gatherObjects()
    objects = {}
    local folder = objectsFolder()
    if not folder then
        return
    end
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("Inspectable") then
            table.insert(objects, m)
        end
    end
end

local function storeOriginals()
    originals = {}
    for _, m in ipairs(objects) do
        local colors = {}
        for _, p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                colors[p] = p.Color
            end
        end
        originals[m] = { pivot = m:GetPivot(), colors = colors }
    end
end

local function revertModel(m)
    local o = m and originals[m]
    if not o then
        return
    end
    if m.PrimaryPart then
        m:PivotTo(o.pivot)
    end
    for p, c in pairs(o.colors) do
        if p.Parent then
            p.Color = c
        end
    end
end

local function findTime(r)
    return math.max(8, 32 - (r - 1) * 1.5)
end

local function applyChange(r)
    local m = objects[math.random(1, #objects)]
    answerModel = m
    local o = originals[m]
    local kind = math.random(1, 3)
    if kind == 1 then -- move
        local ang = math.random() * math.pi * 2
        local dist = math.max(2, 7 - (r - 1) * 0.4)
        m:PivotTo(o.pivot + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist))
    elseif kind == 2 then -- rotate
        local sign = (math.random(0, 1) == 0) and 1 or -1
        local deg = math.max(15, 60 - (r - 1) * 3) * sign
        m:PivotTo(o.pivot * CFrame.Angles(0, math.rad(deg), 0))
    else -- recolor
        local intensity = math.max(0.3, 0.75 - (r - 1) * 0.03)
        local target = RECOLOR_TARGETS[math.random(1, #RECOLOR_TARGETS)]
        for p, base in pairs(o.colors) do
            if p.Parent then
                p.Color = base:Lerp(target, intensity)
            end
        end
    end
end

local function flashAnswer(seconds)
    if not answerModel or not answerModel.Parent then
        return
    end
    local hl = answerModel:FindFirstChild("RevealMark") or Instance.new("Highlight")
    hl.Name = "RevealMark"
    hl.FillColor = Color3.fromRGB(255, 150, 40)
    hl.FillTransparency = 0.4
    hl.OutlineColor = Color3.fromRGB(255, 90, 60)
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = answerModel
    hl.Parent = answerModel
    local m = answerModel
    task.delay(seconds or 2.0, function()
        local existing = m:FindFirstChild("RevealMark")
        if existing then
            existing:Destroy()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- UI helpers
-- ---------------------------------------------------------------------------
local function livesString()
    local s = ""
    for i = 1, MAX_MISSES do
        s = s .. (i <= missesLeft and "♥" or "♡")
    end
    return s
end

local function updateHud()
    roundDisplay.Text = "Round: " .. (roundNum > 0 and tostring(roundNum) or "-")
    scoreDisplay.Text = "Score: " .. tostring(score)
    missDisplay.Text = "Lives: " .. livesString()
    hintDisplay.Text = "Hints: " .. tostring(hintsLeft)
end

local function showBanner(text, color)
    banner.TextColor3 = color or GOLD
    banner.Text = text
    banner.Visible = true
end

local function updatePhaseUI()
    startButton.Visible = (phase == "study")
    noChangeButton.Visible = (phase == "find")
    hintBtn.Visible = (phase == "find")
end

local function fadeDimOut()
    local tween = TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
    tween.Completed:Connect(function()
        dim.Visible = false
    end)
    tween:Play()
end

-- ---------------------------------------------------------------------------
-- Round flow
-- ---------------------------------------------------------------------------
local function reward(isBig)
    local timeBonus = math.floor(math.max(0, findEnd - os.clock()) / 2)
    local value = isBig and (60 + roundNum * 6) or (10 + roundNum * 2 + timeBonus)
    if hintedThisRound then
        value = math.floor(value * 0.3)
    end
    return value
end

local function nextOrOver(delaySeconds)
    if missesLeft <= 0 then
        task.delay(delaySeconds, function()
            gameOver()
        end)
    else
        local r = roundNum
        task.delay(delaySeconds, function()
            beginRound(r + 1)
        end)
    end
end

local function answerCorrect(isBig)
    if phase ~= "find" then
        return
    end
    phase = "resolved"
    local value = reward(isBig)
    score += value
    updateHud()
    showBanner((isBig and "Big bonus! +" or "Correct! +") .. tostring(value), GREEN)
    local r = roundNum
    task.delay(1.0, function()
        beginRound(r + 1)
    end)
end

local function answerWrong(reason)
    if phase ~= "find" then
        return
    end
    phase = "resolved"
    missesLeft -= 1
    updateHud()
    showBanner(reason .. "  (Life -1)", RED)
    if not isNoChange then
        flashAnswer(2.0)
    else
        showBanner("That round had NO change!", RED)
    end
    nextOrOver(2.2)
end

local function onObjectClicked(model)
    if phase ~= "find" then
        return
    end
    if isNoChange then
        answerWrong("Wrong!")
    elseif model == answerModel then
        answerCorrect(false)
    else
        answerWrong("Wrong!")
    end
end

local function noChangeAnswer()
    if phase ~= "find" then
        return
    end
    if isNoChange then
        answerCorrect(true)
    else
        answerWrong("Wrong!")
    end
end

local function doHint()
    if phase ~= "find" then
        return
    end
    if hintsLeft <= 0 then
        showBanner("No hints left.", HINT_COLOR)
        return
    end
    hintsLeft -= 1
    hintedThisRound = true
    updateHud()
    if isNoChange then
        showBanner("Hint: maybe nothing changed here...", HINT_COLOR)
    else
        flashAnswer(1.5)
        showBanner("Hint: something here changed!", HINT_COLOR)
    end
end

beginRound = function(r)
    roundNum = r
    phase = "transition"
    updatePhaseUI()
    dim.Visible = true
    dim.BackgroundTransparency = 0
    showBanner("Get ready...", ACCENT)

    task.delay(TRANSITION_TIME, function()
        if prevAnswer then
            revertModel(prevAnswer)
            prevAnswer = nil
        end
        answerModel = nil
        isNoChange = (math.random() < NO_CHANGE_CHANCE)
        if not isNoChange and #objects > 0 then
            applyChange(r)
            prevAnswer = answerModel
        end
        hintedThisRound = false
        findEnd = os.clock() + findTime(r)
        phase = "find"
        updatePhaseUI()
        updateHud()
        fadeDimOut()
        showBanner("Find what changed!", GOLD)
    end)
end

gameOver = function()
    phase = "over"
    updatePhaseUI()
    if score > bestScore then
        bestScore = score
    end
    panelTitle.Text = "💀 Game Over"
    panelStats.Text = string.format("Score   %d\nBest    %d\nRounds  %d", score, bestScore, math.max(0, roundNum - 1))
    panel.Visible = true
    banner.Visible = false
end

-- ---------------------------------------------------------------------------
-- Click hooks
-- ---------------------------------------------------------------------------
local function hookModel(model)
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and not p:FindFirstChild("AnswerClick") then
            local cd = Instance.new("ClickDetector")
            cd.Name = "AnswerClick"
            cd.MaxActivationDistance = 250
            cd.Parent = p
            cd.MouseClick:Connect(function()
                onObjectClicked(model)
            end)
        end
    end
end

local function hookAll()
    for _, m in ipairs(objects) do
        hookModel(m)
    end
end

local function startStudy()
    gatherObjects()
    if #objects == 0 then
        return
    end
    storeOriginals()
    hookAll()
    score = 0
    missesLeft = MAX_MISSES
    hintsLeft = MAX_HINTS
    roundNum = 0
    prevAnswer = nil
    answerModel = nil
    isNoChange = false
    panel.Visible = false
    dim.Visible = false
    phase = "study"
    studyEnd = os.clock() + STUDY_TIME
    updateHud()
    updatePhaseUI()
    showBanner("Memorize the room! (Start when ready)", ACCENT)
end

-- ---------------------------------------------------------------------------
-- Timer
-- ---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    if phase == "study" then
        local remaining = math.max(0, studyEnd - os.clock())
        timeDisplay.Text = "Study: " .. tostring(math.ceil(remaining))
        timeDisplay.TextColor3 = Color3.fromRGB(220, 220, 235)
        if remaining <= 0 then
            beginRound(1)
        end
    elseif phase == "find" then
        local remaining = math.max(0, findEnd - os.clock())
        timeDisplay.Text = "Time: " .. tostring(math.ceil(remaining))
        timeDisplay.TextColor3 = remaining <= 6 and RED or Color3.fromRGB(220, 220, 235)
        if remaining <= 0 then
            answerWrong("Time up!")
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Inputs
-- ---------------------------------------------------------------------------
startButton.MouseButton1Click:Connect(function()
    if phase == "study" then
        beginRound(1)
    end
end)
noChangeButton.MouseButton1Click:Connect(noChangeAnswer)
hintBtn.MouseButton1Click:Connect(doHint)
playAgain.MouseButton1Click:Connect(function()
    panel.Visible = false
    ReplayEvent:FireServer()
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == Enum.KeyCode.Space and phase == "study" then
        beginRound(1)
    elseif input.KeyCode == Enum.KeyCode.G then
        noChangeAnswer()
    elseif input.KeyCode == Enum.KeyCode.H then
        doHint()
    end
end)

-- ---------------------------------------------------------------------------
-- Server messages / startup
-- ---------------------------------------------------------------------------
UIMessageEvent.OnClientEvent:Connect(function(payload)
    if payload.kind == "WorldReady" then
        task.wait(0.4)
        startStudy()
    end
end)

task.spawn(function()
    local demo = Workspace:WaitForChild("OnichaShootingDemo", 15)
    if demo then
        demo:WaitForChild("Objects", 5)
        task.wait(0.4)
        if phase == "idle" then
            startStudy()
        end
    end
end)
