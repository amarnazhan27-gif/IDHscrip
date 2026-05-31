-- ==========================================================
-- INDO HANGOUT ALL-IN-ONE: AUTOMININGNAZHAN.LUA (v6.0 FINAL)
-- DESIGNED WITH APPLE AESTHETICS & HIGH SECURITY ANTI-DETECTION
-- ==========================================================

-- ==========================================================
-- INSTANCE CLEANUP (ANTI-MULTI RUN)
-- ==========================================================
if shared.IH_Instance then
    pcall(shared.IH_Instance.Clean)
end

local InstanceManager = { Connections = {}, Active = true }

function InstanceManager.Clean()
    InstanceManager.Active = false
    for _, conn in ipairs(InstanceManager.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(InstanceManager.Connections)
end

shared.IH_Instance = InstanceManager

-- ==========================================================
-- ROBLOX SERVICES & VARIABLES
-- ==========================================================
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser         = game:GetService("VirtualUser")
local PathfindingService  = game:GetService("PathfindingService")
local TweenService        = game:GetService("TweenService")
local player              = Players.LocalPlayer

-- ==========================================
-- STATE & CONFIG
-- ==========================================
local mode            = "OFF"
local isSpacePressed  = false
local fishingState    = "IDLE"

local lastCastTime        = 0
local lastMinigameGuiSeen = 0
local isCasting           = false
local minigameJustStarted = false
local miningActive        = false
local lastSpaceToggle     = 0
local lastWhiteCenter     = nil
local lastWhiteSample     = os.clock()
local whiteVelocity       = 0
local cachedWhiteBar      = nil
local cachedRedBar        = nil
local lastGuiScan         = 0
local fishCaughtCount     = 0
local crystalMinedCount   = 0
local currentMiningTarget = nil
local miningFailCount     = 0
local miningHitCount      = 0
local minigameStartTime   = 0
local biteWaitStartTime   = 0
local successHandled      = false
local guiEverSeen         = false

-- FISHING CONFIG
local FISH_BITE_WAIT     = 15.0
local FISH_MINIGAME_MAX  = 15.0
local FISH_RECAST_DELAY  = 1.0
local FISH_CAST_DURATION = 1.8

-- MINING CONFIG
local FISH_TOOL_NAMES      = {"Fishing Rod", "Rod", "Pancing", "FishingRod"}
local MINE_TOOL_NAMES      = {"Pickaxe", "Cangkul", "Kapak", "Mining", "Pick", "Hammer"}
local CRYSTAL_NAMES        = {"8sisi", "Crystal", "Kristal", "Gem", "Ore", "Batu"}
local CRYSTAL_MATERIAL     = Enum.Material.Neon
local MINE_STOP_DISTANCE   = 2.3
local MINE_MAX_SCAN_DISTANCE = 260
local PATH_RETRY_DELAY     = 0.35
local MINE_SMOOTH_MOVE     = true
local MINE_WALK_SPEED      = 24

-- ANTI-DETECTION CONFIG
local ANTI_DET_TIME_JITTER     = true
local ANTI_DET_COORD_JITTER    = true
local ANTI_DET_WAYPOINT_JITTER = true
local FATIGUE_BREAK_ENABLED    = true
local FATIGUE_BREAK_FREQ       = 15
local FATIGUE_BREAK_MIN        = 5
local FATIGUE_BREAK_MAX        = 10
local MOUSE_SWEEP_ENABLED      = true

local actionsSinceLastBreak = 0
local nextBreakThreshold = math.random(10, 20)

-- ==========================================
-- LOGGING SYSTEM
-- ==========================================
local consoleLog = function() end
local originalWarn = warn

local function customWarn(msg)
    originalWarn(msg)
    if consoleLog then consoleLog(tostring(msg)) end
end
warn = customWarn

local function safeRun(f)
    xpcall(f, function(e)
        originalWarn("ERROR: " .. tostring(e))
        if consoleLog then consoleLog("ERROR: " .. tostring(e)) end
    end)
end

-- ==========================================
-- CLEAR PREVIOUS UI INSTANCES
-- ==========================================
pcall(function()
    for _, name in ipairs({"IH_v5", "AppleFarmUI"}) do
        local cg = game:GetService("CoreGui"):FindFirstChild(name)
        if cg then cg:Destroy() end
        local pg = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild(name)
        if pg then pg:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "AppleFarmUI"
gui.ResetOnSpawn = false

local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not ok then
    pcall(function() gui.Parent = player:WaitForChild("PlayerGui") end)
end

-- ==========================================
-- APPLE GLASSMORPHIC DESIGN SYSTEM
-- ==========================================
local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 310, 0, 340)
main.Position = UDim2.new(1, -325, 0.2, 0)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
main.BackgroundTransparency = 0.18
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(55, 55, 60)
mainStroke.Thickness = 1

-- Sleek Apple-like Shadow Effect (using a secondary overlapping background)
local shadowBg = Instance.new("Frame", main)
shadowBg.Size = UDim2.new(1, 0, 1, 0)
shadowBg.Position = UDim2.new(0, 0, 0, 0)
shadowBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadowBg.BackgroundTransparency = 0.95
shadowBg.ZIndex = main.ZIndex - 1
Instance.new("UICorner", shadowBg).CornerRadius = UDim.new(0, 12)

-- Header/Title Bar
local titleBar = Instance.new("Frame", main)
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
titleBar.BackgroundTransparency = 0.2
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleDivider = Instance.new("Frame", titleBar)
titleDivider.Size = UDim2.new(1, 0, 0, 1)
titleDivider.Position = UDim2.new(0, 0, 1, -1)
titleDivider.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
titleDivider.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1, -60, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "System Console"
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left

local byLabel = Instance.new("TextLabel", titleBar)
byLabel.Size = UDim2.new(0, 72, 1, 0)
byLabel.Position = UDim2.new(0, 130, 0, 0)
byLabel.BackgroundTransparency = 1
byLabel.Text = "by nazhan"
byLabel.TextColor3 = Color3.fromRGB(100, 100, 108)
byLabel.Font = Enum.Font.Gotham
byLabel.TextSize = 10
byLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize/Hide Button
local hideBtn = Instance.new("TextButton", titleBar)
hideBtn.Size = UDim2.new(0, 45, 0, 20)
hideBtn.Position = UDim2.new(1, -55, 0.5, -10)
hideBtn.BackgroundTransparency = 1
hideBtn.Text = "Minimize"
hideBtn.Font = Enum.Font.GothamMedium
hideBtn.TextSize = 11
hideBtn.TextColor3 = Color3.fromRGB(150, 150, 155)
hideBtn.BorderSizePixel = 0

-- Floating Float Button for Restoring
local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size = UDim2.new(0, 52, 0, 52)
floatBtn.Position = UDim2.new(1, -65, 0.2, 0)
floatBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
floatBtn.BackgroundTransparency = 0.15
floatBtn.Text = "Console"
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextSize = 10
floatBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
floatBtn.BorderSizePixel = 0
floatBtn.Visible = false
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1, 0)

local floatStroke = Instance.new("UIStroke", floatBtn)
floatStroke.Color = Color3.fromRGB(60, 60, 65)
floatStroke.Thickness = 1

local isMinimized = false
local mainPosition = UDim2.new(1, -325, 0.2, 0)
local minimizedPosition = UDim2.new(1, 50, 0.2, 0)

local function setMinimizeState(minimized)
    isMinimized = minimized
    if minimized then
        local tw = TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = minimizedPosition})
        tw:Play()
        tw.Completed:Connect(function()
            if isMinimized then
                main.Visible = false
                floatBtn.Visible = true
            end
        end)
    else
        main.Visible = true
        floatBtn.Visible = false
        TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = mainPosition}):Play()
    end
end

hideBtn.MouseButton1Click:Connect(function() setMinimizeState(true) end)
floatBtn.MouseButton1Click:Connect(function() setMinimizeState(false) end)

-- ==========================================
-- NAVIGATION BAR (TAB SYSTEM)
-- ==========================================
local navBar = Instance.new("Frame", main)
navBar.Size = UDim2.new(1, 0, 0, 36)
navBar.Position = UDim2.new(0, 0, 0, 42)
navBar.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
navBar.BackgroundTransparency = 0.3
navBar.BorderSizePixel = 0

local navDivider = Instance.new("Frame", navBar)
navDivider.Size = UDim2.new(1, 0, 0, 1)
navDivider.Position = UDim2.new(0, 0, 1, -1)
navDivider.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
navDivider.BorderSizePixel = 0

local navUnderline = Instance.new("Frame", navBar)
navUnderline.Size = UDim2.new(0.25, 0, 0, 2)
navUnderline.Position = UDim2.new(0, 0, 1, -2)
navUnderline.BackgroundColor3 = Color3.fromRGB(0, 122, 255)
navUnderline.BorderSizePixel = 0

local tabNames = {"Fishing", "Mining", "Settings", "Console"}
local tabButtons = {}
local panels = {}
local activeTab = "Fishing"

for i, tabName in ipairs(tabNames) do
    local btn = Instance.new("TextButton", navBar)
    btn.Size = UDim2.new(0.25, 0, 1, -2)
    btn.Position = UDim2.new((i - 1) * 0.25, 0, 0, 0)
    btn.BackgroundTransparency = 1
    btn.Text = tabName
    btn.TextColor3 = (i == 1) and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(140, 140, 145)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    tabButtons[tabName] = btn
end

-- ==========================================
-- TAB CONTENT PANELS
-- ==========================================
local contentContainer = Instance.new("Frame", main)
contentContainer.Size = UDim2.new(1, 0, 1, -78)
contentContainer.Position = UDim2.new(0, 0, 0, 78)
contentContainer.BackgroundTransparency = 1

local function createPanel(name, visible)
    local panel = Instance.new("Frame", contentContainer)
    panel.Size = UDim2.new(1, 0, 1, 0)
    panel.BackgroundTransparency = 1
    panel.Visible = visible
    panels[name] = panel
    return panel
end

local fishingPanel  = createPanel("Fishing", true)
local miningPanel   = createPanel("Mining", false)
local settingsPanel = createPanel("Settings", false)
local consolePanel  = createPanel("Console", false)

local function switchTab(tabName)
    activeTab = tabName
    local index = table.find(tabNames, tabName)
    local targetPos = UDim2.new((index - 1) * 0.25, 0, 1, -2)
    TweenService:Create(navUnderline, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
    
    for name, btn in pairs(tabButtons) do
        local isActive = (name == tabName)
        btn.TextColor3 = isActive and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(140, 140, 145)
        if panels[name] then
            panels[name].Visible = isActive
        end
    end
end

for name, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ==========================================
-- APPLE CAPSULE SWITCH COMPONENT
-- ==========================================
local function createToggle(parent, labelText, yPos, defaultValue, onClick)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, -24, 0, 32)
    frame.Position = UDim2.new(0, 12, 0, yPos)
    frame.BackgroundTransparency = 1

    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.65, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(210, 210, 215)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left

    local switch = Instance.new("TextButton", frame)
    switch.Size = UDim2.new(0, 42, 0, 22)
    switch.Position = UDim2.new(1, -42, 0.5, -11)
    switch.BackgroundColor3 = defaultValue and Color3.fromRGB(52, 199, 89) or Color3.fromRGB(60, 60, 65)
    switch.Text = ""
    switch.BorderSizePixel = 0
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local thumb = Instance.new("Frame", switch)
    thumb.Size = UDim2.new(0, 18, 0, 18)
    thumb.Position = defaultValue and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

    local active = defaultValue
    switch.MouseButton1Click:Connect(function()
        if not InstanceManager.Active then return end
        active = not active
        local targetPos = active and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        local targetColor = active and Color3.fromRGB(52, 199, 89) or Color3.fromRGB(60, 60, 65)
        
        TweenService:Create(thumb, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = targetPos}):Play()
        TweenService:Create(switch, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = targetColor}):Play()
        
        onClick(active)
    end)
    return switch, frame
end

-- ==========================================
-- TEXT FIELD & OPTION ROW BUILDERS
-- ==========================================
local function createTextField(parent, labelText, yPos, defaultValue, onFocusLost)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, -24, 0, 32)
    frame.Position = UDim2.new(0, 12, 0, yPos)
    frame.BackgroundTransparency = 1

    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.6, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(210, 210, 215)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left

    local box = Instance.new("TextBox", frame)
    box.Size = UDim2.new(0, 68, 0, 22)
    box.Position = UDim2.new(1, -72, 0.5, -11)
    box.BackgroundColor3 = Color3.fromRGB(36, 36, 40)
    box.TextColor3 = Color3.fromRGB(240, 240, 245)
    box.Text = defaultValue
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.BorderSizePixel = 0
    box.TextXAlignment = Enum.TextXAlignment.Center
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    
    local stroke = Instance.new("UIStroke", box)
    stroke.Color = Color3.fromRGB(70, 70, 80)
    stroke.Thickness = 1

    box.FocusLost:Connect(function(enterPressed)
        onFocusLost(box.Text, box)
    end)
    return box, frame
end

local function createStatusAndStats(parent)
    local statusLbl = Instance.new("TextLabel", parent)
    statusLbl.Size = UDim2.new(1, -24, 0, 20)
    statusLbl.Position = UDim2.new(0, 12, 0, 12)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text = "Status: Idle"
    statusLbl.TextColor3 = Color3.fromRGB(150, 150, 155)
    statusLbl.Font = Enum.Font.GothamMedium
    statusLbl.TextSize = 12
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left

    local statsLbl = Instance.new("TextLabel", parent)
    statsLbl.Size = UDim2.new(1, -24, 0, 20)
    statsLbl.Position = UDim2.new(0, 12, 0, 32)
    statsLbl.BackgroundTransparency = 1
    statsLbl.Text = "Activity Count: 0"
    statsLbl.TextColor3 = Color3.fromRGB(150, 150, 155)
    statsLbl.Font = Enum.Font.GothamMedium
    statsLbl.TextSize = 12
    statsLbl.TextXAlignment = Enum.TextXAlignment.Left

    return statusLbl, statsLbl
end

-- ==========================================
-- FISHING PANEL GUI
-- ==========================================
local fishStatus, fishStats = createStatusAndStats(fishingPanel)

-- Sleek Horizontal Step Progress Bar for Fishing Phase
local stepContainer = Instance.new("Frame", fishingPanel)
stepContainer.Size = UDim2.new(1, -24, 0, 4)
stepContainer.Position = UDim2.new(0, 12, 0, 70)
stepContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
stepContainer.BorderSizePixel = 0
Instance.new("UICorner", stepContainer).CornerRadius = UDim.new(1, 0)

local timerFill = Instance.new("Frame", stepContainer)
timerFill.Size = UDim2.new(0, 0, 1, 0)
timerFill.BackgroundColor3 = Color3.fromRGB(0, 122, 255)
timerFill.BorderSizePixel = 0
Instance.new("UICorner", timerFill).CornerRadius = UDim.new(1, 0)

local phaseNames = {"Cast", "Wait", "Game", "Done"}
local phaseColors = {
    Color3.fromRGB(0, 122, 255),
    Color3.fromRGB(255, 149, 0),
    Color3.fromRGB(255, 45, 85),
    Color3.fromRGB(52, 199, 89)
}
local phaseLabels = {}

for i = 1, 4 do
    local lbl = Instance.new("TextLabel", fishingPanel)
    lbl.Size = UDim2.new(0.25, 0, 0, 18)
    lbl.Position = UDim2.new((i - 1) * 0.25 + 0.02, 0, 0, 78)
    lbl.BackgroundTransparency = 1
    lbl.Text = phaseNames[i]
    lbl.TextColor3 = Color3.fromRGB(90, 90, 95)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 10
    phaseLabels[i] = lbl
end

local activeFishPhase = -1
local function setFishPhase(phaseIdx)
    activeFishPhase = phaseIdx
    for i = 1, 4 do
        if i == phaseIdx then
            phaseLabels[i].TextColor3 = phaseColors[i]
        elseif i < phaseIdx then
            phaseLabels[i].TextColor3 = Color3.fromRGB(150, 150, 155)
        else
            phaseLabels[i].TextColor3 = Color3.fromRGB(80, 80, 85)
        end
    end
    if phaseIdx == 0 then
        TweenService:Create(timerFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 0, 1, 0)}):Play()
    else
        local targetWidth = phaseIdx * 0.25
        TweenService:Create(timerFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(targetWidth, 0, 1, 0),
            BackgroundColor3 = phaseColors[phaseIdx]
        }):Play()
    end
end

local function updateTimerFill(fraction)
    if activeFishPhase <= 0 then return end
    local baseWidth = (activeFishPhase - 1) * 0.25
    local currentStepWidth = fraction * 0.25
    timerFill.Size = UDim2.new(math.clamp(baseWidth + currentStepWidth, 0, 1), 0, 1, 0)
end

local forceTurnOffFish
local toggleFish
toggleFish = createToggle(fishingPanel, "Fishing System", 115, false, function(active)
    if active then
        if mode == "MINE" then
            pcall(function() shared.MineToggleFunction(false) end)
        end
        mode = "FISH"
        setFishPhase(0)
        fishStatus.Text = "Status: Active"
        warn("[SYSTEM] Fishing mode activated")
    else
        forceTurnOffFish()
    end
end)
shared.FishToggleFunction = function(state)
    local targetPos = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    local targetColor = state and Color3.fromRGB(52, 199, 89) or Color3.fromRGB(60, 60, 65)
    local thumb = toggleFish:FindFirstChildOfClass("Frame")
    if thumb then thumb.Position = targetPos end
    toggleFish.BackgroundColor3 = targetColor
    if not state then forceTurnOffFish() end
end

-- ==========================================
-- MINING PANEL GUI
-- ==========================================
local mineStatus, mineStats = createStatusAndStats(miningPanel)

local toggleMine
toggleMine = createToggle(miningPanel, "Mining System", 70, false, function(active)
    if active then
        if mode == "FISH" then
            pcall(function() shared.FishToggleFunction(false) end)
        end
        mode = "MINE"
        currentMiningTarget = nil
        miningFailCount = 0
        miningHitCount = 0
        mineStatus.Text = "Status: Active"
        warn("[SYSTEM] Mining mode activated")
        if not miningActive then
            task.spawn(function()
                local ok, f = pcall(function() return shared.MineRoutineFunction end)
                if ok and f then f() end
            end)
        end
    else
        mode = "OFF"
        mineStatus.Text = "Status: Idle"
        pcall(function()
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)
        warn("[SYSTEM] Mining mode deactivated")
    end
end)
shared.MineToggleFunction = function(state)
    local targetPos = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    local targetColor = state and Color3.fromRGB(52, 199, 89) or Color3.fromRGB(60, 60, 65)
    local thumb = toggleMine:FindFirstChildOfClass("Frame")
    if thumb then thumb.Position = targetPos end
    toggleMine.BackgroundColor3 = targetColor
    if not state then
        mode = "OFF"
        mineStatus.Text = "Status: Idle"
        pcall(function()
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)
    end
end

-- ==========================================
-- SETTINGS PANEL GUI
-- ==========================================
local settingsScroll = Instance.new("ScrollingFrame", settingsPanel)
settingsScroll.Size = UDim2.new(1, 0, 1, -10)
settingsScroll.Position = UDim2.new(0, 0, 0, 5)
settingsScroll.BackgroundTransparency = 1
settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 280)
settingsScroll.ScrollBarThickness = 2
settingsScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 75)

createTextField(settingsScroll, "Mine Stop Range", 10, string.format("%.1f", MINE_STOP_DISTANCE), function(text)
    local val = tonumber(text)
    if val then
        MINE_STOP_DISTANCE = math.clamp(val, 1.8, 5.0)
        warn("[CONFIG] Mine Stop Range updated to: " .. MINE_STOP_DISTANCE)
    end
end)

local speedRowFrame = Instance.new("Frame", settingsScroll)
speedRowFrame.Size = UDim2.new(1, -24, 0, 32)
speedRowFrame.Position = UDim2.new(0, 12, 0, 45)
speedRowFrame.BackgroundTransparency = 1

local speedLabel = Instance.new("TextLabel", speedRowFrame)
speedLabel.Size = UDim2.new(0.6, 0, 1, 0)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Walk / Sprint Speed"
speedLabel.TextColor3 = Color3.fromRGB(210, 210, 215)
speedLabel.Font = Enum.Font.GothamMedium
speedLabel.TextSize = 12
speedLabel.TextXAlignment = Enum.TextXAlignment.Left

local speedBtn = Instance.new("TextButton", speedRowFrame)
speedBtn.Size = UDim2.new(0, 82, 0, 22)
speedBtn.Position = UDim2.new(1, -86, 0.5, -11)
speedBtn.BackgroundColor3 = Color3.fromRGB(36, 36, 40)
speedBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
speedBtn.Text = "Sprint: " .. MINE_WALK_SPEED
speedBtn.Font = Enum.Font.Gotham
speedBtn.TextSize = 11
speedBtn.BorderSizePixel = 0
Instance.new("UICorner", speedBtn).CornerRadius = UDim.new(0, 5)
local speedStroke = Instance.new("UIStroke", speedBtn)
speedStroke.Color = Color3.fromRGB(70, 70, 80)
speedStroke.Thickness = 1

speedBtn.MouseButton1Click:Connect(function()
    if not InstanceManager.Active then return end
    if MINE_WALK_SPEED == 24 then
        MINE_WALK_SPEED = 16
        speedBtn.Text = "Walk: 16"
    elseif MINE_WALK_SPEED == 16 then
        MINE_WALK_SPEED = 20
        speedBtn.Text = "Jog: 20"
    else
        MINE_WALK_SPEED = 24
        speedBtn.Text = "Sprint: 24"
    end
    warn("[CONFIG] Movement speed updated to: " .. MINE_WALK_SPEED)
end)

createToggle(settingsScroll, "Smooth Movement", 80, MINE_SMOOTH_MOVE, function(state)
    MINE_SMOOTH_MOVE = state
    warn("[CONFIG] Smooth movement updated to: " .. tostring(state))
end)

createToggle(settingsScroll, "Micro Path Jitter", 115, ANTI_DET_WAYPOINT_JITTER, function(state)
    ANTI_DET_WAYPOINT_JITTER = state
    warn("[SECURITY] Path waypoint jitter updated to: " .. tostring(state))
end)

createToggle(settingsScroll, "Farming Break Delay", 150, FATIGUE_BREAK_ENABLED, function(state)
    FATIGUE_BREAK_ENABLED = state
    warn("[SECURITY] Fatigue break intervals updated to: " .. tostring(state))
end)

createToggle(settingsScroll, "Timing Randomization", 185, ANTI_DET_TIME_JITTER, function(state)
    ANTI_DET_TIME_JITTER = state
    warn("[SECURITY] Micro timing jitter updated to: " .. tostring(state))
end)

createToggle(settingsScroll, "Anti-AFK Mouse Sweep", 220, MOUSE_SWEEP_ENABLED, function(state)
    MOUSE_SWEEP_ENABLED = state
    warn("[SECURITY] Anti-AFK mouse sweeps updated to: " .. tostring(state))
end)

-- ==========================================
-- CONSOLE PANEL GUI
-- ==========================================
local consoleHeader = Instance.new("Frame", consolePanel)
consoleHeader.Size = UDim2.new(1, 0, 0, 30)
consoleHeader.BackgroundTransparency = 1

local clearConsoleBtn = Instance.new("TextButton", consoleHeader)
clearConsoleBtn.Size = UDim2.new(0, 80, 0, 20)
clearConsoleBtn.Position = UDim2.new(1, -92, 0.5, -10)
clearConsoleBtn.BackgroundColor3 = Color3.fromRGB(36, 36, 40)
clearConsoleBtn.Text = "Clear Logs"
clearConsoleBtn.Font = Enum.Font.GothamMedium
clearConsoleBtn.TextSize = 10
clearConsoleBtn.TextColor3 = Color3.fromRGB(180, 180, 185)
clearConsoleBtn.BorderSizePixel = 0
Instance.new("UICorner", clearConsoleBtn).CornerRadius = UDim.new(0, 4)
local clearStroke = Instance.new("UIStroke", clearConsoleBtn)
clearStroke.Color = Color3.fromRGB(55, 55, 60)
clearStroke.Thickness = 1

local scrollFrame = Instance.new("ScrollingFrame", consolePanel)
scrollFrame.Size = UDim2.new(1, -24, 1, -40)
scrollFrame.Position = UDim2.new(0, 12, 0, 35)
scrollFrame.BackgroundTransparency = 1
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.ScrollBarThickness = 2
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 65)

local uiList = Instance.new("UIListLayout", scrollFrame)
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.Padding = UDim.new(0, 4)

local function appendConsoleLog(text)
    local ts = os.date("%H:%M:%S")
    local line = "[" .. ts .. "] " .. tostring(text)
    
    local lbl = Instance.new("TextLabel", scrollFrame)
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = line
    lbl.TextColor3 = Color3.fromRGB(180, 180, 185)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Center
    lbl.TextWrapped = true
    
    task.spawn(function()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, uiList.AbsoluteContentSize.Y + 15)
        scrollFrame.CanvasPosition = Vector2.new(0, uiList.AbsoluteContentSize.Y)
    end)
    
    local children = scrollFrame:GetChildren()
    local cLabels = {}
    for _, c in ipairs(children) do
        if c:IsA("TextLabel") then table.insert(cLabels, c) end
    end
    if #cLabels > 60 then
        cLabels[1]:Destroy()
    end
end
consoleLog = appendConsoleLog

clearConsoleBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(scrollFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
end)

-- ==========================================
-- RECURSIVE VISIBILITY CHECK HELPER
-- ==========================================
local function isTrulyVisible(obj)
    if not obj or typeof(obj) ~= "Instance" then return false end
    if not obj:IsA("GuiObject") then return false end
    if not obj.Visible then return false end
    
    local ok, size = pcall(function() return obj.AbsoluteSize end)
    if not ok or not size or size.X <= 0 or size.Y <= 0 then return false end
    
    local current = obj.Parent
    while current and current ~= game do
        if current:IsA("ScreenGui") then
            if not current.Enabled then return false end
            break
        elseif current:IsA("GuiObject") then
            if not current.Visible then return false end
        end
        current = current.Parent
    end
    return true
end

-- ==========================================
-- STATS LABEL UPDATE
-- ==========================================
local function updateActivityStats()
    fishStats.Text = "Fish Caught: " .. tostring(fishCaughtCount)
    mineStats.Text = "Crystals Mined: " .. tostring(crystalMinedCount)
end

-- ==========================================
-- ANTI-AFK INTERCEPT (MOUSE SWEEP SPAMMER)
-- ==========================================
local idledConnection
idledConnection = player.Idled:Connect(function()
    if not InstanceManager.Active then
        if idledConnection then pcall(function() idledConnection:Disconnect() end) end
        return
    end
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.2)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)
table.insert(InstanceManager.Connections, idledConnection)

-- AFK Mouse Sweep Anti-AFK Simulation Loop
task.spawn(function()
    while InstanceManager.Active do
        task.wait(math.random(110, 160))
        if not InstanceManager.Active then break end
        if MOUSE_SWEEP_ENABLED then
            safeRun(function()
                local cam = workspace.CurrentCamera
                if cam then
                    local size = cam.ViewportSize
                    local p1 = Vector2.new(size.X / 2 + math.random(-100, 100), size.Y / 2 + math.random(-100, 100))
                    pcall(function()
                        VirtualUser:MouseMoveEvent(p1, cam.CFrame)
                    end)
                end
            end)
        end
    end
end)

-- ==========================================
-- HUMANIZATION / SECURITY BREAK ENGINE
-- ==========================================
local function performFatigueBreak(overrideStatus)
    if not FATIGUE_BREAK_ENABLED or not InstanceManager.Active then return end
    actionsSinceLastBreak = actionsSinceLastBreak + 1
    if actionsSinceLastBreak >= nextBreakThreshold then
        local breakSec = math.random(FATIGUE_BREAK_MIN, FATIGUE_BREAK_MAX)
        warn("[SECURITY] Triggering artificial fatigue break for " .. breakSec .. " seconds")
        
        local oldStatus = overrideStatus.Text
        overrideStatus.Text = "Status: Resting (" .. breakSec .. "s)"
        
        -- Safe State Resets
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
        isSpacePressed = false
        
        task.wait(breakSec)
        
        actionsSinceLastBreak = 0
        nextBreakThreshold = math.random(12, 22)
        overrideStatus.Text = oldStatus
        warn("[SECURITY] Fatigue break complete. Resuming activities")
    end
end

-- ==========================================
-- TOOLS MANAGEMENT FUNCTIONS
-- ==========================================
local function findTool(nameList)
    local char = player.Character
    local bp   = player.Backpack
    for _, name in ipairs(nameList) do
        if char then
            local t = char:FindFirstChild(name)
            if t and t:IsA("Tool") then return t, "hand" end
        end
        local t = bp:FindFirstChild(name)
        if t then return t, "backpack" end
    end
    if char then
        local t = char:FindFirstChildWhichIsA("Tool")
        if t then return t, "hand" end
    end
    local t = bp:FindFirstChildWhichIsA("Tool")
    if t then return t, "backpack" end
    return nil, nil
end

local function equipTool(nameList)
    local char = player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local inHand = char:FindFirstChildWhichIsA("Tool")
    for _, name in ipairs(nameList) do
        if inHand and inHand.Name:lower():find(name:lower()) then return inHand end
    end
    local tool, loc = findTool(nameList)
    if tool and loc == "backpack" then
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.8)
        return char:FindFirstChildWhichIsA("Tool")
    end
    return inHand
end

-- ==========================================
-- FISHING CORE LOGIC
-- ==========================================
local function resetFishingState()
    isCasting         = false
    isSpacePressed    = false
    minigameJustStarted = false
    successHandled    = false
    guiEverSeen       = false
    cachedWhiteBar    = nil
    cachedRedBar      = nil
    lastGuiScan       = 0
    lastWhiteCenter   = nil
    whiteVelocity     = 0
    lastMinigameGuiSeen = 0
    fishingState      = "IDLE"
    
    setFishPhase(0)
end

local function setSpaceKey(pressed, force)
    if isSpacePressed == pressed then return end
    local now = os.clock()
    if not force and now - lastSpaceToggle < 0.035 then return end
    pcall(function() VirtualInputManager:SendKeyEvent(pressed, Enum.KeyCode.Space, false, game) end)
    isSpacePressed    = pressed
    lastSpaceToggle   = now
end

local function getFishingElements()
    if cachedWhiteBar and cachedRedBar
       and cachedWhiteBar.Parent and cachedRedBar.Parent
       and isTrulyVisible(cachedWhiteBar) and isTrulyVisible(cachedRedBar) then
        return cachedWhiteBar, cachedRedBar
    end

    local now = os.clock()
    if now - lastGuiScan < 0.06 then return nil, nil end
    lastGuiScan = now

    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil, nil end

    -- Match by Names
    for _, v in pairs(pg:GetDescendants()) do
        if v:IsA("GuiObject") and isTrulyVisible(v) then
            local lname  = v.Name:lower()
            local parent = v.Parent
            if (lname == "whitebar" or lname:match("^whitebar") or lname:match("whitebar$") or
                lname == "playerbar" or (lname:find("white") and lname:find("bar"))) and
               parent and parent:IsA("GuiObject") then
                local red = parent:FindFirstChild("RedBar") or parent:FindFirstChild("redbar") or
                            parent:FindFirstChild("TargetBar") or parent:FindFirstChild("targetbar")
                if not red then
                    for _, sib in ipairs(parent:GetChildren()) do
                        if sib ~= v and sib:IsA("GuiObject") and isTrulyVisible(sib) then
                            local sn = sib.Name:lower()
                            if sn:find("red") or sn:find("target") or sn:find("goal") or sn:find("indicator") then
                                red = sib; break
                            end
                        end
                    end
                end
                if red and isTrulyVisible(red) and v.AbsoluteSize.X > 10 and v.AbsoluteSize.Y > 5 then
                    cachedWhiteBar = v; cachedRedBar = red
                    return v, red
                end
            end
        end
    end

    -- Match by Colors
    for _, v in pairs(pg:GetDescendants()) do
        if v:IsA("GuiObject") and isTrulyVisible(v)
           and v.AbsoluteSize.X > 15 and v.AbsoluteSize.Y > 6 then
            local c = v.BackgroundColor3
            local p = v.Parent
            if c.R > 0.85 and c.G > 0.85 and c.B > 0.85 and p and p:IsA("GuiObject") then
                for _, sib in ipairs(p:GetChildren()) do
                    if sib ~= v and sib:IsA("GuiObject") and isTrulyVisible(sib) and sib.AbsoluteSize.X > 15 then
                        local sc = sib.BackgroundColor3
                        if sc.R > 0.52 and sc.G < 0.28 and sc.B < 0.28 then
                            cachedWhiteBar = v; cachedRedBar = sib
                            return v, sib
                        end
                    end
                end
            end
        end
    end

    cachedWhiteBar = nil; cachedRedBar = nil
    return nil, nil
end

local castRod
castRod = function()
    if isCasting or not InstanceManager.Active then return end
    isCasting = true
    safeRun(function()
        local cam = workspace.CurrentCamera
        if not cam then isCasting = false; return end
        
        -- Coordinates Jitter Anti-Detection
        local size = cam.ViewportSize
        local center = size / 2
        if ANTI_DET_COORD_JITTER then
            center = Vector2.new(center.X + math.random(-15, 15), center.Y + math.random(-15, 15))
        end

        fishingState = "CASTING"
        setFishPhase(1)
        updateTimerFill(0)
        fishStatus.Text = "Status: Casting line"
        warn("[FISHING] Casting fishing line")

        local tool = player.Character and player.Character:FindFirstChildWhichIsA("Tool")
        if tool then pcall(function() tool:Activate() end) end
        pcall(function() VirtualUser:Button1Down(center, cam.CFrame) end)

        -- Casting Time Jitter Anti-Detection
        local castDur = FISH_CAST_DURATION
        if ANTI_DET_TIME_JITTER then
            castDur = FISH_CAST_DURATION + (math.random(-12, 12) / 100)
        end

        local castStart = os.clock()
        while os.clock() - castStart < castDur do
            task.wait(0.05)
            if not InstanceManager.Active or mode ~= "FISH" then
                pcall(function() VirtualUser:Button1Up(center, cam.CFrame) end)
                isCasting = false; return
            end
            updateTimerFill((os.clock() - castStart) / castDur)
        end

        pcall(function() VirtualUser:Button1Up(center, cam.CFrame) end)
        if tool then pcall(function() tool:Deactivate() end) end
        updateTimerFill(1)
        
        -- Post-cast delay jitter
        local pDelay = 0.2
        if ANTI_DET_TIME_JITTER then pDelay = 0.2 + (math.random(-4, 8) / 100) end
        task.wait(pDelay)

        if InstanceManager.Active and mode == "FISH" then
            fishingState     = "WAITING"
            biteWaitStartTime = os.clock()
            lastCastTime     = os.clock()
            setFishPhase(2)
            updateTimerFill(0)
            fishStatus.Text = "Status: Waiting for bite"
            warn("[FISHING] Line cast. Waiting for bite")
        end
    end)
    task.wait(0.2)
    isCasting = false
end

local function handleFishSuccess(reason)
    if successHandled then return end
    successHandled = true

    setSpaceKey(false, true)
    fishingState = "SUCCESS"
    setFishPhase(4)
    updateTimerFill(1)

    fishCaughtCount = fishCaughtCount + 1
    updateActivityStats()
    isSpacePressed      = false
    minigameJustStarted = false

    local msg = "Fish caught successfully (" .. tostring(fishCaughtCount) .. ")"
    fishStatus.Text = "Status: Caught"
    warn("[FISHING] " .. msg)

    task.spawn(function()
        -- Jitter recast delay
        local reDelay = FISH_RECAST_DELAY
        if ANTI_DET_TIME_JITTER then
            reDelay = FISH_RECAST_DELAY + (math.random(-15, 30) / 100)
        end
        task.wait(reDelay)
        if not InstanceManager.Active or mode ~= "FISH" then return end
        
        -- Fatigue check before casting again
        performFatigueBreak(fishStatus)
        
        resetFishingState()
        task.wait(0.1)
        if not InstanceManager.Active or mode ~= "FISH" then return end
        task.spawn(castRod)
    end)
end

-- ==========================================
-- FISHING MINIGAME HEARTBEAT ENGINE
-- ==========================================
local heartbeatConnection
heartbeatConnection = RunService.Heartbeat:Connect(function()
    if not InstanceManager.Active then
        if heartbeatConnection then pcall(function() heartbeatConnection:Disconnect() end) end
        return
    end

    if mode ~= "FISH" then
        if isSpacePressed then setSpaceKey(false, true) end
        return
    end

    safeRun(function()
        local now = os.clock()

        -- Waiting Phase
        if fishingState == "WAITING" then
            local elapsed  = now - biteWaitStartTime
            local fraction = math.clamp(elapsed / FISH_BITE_WAIT, 0, 1)
            updateTimerFill(fraction)
            fishStatus.Text = string.format("Status: Waiting (%.1fs)", math.max(0, FISH_BITE_WAIT - elapsed))

            if elapsed >= FISH_BITE_WAIT then
                fishingState     = "MINIGAME"
                minigameStartTime = now
                successHandled   = false
                guiEverSeen      = false
                minigameJustStarted = false
                lastMinigameGuiSeen = 0
                cachedWhiteBar   = nil
                cachedRedBar     = nil
                lastGuiScan      = 0
                lastWhiteCenter  = nil
                whiteVelocity    = 0
                setSpaceKey(false, true)
                setFishPhase(3)
                updateTimerFill(0)
                fishStatus.Text = "Status: Minigame active"
                warn("[FISHING] Starting minigame loop")
            end
            return
        end

        -- Minigame Phase
        if fishingState == "MINIGAME" then
            local elapsed = now - minigameStartTime
            updateTimerFill(math.clamp(elapsed / FISH_MINIGAME_MAX, 0, 1))

            -- Fallback Timeout
            if elapsed >= FISH_MINIGAME_MAX then
                setSpaceKey(false, true)
                warn("[FISHING] Minigame timeout fallback triggered")
                handleFishSuccess("timeout")
                return
            end

            local white, red = getFishingElements()

            if white and red and isTrulyVisible(white) and isTrulyVisible(red) then
                guiEverSeen         = true
                lastMinigameGuiSeen = now

                if not minigameJustStarted then
                    minigameJustStarted = true
                    setSpaceKey(false, true)
                    lastWhiteCenter = nil
                    whiteVelocity   = 0
                end

                local whiteCenter = white.AbsolutePosition.X + white.AbsoluteSize.X / 2
                local redLeft     = red.AbsolutePosition.X
                local redRight    = red.AbsolutePosition.X + red.AbsoluteSize.X
                local redCenter   = (redLeft + redRight) / 2
                local dt          = math.max(now - lastWhiteSample, 0.012)

                if lastWhiteCenter then
                    local inst   = (whiteCenter - lastWhiteCenter) / dt
                    whiteVelocity = whiteVelocity * 0.72 + inst * 0.28
                end
                lastWhiteCenter = whiteCenter
                lastWhiteSample = now

                local lookAhead = math.clamp(math.abs(whiteVelocity) / 2000, 0.04, 0.12)
                local predicted = whiteCenter + whiteVelocity * lookAhead
                local redWidth  = math.max(red.AbsoluteSize.X, 1)
                local tolerance = math.clamp(redWidth * 0.22, 6, 18)
                local inside    = predicted >= (redLeft - tolerance) and predicted <= (redRight + tolerance)

                if inside then
                    if whiteCenter < redLeft then
                        setSpaceKey(true)
                    elseif whiteCenter > redRight then
                        setSpaceKey(false)
                    else
                        local err = whiteCenter - redCenter
                        if math.abs(err) > tolerance * 0.5 then setSpaceKey(err < 0) end
                    end
                else
                    local err = redCenter - predicted
                    if     err >  tolerance then setSpaceKey(true)
                    elseif err < -tolerance then setSpaceKey(false)
                    elseif math.abs(whiteVelocity) > 200 then setSpaceKey(whiteVelocity < 0) end
                end

                fishStatus.Text = string.format("Status: Play (%.1fs)", elapsed)

            else
                if guiEverSeen then
                    -- Instant exit when GUI is gone
                    if lastMinigameGuiSeen > 0 and (now - lastMinigameGuiSeen) >= 0.25 then
                        setSpaceKey(false, true)
                        warn("[FISHING] Minigame GUI disappeared, concluding run")
                        handleFishSuccess("gui-disappeared")
                        return
                    end
                else
                    -- Rhythmic tapping while GUI is loading
                    local rhythm = (math.floor(elapsed * 4) % 2 == 0)
                    setSpaceKey(rhythm)
                    fishStatus.Text = string.format("Status: Sync (%.1fs)", elapsed)
                end
            end
            return
        end
    end)
end)
table.insert(InstanceManager.Connections, heartbeatConnection)

-- Fishing Controller Loop
task.spawn(function()
    while InstanceManager.Active do
        task.wait(0.15)
        if not InstanceManager.Active then break end
        if mode ~= "FISH" then continue end
        
        safeRun(function()
            local char = player.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")

            if hum and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
                hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
            end

            local tool = equipTool(FISH_TOOL_NAMES)
            if tool and not isCasting then
                if fishingState == "IDLE" then
                    fishStatus.Text = "Status: Ready"
                    task.spawn(castRod)
                end
            elseif not tool then
                fishStatus.Text = "Status: No rod found"
            end
        end)
    end
end)

forceTurnOffFish = function()
    mode = "OFF"
    fishStatus.Text = "Status: Idle"
    shared.FishToggleFunction(false)
    
    pcall(function() 
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game) 
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end)
    isSpacePressed = false
    resetFishingState()
    
    pcall(function()
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
    end)
end

-- ==========================================
-- MINING OPERATIONS & ALGORITHMS
-- ==========================================
local function isLikelyCrystal(obj)
    if not (obj:IsA("BasePart") or obj:IsA("MeshPart")) then return false, 0 end
    local lname = obj.Name:lower()
    local score = 0
    for _, cname in ipairs(CRYSTAL_NAMES) do
        if lname:find(cname:lower()) then score = score + 4; break end
    end
    if obj.Material == CRYSTAL_MATERIAL then score = score + 3 end
    if obj:IsA("MeshPart") then score = score + 1 end
    if obj.Transparency < 0.85 then score = score + 1 end
    if obj.CanCollide or obj.CanQuery then score = score + 1 end
    local parent = obj.Parent
    while parent and parent ~= workspace do
        local pname = parent.Name:lower()
        if pname:find("crystal") or pname:find("ore") or pname:find("mine") or pname:find("batu") then
            score = score + 3; break
        end
        parent = parent.Parent
    end
    return score >= 4, score
end

local function belongsToOtherPlayer(obj)
    local cursor = obj
    while cursor and cursor ~= workspace do
        for _, key in ipairs({"Owner","owner","OwnerName","ownerName","UserId","userId","Player","player"}) do
            local value = cursor:GetAttribute(key)
            if value ~= nil then
                if typeof(value) == "number" and value ~= player.UserId then return true end
                if typeof(value) == "string" and value ~= "" and value ~= player.Name
                   and value ~= player.DisplayName and value ~= tostring(player.UserId) then return true end
            end
        end
        for _, cn in ipairs({"Owner","OwnerName","PlayerName","UserId"}) do
            local child = cursor:FindFirstChild(cn)
            if child and child:IsA("ValueBase") then
                local v2 = child.Value
                if typeof(v2) == "number" and v2 ~= player.UserId then return true end
                if typeof(v2) == "string" and v2 ~= "" and v2 ~= player.Name
                   and v2 ~= player.DisplayName and v2 ~= tostring(player.UserId) then return true end
                if typeof(v2) == "Instance" and v2:IsA("Player") and v2 ~= player then return true end
            end
        end
        cursor = cursor.Parent
    end
    return false
end

local function findNearestCrystal()
    local char = player.Character
    if not char or not char.PrimaryPart then return nil end
    local myPos = char.PrimaryPart.Position
    if currentMiningTarget and currentMiningTarget.Parent and not belongsToOtherPlayer(currentMiningTarget) then
        local d = (currentMiningTarget.Position - myPos).Magnitude
        if d < MINE_MAX_SCAN_DISTANCE and miningFailCount < 3 then return currentMiningTarget, d end
    end
    local nearest, nearestValue, nearestDist = nil, math.huge, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        local ok, score = isLikelyCrystal(obj)
        if ok and not belongsToOtherPlayer(obj) then
            local dist = (obj.Position - myPos).Magnitude
            if dist < MINE_MAX_SCAN_DISTANCE then
                local value = dist - score * 10
                if value < nearestValue then nearest = obj; nearestDist = dist; nearestValue = value end
            end
        end
    end
    currentMiningTarget = nearest; miningFailCount = 0
    return nearest, nearestDist
end

local function raycastGround(pos, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = ignoreList or {}
    params.IgnoreWater = false
    return workspace:Raycast(pos + Vector3.new(0,18,0), Vector3.new(0,-70,0), params)
end

local function hasClearLine(fromPos, toPos, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = ignoreList or {}
    local hit = workspace:Raycast(fromPos, toPos - fromPos, params)
    return not hit or hit.Instance == nil
end

local function getMiningStandPoint(crystal)
    local char = player.Character
    if not char or not char.PrimaryPart then return nil end
    local origin = crystal.Position
    local cw     = math.max(crystal.Size.X, crystal.Size.Z)
    local radius = math.clamp(cw * 0.25 + 1.5, MINE_STOP_DISTANCE, 3.8)
    local ignore = {char, crystal}
    local bestPos, bestScore = nil, math.huge
    for i = 1, 16 do
        local angle  = math.pi * 2 * (i / 16)
        local sample = origin + Vector3.new(math.cos(angle)*radius, 0, math.sin(angle)*radius)
        local ground = raycastGround(sample, ignore)
        if ground and ground.Instance and ground.Normal.Y > 0.55 then
            local pos    = ground.Position + Vector3.new(0, 3, 0)
            local hDelta = math.abs(pos.Y - char.PrimaryPart.Position.Y)
            if hDelta < 10 and pos.Y - origin.Y < 4.5 then
                local clear = hasClearLine(pos + Vector3.new(0,2,0), origin, ignore)
                local distC = (Vector3.new(pos.X, origin.Y, pos.Z) - origin).Magnitude
                local sc    = (pos - char.PrimaryPart.Position).Magnitude + math.abs(distC-radius)*4 + (clear and 0 or 12) + hDelta
                if sc < bestScore then bestScore = sc; bestPos = pos end
            end
        end
    end
    if bestPos then return bestPos end
    local delta = char.PrimaryPart.Position - origin
    local flat  = Vector3.new(delta.X, 0, delta.Z)
    if flat.Magnitude < 1 then flat = Vector3.new(1,0,0) end
    local fb     = origin + flat.Unit * radius
    local ground = raycastGround(fb, ignore)
    return ground and (ground.Position + Vector3.new(0,3,0)) or fb
end

local function moveToPosition(hum, targetPos, targetPart)
    local char = player.Character
    if not char or not char.PrimaryPart then return false end
    
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
    end)
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 1.9, AgentHeight = 5.2,
        AgentCanJump = true, AgentCanClimb = true,
        WaypointSpacing = MINE_SMOOTH_MOVE and 7 or 3,
        Costs = {Water = 5},
    })
    local ok = pcall(function() path:ComputeAsync(char.PrimaryPart.Position, targetPos) end)
    local wps
    if ok and path.Status == Enum.PathStatus.Success then
        wps = path:GetWaypoints()
    else
        wps = {{Position = targetPos, Action = Enum.PathWaypointAction.Walk}}
    end
    
    local orig     = hum.WalkSpeed
    hum.WalkSpeed  = MINE_SMOOTH_MOVE and MINE_WALK_SPEED + math.random(-1,1) or MINE_WALK_SPEED
    local lastPos  = char.PrimaryPart.Position
    local stuckFor = 0
    local success  = false

    -- Random jump cadence: pick a random waypoint index to jump on
    local jumpAt = math.random(2, math.max(2, math.floor(#wps * 0.45)))

    for index, wp in ipairs(wps) do
        if mode ~= "MINE" or not InstanceManager.Active then break end
        if targetPart and not targetPart.Parent then break end
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

        -- Randomized human-like jump while running between crystals
        if index == jumpAt and math.random(1, 100) <= 55 then
            hum.Jump = true
            task.wait(0.05)
        end

        -- Micro Path Jitter for Anti-Detection
        local stepPos = wp.Position
        if ANTI_DET_WAYPOINT_JITTER and index < #wps then
            stepPos = wp.Position + Vector3.new(math.random(-4, 4)/10, 0, math.random(-4, 4)/10)
        end

        hum:MoveTo(stepPos)
        local started = os.clock()
        while mode == "MINE" and InstanceManager.Active and os.clock()-started < 4.5 do
            task.wait(MINE_SMOOTH_MOVE and 0.08 or 0.15)
            if not char.PrimaryPart then break end
            local cur = char.PrimaryPart.Position
            
            -- Close boundary distance check
            if targetPart and targetPart.Parent then
                local distToCrystal = (cur - targetPart.Position).Magnitude
                local cw = math.max(targetPart.Size.X, targetPart.Size.Z)
                if distToCrystal <= (cw * 0.5 + 2.2) then
                    success = true
                    break
                end
            end

            local reach = (MINE_SMOOTH_MOVE and index < #wps) and 5.2 or 1.0
            if (cur - wp.Position).Magnitude <= reach then break end
            if (cur - targetPos).Magnitude <= 1.0 then 
                success = true
                break 
            end
            
            if (cur - lastPos).Magnitude < 0.2 then
                stuckFor = stuckFor + (MINE_SMOOTH_MOVE and 0.08 or 0.15)
                if stuckFor > 1.1 then
                    hum.Jump = true
                    local rec = targetPos - cur
                    if rec.Magnitude < 0.1 then rec = Vector3.new(1,0,0) end
                    hum:MoveTo(cur + rec.Unit * 5)
                    task.wait(PATH_RETRY_DELAY)
                    break
                end
            else stuckFor = 0; lastPos = cur end
        end
        if success then break end
    end

    hum.WalkSpeed = orig
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end)
    
    if success then return true end
    return char.PrimaryPart and (char.PrimaryPart.Position - targetPos).Magnitude <= 1.5
end

local function facePart(part)
    local char = player.Character
    if not char or not char.PrimaryPart or not part then return end
    local pos = char.PrimaryPart.Position
    pcall(function()
        char:SetPrimaryPartCFrame(CFrame.lookAt(pos, Vector3.new(part.Position.X, pos.Y, part.Position.Z)))
    end)
end

local function mineRoutine()
    miningActive = true
    while mode == "MINE" and InstanceManager.Active do
        task.wait(0.5)
        if not InstanceManager.Active then break end
        safeRun(function()
            local char = player.Character
            if not char or not char.PrimaryPart then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end

            local crystal, dist = findNearestCrystal()
            if not crystal then
                mineStatus.Text = "Status: Crystal not found"
                warn("[MINE] Target crystal not found")
                task.wait(3); return
            end

            mineStatus.Text = "Status: Moving to target"
            warn("[MINE] Heading to " .. crystal.Name)

            local tool = equipTool(MINE_TOOL_NAMES)
            if not tool then
                mineStatus.Text = "Status: No tool found"
                task.wait(3); return
            end

            -- Pre-check if already in mining proximity range
            local needMove = true
            if crystal and crystal.Parent then
                local cur = char.PrimaryPart.Position
                local cw = math.max(crystal.Size.X, crystal.Size.Z)
                if (cur - crystal.Position).Magnitude <= (cw * 0.5 + 2.2) then
                    needMove = false
                end
            end

            if needMove then
                local standPoint = getMiningStandPoint(crystal)
                if standPoint and (char.PrimaryPart.Position - standPoint).Magnitude > 1.2 then
                    local arrived = moveToPosition(hum, standPoint, crystal)
                    if not arrived then
                        miningFailCount = miningFailCount + 1
                        if miningFailCount >= 3 then currentMiningTarget = nil end
                        task.wait(0.4); return
                    end
                end
            end

            facePart(crystal)
            local cam = workspace.CurrentCamera
            if cam then
                local aimPos = crystal.Position + Vector3.new(0, math.clamp(crystal.Size.Y*0.15, 0.5, 2.5), 0)
                local screenPos, onScreen = cam:WorldToScreenPoint(aimPos)
                if onScreen then
                    local minedThisTarget = false
                    
                    mineStatus.Text = "Status: Harvesting"
                    for i = 1, 7 do
                        if mode ~= "MINE" or not InstanceManager.Active then break end
                        if crystal.Parent == nil then minedThisTarget = true; break end
                        facePart(crystal)
                        
                        -- Coordinate Jitter in Simulation Click
                        local clickX = screenPos.X
                        local clickY = screenPos.Y
                        if ANTI_DET_COORD_JITTER then
                            clickX = clickX + math.random(-8, 8)
                            clickY = clickY + math.random(-8, 8)
                        end
                        
                        pcall(function() VirtualUser:Button1Down(Vector2.new(clickX, clickY), cam.CFrame) end)
                        
                        -- Timing Randomization
                        local clickDur = 0.15
                        if ANTI_DET_TIME_JITTER then clickDur = 0.15 + (math.random(-2, 4) / 100) end
                        task.wait(clickDur)
                        
                        pcall(function() VirtualUser:Button1Up(Vector2.new(clickX, clickY), cam.CFrame) end)
                        
                        local actDur = 0.3
                        if ANTI_DET_TIME_JITTER then actDur = 0.3 + (math.random(-3, 6) / 100) end
                        task.wait(actDur)
                        
                        pcall(function() tool:Activate() end)
                    end
                    
                    if minedThisTarget or crystal.Parent == nil then
                        crystalMinedCount = crystalMinedCount + 1
                        updateActivityStats()
                        mineStatus.Text = "Status: Active"
                        warn("[MINE] Crystal successfully mined")
                        currentMiningTarget = nil
                        miningFailCount = 0
                        
                        -- Fatigue check after successful mining action
                        performFatigueBreak(mineStatus)
                    else
                        miningHitCount = miningHitCount + 1
                        if miningHitCount >= 3 then
                            crystalMinedCount = crystalMinedCount + 1
                            miningHitCount    = 0
                            updateActivityStats()
                        end
                    end
                else
                    pcall(function() tool:Activate() end)
                    task.wait(1)
                end
            end
        end)
        task.wait(0.5)
    end
    miningActive = false
end
shared.MineRoutineFunction = mineRoutine

-- ==========================================
-- ADMIN / MODERATOR DETECTION ENGINE
-- ==========================================
local ADMIN_KICK_ENABLED = true
local ROBLOX_STAFF_GROUP = 1200769
local ADMIN_NAME_PATTERNS = {
    "moderator", "roblox_adm", "admin", "moderat", "rblxmod", "staffmod",
    "gamemaster", "game_master",
}
local ADMIN_BADGE_IDS = {}

local function isPlayerAdmin(p)
    if not p or not p.Parent then return false end
    -- Check Roblox official staff group membership
    local inStaff = false
    pcall(function()
        inStaff = p:IsInGroup(ROBLOX_STAFF_GROUP)
    end)
    if inStaff then return true, "Roblox Staff Group" end

    -- Check suspicious name patterns
    local lname = (p.Name .. p.DisplayName):lower()
    for _, pat in ipairs(ADMIN_NAME_PATTERNS) do
        if lname:find(pat) then return true, "Name Pattern: " .. pat end
    end

    -- Check high group rank in game creator group (if game is group-owned)
    pcall(function()
        local creatorId = game.CreatorType == Enum.CreatorType.Group and game.CreatorId or nil
        if creatorId then
            local rank = p:GetRankInGroup(creatorId)
            if rank >= 200 then
                inStaff = true
            end
        end
    end)
    if inStaff then return true, "High Creator Group Rank" end

    return false, nil
end

local function handlePlayerCheck(p)
    if p == player then return end
    if not ADMIN_KICK_ENABLED then return end
    task.wait(1.5) -- give time for player data to load
    if not p or not p.Parent then return end
    local isAdmin, reason = isPlayerAdmin(p)
    if isAdmin then
        warn("[SECURITY] Moderator detected: " .. p.Name .. " (" .. (reason or "unknown") .. "). Auto-stopping.")
        -- Safely stop all activities first
        mode = "OFF"
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
        isSpacePressed = false
        -- Kick self out of server to avoid detection
        task.wait(0.5)
        player:Kick("Disconnected for maintenance.")
    end
end

-- Scan existing players on load
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(handlePlayerCheck, p)
end

-- Hook into new joiners
local adminConn = Players.PlayerAdded:Connect(function(p)
    if not InstanceManager.Active then return end
    task.spawn(handlePlayerCheck, p)
end)
table.insert(InstanceManager.Connections, adminConn)

-- ==========================================
-- PROGRAM INITIALIZATION
-- ==========================================
setFishPhase(0)
updateActivityStats()

warn("=== CONSOLE LOADED ===")
warn("File: autominingnazhan.lua v7.0")
warn("Security: Anti-detection + Admin guard fully active")
warn("Design: Premium minimalist dark theme")
