-- Indo Hangout Auto Farm
-- finalv9.lua  |  by nazhan
-- ============================================================

-- cleanup script lama jika ada
if shared.NH_v9 then
    pcall(shared.NH_v9.kill)
end

local Manager = { conns = {}, alive = true }
function Manager.kill()
    Manager.alive = false
    for _, c in ipairs(Manager.conns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Manager.conns)
end
shared.NH_v9 = Manager

-- services
local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local VIM      = game:GetService("VirtualInputManager")
local VU       = game:GetService("VirtualUser")
local PFS      = game:GetService("PathfindingService")
local TS       = game:GetService("TweenService")
local me       = Players.LocalPlayer

-- ============================================================
-- ROD DATA  (lure = kecepatan bar, prog = kecepatan progress)
-- ============================================================
local RODS = {
    { name = "Basic Rod",    lure = 1.00, prog = 1.00 },
    { name = "Party Rod",    lure = 1.30, prog = 1.08 },
    { name = "Shark Rod",    lure = 1.57, prog = 1.21 },
    { name = "Piranha Rod",  lure = 1.84, prog = 1.33 },
    { name = "Thermo Rod",   lure = 2.11, prog = 1.46 },
    { name = "Flowers Rod",  lure = 2.38, prog = 1.59 },
    { name = "Trisula Rod",  lure = 2.65, prog = 1.72 },
    { name = "Feather Rod",  lure = 2.92, prog = 1.84 },
    { name = "Wave Rod",     lure = 3.19, prog = 1.97 },
    { name = "Duck Rod",     lure = 3.46, prog = 2.10 },
    { name = "Planet Rod",   lure = 3.73, prog = 2.23 },
    { name = "Earth Rod",    lure = 4.00, prog = 2.35 },
    { name = "Volcano Rod",  lure = 4.27, prog = 2.48 },
}
local selectedRod = 1

-- ============================================================
-- CONFIG & STATE
-- ============================================================
local mode       = "OFF"
local CAST_HOLD  = 1.8
local BITE_WAIT  = 15.0
local RECAST_DLY = 1.0

local FISH_TOOLS  = {"Fishing Rod","Rod","Pancing","FishingRod"}
local MINE_TOOLS  = {"Pickaxe","Cangkul","Kapak","Mining","Pick","Hammer"}
local CRYS_NAMES  = {"8sisi","Crystal","Kristal","Gem","Ore","Batu","Stone","mineral"}
local CRYS_BL     = {
    "lamp","light","glow","torch","lantern","bulb","neon",
    "tree","bush","grass","leaf","vine","flower","plant",
    "wall","floor","ceiling","roof","prop","decor","deco",
    "fence","gate","door","window","sign","board","post",
    "water","ocean","river","lake","pond","sea","wave",
    "cloud","fog","sun","moon","star","sky","air",
    "fire","flame","smoke","ember","spark","ash",
    "spawn","check","zone","region","trigger","sensor",
    "platform","road","path","bridge","stair","rail",
    "house","building","room","ground","terrain","base","frame",
}

local STOP_DIST  = 2.5
local WALK_SPEED = 24

local CFG = {
    timeJitter   = true,
    coordJitter  = true,
    pathJitter   = true,
    fatigueBreak = true,
    mouseAFK     = true,
    adminGuard   = true,
    antiFingerp  = true,
    smoothMove   = true,
}

-- fishing state
local fishState   = "IDLE"
local isSpace     = false
local lastSpTgl   = 0
local biteStart   = 0
local mgStart     = 0
local mgLastSeen  = 0
local mgEverSeen  = false
local mgStarted   = false
local successDone = false
local isCasting   = false
local wBar, rBar  = nil, nil
local lastScan    = 0
local lastWC      = nil
local lastWTime   = os.clock()
local wVel        = 0
local castSession = 0

-- mining state
local mineActive    = false
local currentTarget = nil
local failCount     = 0
local hitCount      = 0

-- counters
local fishCount = 0
local mineCount = 0

-- console state (default OFF)
local consoleOn   = false
local _consLog    = function() end

-- fatigue
local fatCount = 0
local fatNext  = math.random(12, 22)

-- ============================================================
-- LOGGING
-- ============================================================
local _warn = warn
local function lg(msg)
    _warn(msg)
    if consoleOn then _consLog(tostring(msg)) end
end
local function safe(fn)
    local ok, e = xpcall(fn, function(err)
        _warn("[ERR] " .. tostring(err))
        if consoleOn then _consLog("[ERR] " .. tostring(err)) end
    end)
    return ok
end

-- bersihkan gui lama
pcall(function()
    for _, n in ipairs({"NH_v9_GUI","AppleFarmUI","IH_v5"}) do
        local cg = game:GetService("CoreGui"):FindFirstChild(n)
        if cg then cg:Destroy() end
        if me.PlayerGui then
            local pg = me.PlayerGui:FindFirstChild(n)
            if pg then pg:Destroy() end
        end
    end
end)

-- anti-fingerprint: delay acak kecil saat startup
if CFG.antiFingerp then task.wait(math.random() * 0.25) end

-- ============================================================
-- GUI CORE
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "NH_v9_GUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
local gok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gok then gui.Parent = me:WaitForChild("PlayerGui") end

local main = Instance.new("Frame", gui)
main.Name  = "Main"
main.Size  = UDim2.new(0, 308, 0, 368)
main.Position = UDim2.new(1, -324, 0.16, 0)
main.BackgroundColor3 = Color3.fromRGB(17, 17, 21)
main.BackgroundTransparency = 0.08
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local mStroke = Instance.new("UIStroke", main)
mStroke.Color = Color3.fromRGB(48, 48, 55)
mStroke.Thickness = 1

-- header 56px untuk dua baris text
local hdr = Instance.new("Frame", main)
hdr.Size = UDim2.new(1, 0, 0, 56)
hdr.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
hdr.BackgroundTransparency = 0.12
hdr.BorderSizePixel = 0
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 14)

local hdrLine = Instance.new("Frame", hdr)
hdrLine.Size = UDim2.new(1, 0, 0, 1)
hdrLine.Position = UDim2.new(0, 0, 1, -1)
hdrLine.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
hdrLine.BorderSizePixel = 0

-- baris 1: "System Console"
local titleLbl = Instance.new("TextLabel", hdr)
titleLbl.Size = UDim2.new(1, -72, 0, 22)
titleLbl.Position = UDim2.new(0, 14, 0, 7)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "System Console"
titleLbl.TextColor3 = Color3.fromRGB(235, 235, 242)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 14
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

-- baris 2: "by nazhan" — di bawah judul
local byLbl = Instance.new("TextLabel", hdr)
byLbl.Size = UDim2.new(1, -72, 0, 16)
byLbl.Position = UDim2.new(0, 15, 0, 30)
byLbl.BackgroundTransparency = 1
byLbl.Text = "by nazhan"
byLbl.TextColor3 = Color3.fromRGB(85, 85, 96)
byLbl.Font = Enum.Font.Gotham
byLbl.TextSize = 11
byLbl.TextXAlignment = Enum.TextXAlignment.Left

-- tombol hide
local hideBtn = Instance.new("TextButton", hdr)
hideBtn.Size = UDim2.new(0, 50, 0, 22)
hideBtn.Position = UDim2.new(1, -58, 0.5, -11)
hideBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
hideBtn.Text = "Hide"
hideBtn.TextColor3 = Color3.fromRGB(150, 150, 158)
hideBtn.Font = Enum.Font.GothamMedium
hideBtn.TextSize = 11
hideBtn.BorderSizePixel = 0
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)

-- float button
local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size = UDim2.new(0, 52, 0, 52)
floatBtn.Position = UDim2.new(1, -66, 0.16, 0)
floatBtn.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
floatBtn.BackgroundTransparency = 0.08
floatBtn.Text = "IH"
floatBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextSize = 14
floatBtn.BorderSizePixel = 0
floatBtn.Visible = false
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1, 0)
local fbStr = Instance.new("UIStroke", floatBtn)
fbStr.Color = Color3.fromRGB(50, 50, 58)
fbStr.Thickness = 1

local mainPos   = UDim2.new(1, -324, 0.16, 0)
local hidePos   = UDim2.new(1,  56,  0.16, 0)
local isHid     = false

local function setHide(h)
    isHid = h
    if h then
        TS:Create(main, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = hidePos}):Play()
        task.delay(0.27, function()
            if isHid then main.Visible = false; floatBtn.Visible = true end
        end)
    else
        main.Visible = true
        floatBtn.Visible = false
        TS:Create(main, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = mainPos}):Play()
    end
end

hideBtn.MouseButton1Click:Connect(function() setHide(true) end)
floatBtn.MouseButton1Click:Connect(function() setHide(false) end)

-- ============================================================
-- TAB BAR
-- ============================================================
local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1, 0, 0, 34)
tabBar.Position = UDim2.new(0, 0, 0, 56)
tabBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
tabBar.BackgroundTransparency = 0.18
tabBar.BorderSizePixel = 0

local tabLine = Instance.new("Frame", tabBar)
tabLine.Size = UDim2.new(0.25, 0, 0, 2)
tabLine.Position = UDim2.new(0, 0, 1, -2)
tabLine.BackgroundColor3 = Color3.fromRGB(0, 118, 255)
tabLine.BorderSizePixel = 0
Instance.new("UICorner", tabLine).CornerRadius = UDim.new(1, 0)

local tabDivLine = Instance.new("Frame", tabBar)
tabDivLine.Size = UDim2.new(1, 0, 0, 1)
tabDivLine.Position = UDim2.new(0, 0, 1, -1)
tabDivLine.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
tabDivLine.BorderSizePixel = 0

local TABS    = {"Fishing","Mining","Settings","Console"}
local tabBtns = {}
local panels  = {}
local currTab = "Fishing"

local content = Instance.new("Frame", main)
content.Size = UDim2.new(1, 0, 1, -90)
content.Position = UDim2.new(0, 0, 0, 90)
content.BackgroundTransparency = 1

for i, tname in ipairs(TABS) do
    local btn = Instance.new("TextButton", tabBar)
    btn.Size = UDim2.new(0.25, 0, 1, -2)
    btn.Position = UDim2.new((i-1)*0.25, 0, 0, 0)
    btn.BackgroundTransparency = 1
    btn.Text = tname
    btn.TextColor3 = i == 1 and Color3.fromRGB(232,232,240) or Color3.fromRGB(125,125,134)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    tabBtns[tname] = btn

    local panel = Instance.new("Frame", content)
    panel.Size = UDim2.new(1, 0, 1, 0)
    panel.BackgroundTransparency = 1
    panel.Visible = i == 1
    panels[tname] = panel
end

local function switchTab(name)
    currTab = name
    local idx = table.find(TABS, name)
    TS:Create(tabLine, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
        Position = UDim2.new((idx-1)*0.25, 0, 1, -2)
    }):Play()
    for n, btn in pairs(tabBtns) do
        btn.TextColor3 = n == name and Color3.fromRGB(232,232,240) or Color3.fromRGB(125,125,134)
        panels[n].Visible = n == name
    end
end
for name, btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ============================================================
-- GUI HELPERS
-- ============================================================
local function mkSep(parent, y)
    local s = Instance.new("Frame", parent)
    s.Size = UDim2.new(1, -22, 0, 1)
    s.Position = UDim2.new(0, 11, 0, y)
    s.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
    s.BorderSizePixel = 0
    return s
end

local function mkLbl(parent, text, y, sz, color)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1, -22, 0, 18)
    l.Position = UDim2.new(0, 11, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(135,135,144)
    l.Font = Enum.Font.GothamMedium
    l.TextSize = sz or 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    return l
end

local function mkToggle(parent, label, y, def, cb)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, -22, 0, 30)
    row.Position = UDim2.new(0, 11, 0, y)
    row.BackgroundTransparency = 1

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.62, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(196,196,206)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local sw = Instance.new("TextButton", row)
    sw.Size = UDim2.new(0, 40, 0, 21)
    sw.Position = UDim2.new(1, -40, 0.5, -10)
    sw.BackgroundColor3 = def and Color3.fromRGB(46,188,82) or Color3.fromRGB(55,55,62)
    sw.Text = ""
    sw.BorderSizePixel = 0
    Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

    local th = Instance.new("Frame", sw)
    th.Size = UDim2.new(0, 17, 0, 17)
    th.Position = def and UDim2.new(1,-19,0.5,-8.5) or UDim2.new(0,2,0.5,-8.5)
    th.BackgroundColor3 = Color3.fromRGB(255,255,255)
    th.BorderSizePixel = 0
    Instance.new("UICorner", th).CornerRadius = UDim.new(1, 0)

    local active = def
    sw.MouseButton1Click:Connect(function()
        if not Manager.alive then return end
        active = not active
        TS:Create(th, TweenInfo.new(0.15), {
            Position = active and UDim2.new(1,-19,0.5,-8.5) or UDim2.new(0,2,0.5,-8.5)
        }):Play()
        TS:Create(sw, TweenInfo.new(0.15), {
            BackgroundColor3 = active and Color3.fromRGB(46,188,82) or Color3.fromRGB(55,55,62)
        }):Play()
        cb(active)
    end)
    return sw, th
end

-- ============================================================
-- FISHING PANEL
-- ============================================================
local fp = panels["Fishing"]

local fishStatLbl  = mkLbl(fp, "Status: Idle", 10, 12, Color3.fromRGB(135,135,144))
local fishCntLbl   = mkLbl(fp, "Fish Caught: 0", 28, 11)

-- progress bar
local pbBg = Instance.new("Frame", fp)
pbBg.Size = UDim2.new(1, -22, 0, 4)
pbBg.Position = UDim2.new(0, 11, 0, 54)
pbBg.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
pbBg.BorderSizePixel = 0
Instance.new("UICorner", pbBg).CornerRadius = UDim.new(1, 0)

local pbFill = Instance.new("Frame", pbBg)
pbFill.Size = UDim2.new(0, 0, 1, 0)
pbFill.BackgroundColor3 = Color3.fromRGB(0, 118, 255)
pbFill.BorderSizePixel = 0
Instance.new("UICorner", pbFill).CornerRadius = UDim.new(1, 0)

local phaseNm  = {"Cast","Wait","Game","Done"}
local phaseCl  = {Color3.fromRGB(0,118,255), Color3.fromRGB(255,148,0), Color3.fromRGB(255,48,80), Color3.fromRGB(46,188,82)}
local phaseLbs = {}
for i = 1, 4 do
    local l = Instance.new("TextLabel", fp)
    l.Size = UDim2.new(0.25, 0, 0, 16)
    l.Position = UDim2.new((i-1)*0.25 + 0.013, 0, 0, 60)
    l.BackgroundTransparency = 1
    l.Text = phaseNm[i]
    l.TextColor3 = Color3.fromRGB(76,76,84)
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 10
    phaseLbs[i] = l
end

local activePhase = 0
local function setPhase(ph)
    activePhase = ph
    for i = 1, 4 do
        if i < ph then
            phaseLbs[i].TextColor3 = Color3.fromRGB(145,145,154)
        elseif i == ph then
            phaseLbs[i].TextColor3 = phaseCl[i]
        else
            phaseLbs[i].TextColor3 = Color3.fromRGB(74,74,82)
        end
    end
    if ph == 0 then
        TS:Create(pbFill, TweenInfo.new(0.18), {Size = UDim2.new(0,0,1,0), BackgroundColor3 = Color3.fromRGB(0,118,255)}):Play()
    else
        TS:Create(pbFill, TweenInfo.new(0.18), {
            Size = UDim2.new(math.clamp(ph*0.25,0,1), 0, 1, 0),
            BackgroundColor3 = phaseCl[ph]
        }):Play()
    end
end

local function setPBar(frac)
    if activePhase <= 0 then return end
    local base = (activePhase-1)*0.25
    pbFill.Size = UDim2.new(math.clamp(base + frac*0.25, 0, 1), 0, 1, 0)
end

mkSep(fp, 82)

-- rod selector
local rodBox = Instance.new("Frame", fp)
rodBox.Size = UDim2.new(1, -22, 0, 50)
rodBox.Position = UDim2.new(0, 11, 0, 88)
rodBox.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
rodBox.BorderSizePixel = 0
Instance.new("UICorner", rodBox).CornerRadius = UDim.new(0, 9)
local rbStr = Instance.new("UIStroke", rodBox)
rbStr.Color = Color3.fromRGB(40, 40, 47)
rbStr.Thickness = 1

local rodHdrLbl = Instance.new("TextLabel", rodBox)
rodHdrLbl.Size = UDim2.new(1, 0, 0, 16)
rodHdrLbl.Position = UDim2.new(0, 10, 0, 4)
rodHdrLbl.BackgroundTransparency = 1
rodHdrLbl.Text = "Rod Selection"
rodHdrLbl.TextColor3 = Color3.fromRGB(85, 85, 96)
rodHdrLbl.Font = Enum.Font.GothamMedium
rodHdrLbl.TextSize = 10
rodHdrLbl.TextXAlignment = Enum.TextXAlignment.Left

local prevRodBtn = Instance.new("TextButton", rodBox)
prevRodBtn.Size = UDim2.new(0, 24, 0, 22)
prevRodBtn.Position = UDim2.new(0, 6, 1, -28)
prevRodBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
prevRodBtn.Text = "<"
prevRodBtn.TextColor3 = Color3.fromRGB(175,175,184)
prevRodBtn.Font = Enum.Font.GothamBold
prevRodBtn.TextSize = 13
prevRodBtn.BorderSizePixel = 0
Instance.new("UICorner", prevRodBtn).CornerRadius = UDim.new(0, 5)

local nextRodBtn = Instance.new("TextButton", rodBox)
nextRodBtn.Size = UDim2.new(0, 24, 0, 22)
nextRodBtn.Position = UDim2.new(1, -30, 1, -28)
nextRodBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
nextRodBtn.Text = ">"
nextRodBtn.TextColor3 = Color3.fromRGB(175,175,184)
nextRodBtn.Font = Enum.Font.GothamBold
nextRodBtn.TextSize = 13
nextRodBtn.BorderSizePixel = 0
Instance.new("UICorner", nextRodBtn).CornerRadius = UDim.new(0, 5)

local rodNameLbl = Instance.new("TextLabel", rodBox)
rodNameLbl.Size = UDim2.new(1, -64, 0, 22)
rodNameLbl.Position = UDim2.new(0, 36, 1, -28)
rodNameLbl.BackgroundTransparency = 1
rodNameLbl.Text = RODS[1].name
rodNameLbl.TextColor3 = Color3.fromRGB(218,218,228)
rodNameLbl.Font = Enum.Font.GothamMedium
rodNameLbl.TextSize = 12

local rodStatLbl = mkLbl(fp, "Lure: 100%  |  Progress: 100%", 142, 10, Color3.fromRGB(82,82,92))

local function updateRod()
    local r = RODS[selectedRod]
    rodNameLbl.Text = r.name
    rodStatLbl.Text = string.format("Lure: %d%%  |  Progress: %d%%", math.floor(r.lure*100), math.floor(r.prog*100))
end

prevRodBtn.MouseButton1Click:Connect(function()
    selectedRod = selectedRod <= 1 and #RODS or selectedRod - 1
    updateRod()
    lg("[FISH] Rod: " .. RODS[selectedRod].name)
end)
nextRodBtn.MouseButton1Click:Connect(function()
    selectedRod = selectedRod >= #RODS and 1 or selectedRod + 1
    updateRod()
    lg("[FISH] Rod: " .. RODS[selectedRod].name)
end)

mkSep(fp, 162)

-- fishing toggle
local fishSw, fishTh = mkToggle(fp, "Fishing System", 168, false, function(on)
    if on then
        if mode == "MINE" then
            mode = "OFF"
        end
        mode = "FISH"
        fishState = "IDLE"
        fishStatLbl.Text = "Status: Starting"
        lg("[FISH] Activated")
    else
        mode = "OFF"
        fishStatLbl.Text = "Status: Idle"
        isSpace = false
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        setPhase(0)
        lg("[FISH] Deactivated")
    end
end)

-- reset button
local rstBtn = Instance.new("TextButton", fp)
rstBtn.Size = UDim2.new(0, 76, 0, 22)
rstBtn.Position = UDim2.new(1, -88, 0, 200)
rstBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 37)
rstBtn.Text = "Reset"
rstBtn.TextColor3 = Color3.fromRGB(165,165,174)
rstBtn.Font = Enum.Font.GothamMedium
rstBtn.TextSize = 11
rstBtn.BorderSizePixel = 0
Instance.new("UICorner", rstBtn).CornerRadius = UDim.new(0, 6)
local rstStr = Instance.new("UIStroke", rstBtn)
rstStr.Color = Color3.fromRGB(46, 46, 53)
rstStr.Thickness = 1

rstBtn.MouseButton1Click:Connect(function()
    fishState   = "IDLE"
    isSpace     = false
    isCasting   = false
    successDone = false
    mgEverSeen  = false
    mgStarted   = false
    wBar        = nil
    rBar        = nil
    lastScan    = 0
    lastWC      = nil
    wVel        = 0
    mgLastSeen  = 0
    castSession = castSession + 1
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
    setPhase(0)
    fishStatLbl.Text = "Status: Reset"
    lg("[FISH] Manual reset")
    task.delay(0.6, function()
        if mode == "FISH" then fishStatLbl.Text = "Status: Idle" end
    end)
end)

-- ============================================================
-- MINING PANEL
-- ============================================================
local mp = panels["Mining"]

local mineStatLbl = mkLbl(mp, "Status: Idle", 10, 12, Color3.fromRGB(135,135,144))
local mineCntLbl  = mkLbl(mp, "Crystals Mined: 0", 28, 11)

mkSep(mp, 52)

-- stop range field
local function mkNumRow(parent, label, y, defVal, minV, maxV, onChange)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, -22, 0, 30)
    row.Position = UDim2.new(0, 11, 0, y)
    row.BackgroundTransparency = 1

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.6, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(196,196,206)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local box = Instance.new("TextBox", row)
    box.Size = UDim2.new(0, 74, 0, 22)
    box.Position = UDim2.new(1, -78, 0.5, -11)
    box.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
    box.TextColor3 = Color3.fromRGB(228,228,238)
    box.Text = tostring(defVal)
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.BorderSizePixel = 0
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local bs = Instance.new("UIStroke", box)
    bs.Color = Color3.fromRGB(46,46,54)
    bs.Thickness = 1

    box.FocusLost:Connect(function()
        local v = tonumber(box.Text)
        if v then
            v = math.clamp(v, minV, maxV)
            box.Text = string.format("%.1f", v)
            onChange(v)
        else
            box.Text = string.format("%.1f", defVal)
        end
    end)
    return box
end

mkNumRow(mp, "Mine Stop Range", 58, STOP_DIST, 1.5, 6.0, function(v)
    STOP_DIST = v
    lg("[MINE] Stop range: " .. v)
end)

-- walk speed button
local speedRow = Instance.new("Frame", mp)
speedRow.Size = UDim2.new(1, -22, 0, 30)
speedRow.Position = UDim2.new(0, 11, 0, 92)
speedRow.BackgroundTransparency = 1

local spLbl = Instance.new("TextLabel", speedRow)
spLbl.Size = UDim2.new(0.6, 0, 1, 0)
spLbl.BackgroundTransparency = 1
spLbl.Text = "Walk / Sprint Speed"
spLbl.TextColor3 = Color3.fromRGB(196,196,206)
spLbl.Font = Enum.Font.GothamMedium
spLbl.TextSize = 12
spLbl.TextXAlignment = Enum.TextXAlignment.Left

local spBtn = Instance.new("TextButton", speedRow)
spBtn.Size = UDim2.new(0, 88, 0, 22)
spBtn.Position = UDim2.new(1, -92, 0.5, -11)
spBtn.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
spBtn.TextColor3 = Color3.fromRGB(228,228,238)
spBtn.Text = "Sprint: 24"
spBtn.Font = Enum.Font.GothamMedium
spBtn.TextSize = 11
spBtn.BorderSizePixel = 0
Instance.new("UICorner", spBtn).CornerRadius = UDim.new(0, 6)
local spStr = Instance.new("UIStroke", spBtn)
spStr.Color = Color3.fromRGB(46,46,54)
spStr.Thickness = 1

local speedCycle = {{16,"Walk: 16"},{20,"Jog: 20"},{24,"Sprint: 24"}}
local speedIdx   = 3
spBtn.MouseButton1Click:Connect(function()
    speedIdx   = speedIdx % #speedCycle + 1
    WALK_SPEED = speedCycle[speedIdx][1]
    spBtn.Text = speedCycle[speedIdx][2]
    lg("[MINE] Speed: " .. WALK_SPEED)
end)

mkSep(mp, 128)

mkToggle(mp, "Smooth Movement", 134, true, function(v)
    CFG.smoothMove = v
    lg("[MINE] Smooth: " .. tostring(v))
end)

mkSep(mp, 170)

local mineSw, mineTh = mkToggle(mp, "Mining System", 176, false, function(on)
    if on then
        if mode == "FISH" then
            mode = "OFF"
            setPhase(0)
            fishStatLbl.Text = "Status: Idle"
        end
        mode = "MINE"
        currentTarget = nil
        failCount = 0; hitCount = 0
        mineStatLbl.Text = "Status: Active"
        lg("[MINE] Activated")
        if not mineActive then
            task.spawn(mineRoutine)
        end
    else
        mode = "OFF"
        mineStatLbl.Text = "Status: Idle"
        pcall(function()
            local h = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
            if h then h:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
            VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)
        lg("[MINE] Deactivated")
    end
end)

-- ============================================================
-- SETTINGS PANEL
-- ============================================================
local stp  = panels["Settings"]
local stY  = 10

local function addSet(label, key, def)
    CFG[key] = def
    mkToggle(stp, label, stY, def, function(v)
        CFG[key] = v
        lg("[CFG] " .. label .. ": " .. tostring(v))
    end)
    stY = stY + 34
end

mkLbl(stp, "Anti-Detection", 12, 10, Color3.fromRGB(80,80,90))
stY = 32
mkSep(stp, 30)

addSet("Timing Randomization",   "timeJitter",   true)
addSet("Click Coord Jitter",     "coordJitter",  true)
addSet("Path Waypoint Jitter",   "pathJitter",   true)
addSet("Fatigue Break",          "fatigueBreak", true)
addSet("Anti-AFK Mouse Sweep",   "mouseAFK",     true)

mkSep(stp, stY); stY = stY + 8
mkLbl(stp, "Security", stY, 10, Color3.fromRGB(80,80,90))
stY = stY + 20; mkSep(stp, stY); stY = stY + 8

addSet("Admin / Staff Guard",    "adminGuard",   true)
addSet("Anti-Script Fingerprint","antiFingerp",  true)

-- ============================================================
-- CONSOLE PANEL
-- ============================================================
local cp = panels["Console"]

mkToggle(cp, "Console Logging", 10, false, function(v)
    consoleOn = v
    lg("[SYS] Console: " .. (v and "ON" or "OFF"))
end)

local clrBtn = Instance.new("TextButton", cp)
clrBtn.Size = UDim2.new(0, 74, 0, 22)
clrBtn.Position = UDim2.new(1, -86, 0, 10)
clrBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
clrBtn.Text = "Clear"
clrBtn.TextColor3 = Color3.fromRGB(155,155,164)
clrBtn.Font = Enum.Font.GothamMedium
clrBtn.TextSize = 11
clrBtn.BorderSizePixel = 0
Instance.new("UICorner", clrBtn).CornerRadius = UDim.new(0, 6)
local clrStr = Instance.new("UIStroke", clrBtn)
clrStr.Color = Color3.fromRGB(44, 44, 51)
clrStr.Thickness = 1

mkSep(cp, 38)

local logSF = Instance.new("ScrollingFrame", cp)
logSF.Size = UDim2.new(1, -22, 1, -52)
logSF.Position = UDim2.new(0, 11, 0, 48)
logSF.BackgroundTransparency = 1
logSF.CanvasSize = UDim2.new(0, 0, 0, 0)
logSF.ScrollBarThickness = 2
logSF.ScrollBarImageColor3 = Color3.fromRGB(52, 52, 60)

local logLL = Instance.new("UIListLayout", logSF)
logLL.SortOrder = Enum.SortOrder.LayoutOrder
logLL.Padding = UDim.new(0, 3)

local logOrd = 0
local function appendLog(text)
    if not consoleOn then return end
    logOrd = logOrd + 1
    local l = Instance.new("TextLabel", logSF)
    l.LayoutOrder = logOrd
    l.Size = UDim2.new(1, 0, 0, 14)
    l.BackgroundTransparency = 1
    l.Text = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(text)
    l.TextColor3 = Color3.fromRGB(155,155,165)
    l.Font = Enum.Font.Code
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true
    task.defer(function()
        logSF.CanvasSize = UDim2.new(0,0,0,logLL.AbsoluteContentSize.Y + 6)
        logSF.CanvasPosition = Vector2.new(0, math.huge)
    end)
    local lbls = {}
    for _, c in ipairs(logSF:GetChildren()) do
        if c:IsA("TextLabel") then lbls[#lbls+1] = c end
    end
    if #lbls > 80 then lbls[1]:Destroy() end
end
_consLog = appendLog

clrBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(logSF:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    logSF.CanvasSize = UDim2.new(0,0,0,0)
    logOrd = 0
end)

-- ============================================================
-- HELPERS
-- ============================================================
local function trulyVis(obj)
    if not obj or typeof(obj) ~= "Instance" then return false end
    if not obj:IsA("GuiObject") then return false end
    if not obj.Visible then return false end
    local ok, sz = pcall(function() return obj.AbsoluteSize end)
    if not ok or sz.X <= 0 or sz.Y <= 0 then return false end
    local cur = obj.Parent
    while cur and cur ~= game do
        if cur:IsA("ScreenGui") then
            if not cur.Enabled then return false end; break
        elseif cur:IsA("GuiObject") then
            if not cur.Visible then return false end
        end
        cur = cur.Parent
    end
    return true
end

local function findTool(lst)
    local ch = me.Character
    local bp = me.Backpack
    if ch then
        for _, n in ipairs(lst) do
            local t = ch:FindFirstChild(n)
            if t and t:IsA("Tool") then return t, "char" end
        end
    end
    for _, n in ipairs(lst) do
        local t = bp:FindFirstChild(n)
        if t then return t, "bp" end
    end
    if ch then
        local t = ch:FindFirstChildWhichIsA("Tool")
        if t then return t, "char" end
    end
    return bp:FindFirstChildWhichIsA("Tool"), "bp"
end

local function equipTool(lst)
    local ch = me.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local eq = ch:FindFirstChildWhichIsA("Tool")
    for _, n in ipairs(lst) do
        if eq and eq.Name:lower():find(n:lower()) then return eq end
    end
    local t, loc = findTool(lst)
    if t and loc == "bp" then
        pcall(function() hum:EquipTool(t) end)
        task.wait(0.7)
        return ch:FindFirstChildWhichIsA("Tool")
    end
    return eq
end

local function jitterT(base, pct)
    if not CFG.timeJitter then return base end
    return base * (1 + (math.random()*2-1) * (pct or 0.12))
end

local function jitterV2(v)
    if not CFG.coordJitter then return v end
    return Vector2.new(v.X + math.random(-13,13), v.Y + math.random(-11,11))
end

-- ============================================================
-- ANTI-AFK & FATIGUE
-- ============================================================
task.spawn(function()
    while Manager.alive do
        task.wait(math.random(95, 155))
        if not Manager.alive then break end
        if CFG.mouseAFK then
            pcall(function()
                local cam = workspace.CurrentCamera
                if cam then
                    local sz = cam.ViewportSize
                    VU:MouseMoveEvent(Vector2.new(sz.X/2 + math.random(-75,75), sz.Y/2 + math.random(-55,55)), cam.CFrame)
                end
            end)
        end
    end
end)

local afkC = me.Idled:Connect(function()
    pcall(function()
        VU:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(0.13)
        VU:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end)
table.insert(Manager.conns, afkC)

local function checkFatigue(statLbl)
    if not CFG.fatigueBreak then return end
    fatCount = fatCount + 1
    if fatCount < fatNext then return end
    local sec = math.random(5, 11)
    lg("[SEC] Resting " .. sec .. "s")
    local prev = statLbl.Text
    statLbl.Text = "Status: Resting"
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
    isSpace = false
    task.wait(sec)
    fatCount = 0
    fatNext  = math.random(12, 22)
    statLbl.Text = prev
    lg("[SEC] Break done")
end

-- ============================================================
-- ADMIN DETECTION
-- ============================================================
local STAFF_GRP = 1200769
local ADM_PATS  = {"moderator","roblox_adm","rbxadmin","staffmod","gamemaster","game_master","game master"}

local function checkAdmin(p)
    if p == me or not p.Parent then return end
    if not CFG.adminGuard then return end
    task.wait(2.2)
    if not p or not p.Parent then return end
    local isAdm = false
    pcall(function() isAdm = isAdm or p:IsInGroup(STAFF_GRP) end)
    if not isAdm then
        local ln = (p.Name .. p.DisplayName):lower()
        for _, pat in ipairs(ADM_PATS) do
            if ln:find(pat) then isAdm = true; break end
        end
    end
    if not isAdm then
        pcall(function()
            if game.CreatorType == Enum.CreatorType.Group then
                if p:GetRankInGroup(game.CreatorId) >= 200 then isAdm = true end
            end
        end)
    end
    if isAdm then
        lg("[SEC] Moderator detected: " .. p.Name)
        mode = "OFF"
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
        isSpace = false
        task.wait(0.8)
        me:Kick("Disconnected.")
    end
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(checkAdmin, p) end
local admC = Players.PlayerAdded:Connect(function(p) task.spawn(checkAdmin, p) end)
table.insert(Manager.conns, admC)

-- ============================================================
-- FISHING ENGINE
-- ============================================================
local function resetFish()
    fishState   = "IDLE"
    isSpace     = false
    isCasting   = false
    successDone = false
    mgEverSeen  = false
    mgStarted   = false
    wBar        = nil
    rBar        = nil
    lastScan    = 0
    lastWC      = nil
    wVel        = 0
    mgLastSeen  = 0
    castSession = castSession + 1
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
    setPhase(0)
end

local function setSpace(v, force)
    if isSpace == v and not force then return end
    local now = os.clock()
    if not force and (now - lastSpTgl) < 0.03 then return end
    pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
    isSpace  = v
    lastSpTgl = now
end

local function getBars()
    -- Jangan pakai cache jika sudah tidak valid
    if wBar and rBar and wBar.Parent and rBar.Parent and trulyVis(wBar) and trulyVis(rBar) then
        return wBar, rBar
    end
    local now = os.clock()
    if now - lastScan < 0.04 then return nil, nil end
    lastScan = now
    wBar = nil; rBar = nil

    local pg = me:FindFirstChild("PlayerGui")
    if not pg then return nil, nil end

    -- nama-based scan
    for _, v in pairs(pg:GetDescendants()) do
        if v:IsA("GuiObject") and trulyVis(v) then
            local ln = v.Name:lower()
            local par = v.Parent
            if par and par:IsA("GuiObject") then
                local isWhite = ln == "whitebar" or ln == "playerbar"
                    or (ln:find("white") and ln:find("bar"))
                if isWhite then
                    local red = par:FindFirstChild("RedBar") or par:FindFirstChild("TargetBar")
                    if not red then
                        for _, sib in ipairs(par:GetChildren()) do
                            if sib ~= v and sib:IsA("GuiObject") and trulyVis(sib) then
                                local sn = sib.Name:lower()
                                if sn:find("red") or sn:find("target") or sn:find("goal") then
                                    red = sib; break
                                end
                            end
                        end
                    end
                    if red and trulyVis(red) and v.AbsoluteSize.X > 10 then
                        wBar = v; rBar = red
                        return v, red
                    end
                end
            end
        end
    end

    -- color-based fallback
    for _, v in pairs(pg:GetDescendants()) do
        if v:IsA("GuiObject") and trulyVis(v) and v.AbsoluteSize.X > 12 and v.AbsoluteSize.Y > 5 then
            local c = v.BackgroundColor3
            local p = v.Parent
            if c.R > 0.80 and c.G > 0.80 and c.B > 0.80 and p and p:IsA("GuiObject") then
                for _, sib in ipairs(p:GetChildren()) do
                    if sib ~= v and sib:IsA("GuiObject") and trulyVis(sib) and sib.AbsoluteSize.X > 12 then
                        local sc = sib.BackgroundColor3
                        if sc.R > 0.48 and sc.G < 0.24 and sc.B < 0.24 then
                            wBar = v; rBar = sib
                            return v, sib
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end

local function doSuccess(reason)
    if successDone then return end
    successDone = true
    setSpace(false, true)
    fishState = "DONE"
    setPhase(4)
    fishCount = fishCount + 1
    fishCntLbl.Text = "Fish Caught: " .. fishCount
    fishStatLbl.Text = "Status: Caught"
    lg("[FISH] Caught #" .. fishCount .. " via " .. reason)
    checkFatigue(fishStatLbl)
    local sess = castSession
    task.delay(jitterT(RECAST_DLY, 0.15), function()
        if not Manager.alive or mode ~= "FISH" or castSession ~= sess then return end
        resetFish()
        task.wait(0.06)
        if mode == "FISH" then fishState = "IDLE" end
    end)
end

-- Heartbeat: handles minigame logic
local hbC = RS.Heartbeat:Connect(function()
    if not Manager.alive then return end
    if mode ~= "FISH" then
        if isSpace then setSpace(false, true) end
        return
    end

    safe(function()
        local now  = os.clock()
        local rod  = RODS[selectedRod]

        if fishState == "WAITING" then
            local el = now - biteStart
            setPBar(math.clamp(el / BITE_WAIT, 0, 1))
            fishStatLbl.Text = string.format("Status: Waiting (%.0fs)", math.max(0, BITE_WAIT - el))
            if el >= BITE_WAIT then
                fishState  = "MINIGAME"
                mgStart    = now
                mgEverSeen = false
                mgStarted  = false
                mgLastSeen = 0
                successDone = false
                -- PENTING: bersihkan cache bar setiap awal minigame baru
                wBar    = nil
                rBar    = nil
                lastScan = 0
                lastWC  = nil
                wVel    = 0
                lastWTime = now
                setSpace(false, true)
                setPhase(3)
                setPBar(0)
                fishStatLbl.Text = "Status: Minigame"
                lg("[FISH] Minigame start")
            end
            return
        end

        if fishState == "MINIGAME" then
            local el = now - mgStart
            -- timeout adaptif: rod progress lebih cepat = minigame lebih singkat
            local timeout = 11 + rod.prog * 3.5
            setPBar(math.clamp(el / timeout, 0, 1))

            if el >= timeout then
                setSpace(false, true)
                doSuccess("timeout")
                return
            end

            local wb, rb = getBars()

            if wb and rb and trulyVis(wb) and trulyVis(rb) then
                mgEverSeen = true
                mgLastSeen = now

                if not mgStarted then
                    mgStarted = true
                    setSpace(false, true)
                    lastWC    = nil
                    wVel      = 0
                    lastWTime = now
                end

                local wC  = wb.AbsolutePosition.X + wb.AbsoluteSize.X * 0.5
                local rL  = rb.AbsolutePosition.X
                local rR  = rL + rb.AbsoluteSize.X
                local rC  = (rL + rR) * 0.5

                -- Delta time untuk lag compensation — clamp agar prediksi tetap wajar
                local rawDt = now - lastWTime
                local dt    = math.clamp(rawDt, 0.007, 0.14)

                if lastWC then
                    local inst   = (wC - lastWC) / dt
                    -- rod lebih cepat → smoothing lebih cepat
                    local smooth = math.clamp(0.28 / rod.lure, 0.1, 0.32)
                    wVel = wVel * (1 - smooth) + inst * smooth
                end
                lastWC    = wC
                lastWTime = now

                -- Prediksi posisi bar ke depan
                -- rod lebih cepat → perlu prediksi lebih jauh
                local ahead     = math.clamp(math.abs(wVel) / 1700, 0.03, 0.18) * math.sqrt(rod.lure)
                local predicted = wC + wVel * ahead

                local rw  = math.max(rb.AbsoluteSize.X, 1)
                -- toleransi lebih lebar saat lag terdeteksi
                local lag = math.clamp(rawDt / 0.05 - 1, 0, 1.2)
                local tol = math.clamp(rw * (0.18 + lag * 0.14 + rod.lure * 0.025), 4, 26)

                local inside = predicted >= (rL - tol) and predicted <= (rR + tol)

                if inside then
                    if wC < rL then
                        setSpace(true)
                    elseif wC > rR then
                        setSpace(false)
                    else
                        local err = wC - rC
                        if math.abs(err) > tol * 0.4 then setSpace(err < 0) end
                    end
                else
                    local err = rC - predicted
                    if     err >  tol then setSpace(true)
                    elseif err < -tol then setSpace(false)
                    elseif math.abs(wVel) > 140 then setSpace(wVel < 0)
                    end
                end

                fishStatLbl.Text = string.format("Status: Playing (%.0fs)", el)

            else
                if mgEverSeen then
                    -- bar menghilang, berarti minigame selesai
                    if mgLastSeen > 0 and (now - mgLastSeen) >= 0.20 then
                        setSpace(false, true)
                        doSuccess("bar-gone")
                    end
                else
                    -- bar belum muncul, ketuk ritmis sembari tunggu
                    local beat = math.floor((now - mgStart) * 3.2) % 2 == 0
                    setSpace(beat)
                    fishStatLbl.Text = string.format("Status: Sync (%.0fs)", el)
                end
            end
        end
    end)
end)
table.insert(Manager.conns, hbC)

-- Fishing main controller loop
task.spawn(function()
    while Manager.alive do
        task.wait(0.16)
        if not Manager.alive or mode ~= "FISH" then continue end
        safe(function()
            local ch  = me.Character
            if not ch then return end
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if not hum then return end

            if hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
                hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
            end

            local tool = equipTool(FISH_TOOLS)
            if not tool then fishStatLbl.Text = "Status: No rod"; return end

            if fishState == "IDLE" and not isCasting then
                isCasting = true
                castSession = castSession + 1
                local sess = castSession

                task.spawn(function()
                    if not Manager.alive or mode ~= "FISH" or castSession ~= sess then
                        isCasting = false; return
                    end
                    local cam = workspace.CurrentCamera
                    if not cam then isCasting = false; return end

                    local rod    = RODS[selectedRod]
                    local center = jitterV2(cam.ViewportSize / 2)

                    fishState = "CASTING"
                    setPhase(1); setPBar(0)
                    fishStatLbl.Text = "Status: Casting"
                    lg("[FISH] Cast #" .. (fishCount+1) .. " (" .. rod.name .. ")")

                    pcall(function() tool:Activate() end)
                    pcall(function() VU:Button1Down(center, cam.CFrame) end)

                    -- durasi cast dikurangi untuk rod dengan lure tinggi (umpan mudah jatuh)
                    local dur = jitterT(CAST_HOLD / math.max(1, math.sqrt(rod.lure) * 0.85), 0.1)
                    local t0  = os.clock()
                    while os.clock() - t0 < dur do
                        task.wait(0.04)
                        if mode ~= "FISH" or not Manager.alive or castSession ~= sess then
                            pcall(function() VU:Button1Up(center, cam.CFrame) end)
                            isCasting = false; return
                        end
                        setPBar((os.clock()-t0) / dur)
                    end

                    pcall(function() VU:Button1Up(center, cam.CFrame) end)
                    setPBar(1)
                    task.wait(jitterT(0.15, 0.08))

                    if mode ~= "FISH" or not Manager.alive or castSession ~= sess then
                        isCasting = false; return
                    end

                    fishState = "WAITING"
                    biteStart = os.clock()
                    setPhase(2); setPBar(0)
                    fishStatLbl.Text = "Status: Waiting"
                    lg("[FISH] Waiting for bite")
                    isCasting = false
                end)
            end
        end)
    end
end)

-- ============================================================
-- MINING ENGINE
-- ============================================================

-- cek apakah nama termasuk blacklist
local function isBL(name)
    local ln = name:lower()
    for _, bl in ipairs(CRYS_BL) do
        if ln:find(bl, 1, true) then return true end
    end
    return false
end

-- scoring crystal candidate
local function scorePart(part)
    if not (part:IsA("BasePart") or part:IsA("MeshPart")) then return -1 end
    if isBL(part.Name) then return -999 end

    -- cek parent chain juga
    local par = part.Parent
    while par and par ~= workspace do
        if isBL(par.Name) then return -999 end
        par = par.Parent
    end

    local sc = 0
    local ln = part.Name:lower()

    for _, cn in ipairs(CRYS_NAMES) do
        if ln:find(cn:lower(), 1, true) then sc = sc + 5; break end
    end

    if part.Material == Enum.Material.Neon        then sc = sc + 3 end
    if part:IsA("MeshPart")                        then sc = sc + 1 end
    if part.Transparency < 0.85                    then sc = sc + 1 end
    if part.CanCollide                             then sc = sc + 1 end

    local sz = part.Size
    -- terlalu besar = bukan crystal
    if sz.X > 20 or sz.Y > 20 or sz.Z > 20       then sc = sc - 6 end
    -- terlalu kecil = bukan crystal (particle, detail)
    if sz.X < 0.35 and sz.Y < 0.35 and sz.Z < 0.35 then sc = sc - 5 end

    -- bonus nama parent
    local pname = (part.Parent and part.Parent.Name or ""):lower()
    for _, cn in ipairs(CRYS_NAMES) do
        if pname:find(cn:lower(), 1, true) then sc = sc + 3; break end
    end

    return sc
end

-- apakah crystal sedang ditambang player lain?
local function isOccupied(crystal)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= me and p.Character then
            local root = p.Character.PrimaryPart
            if root and (root.Position - crystal.Position).Magnitude < 11 then
                local t = p.Character:FindFirstChildOfClass("Tool")
                if t then
                    local tn = t.Name:lower()
                    for _, mn in ipairs(MINE_TOOLS) do
                        if tn:find(mn:lower(), 1, true) then return true end
                    end
                end
            end
        end
    end
    return false
end

local function findBestCrystal()
    local ch = me.Character
    if not ch or not ch.PrimaryPart then return nil end
    local myPos = ch.PrimaryPart.Position

    -- tetap pakai target saat ini jika masih valid
    if currentTarget and currentTarget.Parent
       and failCount < 4
       and not isOccupied(currentTarget)
       and (currentTarget.Position - myPos).Magnitude < 290 then
        return currentTarget
    end

    local best, bestVal = nil, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        local sc = scorePart(obj)
        if sc >= 6 and not isOccupied(obj) then
            local d = (obj.Position - myPos).Magnitude
            if d < 290 then
                -- lebih dekat + skor lebih tinggi = lebih prioritas
                local val = d - sc * 9
                if val < bestVal then bestVal = val; best = obj end
            end
        end
    end

    currentTarget = best
    failCount     = 0
    return best
end

local function groundRay(pos, ignoreList)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Blacklist
    p.FilterDescendantsInstances = ignoreList or {}
    p.IgnoreWater = false
    return workspace:Raycast(pos + Vector3.new(0,16,0), Vector3.new(0,-58,0), p)
end

-- Hitung titik berdiri di samping crystal (bukan di atasnya)
local function getStandPoint(crystal)
    local ch = me.Character
    if not ch or not ch.PrimaryPart then return nil end
    local origin = crystal.Position
    local cw     = math.max(crystal.Size.X, crystal.Size.Z)
    local radius = math.clamp(cw * 0.28 + 1.3, STOP_DIST, 3.8)
    local ignore = {ch, crystal}

    local best, bestSc = nil, math.huge
    for i = 1, 24 do
        local a   = math.pi * 2 * (i / 24)
        local smp = origin + Vector3.new(math.cos(a)*radius, 0, math.sin(a)*radius)
        local gr  = groundRay(smp, ignore)
        if gr and gr.Instance and gr.Normal.Y > 0.48 then
            local pos = gr.Position + Vector3.new(0, 3.1, 0)
            -- titik ini harus LEBIH RENDAH atau sejajar dengan pusat crystal
            -- supaya player berdiri di sampingnya, bukan di atasnya
            if pos.Y <= origin.Y + crystal.Size.Y * 0.5 then
                local hDelta = math.abs(pos.Y - ch.PrimaryPart.Position.Y)
                if hDelta < 14 then
                    local distC = (Vector3.new(pos.X, origin.Y, pos.Z) - origin).Magnitude
                    local sc    = (pos - ch.PrimaryPart.Position).Magnitude
                                + math.abs(distC - radius) * 5
                                + hDelta
                    if sc < bestSc then bestSc = sc; best = pos end
                end
            end
        end
    end

    if best then return best end

    -- fallback: arah dari player ke crystal
    local d    = ch.PrimaryPart.Position - origin
    local flat = Vector3.new(d.X, 0, d.Z)
    if flat.Magnitude < 0.4 then flat = Vector3.new(1,0,0) end
    local fb = origin + flat.Unit * radius
    local gr = groundRay(fb, ignore)
    return gr and (gr.Position + Vector3.new(0,3.1,0)) or fb
end

-- Lompat yang benar-benar bekerja (bukan hanya set .Jump)
local function doJump(hum)
    task.spawn(function()
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        task.wait(0.02)
        pcall(function()
            VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
            task.wait(0.13)
            VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
    end)
end

local function moveToPos(hum, targetPos, targetPart)
    local ch = me.Character
    if not ch or not ch.PrimaryPart then return false end

    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game) end)

    local path = PFS:CreatePath({
        AgentRadius   = 1.8,
        AgentHeight   = 5.0,
        AgentCanJump  = true,
        AgentCanClimb = false,  -- false: cegah naik ke atas crystal
        WaypointSpacing = CFG.smoothMove and 6 or 3,
        Costs = {Water = 8},
    })

    local ok = pcall(function() path:ComputeAsync(ch.PrimaryPart.Position, targetPos) end)
    local wps
    if ok and path.Status == Enum.PathStatus.Success then
        wps = path:GetWaypoints()
    else
        wps = {{Position = targetPos, Action = Enum.PathWaypointAction.Walk}}
    end

    local origSpeed = hum.WalkSpeed
    hum.WalkSpeed   = WALK_SPEED + (CFG.timeJitter and math.random(-1,2) or 0)

    local lastPos  = ch.PrimaryPart.Position
    local stuckT   = 0
    local arrived  = false

    -- satu titik lompatan acak di tengah perjalanan
    local jumpIdx  = (#wps > 3) and math.random(2, math.floor(#wps * 0.5)) or -1

    for i, wp in ipairs(wps) do
        if mode ~= "MINE" or not Manager.alive then break end
        if targetPart and not targetPart.Parent then break end

        if wp.Action == Enum.PathWaypointAction.Jump then doJump(hum) end

        -- lompat acak di waypoint yang sudah ditentukan
        if i == jumpIdx and math.random() < 0.62 then
            doJump(hum)
        end

        local step = wp.Position
        if CFG.pathJitter and i < #wps then
            step = wp.Position + Vector3.new((math.random()-0.5)*0.55, 0, (math.random()-0.5)*0.55)
        end

        hum:MoveTo(step)

        local t0 = os.clock()
        while mode == "MINE" and Manager.alive and os.clock()-t0 < 5.5 do
            task.wait(CFG.smoothMove and 0.07 or 0.13)
            if not ch.PrimaryPart then break end
            local cur = ch.PrimaryPart.Position

            -- proximity check ke crystal
            if targetPart and targetPart.Parent then
                local dc = (cur - targetPart.Position).Magnitude
                local cw = math.max(targetPart.Size.X, targetPart.Size.Z)
                if dc <= (cw * 0.5 + STOP_DIST + 0.3) then arrived = true; break end
            end

            local reach = (CFG.smoothMove and i < #wps) and 5.2 or 1.3
            if (cur - wp.Position).Magnitude <= reach then break end
            if (cur - targetPos).Magnitude <= 1.3 then arrived = true; break end

            if (cur - lastPos).Magnitude < 0.17 then
                stuckT = stuckT + (CFG.smoothMove and 0.07 or 0.13)
                if stuckT > 1.3 then
                    doJump(hum)
                    local dir = targetPos - cur
                    local d2  = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1,0,0)
                    hum:MoveTo(cur + d2 * 4.5)
                    task.wait(0.35)
                    break
                end
            else
                stuckT  = 0
                lastPos = cur
            end
        end
        if arrived then break end
    end

    hum.WalkSpeed = origSpeed
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)

    if arrived then return true end
    if not ch.PrimaryPart then return false end
    return (ch.PrimaryPart.Position - targetPos).Magnitude <= 2.2
end

local function facePart(part)
    local ch = me.Character
    if not ch or not ch.PrimaryPart or not part then return end
    local p = ch.PrimaryPart.Position
    pcall(function()
        ch:SetPrimaryPartCFrame(CFrame.lookAt(p, Vector3.new(part.Position.X, p.Y, part.Position.Z)))
    end)
end

-- Mining main loop
function mineRoutine()
    mineActive = true
    while mode == "MINE" and Manager.alive do
        task.wait(0.45)
        if not Manager.alive then break end

        safe(function()
            local ch = me.Character
            if not ch or not ch.PrimaryPart then return end
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if not hum then return end

            local crystal = findBestCrystal()
            if not crystal then
                mineStatLbl.Text = "Status: Searching"
                lg("[MINE] No crystal")
                task.wait(3); return
            end

            -- cek occupied lagi tepat sebelum gerak
            if isOccupied(crystal) then
                lg("[MINE] Occupied, skipping")
                currentTarget = nil; return
            end

            local tool = equipTool(MINE_TOOLS)
            if not tool then
                mineStatLbl.Text = "Status: No tool"
                task.wait(2); return
            end

            local myPos = ch.PrimaryPart.Position
            local cw    = math.max(crystal.Size.X, crystal.Size.Z)
            local dist  = (myPos - crystal.Position).Magnitude

            mineStatLbl.Text = "Status: Moving"
            lg("[MINE] Moving to " .. crystal.Name .. " (" .. math.floor(dist) .. "m)")

            local closeEnough = dist <= (cw * 0.5 + STOP_DIST + 0.6)

            if not closeEnough then
                local sp = getStandPoint(crystal)
                if sp and (myPos - sp).Magnitude > 1.0 then
                    local ok = moveToPos(hum, sp, crystal)
                    if not ok then
                        failCount = failCount + 1
                        if failCount >= 4 then currentTarget = nil end
                        task.wait(0.3); return
                    end
                end
            end

            -- nudge ke arah crystal setelah tiba supaya tidak "kurang maju"
            local ch2 = me.Character
            if ch2 and ch2.PrimaryPart and crystal.Parent then
                local cur  = ch2.PrimaryPart.Position
                local diff = crystal.Position - cur
                local flat = Vector3.new(diff.X, 0, diff.Z)
                if flat.Magnitude > 0.3 then
                    local nudge = math.clamp(cw * 0.22, 0.35, 1.0)
                    hum:MoveTo(cur + flat.Unit * nudge)
                    task.wait(0.22)
                end
            end

            facePart(crystal)

            local cam = workspace.CurrentCamera
            if not cam then return end

            local aimPos = crystal.Position + Vector3.new(0, math.clamp(crystal.Size.Y * 0.1, 0.25, 2.2), 0)
            local sPx, onSc = cam:WorldToScreenPoint(aimPos)

            mineStatLbl.Text = "Status: Mining"

            local swings = 0
            for s = 1, 9 do
                if mode ~= "MINE" or not Manager.alive then break end
                if not crystal.Parent then
                    lg("[MINE] Crystal broke after " .. s .. " swings")
                    break
                end
                facePart(crystal)

                -- update screen pos setiap 3 swing
                if s % 3 == 1 then
                    local sp2, os2 = cam:WorldToScreenPoint(aimPos)
                    if os2 then sPx = sp2; onSc = os2 end
                end

                if onSc then
                    local cx = sPx.X + (CFG.coordJitter and math.random(-7,7) or 0)
                    local cy = sPx.Y + (CFG.coordJitter and math.random(-5,6) or 0)
                    pcall(function() VU:Button1Down(Vector2.new(cx,cy), cam.CFrame) end)
                    task.wait(jitterT(0.11, 0.08))
                    pcall(function() VU:Button1Up(Vector2.new(cx,cy), cam.CFrame) end)
                end

                pcall(function() tool:Activate() end)
                swings = swings + 1
                task.wait(jitterT(0.27, 0.1))
            end

            if not crystal.Parent or swings >= 8 then
                mineCount = mineCount + 1
                mineCntLbl.Text = "Crystals Mined: " .. mineCount
                mineStatLbl.Text = "Status: Active"
                lg("[MINE] Crystal #" .. mineCount .. " mined")
                currentTarget = nil
                failCount = 0; hitCount = 0
                checkFatigue(mineStatLbl)
            else
                hitCount = hitCount + 1
                if hitCount >= 5 then
                    mineCount = mineCount + 1
                    mineCntLbl.Text = "Crystals Mined: " .. mineCount
                    hitCount = 0
                    currentTarget = nil
                end
            end
        end)

        task.wait(0.4)
    end
    mineActive = false
end

-- ============================================================
-- INIT
-- ============================================================
setPhase(0)
updateRod()

lg("=== finalv9.lua ready ===")
lg("Rod: " .. RODS[selectedRod].name .. " | Anti-detect: ON")
