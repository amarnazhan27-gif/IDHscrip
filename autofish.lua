--[[
╔══════════════════════════════════════════════════════════════╗
║  Nazhan Fish  v3.0  –  Auto Fishing (standalone entry)       ║
║  Compatible with NasiHub v3.0 shared runtime.                ║
║  Delegates to NazhanHub.lua when hub is loaded, or runs      ║
║  standalone using the same FishingController architecture.   ║
╚══════════════════════════════════════════════════════════════╝

NOTES:
  - If NazhanHub.lua is already loaded (shared.IDH_CLIENT_RUNTIME exists
    and has currentMode), this script skips re-initialising the runtime.
  - Standalone mode provides only Auto Fishing with a minimal UI.
  - Bar-gone alone does NOT count as success (RESULT_UNCONFIRMED).
  - Fish counter increments ONLY on SUCCESS_CONFIRMED.
  - Rod resolver priority:
      1. Equipped Tool with fishing attributes
      2. Equipped Tool matching known rod names
      3. Backpack Tool matching same criteria
      4. Static fallback name list (UI shows "FALLBACK")
]]

-- ── If NasiHub v3.0 hub is already running, just activate fishing
if shared.IDH_CLIENT_RUNTIME and shared.IDH_CLIENT_RUNTIME.alive then
    shared.IDH_CLIENT_RUNTIME.currentMode = "FISH"
    print("[autofish] NasiHub v3.0 runtime detected – delegated to hub.")
    return
end

-- ── Kill old standalone instance
if shared._nzh2 then pcall(shared._nzh2.stop) end
if shared._autofish_v3 then pcall(shared._autofish_v3.stop) end

-- ── Services ─────────────────────────────────────────────────
local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local VIM     = game:GetService("VirtualInputManager")
local VU      = game:GetService("VirtualUser")
local TS      = game:GetService("TweenService")
local HTTP    = game:GetService("HttpService")
local me      = Players.LocalPlayer

-- ── Capability detection ──────────────────────────────────────
local Capabilities = {
    fileIO    = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function",
    clipboard = type(setclipboard) == "function",
    vim       = pcall(function() return VIM.ClassName end),
    vu        = pcall(function() return VU.ClassName end),
}

-- ── Rod fallback profiles (FALLBACK source only) ──────────────
local RODS_FALLBACK = {
    { name="Basic Rod",   lure=1.00, prog=1.00 },
    { name="Party Rod",   lure=1.30, prog=1.08 },
    { name="Shark Rod",   lure=1.57, prog=1.21 },
    { name="Piranha Rod", lure=1.84, prog=1.33 },
    { name="Thermo Rod",  lure=2.11, prog=1.46 },
    { name="Flowers Rod", lure=2.38, prog=1.59 },
    { name="Trisula Rod", lure=2.65, prog=1.72 },
    { name="Feather Rod", lure=2.92, prog=1.84 },
    { name="Wave Rod",    lure=3.19, prog=1.97 },
    { name="Duck Rod",    lure=3.46, prog=2.10 },
    { name="Planet Rod",  lure=3.73, prog=2.23 },
    { name="Earth Rod",   lure=4.00, prog=2.35 },
    { name="Volcano Rod", lure=4.27, prog=2.48 },
}

local FISH_TOOL_NAMES = { "fishing rod", "rod", "pancing", "fishingrod" }

-- ── Config ────────────────────────────────────────────────────
local CFG = {
    fishing = {
        castHold       = 1.8,
        biteTimeout    = 15.0,
        recastDelay    = 0.9,
        minigameGuard  = 0.20,
        watchdogIdle   = 14,
        watchdogWait   = 23,
        watchdogCast   = 12,
        scanCooldown   = 0.05,
        fatigueEvery   = 25,
        fatigueDur     = 8,
    },
    performance = {
        smooth        = 0.08,
        slowThreshold = 0.05,
    },
}

-- ── Performance monitor (frameTime – NOT network lag) ─────────
local frameTime = 0.016
local frameSlow = false
local function updateFrameTime(dt)
    frameTime = frameTime * (1 - CFG.performance.smooth) + dt * CFG.performance.smooth
    frameSlow = frameTime > CFG.performance.slowThreshold
end

-- ── Counters ──────────────────────────────────────────────────
local fishAttempts  = 0
local fishConfirmed = 0
local fishFailed    = 0
local fishUnknown   = 0
local sessStart     = os.clock()

-- ── Runtime controller ────────────────────────────────────────
local _S = { alive = true, connections = {}, active = false }
_S.stop = function()
    _S.alive  = false
    _S.active = false
    -- Release all tracked connections
    for _, v in ipairs(_S.connections) do pcall(function() v:Disconnect() end) end
    table.clear(_S.connections)
    -- Release Space key
    if Capabilities.vim then
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
    end
    -- Restore jump
    pcall(function()
        local ch  = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
    end)
    -- Restore original WalkSpeed
    pcall(function()
        local ch  = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum and _S._origWalkSpeed then hum.WalkSpeed = _S._origWalkSpeed end
    end)
    -- Destroy GUI
    pcall(function()
        local old = me.PlayerGui:FindFirstChild("_nzh_fish3")
        if old then old:Destroy() end
        local cg = game:GetService("CoreGui"):FindFirstChild("_nzh_fish3")
        if cg then cg:Destroy() end
    end)
end
_S._origWalkSpeed = nil

shared._nzh2       = _S   -- backward compat
shared._autofish_v3 = _S

-- ── Fishing state machine ─────────────────────────────────────
local STATES = {
    IDLE          = "IDLE",
    CASTING       = "CASTING",
    WAITING_BITE  = "WAITING_BITE",
    REELING       = "REELING",
    RESULT_PENDING= "RESULT_PENDING",
    STOPPING      = "STOPPING",
}

local fishState   = STATES.IDLE
local generation  = 0    -- incremented on every reset/cast
local _casting    = false
local _biteAt     = 0
local _mgAt       = 0
local _mgEverSeen = false
local _mgStarted  = false
local _mgLastSeen = 0
local _idleAt     = os.clock()
local _fatCount   = 0

-- Space key state (centralised)
local _spaceHeld = false
local _lastSpTgl = 0
local function setSpace(v, force)
    if _spaceHeld == v and not force then return end
    local now = os.clock()
    if not force and (now - _lastSpTgl) < 0.03 then return end
    if Capabilities.vim then
        pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
    end
    _spaceHeld = v; _lastSpTgl = now
end

local function releaseAllInput()
    if _spaceHeld then
        if Capabilities.vim then
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        end
        _spaceHeld = false
    end
end

-- ── Fishing result states ─────────────────────────────────────
-- UNKNOWN | ACTIVE | SUCCESS_CONFIRMED | TIMEOUT | RESET
local resultState = "UNKNOWN"

-- ── Character state management ────────────────────────────────
local _savedWalkSpeed = nil
local _savedJumpEnabled = true

local function saveCharState(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    _savedWalkSpeed  = hum.WalkSpeed
    _savedJumpEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    _S._origWalkSpeed = _savedWalkSpeed
end

local function setJumpEnabled(v)
    pcall(function()
        local ch  = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, v) end
    end)
end

local function restoreCharState()
    releaseAllInput()
    setJumpEnabled(_savedJumpEnabled ~= false)
    pcall(function()
        local ch  = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum and _savedWalkSpeed then hum.WalkSpeed = _savedWalkSpeed end
    end)
end

-- Save on init
local char0 = me.Character
if char0 then saveCharState(char0) end

-- ── Rod resolver ──────────────────────────────────────────────
local _currentRod = { name="—", lure=1.0, prog=1.0, source="NONE" }

local function normalizeToolName(s)
    return tostring(s or ""):lower():gsub("%s+", "")
end

local function isFishingCandidate(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local tn = normalizeToolName(tool.Name)
    -- Priority 1: Tool attributes for fishing semantics
    if tool:GetAttribute("IsFishingRod") == true
    or tool:GetAttribute("FishingRod") == true then return true end
    -- Priority 2: Generic name matching
    for _, n in ipairs(FISH_TOOL_NAMES) do
        local nn = normalizeToolName(n)
        if tn == nn or tn:find(nn, 1, true) then return true end
    end
    -- Priority 3: Known fallback rod names
    for _, r in ipairs(RODS_FALLBACK) do
        if tn == normalizeToolName(r.name) then return true end
    end
    return false
end

local function syncRodProfile(tool)
    if not tool then _currentRod = {name="—",lure=1.0,prog=1.0,source="NONE"}; return end
    -- Try live Tool attributes first
    local lure = tool:GetAttribute("LureSpeed") or tool:GetAttribute("lureSpeed")
    local prog = tool:GetAttribute("ProgressSpeed") or tool:GetAttribute("progressSpeed")
    if lure and prog then
        _currentRod = {name=tool.Name, lure=lure, prog=prog, source="LIVE"}
        return
    end
    -- Try fallback static profile
    local tn = normalizeToolName(tool.Name)
    for _, r in ipairs(RODS_FALLBACK) do
        if tn == normalizeToolName(r.name) then
            _currentRod = {name=r.name, lure=r.lure, prog=r.prog, source="FALLBACK"}
            return
        end
    end
    _currentRod = {name=tool.Name, lure=1.0, prog=1.0, source="UNKNOWN"}
    warn("[autofish] No rod profile for: " .. tool.Name .. " – using defaults")
end

local function equipBestRod()
    local ch  = me.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end

    -- Already equipped?
    for _, item in ipairs(ch:GetChildren()) do
        if isFishingCandidate(item) then
            syncRodProfile(item)
            return item
        end
    end

    -- Equip from Backpack
    local bp = me:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if isFishingCandidate(item) then
                local ok = pcall(function() hum:EquipTool(item) end)
                if ok then
                    task.wait(0.35)
                    for _, it in ipairs(ch:GetChildren()) do
                        if isFishingCandidate(it) then
                            syncRodProfile(it); return it
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- ── Fishing GUI resolver / UI adapter ─────────────────────────
local _wBar = nil
local _rBar = nil
local _pBar = nil
local _lastScan = 0

local function trulyVis(obj)
    if not obj or typeof(obj) ~= "Instance" then return false end
    if not obj:IsA("GuiObject") or not obj.Visible then return false end
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

local function cacheValid()
    return _wBar and _rBar and _wBar.Parent and _rBar.Parent
        and trulyVis(_wBar) and trulyVis(_rBar)
end

local function resolveBars()
    if cacheValid() then return true end
    local now = os.clock()
    local cooldown = frameSlow and 0.12 or CFG.fishing.scanCooldown
    if now - _lastScan < cooldown then return false end
    _lastScan = now; _wBar = nil; _rBar = nil; _pBar = nil

    local pg = me:FindFirstChild("PlayerGui")
    if not pg then return false end

    -- Priority A: named Reeling path
    local reel = pg:FindFirstChild("Reeling")
    if reel then
        local mf = reel:FindFirstChild("MainFrame")
        if mf then
            local fr = mf:FindFirstChild("Frame")
            if fr then
                local wb = fr:FindFirstChild("WhiteBar")
                local rb = fr:FindFirstChild("RedBar")
                local pbBg = mf:FindFirstChild("ProgressBg")
                local pb = pbBg and pbBg:FindFirstChild("ProgressBar")
                if wb and rb then _wBar=wb; _rBar=rb; _pBar=pb; return true end
            end
        end
    end

    -- Priority B: structural ScreenGui search
    for _, sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") then
            local wb2, rb2, pb2 = nil, nil, nil
            for _, desc in ipairs(sg:GetDescendants()) do
                if desc:IsA("GuiObject") and trulyVis(desc) then
                    local ln = desc.Name:lower()
                    if ln == "whitebar" or ln == "playerbar" or (ln:find("white") and ln:find("bar")) then
                        wb2 = desc
                    elseif ln:find("red") and ln:find("bar") then rb2 = desc
                    elseif ln:find("progress") and ln:find("bar") then pb2 = desc
                    end
                end
            end
            if wb2 and rb2 then _wBar=wb2; _rBar=rb2; _pBar=pb2; return true end
        end
    end

    -- Priority C: color fallback
    for _, v in ipairs(pg:GetDescendants()) do
        if v:IsA("GuiObject") and trulyVis(v) and v.AbsoluteSize.X > 12 and v.AbsoluteSize.Y > 5 then
            local c = v.BackgroundColor3; local par = v.Parent
            if c.R > 0.78 and c.G > 0.78 and c.B > 0.78 and par and par:IsA("GuiObject") then
                for _, sib in ipairs(par:GetChildren()) do
                    if sib ~= v and sib:IsA("GuiObject") and trulyVis(sib) and sib.AbsoluteSize.X > 12 then
                        local sc = sib.BackgroundColor3
                        if sc.R > 0.46 and sc.G < 0.22 and sc.B < 0.22 then
                            _wBar = v; _rBar = sib; return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- ── Spots file ────────────────────────────────────────────────
local SPOTS_FILE = "nzh_spots.json"
local spots = {}
local MAX_SPOTS = 10

local function validateSpot(sp)
    if type(sp) ~= "table" then return false end
    if type(sp.name) ~= "string" or sp.name == "" then return false end
    if not (type(sp.x) == "number" and math.abs(sp.x) < 1e9 and sp.x == sp.x) then return false end
    if not (type(sp.y) == "number" and math.abs(sp.y) < 1e9 and sp.y == sp.y) then return false end
    if not (type(sp.z) == "number" and math.abs(sp.z) < 1e9 and sp.z == sp.z) then return false end
    return true
end

local function saveSpots()
    if not Capabilities.fileIO then return end
    pcall(function() writefile(SPOTS_FILE, HTTP:JSONEncode(spots)) end)
end

local function loadSpots()
    if not Capabilities.fileIO then return end
    pcall(function()
        if isfile(SPOTS_FILE) then
            local ok, data = pcall(HTTP.JSONDecode, HTTP, readfile(SPOTS_FILE))
            if ok and type(data) == "table" then
                local clean = {}
                for _, sp in ipairs(data) do
                    if validateSpot(sp) then
                        clean[#clean+1] = sp
                        if #clean >= MAX_SPOTS then break end
                    end
                end
                spots = clean
            end
        end
    end)
end
loadSpots()

-- ── Webhook (off by default, never logs URL) ──────────────────
local webhookURL = ""
local webhookOn  = false
local function sendWebhook(title, body, colorInt)
    if not webhookOn or webhookURL == "" then return end
    if not webhookURL:find("discord%.com/api/webhooks") then return end
    task.spawn(function()
        local el = os.clock() - sessStart
        local h, m, s = math.floor(el/3600), math.floor(el%3600/60), math.floor(el%60)
        local rod = _currentRod
        local ok, payload = pcall(HTTP.JSONEncode, HTTP, {
            embeds = {{
                title       = title,
                description = body,
                color       = colorInt or 0xb49352,
                fields = {
                    { name="Confirmed", value=tostring(fishConfirmed), inline=true },
                    { name="Duration",  value=string.format("%02d:%02d:%02d",h,m,s), inline=true },
                    { name="Rod",       value=rod.name.." ("..rod.source..")", inline=true },
                },
                footer = { text = "NasiHub v3.0" },
            }},
        })
        if not ok then return end
        local req = (type(request)=="function" and request)
                 or (type(syn)=="table" and type((syn or {}).request)=="function" and syn.request)
                 or (type(http_request)=="function" and http_request)
        if req then
            pcall(req, {
                Url = webhookURL, Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = payload,
            })
        end
    end)
end

-- ── GUI CLEANUP ───────────────────────────────────────────────
pcall(function()
    local cg = game:GetService("CoreGui")
    for _, n in ipairs({"_NZH2","_NZH_UI","NH_v9_GUI","IH_v5","NH_v6_GUI","_nzh_fish3"}) do
        local a = cg:FindFirstChild(n); if a then a:Destroy() end
        if me.PlayerGui then
            local b = me.PlayerGui:FindFirstChild(n); if b then b:Destroy() end
        end
    end
end)

task.wait(0.05)

-- ── PALETTE ───────────────────────────────────────────────────
local C = {
    bg     = Color3.fromRGB(13,13,16),
    card   = Color3.fromRGB(20,20,25),
    border = Color3.fromRGB(36,36,44),
    accent = Color3.fromRGB(220,45,45),
    txt    = Color3.fromRGB(238,238,245),
    subtxt = Color3.fromRGB(168,168,183),
    dim    = Color3.fromRGB(112,112,128),
    muted  = Color3.fromRGB(62,62,75),
    swOn   = Color3.fromRGB(220,45,45),
    swOff  = Color3.fromRGB(38,38,46),
}

local function rnd(obj, r)
    Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r or 6)
end
local function mkStroke(obj, col, thick)
    local s = Instance.new("UIStroke", obj)
    s.Color = col or C.border; s.Thickness = thick or 1
    return s
end
local function mkLbl(parent, text, size, font, color)
    local l = Instance.new("TextLabel", parent)
    l.BackgroundTransparency = 1; l.Text = text or ""; l.TextSize = size or 10
    l.Font = font or Enum.Font.GothamMedium; l.TextColor3 = color or C.txt
    l.TextXAlignment = Enum.TextXAlignment.Left; l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Size = UDim2.new(1,0,0,(size or 10)+4)
    return l
end
local function mkBtn(parent, text, bg, tc, tsz)
    local b = Instance.new("TextButton", parent)
    b.BackgroundColor3 = bg or C.card; b.Text = text or ""; b.TextColor3 = tc or C.txt
    b.Font = Enum.Font.GothamBold; b.TextSize = tsz or 9.5; b.BorderSizePixel = 0
    b.AutoButtonColor = false; rnd(b,6); mkStroke(b,C.border,1)
    local orig = b.BackgroundColor3; local hi = orig:Lerp(C.accent, 0.18)
    b.MouseEnter:Connect(function() TS:Create(b,TweenInfo.new(0.12),{BackgroundColor3=hi}):Play() end)
    b.MouseLeave:Connect(function() TS:Create(b,TweenInfo.new(0.12),{BackgroundColor3=orig}):Play() end)
    return b
end

-- ── GUI ───────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "_nzh_fish3"; gui.ResetOnSpawn = false; gui.DisplayOrder = 25
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
    gui.Parent = me:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0,350,0,260); main.Position = UDim2.new(1,-365,0.5,-130)
main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0; main.Active = true; main.Draggable = true
rnd(main,12); mkStroke(main,C.border,1)

local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size = UDim2.new(0,36,0,36); floatBtn.Position = UDim2.new(1,-44,0.5,-18)
floatBtn.BackgroundColor3 = C.card; floatBtn.Text = "NF"; floatBtn.TextColor3 = C.accent
floatBtn.Font = Enum.Font.GothamBold; floatBtn.TextSize = 11; floatBtn.BorderSizePixel = 0
floatBtn.Visible = false; floatBtn.Active = true; floatBtn.Draggable = true
rnd(floatBtn,18); mkStroke(floatBtn,C.border,1)

-- Top bar
local topBar = Instance.new("Frame", main)
topBar.Size = UDim2.new(1,0,0,36); topBar.BackgroundColor3 = C.bg; topBar.BorderSizePixel = 0
do
    local div = Instance.new("Frame",topBar)
    div.Size=UDim2.new(1,0,0,1); div.Position=UDim2.new(0,0,1,-1)
    div.BackgroundColor3=C.border; div.BorderSizePixel=0
end
local function mkDot(x,col)
    local d=Instance.new("Frame",topBar)
    d.Size=UDim2.new(0,8,0,8); d.Position=UDim2.new(0,x,0.5,-4)
    d.BackgroundColor3=col; d.BorderSizePixel=0; rnd(d,4)
end
mkDot(12, Color3.fromRGB(255,95,87)); mkDot(24, Color3.fromRGB(254,188,47)); mkDot(36, Color3.fromRGB(40,200,64))
local titleL = mkLbl(topBar,"Nazhan Fish",11,Enum.Font.GothamBold,C.txt)
titleL.Size=UDim2.new(0,90,0,14); titleL.Position=UDim2.new(0,52,0,3)
local verL = mkLbl(topBar,"v3.0",7.5,Enum.Font.Gotham,C.dim)
verL.Size=UDim2.new(0,30,0,11); verL.Position=UDim2.new(0,52,0,19)
local hideBtn = mkBtn(topBar,"×",C.bg,C.dim,16)
hideBtn.Size=UDim2.new(0,20,0,20); hideBtn.Position=UDim2.new(1,-28,0.5,-10)

-- Content frame
local cont = Instance.new("Frame", main)
cont.Size = UDim2.new(1,-16,1,-46); cont.Position = UDim2.new(0,8,0,38)
cont.BackgroundTransparency = 1; cont.BorderSizePixel = 0

-- Status hero card
local stCard = Instance.new("Frame", cont)
stCard.Size = UDim2.new(1,0,0,62); stCard.Position = UDim2.new(0,0,0,0)
stCard.BackgroundColor3 = C.card; stCard.BorderSizePixel = 0
rnd(stCard,8); mkStroke(stCard,C.border)

local stDot = Instance.new("Frame", stCard)
stDot.Size=UDim2.new(0,7,0,7); stDot.Position=UDim2.new(0,10,0,12)
stDot.BackgroundColor3=C.muted; stDot.BorderSizePixel=0; rnd(stDot,4)

local stateL = mkLbl(stCard,"Idle",10,Enum.Font.GothamBold,C.txt)
stateL.Size=UDim2.new(1,-30,0,14); stateL.Position=UDim2.new(0,22,0,8)

local cntL = mkLbl(stCard,"Confirmed: 0 | Attempts: 0 | Unknown: 0",8,Enum.Font.Gotham,C.subtxt)
cntL.Size=UDim2.new(1,-16,0,12); cntL.Position=UDim2.new(0,10,0,27)

local rodL = mkLbl(stCard,"Rod: — (NONE)",7.5,Enum.Font.Gotham,C.dim)
rodL.Size=UDim2.new(1,-16,0,12); rodL.Position=UDim2.new(0,10,0,42)

local dotPulse
local function setDot(col)
    if dotPulse then dotPulse:Cancel() end
    stDot.BackgroundColor3 = col
    dotPulse = TS:Create(stDot,
        TweenInfo.new(0.65,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),
        {BackgroundColor3=col:Lerp(C.txt,0.42)})
    dotPulse:Play()
end
setDot(C.muted)

-- Phase bar
local phaseCont = Instance.new("Frame",cont)
phaseCont.Size=UDim2.new(1,0,0,20); phaseCont.Position=UDim2.new(0,0,0,68)
phaseCont.BackgroundTransparency=1
local barBg = Instance.new("Frame",phaseCont)
barBg.Size=UDim2.new(1,0,0,3); barBg.Position=UDim2.new(0,0,1,-3)
barBg.BackgroundColor3=C.border; barBg.BorderSizePixel=0; rnd(barBg,2)
local barFill = Instance.new("Frame",barBg)
barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=C.accent
barFill.BorderSizePixel=0; rnd(barFill,2)

local function setPhaseBar(pct)
    TS:Create(barFill,TweenInfo.new(0.15,Enum.EasingStyle.Quart),
        {Size=UDim2.new(math.clamp(pct,0,1),0,1,0)}):Play()
end

-- Toggle ON/OFF row
local fishRow = Instance.new("Frame",cont)
fishRow.Size=UDim2.new(1,0,0,36); fishRow.Position=UDim2.new(0,0,0,94)
fishRow.BackgroundColor3=C.bg; fishRow.BorderSizePixel=0
rnd(fishRow,8); mkStroke(fishRow,C.border)

local fLbl = mkLbl(fishRow,"Auto Fishing Engine",9.5,Enum.Font.GothamBold,C.txt)
fLbl.Size=UDim2.new(1,-54,0,14); fLbl.Position=UDim2.new(0,10,0,5)
local fSub = mkLbl(fishRow,"SUCCESS_CONFIRMED only (bar-gone = UNKNOWN)",7.5,Enum.Font.Gotham,C.dim)
fSub.Size=UDim2.new(1,-54,0,12); fSub.Position=UDim2.new(0,10,0,20)

local fishSw = Instance.new("TextButton",fishRow)
fishSw.Size=UDim2.new(0,36,0,20); fishSw.Position=UDim2.new(1,-46,0.5,-10)
fishSw.BackgroundColor3=C.swOff; fishSw.Text=""; fishSw.BorderSizePixel=0
fishSw.AutoButtonColor=false; rnd(fishSw,10)
local fishKnob=Instance.new("Frame",fishSw)
fishKnob.Size=UDim2.new(0,16,0,16); fishKnob.Position=UDim2.new(0,2,0.5,-8)
fishKnob.BackgroundColor3=C.txt; fishKnob.BorderSizePixel=0; rnd(fishKnob,8)

-- Reset / Diagnostics row
local actRow = Instance.new("Frame",cont)
actRow.Size=UDim2.new(1,0,0,28); actRow.Position=UDim2.new(0,0,0,136)
actRow.BackgroundTransparency=1
local rstBtn = mkBtn(actRow,"Reset",C.bg,C.dim,8.5)
rstBtn.Size=UDim2.new(0.48,0,1,0)

-- Confidence note
local confL = mkLbl(cont,"Fishing result: NOT RUNTIME VERIFIED",7.5,Enum.Font.Gotham,C.dim)
confL.Size=UDim2.new(1,0,0,13); confL.Position=UDim2.new(0,0,0,170)
confL.TextColor3 = C.dim

-- Hide/show
local savedPos = main.Position; local isHid = false
local function doHide(h)
    isHid = h
    if h then
        savedPos = main.Position
        TS:Create(main,TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.In),
            {Position=UDim2.new(1,10,0.5,-130)}):Play()
        task.delay(0.19,function()
            if isHid then main.Visible=false; floatBtn.Visible=true end
        end)
    else
        main.Visible=true; floatBtn.Visible=false
        main.Position=UDim2.new(1,10,0.5,-130)
        TS:Create(main,TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
            {Position=savedPos}):Play()
    end
end
hideBtn.MouseButton1Click:Connect(function() doHide(true) end)
floatBtn.MouseButton1Click:Connect(function() doHide(false) end)

-- ── FISHING RESET ─────────────────────────────────────────────
local function doReset(reason)
    generation = generation + 1
    fishState   = STATES.IDLE
    _casting    = false
    _mgEverSeen = false
    _mgStarted  = false
    _mgLastSeen = 0
    _idleAt     = os.clock()
    resultState = "UNKNOWN"
    _wBar = nil; _rBar = nil; _pBar = nil; _lastScan = 0
    releaseAllInput()
    setPhaseBar(0)
    if _S.active then
        stateL.Text = "Idle"; setDot(C.accent)
    end
    if reason then print("[NF] Reset: " .. tostring(reason)) end
end

rstBtn.MouseButton1Click:Connect(function()
    if _S.active then doReset("manual") end
end)

-- ── MINIGAME TICKER (called from Heartbeat) ───────────────────
local function tickMinigame(now)
    if not _S.active or fishState ~= STATES.REELING then return end
    local gen  = generation
    local rod  = _currentRod
    local slow = frameSlow
    local el   = now - _mgAt
    local timeout = (11 + rod.prog * 3.2) * (slow and 1.4 or 1.0)

    setPhaseBar(0.5 + math.clamp(el/timeout,0,1)*0.5)

    if el >= timeout then
        releaseAllInput()
        resultState = "TIMEOUT"
        fishFailed  = fishFailed + 1
        fishAttempts = fishAttempts + 1
        doReset("minigame-timeout")
        return
    end

    -- Try to resolve bars
    local hasBars = resolveBars()
    if hasBars and _wBar and _rBar and trulyVis(_wBar) and trulyVis(_rBar) then
        resultState = "ACTIVE"
        _mgEverSeen = true; _mgLastSeen = now

        if not _mgStarted then
            _mgStarted = true; setSpace(false, true)
        end

        local wC = _wBar.AbsolutePosition.X + _wBar.AbsoluteSize.X * 0.5
        local rL = _rBar.AbsolutePosition.X
        local rR = rL + _rBar.AbsoluteSize.X
        local rC = (rL + rR) * 0.5
        local rw = math.max(_rBar.AbsoluteSize.X, 1)
        local tol = math.clamp(rw * (0.18 + rod.lure * 0.025), 4, 28)
        local inside = wC >= (rL - tol) and wC <= (rR + tol)

        if inside then
            if     wC < rL then setSpace(true)
            elseif wC > rR then setSpace(false)
            else
                local e = wC - rC
                if math.abs(e) > tol * 0.4 then setSpace(e < 0) end
            end
        else
            local e = rC - wC
            if     e >  tol then setSpace(true)
            elseif e < -tol then setSpace(false)
            end
        end

        stateL.Text = string.format("Reeling... %.0fs", el)

    else
        -- Bars not visible
        if _mgStarted and _mgEverSeen and _mgLastSeen > 0 then
            local gone = now - _mgLastSeen
            if gone >= CFG.fishing.minigameGuard then
                releaseAllInput()
                -- bar-gone → UNKNOWN (NOT counted as success)
                resultState  = "UNKNOWN"
                fishUnknown  = fishUnknown + 1
                fishAttempts = fishAttempts + 1

                local gen2 = generation
                task.delay(CFG.fishing.recastDelay, function()
                    if gen2 ~= generation then return end
                    doReset(nil)
                    task.wait(0.06)
                    if _S.active and gen2 == generation then
                        fishState = STATES.IDLE; _idleAt = os.clock()
                    end
                end)

                cntL.Text = string.format("Confirmed: %d | Attempts: %d | Unknown: %d",
                    fishConfirmed, fishAttempts, fishUnknown)
                stateL.Text = "RESULT_UNCONFIRMED"
                fishState = STATES.RESULT_PENDING
            end
        elseif not _mgEverSeen then
            local beat = math.floor((now - _mgAt) * 3.0) % 2 == 0
            setSpace(beat)
            stateL.Text = string.format("Sync... %.0fs", el)
        end
    end
end

-- ── MAIN HEARTBEAT ────────────────────────────────────────────
local _hbLast = 0
local hbConn = RS.Heartbeat:Connect(function(dt)
    updateFrameTime(dt)
    if not _S.alive then return end

    if not _S.active then
        if _spaceHeld then releaseAllInput() end
        return
    end

    local now = os.clock()
    if now - _hbLast < 0.016 then return end
    _hbLast = now

    local ok, err = xpcall(function()
        if fishState == STATES.REELING then
            tickMinigame(now)
        elseif fishState == STATES.WAITING_BITE then
            local el = now - _biteAt
            setPhaseBar(0.25 + math.clamp(el / CFG.fishing.biteTimeout, 0, 1) * 0.25)
            stateL.Text = string.format("Waiting... %.0fs", math.max(0, CFG.fishing.biteTimeout - el))
            if el >= CFG.fishing.biteTimeout then
                fishState   = STATES.REELING
                _mgAt       = now
                _mgEverSeen = false
                _mgStarted  = false
                _mgLastSeen = 0
                resultState = "UNKNOWN"
                _wBar = nil; _rBar = nil; _lastScan = 0
                releaseAllInput()
                setPhaseBar(0.5)
                stateL.Text = "Reeling..."
                setDot(C.accent)
            end
        end
    end, function(e) return e end)

    if not ok then warn("[NF] hb error: " .. tostring(err)) end
end)
table.insert(_S.connections, hbConn)

-- ── CAST LOOP ────────────────────────────────────────────────
task.spawn(function()
    while _S.alive do
        task.wait(0.15)
        if not _S.alive then break end
        if _S.active then

        local ok2, err2 = xpcall(function()
            local ch  = me.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if not ch or not hum then return end

            local tool = equipBestRod()
            if not tool then
                stateL.Text = "No rod found"
                setDot(C.dim)
                return
            end

            rodL.Text = string.format("Rod: %s (src: %s)", _currentRod.name, _currentRod.source)
            setJumpEnabled(false)

            if fishState == STATES.IDLE and not _casting then
                _casting = true
                local gen = generation
                task.spawn(function()
                    if gen ~= generation or not _S.active or not _S.alive then
                        _casting = false; return
                    end

                    local cam = workspace.CurrentCamera
                    if not cam then _casting = false; return end

                    local rod  = _currentRod
                    local ctr  = cam.ViewportSize / 2
                    local slow = frameSlow
                    local lagM = slow and 1.2 or 1.0
                    local dur  = CFG.fishing.castHold / math.max(1, math.sqrt(rod.lure)*0.85) * lagM

                    fishState = STATES.CASTING
                    stateL.Text = "Casting..."
                    setDot(C.accent)
                    setPhaseBar(0.05)

                    pcall(function() tool:Activate() end)
                    if Capabilities.vu then
                        pcall(function() VU:Button1Down(ctr, cam.CFrame) end)
                    end

                    local t0 = os.clock()
                    while os.clock()-t0 < dur do
                        task.wait(0.04)
                        if gen ~= generation or not _S.active or not _S.alive then
                            if Capabilities.vu then pcall(function() VU:Button1Up(ctr,cam.CFrame) end) end
                            _casting = false; return
                        end
                        setPhaseBar(math.clamp((os.clock()-t0)/dur*0.25, 0, 0.25))
                    end

                    if Capabilities.vu then
                        pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
                    end
                    task.wait(0.12)

                    if gen ~= generation or not _S.active or not _S.alive then _casting=false; return end

                    fishState = STATES.WAITING_BITE
                    _biteAt   = os.clock()
                    setPhaseBar(0.25)
                    stateL.Text = "Waiting bite..."
                    _casting = false
                end)
            end
        end, function(e) return e end)

        if not ok2 then warn("[NF] cast error: " .. tostring(err2)) end
        end  -- if _S.active
    end
end)

-- ── WATCHDOG ─────────────────────────────────────────────────
task.spawn(function()
    while _S.alive do
        task.wait(5)
        if not _S.alive then break end
        if not _S.active then _idleAt = os.clock() end
        if _S.active then
            local now  = os.clock()
            local slow = frameSlow
            if fishState == STATES.IDLE and not _casting and (now-_idleAt) > (slow and 22 or CFG.fishing.watchdogIdle) then
                warn("[NF] watchdog: idle-lock"); doReset("watchdog-idle")
            elseif fishState == STATES.WAITING_BITE and (now-_biteAt) > (CFG.fishing.biteTimeout + CFG.fishing.watchdogWait) then
                warn("[NF] watchdog: bite-timeout"); doReset("watchdog-bite")
            elseif fishState == STATES.CASTING and not _casting and (now-_idleAt) > CFG.fishing.watchdogCast then
                warn("[NF] watchdog: cast-stuck"); doReset("watchdog-cast")
            end
        end
    end
end)

-- ── SESSION STAT UPDATER ──────────────────────────────────────
task.spawn(function()
    while _S.alive do
        task.wait(1)
        if _S.active then
            cntL.Text = string.format("Confirmed: %d | Attempts: %d | Unknown: %d",
                fishConfirmed, fishAttempts, fishUnknown)
        end
    end
end)

-- ── FISHING ON/OFF TOGGLE ─────────────────────────────────────
fishSw.MouseButton1Click:Connect(function()
    if not _S.alive then return end
    _S.active = not _S.active
    TS:Create(fishSw,TweenInfo.new(0.12),{BackgroundColor3=_S.active and C.swOn or C.swOff}):Play()
    TS:Create(fishKnob,TweenInfo.new(0.12),{
        Position=_S.active and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
    }):Play()

    if _S.active then
        sessStart    = os.clock()
        fishAttempts = 0; fishConfirmed = 0; fishFailed = 0; fishUnknown = 0
        doReset("start")
        setDot(C.accent)
        stateL.Text = "Starting..."
        sendWebhook("Auto Fishing ON", "NasiHub Nazhan Fish v3.0 started.", 0xb49352)
    else
        doReset("stopped")
        restoreCharState()
        setDot(C.muted)
        stateL.Text = "Idle"
        cntL.Text   = string.format("Confirmed: %d | Attempts: %d | Unknown: %d",
            fishConfirmed, fishAttempts, fishUnknown)
        sendWebhook("Auto Fishing OFF", "Fishing stopped.", 0x888888)
    end
end)

-- ── CHARACTER ADDED ───────────────────────────────────────────
local charConn = me.CharacterAdded:Connect(function(char)
    saveCharState(char)
    _wBar = nil; _rBar = nil; _pBar = nil; _lastScan = 0
    releaseAllInput()
    setJumpEnabled(true)
    if _S.active then
        doReset("respawn")
    end
end)
table.insert(_S.connections, charConn)

print("[NF] Nazhan Fish v3.0 loaded.")
print("[NF] bar-gone alone = RESULT_UNCONFIRMED (not counted).")
print("[NF] Rod source shown in UI: LIVE / FALLBACK / UNKNOWN.")
