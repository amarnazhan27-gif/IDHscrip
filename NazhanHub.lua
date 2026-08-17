--[[
╔══════════════════════════════════════════════════════════════╗
║   NasiHub  v3.0  –  IDH/NasihHub Client System              ║
║   Auto Fishing | Auto Mining | Copy Avatar | Diagnostics     ║
║   PRIVATE/TEST EXPERIENCE ONLY                               ║
║   No anti-ban. No remote farming. No server-auth bypass.     ║
╚══════════════════════════════════════════════════════════════╝

Architecture: flat module-like sections with lifecycle controllers.
  RuntimeController        – singleton lifecycle, connection tracking
  CharacterState           – save/restore Humanoid state
  PerformanceMonitor       – frame-time stats (NOT network ping)
  Capabilities             – optional executor feature detection
  Logger                   – rolling 150-line central log
  CFG                      – single config table, no duplicated constants
  FishingUIAdapter         – GUI resolver for reeling UI
  FishingInputManager      – centralised Space key state
  FishingRodResolver       – tool detection with priority scoring
  FishingRodProfileProvider– live→config→fallback rod profiles
  FishingResultObserver    – UNKNOWN/ACTIVE/SUCCESS_CONFIRMED/etc
  FishingController        – explicit state machine + generation ID
  MiningTargetResolver     – CollectionService→Attribute→struct→name heuristic
  MiningTargetValidator    – instance validity checks
  MiningMovement           – PathfindingService + fallback MoveTo
  MiningActionAdapter      – Tool:Activate with MIN_HIT_INTERVAL guard
  MiningController         – state machine + generation ID
  AvatarController         – HumanoidDescription copy/restore
  PlayerController         – player list, spectate, utilities
  SpotManager              – spot file with schema validation
  UIController             – consolidated single hub window
  Diagnostics              – UI panel showing cached refs + state

SUCCESS COUNTER RULES:
  Fish counted ONLY on SUCCESS_CONFIRMED (never timeout/bar-gone alone)
  Mine counted ONLY when target instance legitimately disappears

MOVEMENT:
  WalkSpeed saved before modification, restored exact original after.
  No permanent WalkSpeed=N.
]]

---------------------------------------------------------------------------
-- 0. RUNTIME GUARD – destroy old instance cleanly
---------------------------------------------------------------------------
if shared.IDH_CLIENT_RUNTIME then
    pcall(function()
        shared.IDH_CLIENT_RUNTIME:destroy()
    end)
end
task.wait(0.05)

---------------------------------------------------------------------------
-- 1. SERVICES
---------------------------------------------------------------------------
local Players     = game:GetService("Players")
local RS          = game:GetService("RunService")
local VIM         = game:GetService("VirtualInputManager")
local VU          = game:GetService("VirtualUser")
local PFS         = game:GetService("PathfindingService")
local TS          = game:GetService("TweenService")
local HTTP        = game:GetService("HttpService")
local CS          = game:GetService("CollectionService")
local me          = Players.LocalPlayer
local PlayerController = nil

---------------------------------------------------------------------------
-- 2. CAPABILITIES – executor feature detection
---------------------------------------------------------------------------
local Capabilities = {
    fileIO    = (type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"),
    clipboard = (type(setclipboard) == "function"),
    httpReq   = (type(request) == "function" or type(syn) == "table" and type((syn or {}).request) == "function" or type(http_request) == "function"),
    vim       = pcall(function() return VIM.ClassName end),
    vu        = pcall(function() return VU.ClassName end),
}

local function execRequest(opts)
    local req = (type(request) == "function" and request)
             or (type(syn) == "table" and type((syn or {}).request) == "function" and syn.request)
             or (type(http_request) == "function" and http_request)
    if req then
        return pcall(req, opts)
    end
    return false, "no http executor"
end

---------------------------------------------------------------------------
-- 3. CFG – single source of truth, no duplicated timing constants
---------------------------------------------------------------------------
local CFG = {
    fishing = {
        castHold       = 1.8,
        biteTimeout    = 15.0,
        recastDelay    = 0.9,
        minigameGuard  = 0.20,   -- seconds without bar before UNKNOWN
        watchdogIdle   = 14,
        watchdogWait   = 23,
        watchdogCast   = 12,
        scanCooldown   = 0.05,   -- min seconds between GUI scans
        fatigueEvery   = 25,     -- attempts between fatigue breaks
        fatigueDur     = 8,
    },
    mining = {
        scanInterval      = 1.5,    -- seconds between full workspace scans
        stopDistance      = 2.5,
        moveTimeout       = 20,
        hitInterval       = 0.28,   -- MIN_HIT_INTERVAL between activations
        maxHitCycles      = 8,      -- swing cycles before giving up on target
        maxFailCount      = 4,
        maxPathRecomputes = 3,      -- max recomputes on Path.Blocked
        targetMaxDist     = 300,
        scoreThreshold    = 5,
    },
    performance = {
        smooth = 0.08,           -- EMA weight for frame-time rolling avg
        slowThreshold = 0.05,    -- >50ms dt = "slow"
    },
    ui = {
        maxLogLines    = 150,
    },
}

---------------------------------------------------------------------------
-- 4. LOGGER – rolling 150-line log, no memory growth
---------------------------------------------------------------------------
local Logger = {}
do
    local lines = {}
    local MAX   = CFG.ui.maxLogLines

    local function trim()
        while #lines > MAX do table.remove(lines, 1) end
    end

    function Logger.log(level, subsystem, msg)
        local entry = string.format("[%s][%s][%s] %s",
            os.date("%H:%M:%S"), level, subsystem, tostring(msg))
        table.insert(lines, entry)
        trim()
        -- always print for developer visibility
        local pr = (level == "WARN" or level == "ERROR") and warn or print
        pr(entry)
    end

    function Logger.info(sub, msg)  Logger.log("INFO",  sub, msg) end
    function Logger.warn(sub, msg)  Logger.log("WARN",  sub, msg) end
    function Logger.error(sub, msg) Logger.log("ERROR", sub, msg) end

    function Logger.getLines() return lines end
    function Logger.clear() table.clear(lines) end
end

local function LOG(sub, msg)  Logger.info(sub, msg) end
local function WARN(sub, msg) Logger.warn(sub, msg) end

---------------------------------------------------------------------------
-- 5. RUNTIME CONTROLLER – lifecycle, connection/task tracking
---------------------------------------------------------------------------
local RuntimeController = {}
do
    RuntimeController.alive = true
    RuntimeController.connections = {}
    RuntimeController.taskGroups  = {}   -- name -> generation
    RuntimeController.currentMode = "OFF"
    RuntimeController.sessionCounters = {
        fishAttempts  = 0,
        fishConfirmed = 0,
        fishFailed    = 0,
        fishUnknown   = 0,
        mineAttempts  = 0,
        mineConfirmed = 0,
        mineFailed    = 0,
    }

    function RuntimeController.trackConnection(conn)
        table.insert(RuntimeController.connections, conn)
        return conn
    end

    -- Bump generation for a named task group; stale tasks see mismatch
    function RuntimeController.invalidateTaskGroup(name)
        RuntimeController.taskGroups[name] = (RuntimeController.taskGroups[name] or 0) + 1
        return RuntimeController.taskGroups[name]
    end

    function RuntimeController.isTaskValid(name, generation)
        return RuntimeController.alive and RuntimeController.taskGroups[name] == generation
    end

    function RuntimeController.getGeneration(name)
        return RuntimeController.taskGroups[name] or 0
    end

    function RuntimeController.cleanup()
        RuntimeController.alive       = false
        RuntimeController.currentMode = "OFF"

        -- Stop spectating and restore camera subject if active
        if PlayerController and type(PlayerController.stopSpectate) == "function" then
            pcall(function() PlayerController.stopSpectate() end)
        end

        -- Disconnect all tracked connections
        for _, conn in ipairs(RuntimeController.connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(RuntimeController.connections)

        -- Destroy temp workspace objects
        pcall(function()
            local pt = workspace:FindFirstChild("_idh_plat")
            if pt then pt:Destroy() end
        end)

        LOG("RUNTIME", "Cleanup complete")
    end

    RuntimeController.destroy = RuntimeController.cleanup
end

-- Register as global so next execution can kill this one
shared.IDH_CLIENT_RUNTIME = RuntimeController

---------------------------------------------------------------------------
-- 6. CHARACTER STATE MANAGER – save and restore exact Humanoid values
---------------------------------------------------------------------------
local CharacterState = {}
do
    local _saved = {}

    function CharacterState.save(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        _saved.walkSpeed   = hum.WalkSpeed
        _saved.jumpPower   = hum.JumpPower
        _saved.jumpHeight  = hum.JumpHeight
        _saved.autoRotate  = hum.AutoRotate
        _saved.jumpEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
        LOG("CHARSTATE", string.format("Saved: WalkSpeed=%.1f JumpEnabled=%s",
            _saved.walkSpeed, tostring(_saved.jumpEnabled)))
    end

    function CharacterState.restoreHumanoid(hum)
        if not hum or not _saved.walkSpeed then return end
        pcall(function()
            hum.WalkSpeed  = _saved.walkSpeed
            hum.JumpPower  = _saved.jumpPower
            hum.JumpHeight = _saved.jumpHeight
            hum.AutoRotate = _saved.autoRotate
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, _saved.jumpEnabled ~= false)
        end)
    end

    function CharacterState.setJumpEnabled(enabled)
        pcall(function()
            local ch  = me.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
            end
        end)
    end

    function CharacterState.restoreAll()
        local ch  = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        CharacterState.restoreHumanoid(hum)
    end

    -- Save initial state on first call
    local ch0 = me.Character
    if ch0 then
        CharacterState.save(ch0)
    end
end

---------------------------------------------------------------------------
-- 7. PERFORMANCE MONITOR – frame TIME, not network ping/lag
---------------------------------------------------------------------------
local PerformanceMonitor = {}
do
    PerformanceMonitor.frameTime    = 0.016
    PerformanceMonitor.frameFPS     = 60
    PerformanceMonitor.performanceSlow = false

    local smooth = CFG.performance.smooth
    local thresh = CFG.performance.slowThreshold

    function PerformanceMonitor.update(dt)
        local ft = PerformanceMonitor.frameTime
        ft = ft * (1 - smooth) + dt * smooth
        PerformanceMonitor.frameTime       = ft
        PerformanceMonitor.performanceSlow = ft > thresh
        local fps_denom = math.max(ft, 0.001)
        PerformanceMonitor.frameFPS        = math.floor(1 / fps_denom + 0.5)
    end

    -- Connect frame-time tracking (not named "network lag")
    RuntimeController.trackConnection(
        RS.Heartbeat:Connect(function(dt)
            PerformanceMonitor.update(dt)
        end)
    )
end

---------------------------------------------------------------------------
-- 8. SPOT MANAGER – validated JSON schema
---------------------------------------------------------------------------
local SpotManager = {}
do
    local SPOTS_FILE = "nzh_spots.json"
    local MAX_SPOTS  = 10
    local _spots     = {}

    local function validateSpot(sp)
        if type(sp) ~= "table" then return false end
        if type(sp.name) ~= "string" or sp.name == "" then return false end
        if not (type(sp.x) == "number" and math.abs(sp.x) < 1e9 and sp.x == sp.x) then return false end
        if not (type(sp.y) == "number" and math.abs(sp.y) < 1e9 and sp.y == sp.y) then return false end
        if not (type(sp.z) == "number" and math.abs(sp.z) < 1e9 and sp.z == sp.z) then return false end
        return true
    end

    function SpotManager.load()
        if not Capabilities.fileIO then return end
        pcall(function()
            if isfile(SPOTS_FILE) then
                local ok, data = pcall(HTTP.JSONDecode, HTTP, readfile(SPOTS_FILE))
                if ok and type(data) == "table" then
                    local clean = {}
                    for _, sp in ipairs(data) do
                        if validateSpot(sp) then
                            clean[#clean + 1] = {
                                name = tostring(sp.name):sub(1, 64),
                                x = sp.x, y = sp.y, z = sp.z
                            }
                            if #clean >= MAX_SPOTS then break end
                        else
                            WARN("SPOTS", "Ignoring malformed entry: " .. tostring(sp))
                        end
                    end
                    _spots = clean
                    LOG("SPOTS", "Loaded " .. #_spots .. " valid spots")
                end
            end
        end)
    end

    function SpotManager.save()
        if not Capabilities.fileIO then return end
        pcall(function()
            writefile(SPOTS_FILE, HTTP:JSONEncode(_spots))
        end)
    end

    function SpotManager.getAll() return _spots end

    function SpotManager.add(name, pos)
        if #_spots >= MAX_SPOTS then return false, "max spots reached" end
        local nm = tostring(name or ""):match("^%s*(.-)%s*$")
        if nm == "" then nm = "Spot " .. (#_spots + 1) end
        local sp = { name = nm, x = pos.X, y = pos.Y, z = pos.Z }
        if not validateSpot(sp) then return false, "invalid position" end
        table.insert(_spots, sp)
        SpotManager.save()
        return true
    end

    function SpotManager.remove(idx)
        table.remove(_spots, idx)
        SpotManager.save()
    end

    function SpotManager.getPosition(sp)
        -- Always validate before constructing Vector3
        if not validateSpot(sp) then return nil end
        return Vector3.new(sp.x, sp.y, sp.z)
    end

    SpotManager.load()
end

---------------------------------------------------------------------------
-- 9. FISHING – Rod Profile Provider
--    Priority: live Tool attributes → known profile fallback
---------------------------------------------------------------------------
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

local FishingRodProfileProvider = {}
do
    local _current = { name="—", lure=1.0, prog=1.0, source="NONE" }

    local function tryReadAttributes(tool)
        if not tool then return nil end
        local lure = tool:GetAttribute("LureSpeed") or tool:GetAttribute("lureSpeed")
        local prog = tool:GetAttribute("ProgressSpeed") or tool:GetAttribute("progressSpeed")
        if lure and prog then
            return { name = tool.Name, lure = lure, prog = prog, source = "LIVE" }
        end
        return nil
    end

    local function tryFallback(tool)
        if not tool then return nil end
        local tn = tool.Name:lower():gsub("%s+", "")
        for _, r in ipairs(RODS_FALLBACK) do
            if tn == r.name:lower():gsub("%s+", "") then
                return { name = r.name, lure = r.lure, prog = r.prog, source = "FALLBACK" }
            end
        end
        return nil
    end

    function FishingRodProfileProvider.sync(tool)
        if not tool then _current = { name="—", lure=1.0, prog=1.0, source="NONE" }; return end
        local prof = tryReadAttributes(tool) or tryFallback(tool)
        if prof then
            _current = prof
            LOG("ROD", string.format("Profile: %s (source=%s lure=%.2f prog=%.2f)",
                prof.name, prof.source, prof.lure, prof.prog))
        else
            _current = { name = tool.Name, lure = 1.0, prog = 1.0, source = "UNKNOWN" }
            WARN("ROD", "No profile found for: " .. tool.Name .. " – using defaults")
        end
    end

    function FishingRodProfileProvider.get() return _current end
end

---------------------------------------------------------------------------
-- 10. FISHING – Tool Resolver
--     Priority: 1) equipped fishing Tool  2) Backpack  3) exact names
--     No random first Tool selection.
---------------------------------------------------------------------------
local FISH_TOOL_NAMES = { "fishing rod", "rod", "pancing", "fishingrod" }

local FishingToolResolver = {}
do
    local function normalize(s)
        return tostring(s or ""):lower():gsub("%s+", "")
    end

    local function isFishingCandidate(tool)
        if not tool or not tool:IsA("Tool") then return false, 0 end
        local tn = normalize(tool.Name)

        -- Check FISH_TOOL_NAMES generic matches
        for _, n in ipairs(FISH_TOOL_NAMES) do
            local nn = normalize(n)
            if tn == nn or tn:find(nn, 1, true) then return true, 4 end
        end

        -- Check known rod profiles (fallback names)
        for _, r in ipairs(RODS_FALLBACK) do
            if tn == normalize(r.name) then return true, 3 end
        end

        -- Check Tool attributes for fishing semantics
        if tool:GetAttribute("IsFishingRod") == true
        or tool:GetAttribute("FishingRod") == true then
            return true, 5
        end

        return false, 0
    end

    function FishingToolResolver.resolve()
        local ch = me.Character
        if not ch then return nil end

        -- 1) Currently equipped tool in character
        for _, item in ipairs(ch:GetChildren()) do
            local ok, _ = isFishingCandidate(item)
            if ok then
                FishingRodProfileProvider.sync(item)
                return item
            end
        end

        -- 2) Backpack
        local bp = me:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                local ok, _ = isFishingCandidate(item)
                if ok then
                    return item   -- caller must equip
                end
            end
        end

        return nil
    end

    function FishingToolResolver.equipBest()
        local ch = me.Character
        if not ch then return nil end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum then return nil end

        -- Already equipped?
        for _, item in ipairs(ch:GetChildren()) do
            local ok, _ = isFishingCandidate(item)
            if ok then
                FishingRodProfileProvider.sync(item)
                return item
            end
        end

        -- Equip from Backpack
        local bp = me:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                local ok2, _ = isFishingCandidate(item)
                if ok2 then
                    local eOk = pcall(function() hum:EquipTool(item) end)
                    if eOk then
                        task.wait(0.35)
                        for _, it in ipairs(ch:GetChildren()) do
                            local ok3, _ = isFishingCandidate(it)
                            if ok3 then
                                FishingRodProfileProvider.sync(it)
                                return it
                            end
                        end
                    end
                end
            end
        end

        return nil
    end

    function FishingToolResolver.isFishing(tool)
        local ok, _ = isFishingCandidate(tool)
        return ok
    end
end

---------------------------------------------------------------------------
-- 11. FISHING – UI Adapter (Resolver + Geometry helpers)
---------------------------------------------------------------------------
local FishingUIAdapter = {}
do
    local _reel  = nil   -- cached Reeling ScreenGui root
    local _wBar  = nil   -- WhiteBar
    local _rBar  = nil   -- RedBar
    local _pBar  = nil   -- ProgressBar
    local _lastScan = 0

    -- Geometry helpers
    local function getRect(obj)
        local p = obj.AbsolutePosition
        local s = obj.AbsoluteSize
        return p.X, p.X + s.X, p.Y, p.Y + s.Y
    end

    local function trulyVis(obj)
        if not obj or typeof(obj) ~= "Instance" then return false end
        if not obj:IsA("GuiObject") or not obj.Visible then return false end
        local ok, sz = pcall(function() return obj.AbsoluteSize end)
        if not ok or sz.X <= 0 or sz.Y <= 0 then return false end
        local cur = obj.Parent
        while cur and cur ~= game do
            if cur:IsA("ScreenGui") then
                if not cur.Enabled then return false end
                break
            elseif cur:IsA("GuiObject") then
                if not cur.Visible then return false end
            end
            cur = cur.Parent
        end
        return true
    end

    local function invalidateCache()
        _reel = nil; _wBar = nil; _rBar = nil; _pBar = nil
        _lastScan = 0
    end

    -- Validate cached references are still alive
    local function cacheValid()
        return _wBar and _rBar
            and _wBar.Parent and _rBar.Parent
            and trulyVis(_wBar) and trulyVis(_rBar)
    end

    -- Priority A: PlayerGui.Reeling structural path
    local function tryNamedPath(pg)
        local reel = pg:FindFirstChild("Reeling")
        if not reel then return false end
        local mf = reel:FindFirstChild("MainFrame")
        if not mf then return false end
        local frame = mf:FindFirstChild("Frame")
        if frame then
            local wb = frame:FindFirstChild("WhiteBar")
            local rb = frame:FindFirstChild("RedBar")
            local pbBg = mf:FindFirstChild("ProgressBg")
            local pb = pbBg and pbBg:FindFirstChild("ProgressBar")
            if wb and rb then
                _reel = reel; _wBar = wb; _rBar = rb; _pBar = pb
                return true
            end
        end
        return false
    end

    -- Priority B: Search for ScreenGui containing both RedBar and WhiteBar
    local function tryStructuralSearch(pg)
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") then
                local found_wb, found_rb, found_pb = nil, nil, nil
                for _, desc in ipairs(sg:GetDescendants()) do
                    if desc:IsA("GuiObject") and trulyVis(desc) then
                        local ln = desc.Name:lower()
                        if ln == "whitebar" or ln == "playerbar" or (ln:find("white") and ln:find("bar")) then
                            found_wb = desc
                        elseif ln == "redbar" or (ln:find("red") and ln:find("bar")) then
                            found_rb = desc
                        elseif ln == "progressbar" or (ln:find("progress") and ln:find("bar")) then
                            found_pb = desc
                        end
                    end
                end
                if found_wb and found_rb then
                    _reel = sg; _wBar = found_wb; _rBar = found_rb; _pBar = found_pb
                    return true
                end
            end
        end
        return false
    end

    -- Priority C: Color-based fallback (white bar + red sibling)
    local function tryColorFallback(pg)
        for _, v in ipairs(pg:GetDescendants()) do
            if v:IsA("GuiObject") and trulyVis(v)
                and v.AbsoluteSize.X > 12 and v.AbsoluteSize.Y > 5 then
                local c   = v.BackgroundColor3
                local par = v.Parent
                if c.R > 0.78 and c.G > 0.78 and c.B > 0.78
                    and par and par:IsA("GuiObject") then
                    for _, sib in ipairs(par:GetChildren()) do
                        if sib ~= v and sib:IsA("GuiObject") and trulyVis(sib)
                            and sib.AbsoluteSize.X > 12 then
                            local sc = sib.BackgroundColor3
                            if sc.R > 0.46 and sc.G < 0.22 and sc.B < 0.22 then
                                _wBar = v; _rBar = sib
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end

    function FishingUIAdapter.resolveFishingGui()
        local now = os.clock()
        local cooldown = PerformanceMonitor.performanceSlow and 0.12 or CFG.fishing.scanCooldown
        if cacheValid() then return true end
        if now - _lastScan < cooldown then return false end
        _lastScan = now
        _wBar = nil; _rBar = nil; _pBar = nil; _reel = nil

        local pg = me:FindFirstChild("PlayerGui")
        if not pg then return false end

        if tryNamedPath(pg) then
            LOG("FISH_UI", "Resolved via named path (Priority A)")
            return true
        end
        if tryStructuralSearch(pg) then
            LOG("FISH_UI", "Resolved via structural search (Priority B)")
            return true
        end
        if tryColorFallback(pg) then
            LOG("FISH_UI", "Resolved via color fallback (Priority C)")
            return true
        end
        return false
    end

    function FishingUIAdapter.invalidate() invalidateCache() end

    function FishingUIAdapter.getWhiteBar()    return _wBar end
    function FishingUIAdapter.getRedBar()      return _rBar end
    function FishingUIAdapter.getProgressBar() return _pBar end

    function FishingUIAdapter.isReelingVisible()
        if not _wBar or not _rBar then return false end
        return trulyVis(_wBar) and trulyVis(_rBar)
    end

    function FishingUIAdapter.getWhiteBarCenterX()
        if not _wBar then return nil end
        return _wBar.AbsolutePosition.X + _wBar.AbsoluteSize.X * 0.5
    end

    function FishingUIAdapter.getRedBarRect()
        if not _rBar then return nil, nil, nil, nil end
        local l, r, t, b = getRect(_rBar)
        return l, r, t, b
    end

    function FishingUIAdapter.getProgress()
        if not _pBar then return nil end
        -- Try Scale X first, then AbsoluteSize relative to parent
        local ok, sx = pcall(function() return _pBar.Size.X.Scale end)
        if ok and sx ~= nil then return math.clamp(sx, 0, 1) end
        local par = _pBar.Parent
        if par and par.AbsoluteSize.X > 0 then
            return math.clamp(_pBar.AbsoluteSize.X / par.AbsoluteSize.X, 0, 1)
        end
        return nil
    end

    -- Invalidate cache when PlayerGui changes
    RuntimeController.trackConnection(
        me.CharacterAdded:Connect(function() invalidateCache() end)
    )
end

---------------------------------------------------------------------------
-- 12. FISHING – Input Manager (centralised Space key)
---------------------------------------------------------------------------
local FishingInputManager = {}
do
    local _spaceHeld  = false
    local _lastToggle = 0

    function FishingInputManager.setSpaceHeld(v, force)
        if _spaceHeld == v and not force then return end
        local now = os.clock()
        if not force and (now - _lastToggle) < 0.03 then return end
        if Capabilities.vim then
            pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
        end
        _spaceHeld = v; _lastToggle = now
    end

    function FishingInputManager.releaseAll()
        if not _spaceHeld then return end
        if Capabilities.vim then
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        end
        _spaceHeld = false
    end

    function FishingInputManager.isHeld() return _spaceHeld end
end

---------------------------------------------------------------------------
-- 13. FISHING RESULT OBSERVER
--     Results: UNKNOWN | ACTIVE | SUCCESS_CONFIRMED | FAIL_CONFIRMED |
--              TIMEOUT | RESET
---------------------------------------------------------------------------
local FishingResultObserver = {}
do
    local state = "UNKNOWN"
    local lastReason = "none"
    local lastProgress = 0.0
    local lastGuiOpenedAt = 0
    local lastGuiClosedAt = 0
    local lastToolState = "None"

    function FishingResultObserver.setState(s)
        state = s
    end
    function FishingResultObserver.getState() return state end

    function FishingResultObserver.setToolState(ts)
        lastToolState = tostring(ts or "None")
    end

    function FishingResultObserver.getTrace()
        return {
            lastFishingResultReason = lastReason,
            lastFishingResultState  = state,
            lastFishingProgress     = lastProgress,
            lastFishingGuiOpenedAt  = lastGuiOpenedAt,
            lastFishingGuiClosedAt  = lastGuiClosedAt,
            lastFishingToolState    = lastToolState,
        }
    end

    function FishingResultObserver.observeStart()
        state = "ACTIVE"
        lastReason = "gui-opened"
        lastGuiOpenedAt = os.clock()
        LOG("FISH_OBS", "observeStart → ACTIVE")
    end

    function FishingResultObserver.observeActive()
        -- called each frame while reeling bars are visible
        state = "ACTIVE"
    end

    function FishingResultObserver.observeProgress(pct)
        if pct ~= nil then
            lastProgress = pct
            if pct >= 0.98 then
                LOG("FISH_OBS", string.format("High progress: %.2f – marking ACTIVE", pct))
            end
        end
    end

    function FishingResultObserver.observeEnd(reason)
        lastReason = tostring(reason or "unknown")
        -- "bar-gone" alone → UNKNOWN, not success
        if reason == "bar-gone" or reason == "gui-hidden" then
            lastGuiClosedAt = os.clock()
            if state == "ACTIVE" then
                state = "UNKNOWN"
                LOG("FISH_OBS", "observeEnd(bar-gone) → UNKNOWN (not counted)")
            end
        elseif reason == "timeout" or reason == "bite-timeout-no-gui" then
            state = "TIMEOUT"
            LOG("FISH_OBS", "observeEnd(" .. reason .. ") → TIMEOUT")
        elseif reason == "tool-deactivate" then
            state = "UNKNOWN"
            LOG("FISH_OBS", "observeEnd(tool-deactivate) → UNKNOWN (unconfirmed)")
        elseif reason == "explicit-catch" then
            -- ONLY if genuinely confirmed client evidence exists (currently unconfirmed)
            state = "SUCCESS_CONFIRMED"
            LOG("FISH_OBS", "observeEnd(explicit-catch) → SUCCESS_CONFIRMED")
        elseif reason == "reset" then
            state = "RESET"
        else
            state = "UNKNOWN"
            LOG("FISH_OBS", "observeEnd(" .. tostring(reason) .. ") → UNKNOWN")
        end
    end

    function FishingResultObserver.reset()
        state = "UNKNOWN"
        lastReason = "reset"
    end
end

---------------------------------------------------------------------------
-- 14. FISHING CONTROLLER – explicit state machine with generation IDs
---------------------------------------------------------------------------
local FishingController = {}
do
    local STATES = {
        IDLE           = "IDLE",
        PREPARING      = "PREPARING",
        EQUIP_ROD      = "EQUIP_ROD",
        CASTING        = "CASTING",
        WAITING_BITE   = "WAITING_BITE",
        REELING        = "REELING",
        RESULT_PENDING = "RESULT_PENDING",
        SUCCESS        = "SUCCESS",
        FAILED         = "FAILED",
        COOLDOWN       = "COOLDOWN",
        STOPPING       = "STOPPING",
    }

    local _state       = STATES.IDLE
    local _generation  = 0
    local _casting     = false
    local _biteAt      = 0
    local _mgAt        = 0
    local _mgEverSeen  = false
    local _mgStarted   = false
    local _mgLastSeen  = 0
    local _idleAt      = os.clock()
    local _fatCount    = 0

    -- UI callbacks (set by UIController)
    local _onStateChange  = nil
    local _onCountChange  = nil
    local _onRodChange    = nil

    function FishingController.onStateChange(fn)  _onStateChange  = fn end
    function FishingController.onCountChange(fn)  _onCountChange  = fn end
    function FishingController.onRodChange(fn)    _onRodChange    = fn end

    local function setState(s)
        _state = s
        if _onStateChange then pcall(_onStateChange, s) end
    end

    local function isRunning()
        return RuntimeController.alive and RuntimeController.currentMode == "FISH"
    end

    local function bumpGeneration()
        _generation = _generation + 1
        return _generation
    end

    function FishingController.getState()    return _state end
    function FishingController.getGeneration() return _generation end

    function FishingController.reset(reason)
        bumpGeneration()
        _casting    = false
        _mgEverSeen = false
        _mgStarted  = false
        _mgLastSeen = 0
        _idleAt     = os.clock()
        FishingInputManager.releaseAll()
        FishingResultObserver.reset()
        FishingUIAdapter.invalidate()
        setState(STATES.IDLE)
        if reason then LOG("FISH", "Reset: " .. tostring(reason)) end
    end

    function FishingController.stop()
        bumpGeneration()
        _casting = false
        FishingInputManager.releaseAll()
        CharacterState.setJumpEnabled(true)
        CharacterState.restoreAll()
        setState(STATES.STOPPING)
        LOG("FISH", "Stopped")
    end

    -- Called by minigame observer each Heartbeat tick
    function FishingController.tickMinigame(now)
        if not isRunning() then return end
        if _state ~= STATES.REELING then return end

        local gen = _generation
        local rod = FishingRodProfileProvider.get()
        local slow = PerformanceMonitor.performanceSlow
        local el   = now - _mgAt
        local timeout = (11 + rod.prog * 3.2) * (slow and 1.4 or 1.0)

        if el >= timeout then
            FishingInputManager.releaseAll()
            FishingResultObserver.observeEnd("timeout")
            setState(STATES.RESULT_PENDING)
            RuntimeController.sessionCounters.fishFailed = RuntimeController.sessionCounters.fishFailed + 1
            LOG("FISH", "Minigame timeout → RESULT_PENDING TIMEOUT")
            FishingController.reset("minigame-timeout")
            return
        end

        -- Try to resolve bars
        local hasBars = FishingUIAdapter.resolveFishingGui()
        local wb      = FishingUIAdapter.getWhiteBar()
        local rb      = FishingUIAdapter.getRedBar()
        local pBar    = FishingUIAdapter.getProgressBar()

        if hasBars and wb and rb and FishingUIAdapter.isReelingVisible() then
            FishingResultObserver.observeActive()
            _mgEverSeen = true
            _mgLastSeen = now

            if pBar then
                local pct = FishingUIAdapter.getProgress()
                if pct then FishingResultObserver.observeProgress(pct) end
            end

            if not _mgStarted then
                _mgStarted = true
                FishingInputManager.setSpaceHeld(false, true)
            end

            -- Velocity-predictive Space control
            local wC  = FishingUIAdapter.getWhiteBarCenterX()
            local rL, rR = FishingUIAdapter.getRedBarRect()
            if wC and rL and rR then
                local rC   = (rL + rR) * 0.5
                local rw   = math.max(rb.AbsoluteSize.X, 1)
                local lag  = 0   -- simplified; we don't track rawDt here
                local tol  = math.clamp(rw * (0.18 + rod.lure * 0.025), 4, 28)
                local inside = wC >= (rL - tol) and wC <= (rR + tol)
                if inside then
                    if     wC < rL then FishingInputManager.setSpaceHeld(true)
                    elseif wC > rR then FishingInputManager.setSpaceHeld(false)
                    else
                        local e = wC - rC
                        if math.abs(e) > tol * 0.4 then
                            FishingInputManager.setSpaceHeld(e < 0)
                        end
                    end
                else
                    local e = rC - wC
                    if     e >  tol then FishingInputManager.setSpaceHeld(true)
                    elseif e < -tol then FishingInputManager.setSpaceHeld(false)
                    end
                end
            end

        else
            -- Bars not visible
            if _mgStarted and _mgEverSeen and _mgLastSeen > 0 then
                local gone = now - _mgLastSeen
                if gone >= CFG.fishing.minigameGuard then
                    -- GUI disappeared – observe as "bar-gone" which yields UNKNOWN
                    FishingInputManager.setSpaceHeld(false, true)
                    FishingResultObserver.observeEnd("bar-gone")
                    local result = FishingResultObserver.getState()
                    setState(STATES.RESULT_PENDING)

                    -- Only count SUCCESS_CONFIRMED
                    if result == "SUCCESS_CONFIRMED" then
                        RuntimeController.sessionCounters.fishConfirmed = RuntimeController.sessionCounters.fishConfirmed + 1
                        if _onCountChange then pcall(_onCountChange, "confirmed", RuntimeController.sessionCounters.fishConfirmed) end
                        LOG("FISH", "SUCCESS_CONFIRMED – counted")
                    else
                        RuntimeController.sessionCounters.fishUnknown = RuntimeController.sessionCounters.fishUnknown + 1
                        LOG("FISH", "RESULT_UNCONFIRMED (bar-gone, not counted) result=" .. tostring(result))
                    end

                    -- Fatigue break
                    RuntimeController.sessionCounters.fishAttempts = RuntimeController.sessionCounters.fishAttempts + 1
                    _fatCount = _fatCount + 1
                    if _fatCount >= CFG.fishing.fatigueEvery then
                        _fatCount = 0
                        LOG("FISH", "Fatigue break " .. CFG.fishing.fatigueDur .. "s")
                        task.spawn(function()
                            if gen == _generation then
                                task.wait(CFG.fishing.fatigueDur)
                            end
                        end)
                    end

                    task.delay(CFG.fishing.recastDelay, function()
                        if gen ~= _generation then return end
                        FishingController.reset(nil)
                        task.wait(0.06)
                        if isRunning() and gen == _generation then
                            setState(STATES.IDLE)
                            _idleAt = os.clock()
                        end
                    end)
                end
            elseif not _mgEverSeen then
                -- Sync mode: alternate Space while waiting for bars to appear
                local beat = math.floor((now - _mgAt) * 3.0) % 2 == 0
                FishingInputManager.setSpaceHeld(beat)
            end
        end
    end

    -- Cast one time
    function FishingController.startCast()
        if not isRunning() then return end
        if _casting or _state ~= STATES.IDLE then return end
        _casting = true
        local gen = bumpGeneration()
        setState(STATES.CASTING)

        task.spawn(function()
            if not RuntimeController.isTaskValid("fish_cast_" .. gen, 0) then
                -- use generation check differently:
                if gen ~= _generation then _casting = false; return end
            end

            local ch  = me.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if not hum then _casting = false; setState(STATES.IDLE); return end

            local tool = FishingToolResolver.equipBest()
            if not tool then
                FishingResultObserver.setToolState("None")
                WARN("FISH", "No rod – cannot cast")
                _casting = false
                setState(STATES.IDLE)
                return
            end

            FishingResultObserver.setToolState("Equipped (" .. tool.Name .. ")")
            CharacterState.setJumpEnabled(false)

            local cam = workspace.CurrentCamera
            if not cam then _casting = false; setState(STATES.IDLE); return end

            local rod = FishingRodProfileProvider.get()
            local ctr = cam.ViewportSize / 2
            local slow = PerformanceMonitor.performanceSlow

            pcall(function() tool:Activate() end)
            if Capabilities.vu then
                pcall(function() VU:Button1Down(ctr, cam.CFrame) end)
            end

            local lagMult = slow and 1.2 or 1.0
            local dur = CFG.fishing.castHold / math.max(1, math.sqrt(rod.lure) * 0.85) * lagMult

            local t0 = os.clock()
            while os.clock() - t0 < dur do
                task.wait(0.04)
                if gen ~= _generation or not isRunning() then
                    if Capabilities.vu then pcall(function() VU:Button1Up(ctr, cam.CFrame) end) end
                    _casting = false
                    return
                end
            end

            if Capabilities.vu then
                pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
            end
            task.wait(0.12)

            if gen ~= _generation or not isRunning() then
                _casting = false
                return
            end

            setState(STATES.WAITING_BITE)
            _biteAt = os.clock()
            _casting = false
            LOG("FISH", "Cast complete → WAITING_BITE")
        end)
    end

    -- Called every 0.016s on Heartbeat
    function FishingController.tick()
        if not isRunning() then return end
        local now = os.clock()

        if _state == STATES.IDLE then
            if not _casting then
                FishingController.startCast()
            end
            return
        end

        if _state == STATES.WAITING_BITE then
            -- Continuously check if Reeling GUI becomes visible
            local hasBars = FishingUIAdapter.resolveFishingGui()
            if hasBars and FishingUIAdapter.isReelingVisible() then
                _state       = STATES.REELING
                _mgAt        = now
                _mgEverSeen  = true
                _mgStarted   = false
                _mgLastSeen  = now
                FishingInputManager.setSpaceHeld(false, true)
                FishingResultObserver.observeStart()
                LOG("FISH", "Reeling GUI detected → REELING")
                return
            end

            local el = now - _biteAt
            if el >= CFG.fishing.biteTimeout then
                -- Bite timeout expired WITHOUT Reeling GUI appearing!
                FishingInputManager.releaseAll()
                FishingResultObserver.observeEnd("bite-timeout-no-gui")
                RuntimeController.sessionCounters.fishFailed = RuntimeController.sessionCounters.fishFailed + 1
                LOG("FISH", "Bite timeout without Reeling GUI → reset/recast")
                FishingController.reset("bite-timeout-no-gui")
            end
            return
        end

        if _state == STATES.REELING then
            FishingController.tickMinigame(now)
            return
        end
    end

    -- Watchdog loop
    task.spawn(function()
        while RuntimeController.alive do
            task.wait(5)
            if not RuntimeController.alive then break end
            if RuntimeController.currentMode ~= "FISH" then
                _idleAt = os.clock()
            end
            if RuntimeController.currentMode == "FISH" then
                local now = os.clock()
                local slow = PerformanceMonitor.performanceSlow
                local idleThresh = slow and 22 or CFG.fishing.watchdogIdle
                local waitThresh = CFG.fishing.biteTimeout + CFG.fishing.watchdogWait

                if _state == STATES.IDLE and not _casting and (now - _idleAt) > idleThresh then
                    WARN("FISH", "Watchdog: idle-lock")
                    FishingController.reset("watchdog-idle")
                elseif _state == STATES.WAITING_BITE and (now - _biteAt) > waitThresh then
                    WARN("FISH", "Watchdog: bite-timeout")
                    FishingController.reset("watchdog-bite")
                elseif _state == STATES.CASTING and not _casting and (now - _idleAt) > CFG.fishing.watchdogCast then
                    WARN("FISH", "Watchdog: cast-stuck")
                    FishingController.reset("watchdog-cast")
                end
            end
        end
    end)

    -- Heartbeat driver
    local _hbLast = 0
    RuntimeController.trackConnection(RS.Heartbeat:Connect(function()
        if not RuntimeController.alive then return end
        local now = os.clock()
        if now - _hbLast < 0.016 then return end
        _hbLast = now
        if RuntimeController.currentMode ~= "FISH" then
            if FishingInputManager.isHeld() then FishingInputManager.releaseAll() end
            return
        end
        local ok, err = xpcall(FishingController.tick, function(e) return e end)
        if not ok then WARN("FISH", "tick error: " .. tostring(err)) end
    end))
end

---------------------------------------------------------------------------
-- 15. MINING – Target Resolver
--     Priority: CollectionService tags → Attributes → known folders →
--               object semantics → exact name list → CRYS_OK last fallback
---------------------------------------------------------------------------
local MINE_TOOL_NAMES = { "pickaxe", "cangkul", "kapak", "mining", "pick", "hammer" }

-- CRYS_OK/CRYS_NO are FALLBACK ONLY – listed explicitly for audit
local CRYS_OK_FALLBACK = { "8sisi","crystal","kristal","gem","ore","batu","stone","mineral" }
local CRYS_NO_BLACKLIST = {
    "lamp","light","glow","torch","lantern","bulb",
    "tree","bush","grass","leaf","vine","flower","plant",
    "wall","floor","ceiling","roof","prop","decor",
    "fence","gate","door","window","sign","board",
    "water","ocean","river","lake","pond",
    "cloud","fog","sun","moon","star","sky",
    "fire","flame","smoke","ember",
    "spawn","zone","region","trigger","sensor",
    "platform","road","path","bridge","stair","rail",
    "house","building","room","ground","terrain","base",
}

local MIN_SEMANTIC_SCORE = 3

local function getTargetPosition(target)
    if not target then return nil end
    if target:IsA("Model") then
        if target.PrimaryPart then
            return target.PrimaryPart.Position
        end
        local ok, pivot = pcall(function() return target:GetPivot().Position end)
        if ok and pivot then return pivot end
        for _, c in ipairs(target:GetChildren()) do
            if c:IsA("BasePart") then return c.Position end
        end
        return nil
    elseif target:IsA("BasePart") then
        return target.Position
    end
    return nil
end

local function getTargetSize(target)
    if not target then return Vector3.new(1, 1, 1) end
    if target:IsA("Model") then
        local ok, _, sz = pcall(function() return target:GetBoundingBox() end)
        if ok and sz then return sz end
        if target.PrimaryPart then return target.PrimaryPart.Size end
        for _, c in ipairs(target:GetChildren()) do
            if c:IsA("BasePart") then return c.Size end
        end
        return Vector3.new(4, 4, 4)
    elseif target:IsA("BasePart") then
        return target.Size
    end
    return Vector3.new(1, 1, 1)
end

-- Depletion check: conservative confirmation that target instance was legitimately destroyed/depleted
local function isTargetDepleted(target)
    if not target then return true end
    if not target.Parent then return true end
    local ok, inWs = pcall(function() return target:IsDescendantOf(workspace) end)
    if not ok or not inWs then return true end

    if target:IsA("Model") then
        local hasPart = false
        for _, desc in ipairs(target:GetDescendants()) do
            if desc:IsA("BasePart") then
                hasPart = true
                break
            end
        end
        if not hasPart then return true end
    end

    return false
end

-- Evaluates semantic mining evidence WITHOUT distance and WITHOUT generic visual bonuses
local function getMiningEvidenceScore(inst)
    if not inst or typeof(inst) ~= "Instance" then return 0, "none" end

    -- Blacklist check on instance name
    local ln = inst.Name:lower()
    for _, bl in ipairs(CRYS_NO_BLACKLIST) do
        if ln:find(bl, 1, true) then return -999, "blacklisted-name" end
    end

    local semScore = 0
    local semReason = "none"

    -- Priority 1: CollectionService tags (Strong: +20)
    local okTags, tags = pcall(function() return CS:GetTags(inst) end)
    if okTags and tags then
        for _, tag in ipairs(tags) do
            local tl = tag:lower()
            if tl:find("ore") or tl:find("crystal") or tl:find("mine") or tl:find("gem") then
                semScore = semScore + 20
                semReason = "tag:" .. tag
                break
            end
        end
    end

    -- Priority 2: Attributes (Strong: +15, +10)
    local isOre = inst:GetAttribute("IsOre") == true
               or inst:GetAttribute("IsCrystal") == true
               or inst:GetAttribute("IsMineTarget") == true
               or inst:GetAttribute("Mineable") == true
    if isOre then
        semScore = semScore + 15
        if semReason == "none" then semReason = "attribute:ore" end
    end
    local oreType = inst:GetAttribute("OreType") or inst:GetAttribute("ResourceType")
    if oreType then
        semScore = semScore + 10
        if semReason == "none" then semReason = "attribute:resource" end
    end

    -- Priority 3: Container/folder parent name match (Medium: +8)
    local par = inst.Parent
    if par and par ~= workspace then
        local parName = par.Name:lower()
        for _, cn in ipairs(CRYS_OK_FALLBACK) do
            if parName:find(cn:lower(), 1, true) then
                semScore = semScore + 8
                if semReason == "none" then semReason = "container-name:" .. par.Name end
                break
            end
        end
    end

    -- Priority 5: Name heuristic (Weak: +3)
    for _, cn in ipairs(CRYS_OK_FALLBACK) do
        if ln:find(cn:lower(), 1, true) then
            semScore = semScore + 3
            if semReason == "none" then semReason = "name-heuristic" end
            break
        end
    end

    return semScore, semReason
end

local MiningTargetResolver = {}
local MiningTargetValidator = {}
do
    -------------------------------------------------------------------
    -- VALIDATOR (supports BasePart, MeshPart, and Model)
    -------------------------------------------------------------------
    function MiningTargetValidator.isValid(inst)
        if not inst then return false end
        if typeof(inst) ~= "Instance" then return false end
        -- Must have a parent in workspace hierarchy
        if not inst.Parent then return false end
        local ok, _ = pcall(function() return inst.Parent end)
        if not ok then return false end

        -- Must be a geometric object (BasePart or Model)
        if not (inst:IsA("BasePart") or inst:IsA("MeshPart") or inst:IsA("Model")) then
            return false
        end

        -- If Model, must have at least one BasePart descendant
        if inst:IsA("Model") then
            local hasPart = false
            for _, desc in ipairs(inst:GetDescendants()) do
                if desc:IsA("BasePart") then hasPart = true; break end
            end
            if not hasPart then return false end
        end

        -- Must have a valid position
        local pos = getTargetPosition(inst)
        if not pos then return false end

        -- Must not be a player character part/model
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then
                if inst == p.Character or inst:IsDescendantOf(p.Character) then
                    return false
                end
            end
        end

        -- Must not be terrain
        if inst:IsA("Terrain") then return false end

        -- Must not be a GUI element
        if inst:IsA("GuiObject") then return false end

        -- Must be in workspace (not some temp client object)
        if not inst:IsDescendantOf(workspace) then return false end

        return true
    end

    -------------------------------------------------------------------
    -- CANONICAL TARGET RESOLVER
    -------------------------------------------------------------------
    local function resolveCanonicalMiningTarget(obj)
        if not obj or typeof(obj) ~= "Instance" then return nil end

        if obj:IsA("Model") then
            if not MiningTargetValidator.isValid(obj) then return nil end
            local modelSemScore, _ = getMiningEvidenceScore(obj)
            -- Aggregate evidence from descendants (up to first 15 BaseParts)
            local count = 0
            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("BasePart") then
                    count = count + 1
                    local descSemScore, _ = getMiningEvidenceScore(desc)
                    if descSemScore > 0 then
                        modelSemScore = math.max(modelSemScore, descSemScore)
                    end
                    if count >= 15 then break end
                end
            end
            if modelSemScore >= MIN_SEMANTIC_SCORE then
                return obj
            end
            return nil

        elseif obj:IsA("BasePart") then
            if not MiningTargetValidator.isValid(obj) then return nil end
            local childSemScore, _ = getMiningEvidenceScore(obj)

            local parent = obj.Parent
            if parent and parent:IsA("Model") and parent ~= workspace and not parent:IsA("Workspace") then
                if MiningTargetValidator.isValid(parent) then
                    local parentDirectSem, _ = getMiningEvidenceScore(parent)
                    local parentAggSem = parentDirectSem
                    local count = 0
                    for _, desc in ipairs(parent:GetDescendants()) do
                        if desc:IsA("BasePart") then
                            count = count + 1
                            local dScore, _ = getMiningEvidenceScore(desc)
                            if dScore > 0 then
                                parentAggSem = math.max(parentAggSem, dScore)
                            end
                            if count >= 15 then break end
                        end
                    end

                    -- If parent Model has equal or stronger meaningful mining evidence, return parent Model
                    if parentAggSem >= MIN_SEMANTIC_SCORE and parentAggSem >= childSemScore then
                        return parent
                    end

                    -- If child Part has stronger evidence, keep the Part
                    if childSemScore >= MIN_SEMANTIC_SCORE then
                        return obj
                    end

                    return nil
                end
            end

            if childSemScore >= MIN_SEMANTIC_SCORE then
                return obj
            end
            return nil
        end

        return nil
    end

    -------------------------------------------------------------------
    -- SCORING
    -------------------------------------------------------------------
    local function isBlacklisted(name)
        local ln = name:lower()
        for _, bl in ipairs(CRYS_NO_BLACKLIST) do
            if ln:find(bl, 1, true) then return true end
        end
        return false
    end

    function MiningTargetResolver.scoreTarget(inst)
        if not MiningTargetValidator.isValid(inst) then
            return -999, "invalid"
        end

        if isBlacklisted(inst.Name) then return -999, "blacklisted-name" end
        local par = inst.Parent
        while par and par ~= workspace do
            if isBlacklisted(par.Name) then return -999, "blacklisted-ancestor" end
            par = par.Parent
        end

        -- Calculate semantic score
        local semScore, semReason = getMiningEvidenceScore(inst)
        if inst:IsA("Model") then
            local count = 0
            for _, desc in ipairs(inst:GetDescendants()) do
                if desc:IsA("BasePart") then
                    count = count + 1
                    local descScore, descReason = getMiningEvidenceScore(desc)
                    if descScore > semScore then
                        semScore = descScore
                        semReason = "descendant:" .. descReason
                    end
                    if count >= 15 then break end
                end
            end
        end

        -- Require semantic floor
        if semScore < MIN_SEMANTIC_SCORE then
            return -999, "below-semantic-floor"
        end

        local visualScore = 0
        -- Visual / structural bonuses (applied only after passing semantic floor)
        if inst:IsA("Model") then
            visualScore = visualScore + 3
            for _, c in ipairs(inst:GetChildren()) do
                if c:IsA("BasePart") and c.Material == Enum.Material.Neon then
                    visualScore = visualScore + 4
                    break
                end
            end
        else
            if inst.Material == Enum.Material.Neon then visualScore = visualScore + 4 end
            if inst:IsA("MeshPart") then visualScore = visualScore + 2 end
            if inst.Transparency < 0.85 then visualScore = visualScore + 1 end
            if inst.CanCollide then visualScore = visualScore + 1 end
        end

        -- Size penalties
        local sizeScore = 0
        local sz = getTargetSize(inst)
        if sz.X > 22 or sz.Y > 22 or sz.Z > 22 then sizeScore = sizeScore - 6 end
        if sz.X < 0.35 and sz.Y < 0.35 and sz.Z < 0.35 then sizeScore = sizeScore - 5 end

        local finalScore = semScore + visualScore + sizeScore
        return finalScore, semReason
    end

    -------------------------------------------------------------------
    -- CACHE
    -------------------------------------------------------------------
    local _cache   = {}
    local _cacheAt = 0

    function MiningTargetResolver.refreshCache()
        _cache  = {}
        _cacheAt = os.clock()
        local threshold = CFG.mining.scoreThreshold
        local seen = {}

        for _, obj in ipairs(workspace:GetDescendants()) do
            local canonical = resolveCanonicalMiningTarget(obj)
            if canonical and not seen[canonical] then
                seen[canonical] = true
                local sc, _ = MiningTargetResolver.scoreTarget(canonical)
                if sc >= threshold then
                    _cache[#_cache + 1] = canonical
                end
            end
        end
        LOG("MINE", "Cache refreshed: " .. #_cache .. " candidates")
    end

    function MiningTargetResolver.getCache() return _cache end
    function MiningTargetResolver.getCacheAge() return os.clock() - _cacheAt end
    function MiningTargetResolver.invalidateCache() _cache = {}; _cacheAt = 0 end

    function MiningTargetResolver.findBest(myPos)
        local threshold = CFG.mining.scoreThreshold
        local maxDist   = CFG.mining.targetMaxDist

        -- Refresh cache if stale or empty
        if os.clock() - _cacheAt > CFG.mining.scanInterval or #_cache == 0 then
            MiningTargetResolver.refreshCache()
        end

        local best, bestScore, bestDist, bestReason = nil, -999, math.huge, "none"
        for _, obj in ipairs(_cache) do
            if MiningTargetValidator.isValid(obj) then
                local sc, reason = MiningTargetResolver.scoreTarget(obj)
                if sc >= threshold then
                    local objPos = getTargetPosition(obj)
                    if objPos then
                        local dist = (objPos - myPos).Magnitude
                        if dist <= maxDist then
                            -- Combine distance and score
                            local combined = sc - (dist / 50)
                            if combined > bestScore then
                                bestScore  = combined
                                best       = obj
                                bestDist   = dist
                                bestReason = reason
                            end
                        end
                    end
                end
            end
        end

        return best, bestScore, bestDist, bestReason
    end
end

---------------------------------------------------------------------------
-- 16. MINING – Tool Resolver
---------------------------------------------------------------------------
local MiningToolResolver = {}
do
    local function normalize(s)
        return tostring(s or ""):lower():gsub("%s+", "")
    end

    local function isMiningCandidate(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local tn = normalize(tool.Name)
        for _, n in ipairs(MINE_TOOL_NAMES) do
            if tn == normalize(n) or tn:find(normalize(n), 1, true) then return true end
        end
        if tool:GetAttribute("IsMiningTool") == true then return true end
        if tool:GetAttribute("ToolType") == "Mining" then return true end
        return false
    end

    function MiningToolResolver.resolveMiningTool()
        local ch = me.Character
        if not ch then return nil end

        for _, item in ipairs(ch:GetChildren()) do
            if isMiningCandidate(item) then return item end
        end

        local bp = me:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if isMiningCandidate(item) then return item end
            end
        end
        return nil
    end

    function MiningToolResolver.equipMiningTool()
        local ch = me.Character
        if not ch then return nil end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum then return nil end

        for _, item in ipairs(ch:GetChildren()) do
            if item:IsA("Tool") and MiningToolResolver.resolveMiningTool() == item then
                return item
            end
        end

        local bp = me:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if item:IsA("Tool") then
                    local candidate = MiningToolResolver.resolveMiningTool()
                    if candidate == item then
                        pcall(function() hum:EquipTool(item) end)
                        task.wait(0.35)
                        return MiningToolResolver.resolveMiningTool()
                    end
                end
            end
        end
        return nil
    end
end

---------------------------------------------------------------------------
-- 17. MINING – Movement (PathfindingService + fallback MoveTo)
---------------------------------------------------------------------------
local MiningMovement = {}
do
    local function doJump(hum)
        task.spawn(function()
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
            task.wait(0.02)
            if Capabilities.vim then
                pcall(function()
                    VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
                    task.wait(0.13)
                    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                end)
            end
        end)
    end

    local function groundRay(pos, ign)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = ign or {}
        rp.IgnoreWater = false
        return workspace:Raycast(pos + Vector3.new(0, 16, 0), Vector3.new(0, -56, 0), rp)
    end

    -- Compute a stand position near target (Model or BasePart)
    function MiningMovement.getStandPoint(target, myPos)
        local origin = getTargetPosition(target)
        if not origin then return nil end
        local tSize = getTargetSize(target)
        local cw = math.max(tSize.X, tSize.Z)
        local radius = math.clamp(cw * 0.28 + 1.3, CFG.mining.stopDistance, 3.8)
        local ignore = { me.Character, target }
        local best, bestSc = nil, math.huge

        for i = 1, 24 do
            local a = math.pi * 2 * (i / 24)
            local smp = origin + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
            local gr  = groundRay(smp, ignore)
            if gr and gr.Instance and gr.Normal.Y > 0.45 then
                local pos = gr.Position + Vector3.new(0, 3.1, 0)
                if pos.Y <= origin.Y + tSize.Y * 0.5 then
                    local hd = math.abs(pos.Y - myPos.Y)
                    if hd < 14 then
                        local dc = (Vector3.new(pos.X, origin.Y, pos.Z) - origin).Magnitude
                        local sc = (pos - myPos).Magnitude + math.abs(dc - radius) * 5 + hd
                        if sc < bestSc then bestSc = sc; best = pos end
                    end
                end
            end
        end

        if best then return best end
        local d    = myPos - origin
        local flat = Vector3.new(d.X, 0, d.Z)
        if flat.Magnitude < 0.4 then flat = Vector3.new(1, 0, 0) end
        local fb = origin + flat.Unit * radius
        local gr2 = groundRay(fb, ignore)
        return gr2 and (gr2.Position + Vector3.new(0, 3.1, 0)) or fb
    end

    --[[
        Move to targetPos using Pathfinding with Path.Blocked handling and fallback MoveTo.
        Saves and restores exact original WalkSpeed in finally-style cleanup.
        Returns: "arrived" | "mode-changed" | "target-gone" | "timeout" | "blocked" | "failed"
    ]]
    function MiningMovement.moveTo(hum, targetPos, targetPart, miningGeneration)
        local ch = me.Character
        if not ch or not ch.PrimaryPart then return "failed" end

        -- Save exact WalkSpeed
        local origWalkSpeed = hum.WalkSpeed
        local MOVE_SPEED    = math.max(origWalkSpeed, 20)
        local result        = "failed"
        local recomputes    = 0
        local maxRecomputes = CFG.mining.maxPathRecomputes or 3
        local blockedConn   = nil

        local function cleanup()
            if blockedConn then
                pcall(function() blockedConn:Disconnect() end)
                blockedConn = nil
            end
            pcall(function() hum.WalkSpeed = origWalkSpeed end)
        end

        pcall(function()
            local t0_total = os.clock()
            hum.WalkSpeed = MOVE_SPEED

            local function computeAndGetWaypoints(startPos)
                local path = PFS:CreatePath({
                    AgentRadius     = 1.8,
                    AgentHeight     = 5.0,
                    AgentCanJump    = true,
                    AgentCanClimb   = false,
                    WaypointSpacing = 6,
                    Costs           = { Water = 8 },
                })
                local ok = pcall(function() path:ComputeAsync(startPos, targetPos) end)
                if ok and path.Status == Enum.PathStatus.Success then
                    return path, path:GetWaypoints()
                end
                return nil, { { Position = targetPos, Action = Enum.PathWaypointAction.Walk } }
            end

            while recomputes <= maxRecomputes do
                if RuntimeController.currentMode ~= "MINE" or not RuntimeController.alive then
                    result = "mode-changed"; break
                end
                if miningGeneration ~= RuntimeController.getGeneration("mine_ctrl") then
                    result = "mode-changed"; break
                end
                if targetPart and isTargetDepleted(targetPart) then
                    result = "target-gone"; break
                end
                if os.clock() - t0_total > CFG.mining.moveTimeout then
                    result = "timeout"; break
                end

                if not ch.PrimaryPart then break end
                local curPos = ch.PrimaryPart.Position
                local pathObj, wps = computeAndGetWaypoints(curPos)

                local pathNeedsRecompute = false
                local currentWpIndex     = 1

                if blockedConn then
                    pcall(function() blockedConn:Disconnect() end)
                    blockedConn = nil
                end

                if pathObj then
                    blockedConn = pathObj.Blocked:Connect(function(blockedWaypointIndex)
                        if blockedWaypointIndex >= currentWpIndex then
                            pathNeedsRecompute = true
                        end
                    end)
                end

                local lastPos = ch.PrimaryPart.Position
                local stuckT  = 0
                local isArr   = false

                for i, wp in ipairs(wps) do
                    currentWpIndex = i
                    if RuntimeController.currentMode ~= "MINE" or not RuntimeController.alive then
                        result = "mode-changed"; isArr = false; break
                    end
                    if miningGeneration ~= RuntimeController.getGeneration("mine_ctrl") then
                        result = "mode-changed"; isArr = false; break
                    end
                    if targetPart and isTargetDepleted(targetPart) then
                        result = "target-gone"; isArr = false; break
                    end
                    if os.clock() - t0_total > CFG.mining.moveTimeout then
                        result = "timeout"; isArr = false; break
                    end
                    if pathNeedsRecompute then
                        break
                    end

                    if wp.Action == Enum.PathWaypointAction.Jump then doJump(hum) end

                    hum:MoveTo(wp.Position)
                    local t0 = os.clock()

                    while RuntimeController.currentMode == "MINE" and RuntimeController.alive do
                        task.wait(0.06)
                        if not ch.PrimaryPart then break end

                        if miningGeneration ~= RuntimeController.getGeneration("mine_ctrl") then
                            result = "mode-changed"; isArr = false; break
                        end
                        if targetPart and isTargetDepleted(targetPart) then
                            result = "target-gone"; isArr = false; break
                        end
                        if os.clock() - t0_total > CFG.mining.moveTimeout then
                            result = "timeout"; isArr = false; break
                        end
                        if pathNeedsRecompute then
                            break
                        end

                        local cur = ch.PrimaryPart.Position

                        if targetPart and targetPart.Parent then
                            local tPos = getTargetPosition(targetPart)
                            local tSz  = getTargetSize(targetPart)
                            if tPos then
                                local cw   = math.max(tSz.X, tSz.Z)
                                local dist = (cur - tPos).Magnitude
                                if dist <= (cw * 0.5 + CFG.mining.stopDistance + 0.3) then
                                    isArr = true; break
                                end
                            end
                        end

                        if (cur - targetPos).Magnitude <= 1.2 then isArr = true; break end

                        local reach = (i < #wps) and 5.0 or 1.2
                        if (cur - wp.Position).Magnitude <= reach then break end

                        if os.clock() - t0 > 5.5 then break end

                        if (cur - lastPos).Magnitude < 0.17 then
                            stuckT = stuckT + 0.06
                            if stuckT > 1.2 then
                                doJump(hum)
                                local dir = targetPos - cur
                                hum:MoveTo(cur + (dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)) * 4.5)
                                task.wait(0.3)
                                stuckT = 0
                                break
                            end
                        else
                            stuckT  = 0
                            lastPos = cur
                        end
                    end

                    if isArr or pathNeedsRecompute or result == "mode-changed" or result == "target-gone" or result == "timeout" then
                        break
                    end
                end

                if isArr then
                    result = "arrived"
                    break
                elseif pathNeedsRecompute then
                    if recomputes >= maxRecomputes then
                        WARN("MINE", "Path blocked — recompute limit reached")
                        result = "blocked"
                        break
                    end
                    recomputes = recomputes + 1
                    WARN("MINE", string.format("Path.Blocked — recomputing (%d/%d)", recomputes, maxRecomputes))
                    task.wait(0.1)
                else
                    if ch.PrimaryPart and (ch.PrimaryPart.Position - targetPos).Magnitude <= 2.5 then
                        result = "arrived"
                    end
                    break
                end
            end
        end)

        cleanup()
        return result
    end
end

---------------------------------------------------------------------------
-- 18. MINING – Action Adapter
---------------------------------------------------------------------------
local MiningActionAdapter = {}
do
    local _lastActivation = 0

    function MiningActionAdapter.tryActivate(tool, targetPos)
        if not tool or not tool.Parent then return false end
        local now = os.clock()
        if now - _lastActivation < CFG.mining.hitInterval then return false end
        _lastActivation = now

        local cam = workspace.CurrentCamera
        if cam and Capabilities.vu then
            local ok, sp, onSc = pcall(function()
                return cam:WorldToScreenPoint(targetPos)
            end)
            if ok and onSc then
                local px = Vector2.new(sp.X, sp.Y)
                pcall(function() VU:Button1Down(px, cam.CFrame) end)
                task.wait(0.08)
                pcall(function() VU:Button1Up(px, cam.CFrame) end)
            end
        end

        pcall(function() tool:Activate() end)
        return true
    end

    function MiningActionAdapter.reset()
        _lastActivation = 0
    end
end

---------------------------------------------------------------------------
-- 19. MINING CONTROLLER – explicit state machine
---------------------------------------------------------------------------
local MiningController = {}
do
    local STATES = {
        IDLE           = "IDLE",
        SCAN           = "SCAN",
        TARGET_SELECTED= "TARGET_SELECTED",
        MOVING         = "MOVING",
        EQUIPPING      = "EQUIPPING",
        MINING         = "MINING",
        VERIFYING      = "VERIFYING",
        COMPLETED      = "COMPLETED",
        FAILED         = "FAILED",
        COOLDOWN       = "COOLDOWN",
    }

    local _state         = STATES.IDLE
    local _active        = false
    local _currentTarget = nil
    local _failCount     = 0
    local _hitCycles     = 0
    local _locked        = false

    local _onStateChange = nil
    local _onCountChange = nil

    function MiningController.onStateChange(fn)  _onStateChange = fn end
    function MiningController.onCountChange(fn)  _onCountChange = fn end

    local function setState(s)
        _state = s
        if _onStateChange then pcall(_onStateChange, s) end
    end

    function MiningController.getState()         return _state end
    function MiningController.getCurrentTarget() return _currentTarget end
    function MiningController.isLocked()         return _locked end

    function MiningController.stop()
        local gen = RuntimeController.invalidateTaskGroup("mine_ctrl")
        _active        = false
        _locked        = false
        _currentTarget = nil
        MiningActionAdapter.reset()
        CharacterState.restoreAll()
        setState(STATES.IDLE)
        LOG("MINE", "Stopped (gen=" .. gen .. ")")
    end

    function MiningController.isOccupied(target)
        local targetPos = getTargetPosition(target)
        if not targetPos then return false end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= me and p.Character then
                local root = p.Character.PrimaryPart
                if root and (root.Position - targetPos).Magnitude < 10 then
                    local t = p.Character:FindFirstChildOfClass("Tool")
                    if t then
                        local tn = t.Name:lower()
                        for _, mn in ipairs(MINE_TOOL_NAMES) do
                            if tn:find(mn, 1, true) then return true end
                        end
                    end
                end
            end
        end
        return false
    end

    function MiningController.run()
        if _active then return end
        _active = true
        local gen = RuntimeController.invalidateTaskGroup("mine_ctrl")

        task.spawn(function()
            while RuntimeController.currentMode == "MINE" and RuntimeController.alive do
                local ok, err = xpcall(function()
                    if gen ~= RuntimeController.getGeneration("mine_ctrl") then return end

                    local ch  = me.Character
                    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                    if not ch or not hum then
                        task.wait(0.5)
                        return
                    end

                    local myPos = ch.PrimaryPart and ch.PrimaryPart.Position
                    if not myPos then task.wait(0.5); return end

                    -- Respect lock: keep current target while mining
                    if _locked and _currentTarget and _currentTarget.Parent and MiningTargetValidator.isValid(_currentTarget) then
                        -- Continue mining below
                    else
                        -- Scan for target
                        setState(STATES.SCAN)
                        local target, score, dist, reason = MiningTargetResolver.findBest(myPos)

                        if not target then
                            setState(STATES.IDLE)
                            LOG("MINE", "No target found – waiting")
                            task.wait(2.5)
                            return
                        end

                        if MiningController.isOccupied(target) then
                            _currentTarget = nil
                            task.wait(0.3)
                            return
                        end

                        _currentTarget = target
                        _failCount     = 0
                        _hitCycles     = 0
                        setState(STATES.TARGET_SELECTED)
                        LOG("MINE", string.format("Target: %s (%s) | score=%.1f dist=%.1f reason=%s",
                            target.Name, target.ClassName, score, dist, reason))
                    end

                    local crystal = _currentTarget
                    if not MiningTargetValidator.isValid(crystal) then
                        _currentTarget = nil; _locked = false; return
                    end

                    local tPos = getTargetPosition(crystal)
                    local tSz  = getTargetSize(crystal)
                    if not tPos then
                        _currentTarget = nil; _locked = false; return
                    end

                    -- Equip tool
                    setState(STATES.EQUIPPING)
                    local tool = MiningToolResolver.equipMiningTool()
                    if not tool then
                        LOG("MINE", "No mining tool available")
                        setState(STATES.IDLE)
                        task.wait(1.5)
                        return
                    end

                    -- Check distance
                    local cw   = math.max(tSz.X, tSz.Z)
                    local dist = (myPos - tPos).Magnitude
                    local closeEnough = dist <= (cw * 0.5 + CFG.mining.stopDistance + 0.5)

                    if not closeEnough then
                        setState(STATES.MOVING)
                        local sp = MiningMovement.getStandPoint(crystal, myPos)
                        if sp and (myPos - sp).Magnitude > 1.0 then
                            local moveResult = MiningMovement.moveTo(hum, sp, crystal, gen)
                            if moveResult == "mode-changed" then
                                return
                            elseif moveResult == "target-gone" then
                                _currentTarget = nil; _locked = false; return
                            elseif moveResult == "timeout" or moveResult == "blocked" or moveResult == "failed" then
                                _failCount = _failCount + 1
                                if _failCount >= CFG.mining.maxFailCount then
                                    WARN("MINE", "Max fail count – retargeting")
                                    _currentTarget = nil; _locked = false; _failCount = 0
                                end
                                return
                            end
                        end
                    end

                    -- Nudge toward crystal
                    local ch2 = me.Character
                    if ch2 and ch2.PrimaryPart and crystal.Parent then
                        local cur     = ch2.PrimaryPart.Position
                        local curTPos = getTargetPosition(crystal) or tPos
                        local diff    = curTPos - cur
                        local flat    = Vector3.new(diff.X, 0, diff.Z)
                        if flat.Magnitude > 0.3 then
                            local nudge = math.clamp(cw * 0.22, 0.35, 1.0)
                            hum:MoveTo(cur + flat.Unit * nudge)
                            task.wait(0.18)
                        end
                    end

                    -- Face crystal
                    if me.Character and me.Character.PrimaryPart and crystal.Parent then
                        local p       = me.Character.PrimaryPart.Position
                        local curTPos = getTargetPosition(crystal) or tPos
                        pcall(function()
                            me.Character:SetPrimaryPartCFrame(
                                CFrame.lookAt(p, Vector3.new(curTPos.X, p.Y, curTPos.Z))
                            )
                        end)
                    end

                    -- MINING loop
                    setState(STATES.MINING)
                    _locked = true
                    local curTPos = getTargetPosition(crystal) or tPos
                    local curTSz  = getTargetSize(crystal) or tSz
                    local aimPos  = curTPos + Vector3.new(0, math.clamp(curTSz.Y * 0.1, 0.25, 2.2), 0)

                    RuntimeController.sessionCounters.mineAttempts = RuntimeController.sessionCounters.mineAttempts + 1

                    for s = 1, 10 do
                        if gen ~= RuntimeController.getGeneration("mine_ctrl") then break end
                        if RuntimeController.currentMode ~= "MINE" then break end
                        if isTargetDepleted(crystal) or not MiningTargetValidator.isValid(crystal) then break end

                        MiningActionAdapter.tryActivate(tool, aimPos)
                        task.wait(CFG.mining.hitInterval + 0.05)
                    end

                    _locked = false
                    _hitCycles = _hitCycles + 1

                    -- VERIFYING – only count if target actually disappeared / depleted
                    setState(STATES.VERIFYING)
                    task.wait(0.15)

                    if isTargetDepleted(crystal) then
                        -- TARGET LEGITIMATELY DEPLETED = CONFIRMED MINE
                        RuntimeController.sessionCounters.mineConfirmed = RuntimeController.sessionCounters.mineConfirmed + 1
                        if _onCountChange then
                            pcall(_onCountChange, "confirmed", RuntimeController.sessionCounters.mineConfirmed)
                        end
                        setState(STATES.COMPLETED)
                        _currentTarget = nil
                        _failCount     = 0
                        _hitCycles     = 0
                        LOG("MINE", "Confirmed mined: " .. crystal.Name)
                        task.wait(0.3)
                    else
                        -- Target still alive
                        if _hitCycles >= CFG.mining.maxHitCycles then
                            RuntimeController.sessionCounters.mineFailed = RuntimeController.sessionCounters.mineFailed + 1
                            WARN("MINE", "Target survived " .. _hitCycles .. " cycles – retargeting: " .. crystal.Name)
                            _currentTarget = nil
                            _hitCycles     = 0
                            _failCount     = _failCount + 1
                            if _failCount >= CFG.mining.maxFailCount then _failCount = 0 end
                            MiningTargetResolver.invalidateCache()
                        else
                            LOG("MINE", string.format("Target alive after %d cycles – continuing", _hitCycles))
                        end
                    end
                end, function(e) return e end)

                if not ok then
                    WARN("MINE", "Loop error: " .. tostring(err))
                    task.wait(0.5)
                end
            end

            _active = false
            setState(STATES.IDLE)
            LOG("MINE", "Loop ended")
        end)
    end
end

---------------------------------------------------------------------------
-- 20. AVATAR CONTROLLER – HumanoidDescription copy/restore
---------------------------------------------------------------------------
local AvatarController = {}
do
    local _originalDesc  = nil
    local _status        = "Ready"
    local _onStatus      = nil
    local _targetPlayer  = nil
    local _avatarGen     = 0

    function AvatarController.onStatus(fn) _onStatus = fn end

    local function setStatus(s)
        _status = s
        if _onStatus then pcall(_onStatus, s) end
        LOG("AVATAR", "Status: " .. s)
    end

    function AvatarController.getStatus() return _status end

    local function getLocalHumanoid()
        local ch = me.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end

    local function applyHumanoidDescription(humanoid, desc)
        if not humanoid or not desc then return false, "invalid arguments" end
        local ok, err
        local hasAsync = false
        pcall(function()
            if type(humanoid.ApplyDescriptionAsync) == "function" or humanoid.ApplyDescriptionAsync ~= nil then
                hasAsync = true
            end
        end)
        if hasAsync then
            ok, err = pcall(function() humanoid:ApplyDescriptionAsync(desc) end)
            if ok then return true end
        end
        ok, err = pcall(function() humanoid:ApplyDescription(desc) end)
        return ok, err
    end

    -- Save original description once
    function AvatarController.ensureOriginalSaved()
        if _originalDesc then return true end
        local hum = getLocalHumanoid()
        if not hum then return false end
        local ok, desc = pcall(function() return hum:GetAppliedDescription() end)
        if ok and desc then
            _originalDesc = desc:Clone()
            LOG("AVATAR", "Original HumanoidDescription saved")
            return true
        end
        WARN("AVATAR", "Could not save original description")
        return false
    end

    function AvatarController.setTarget(player)
        _targetPlayer = player
    end

    function AvatarController.getTargetName()
        if not _targetPlayer then return "—" end
        return _targetPlayer.DisplayName .. " (@" .. _targetPlayer.Name .. ")"
    end

    function AvatarController.copyAvatar()
        AvatarController.ensureOriginalSaved()

        local target = _targetPlayer
        if not target then setStatus("Target unavailable"); return end
        if not target.Parent then setStatus("Target unavailable"); return end

        _avatarGen = _avatarGen + 1
        local curGen = _avatarGen
        setStatus("Applying...")

        task.spawn(function()
            local ok, err = xpcall(function()
                local tChar = target.Character
                local tHum  = tChar and tChar:FindFirstChildOfClass("Humanoid")
                if not tHum then
                    setStatus("Target unavailable"); return
                end

                local descOk, desc = pcall(function()
                    return tHum:GetAppliedDescription()
                end)
                if not descOk or not desc then
                    setStatus("Failed"); return
                end

                if curGen ~= _avatarGen then
                    LOG("AVATAR", "copyAvatar cancelled due to generation change")
                    return
                end

                local cloned = desc:Clone()
                local lHum   = getLocalHumanoid()
                if not lHum then setStatus("Failed"); return end

                local applyOk, applyErr = applyHumanoidDescription(lHum, cloned)
                if curGen ~= _avatarGen then return end

                if applyOk then
                    setStatus("Copied from @" .. target.Name)
                else
                    setStatus("Failed")
                    WARN("AVATAR", "applyHumanoidDescription failed: " .. tostring(applyErr))
                end
            end, function(e) return debug and debug.traceback and debug.traceback(e) or e end)

            if not ok then
                setStatus("Failed")
                WARN("AVATAR", "copyAvatar error: " .. tostring(err))
            end
        end)
    end

    function AvatarController.restoreOriginal()
        if not _originalDesc then
            setStatus("No original saved")
            return
        end
        local hum = getLocalHumanoid()
        if not hum then setStatus("Failed"); return end

        _avatarGen = _avatarGen + 1
        local curGen = _avatarGen
        setStatus("Restoring...")

        task.spawn(function()
            local ok, err = applyHumanoidDescription(hum, _originalDesc:Clone())
            if curGen ~= _avatarGen then return end

            if ok then
                setStatus("Restored")
            else
                setStatus("Failed")
                WARN("AVATAR", "Restore failed: " .. tostring(err))
            end
        end)
    end

    -- Handle respawn: update humanoid reference and bump generation
    RuntimeController.trackConnection(
        me.CharacterAdded:Connect(function(char)
            _avatarGen = _avatarGen + 1
            task.wait(2)
            if not _originalDesc then
                AvatarController.ensureOriginalSaved()
            end
        end)
    )

    AvatarController.ensureOriginalSaved()
end

---------------------------------------------------------------------------
-- 21. PLAYER CONTROLLER – player list, spectate, utilities
---------------------------------------------------------------------------
PlayerController = {}
do
    local _spectating     = false
    local _spectatePlayer = nil
    local _origSubject    = nil

    -- Efficient player list (event-driven, not rebuilt every frame)
    local _playerList = {}

    local function rebuildList()
        _playerList = Players:GetPlayers()
    end

    rebuildList()

    RuntimeController.trackConnection(
        Players.PlayerAdded:Connect(function(p)
            table.insert(_playerList, p)
        end)
    )

    RuntimeController.trackConnection(
        Players.PlayerRemoving:Connect(function(p)
            -- Stop spectate if they leave
            if _spectating and _spectatePlayer == p then
                PlayerController.stopSpectate()
            end
            for i, pl in ipairs(_playerList) do
                if pl == p then table.remove(_playerList, i); break end
            end
        end)
    )

    function PlayerController.getPlayers() return _playerList end

    function PlayerController.spectate(player)
        if not player or not player.Character then
            LOG("PLAYER", "Spectate failed: no character")
            return false
        end
        local tHum = player.Character:FindFirstChildOfClass("Humanoid")
        if not tHum then
            LOG("PLAYER", "Spectate failed: no Humanoid")
            return false
        end

        local cam = workspace.CurrentCamera
        if not cam then return false end

        if not _spectating then
            _origSubject = cam.CameraSubject
        end

        cam.CameraSubject = tHum
        _spectating       = true
        _spectatePlayer   = player
        LOG("PLAYER", "Spectating: @" .. player.Name)
        return true
    end

    function PlayerController.stopSpectate()
        if not _spectating then return end
        local cam = workspace.CurrentCamera
        if cam then
            local lHum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
            cam.CameraSubject = lHum or _origSubject
        end
        _spectating       = false
        _spectatePlayer   = nil
        LOG("PLAYER", "Spectate stopped – camera restored")
    end

    function PlayerController.isSpectating() return _spectating end
    function PlayerController.getSpectateTarget() return _spectatePlayer end

    function PlayerController.copyXYZToClipboard()
        if not Capabilities.clipboard then return false end
        local ch   = me.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local pos = root.Position
        local s   = string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z)
        pcall(setclipboard, s)
        LOG("PLAYER", "Copied XYZ: " .. s)
        return true
    end

    -- Handle re-execute while spectating
    RuntimeController.trackConnection(
        me.CharacterAdded:Connect(function()
            if _spectating then
                task.wait(1)
                PlayerController.stopSpectate()
            end
        end)
    )
end

---------------------------------------------------------------------------
-- 22. GUI CLEANUP – kill old GUIs from previous sessions
---------------------------------------------------------------------------
pcall(function()
    local cg = game:GetService("CoreGui")
    for _, n in ipairs({ "_NZH2", "_NZH_UI", "NH_v9_GUI", "IH_v5", "NH_v6_GUI", "_IDH_HUB" }) do
        local a = cg:FindFirstChild(n); if a then a:Destroy() end
        if me.PlayerGui then
            local b = me.PlayerGui:FindFirstChild(n); if b then b:Destroy() end
        end
    end
end)

task.wait(0.05)

---------------------------------------------------------------------------
-- 23. GUI – PALETTE & BUILDER HELPERS
---------------------------------------------------------------------------
local C = {
    bg        = Color3.fromRGB(13,  13,  16),
    card      = Color3.fromRGB(20,  20,  25),
    cardHover = Color3.fromRGB(26,  26,  33),
    border    = Color3.fromRGB(36,  36,  44),
    borderHi  = Color3.fromRGB(52,  52,  64),
    accent    = Color3.fromRGB(220,  45,  45),
    blue      = Color3.fromRGB( 38, 115, 255),
    green     = Color3.fromRGB( 38, 180,  75),
    gold      = Color3.fromRGB(220, 160,  40),
    txt       = Color3.fromRGB(238, 238, 245),
    subtxt    = Color3.fromRGB(168, 168, 183),
    dim       = Color3.fromRGB(112, 112, 128),
    muted     = Color3.fromRGB( 62,  62,  75),
    navActive = Color3.fromRGB( 22,  22,  30),
    swOn      = Color3.fromRGB(220,  45,  45),
    swOff     = Color3.fromRGB( 38,  38,  46),
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
    l.BackgroundTransparency = 1
    l.Text           = text or ""
    l.TextSize       = size or 10
    l.Font           = font or Enum.Font.GothamMedium
    l.TextColor3     = color or C.txt
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate   = Enum.TextTruncate.AtEnd
    l.Size           = UDim2.new(1, 0, 0, (size or 10) + 4)
    return l
end

local function mkBtn(parent, text, bg, tc, tsz)
    local b = Instance.new("TextButton", parent)
    b.BackgroundColor3 = bg or C.card
    b.Text             = text or ""
    b.TextColor3       = tc or C.txt
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = tsz or 9.5
    b.BorderSizePixel  = 0
    b.AutoButtonColor  = false
    rnd(b, 6)
    mkStroke(b, C.border, 1)
    local orig = b.BackgroundColor3
    local hi   = orig:Lerp(C.accent, 0.18)
    b.MouseEnter:Connect(function()
        TS:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = hi}):Play()
    end)
    b.MouseLeave:Connect(function()
        TS:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = orig}):Play()
    end)
    return b
end

local function mkSwitch(parent, defVal)
    local sw = Instance.new("TextButton", parent)
    sw.Size              = UDim2.new(0, 36, 0, 20)
    sw.BackgroundColor3  = defVal and C.swOn or C.swOff
    sw.Text              = ""
    sw.BorderSizePixel   = 0
    sw.AutoButtonColor   = false
    rnd(sw, 10)
    local knob = Instance.new("Frame", sw)
    knob.Size             = UDim2.new(0, 16, 0, 16)
    knob.Position         = defVal and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
    knob.BackgroundColor3 = C.txt
    knob.BorderSizePixel  = 0
    rnd(knob, 8)
    local val = defVal
    local function setVal(v)
        val = v
        TS:Create(sw,   TweenInfo.new(0.12), {BackgroundColor3 = v and C.swOn or C.swOff}):Play()
        TS:Create(knob, TweenInfo.new(0.12), {
            Position = v and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        }):Play()
    end
    return sw, knob, setVal, function() return val end
end

local function mkToggleRow(parent, y, label, sub, defVal, callback)
    local row = Instance.new("Frame", parent)
    row.Size              = UDim2.new(1, -16, 0, 36)
    row.Position          = UDim2.new(0, 8, 0, y)
    row.BackgroundColor3  = C.card
    row.BorderSizePixel   = 0
    rnd(row, 7); mkStroke(row, C.border)
    local lbl = mkLbl(row, label, 9.5, Enum.Font.GothamBold, C.txt)
    lbl.Size = UDim2.new(1,-54,0,14); lbl.Position = UDim2.new(0,10,0,sub and 4 or 11)
    if sub then
        local sl = mkLbl(row, sub, 7.5, Enum.Font.Gotham, C.dim)
        sl.Size = UDim2.new(1,-54,0,12); sl.Position = UDim2.new(0,10,0,20)
    end
    local sw, _, setFn, _ = mkSwitch(row, defVal)
    sw.Position = UDim2.new(1,-46,0.5,-10)
    sw.MouseButton1Click:Connect(function()
        if not RuntimeController.alive then return end
        local newVal = not (sw.BackgroundColor3 == C.swOn)
        setFn(newVal)
        callback(newVal)
    end)
    return sw
end

---------------------------------------------------------------------------
-- 24. MAIN HUB WINDOW
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name           = "_IDH_HUB"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 25
gui.IgnoreGuiInset = false
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
    gui.Parent = me:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame", gui)
main.Size             = UDim2.new(0, 470, 0, 370)
main.Position         = UDim2.new(1, -485, 0.5, -185)
main.BackgroundColor3 = C.bg
main.BorderSizePixel  = 0
main.Active           = true
main.Draggable        = true
rnd(main, 12); mkStroke(main, C.border, 1)

local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size             = UDim2.new(0, 38, 0, 38)
floatBtn.Position         = UDim2.new(1, -48, 0.5, -19)
floatBtn.BackgroundColor3 = C.card
floatBtn.Text             = "NH"
floatBtn.TextColor3       = C.accent
floatBtn.Font             = Enum.Font.GothamBold
floatBtn.TextSize         = 11
floatBtn.BorderSizePixel  = 0
floatBtn.Visible          = false
floatBtn.Active           = true
floatBtn.Draggable        = true
rnd(floatBtn, 19); mkStroke(floatBtn, C.border, 1)

-- TOP BAR
local topBar = Instance.new("Frame", main)
topBar.Size             = UDim2.new(1, 0, 0, 38)
topBar.BackgroundColor3 = C.bg
topBar.BorderSizePixel  = 0

do
    local div = Instance.new("Frame", topBar)
    div.Size = UDim2.new(1,0,0,1); div.Position = UDim2.new(0,0,1,-1)
    div.BackgroundColor3 = C.border; div.BorderSizePixel = 0
end

local function mkDot(x, col)
    local d = Instance.new("Frame", topBar)
    d.Size = UDim2.new(0,9,0,9); d.Position = UDim2.new(0,x,0.5,-4.5)
    d.BackgroundColor3 = col; d.BorderSizePixel = 0; rnd(d,5)
end
mkDot(12, Color3.fromRGB(255,95,87))
mkDot(26, Color3.fromRGB(254,188,47))
mkDot(40, Color3.fromRGB(40,200,64))

local titleL = mkLbl(topBar, "NasiHub", 11.5, Enum.Font.GothamBold, C.txt)
titleL.Size = UDim2.new(0,70,0,15); titleL.Position = UDim2.new(0,58,0,4)

local subL = mkLbl(topBar, "v3.0 · IDH", 8, Enum.Font.Gotham, C.dim)
subL.Size = UDim2.new(0,70,0,12); subL.Position = UDim2.new(0,58,0,20)

local hideBtn = mkBtn(topBar, "×", C.bg, C.dim, 16)
hideBtn.Size = UDim2.new(0,22,0,22); hideBtn.Position = UDim2.new(1,-30,0.5,-11)

-- SIDEBAR
local sidebar = Instance.new("Frame", main)
sidebar.Size = UDim2.new(0,130,1,-38); sidebar.Position = UDim2.new(0,0,0,38)
sidebar.BackgroundColor3 = C.bg; sidebar.BorderSizePixel = 0
do
    local sd = Instance.new("Frame", sidebar)
    sd.Size = UDim2.new(0,1,1,0); sd.Position = UDim2.new(1,-1,0,0)
    sd.BackgroundColor3 = C.border; sd.BorderSizePixel = 0
end

-- CONTENT AREA
local contentBg = Instance.new("Frame", main)
contentBg.Size = UDim2.new(1,-130,1,-38); contentBg.Position = UDim2.new(0,130,0,38)
contentBg.BackgroundColor3 = C.card; contentBg.BorderSizePixel = 0
contentBg.ClipsDescendants = true

-- NAVIGATION
local NAV = {
    { key="Home",     label="Home",      icon="🏠" },
    { key="Fishing",  label="Fishing",   icon="🎣" },
    { key="Mining",   label="Mining",    icon="⛏️" },
    { key="Avatar",   label="Avatar",    icon="👤" },
    { key="Spots",    label="Spots",     icon="📍" },
    { key="Settings", label="Settings",  icon="⚙️" },
    { key="Diag",     label="Diag",      icon="📊" },
}

local navBtns = {}
local panels  = {}

for i, item in ipairs(NAV) do
    local ny  = 8 + (i-1)*38
    local btn = Instance.new("TextButton", sidebar)
    btn.Size            = UDim2.new(1,-12,0,32)
    btn.Position        = UDim2.new(0,6,0,ny)
    btn.BackgroundColor3= C.bg
    btn.BorderSizePixel = 0
    btn.Text = ""; btn.AutoButtonColor = false; rnd(btn,7)

    local ico = Instance.new("TextLabel", btn)
    ico.BackgroundTransparency = 1
    ico.Size = UDim2.new(0,20,1,0); ico.Position = UDim2.new(0,8,0,0)
    ico.Text = item.icon; ico.Font = Enum.Font.Gotham; ico.TextSize = 10
    ico.TextColor3 = C.dim; ico.TextXAlignment = Enum.TextXAlignment.Center

    local lbl = mkLbl(btn, item.label, 9, Enum.Font.GothamMedium, C.dim)
    lbl.Size = UDim2.new(1,-34,1,0); lbl.Position = UDim2.new(0,32,0,0)

    navBtns[item.key] = { btn=btn, ico=ico, lbl=lbl }

    local p = Instance.new("ScrollingFrame", contentBg)
    p.Size = UDim2.new(1,0,1,0)
    p.BackgroundTransparency = 1; p.BorderSizePixel = 0
    p.ScrollBarThickness = 2; p.ScrollBarImageColor3 = C.border
    p.CanvasSize = UDim2.new(0,0,0,0); p.Visible = (i==1)
    panels[item.key] = p
end

local activeNav = "Home"
local function switchNav(name)
    if activeNav == name then return end
    local old = navBtns[activeNav]
    if old then
        TS:Create(old.btn, TweenInfo.new(0.12), {BackgroundColor3=C.bg}):Play()
        old.lbl.TextColor3 = C.dim; old.lbl.Font = Enum.Font.GothamMedium
    end
    activeNav = name
    local nb = navBtns[name]
    if nb then
        TS:Create(nb.btn, TweenInfo.new(0.12), {BackgroundColor3=C.navActive}):Play()
        nb.lbl.TextColor3 = C.txt; nb.lbl.Font = Enum.Font.GothamBold
    end
    for n, p in pairs(panels) do p.Visible = (n==name) end
end

for name, nb in pairs(navBtns) do
    nb.btn.MouseButton1Click:Connect(function() switchNav(name) end)
end

-- Activate first nav visually
do
    local nb = navBtns["Home"]
    nb.btn.BackgroundColor3 = C.navActive
    nb.lbl.TextColor3 = C.txt; nb.lbl.Font = Enum.Font.GothamBold
end

-- Hide/Show
local savedPos = main.Position; local isHid = false
local function doHide(h)
    isHid = h
    if h then
        savedPos = main.Position
        TS:Create(main, TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.In),
            {Position=UDim2.new(1,10,0.5,-185)}):Play()
        task.delay(0.19,function()
            if isHid then main.Visible=false; floatBtn.Visible=true end
        end)
    else
        main.Visible=true; floatBtn.Visible=false
        main.Position=UDim2.new(1,10,0.5,-185)
        TS:Create(main, TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
            {Position=savedPos}):Play()
    end
end
hideBtn.MouseButton1Click:Connect(function() doHide(true) end)
floatBtn.MouseButton1Click:Connect(function() doHide(false) end)

---------------------------------------------------------------------------
-- 25. HOME TAB
---------------------------------------------------------------------------
do
    local p = panels["Home"]

    -- Mode status hero
    local hero = Instance.new("Frame", p)
    hero.Size = UDim2.new(1,-16,0,72); hero.Position = UDim2.new(0,8,0,8)
    hero.BackgroundColor3 = C.bg; hero.BorderSizePixel = 0
    rnd(hero,8); mkStroke(hero,C.border)

    local dot = Instance.new("Frame", hero)
    dot.Size = UDim2.new(0,7,0,7); dot.Position = UDim2.new(0,10,0,12)
    dot.BackgroundColor3 = C.muted; dot.BorderSizePixel = 0; rnd(dot,4)

    local modeLbl  = mkLbl(hero, "Idle", 10, Enum.Font.GothamBold, C.txt)
    modeLbl.Size = UDim2.new(1,-30,0,14); modeLbl.Position = UDim2.new(0,22,0,8)

    local fishStatL = mkLbl(hero, "Fish: 0 confirmed", 8.5, Enum.Font.Gotham, C.subtxt)
    fishStatL.Size = UDim2.new(0.5,-10,0,12); fishStatL.Position = UDim2.new(0,10,0,27)

    local mineStatL = mkLbl(hero, "Mine: 0 confirmed", 8.5, Enum.Font.Gotham, C.subtxt)
    mineStatL.Size = UDim2.new(0.5,-10,0,12); mineStatL.Position = UDim2.new(0.5,0,0,27)

    local sessL = mkLbl(hero, "Session: 00:00:00", 7.5, Enum.Font.Gotham, C.dim)
    sessL.Size = UDim2.new(0.5,0,0,12); sessL.Position = UDim2.new(0,10,0,44)

    local perfL = mkLbl(hero, "FPS: 60", 7.5, Enum.Font.Gotham, C.dim)
    perfL.Size = UDim2.new(0.5,0,0,12); perfL.Position = UDim2.new(0.5,0,0,44)
    perfL.TextXAlignment = Enum.TextXAlignment.Right

    local dotPulse
    local function setDot(col)
        if dotPulse then dotPulse:Cancel() end
        dot.BackgroundColor3 = col
        dotPulse = TS:Create(dot,
            TweenInfo.new(0.65,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),
            {BackgroundColor3=col:Lerp(C.txt,0.42)})
        dotPulse:Play()
    end
    setDot(C.muted)

    local sessStart = os.clock()
    local _active   = false  -- local flag

    -- Expose updaters
    local function updateHomeMode(mode, dot_col)
        modeLbl.Text = mode
        if dot_col then setDot(dot_col) else setDot(C.muted) end
        _active = (mode ~= "Idle")
        if _active and sessStart == 0 then sessStart = os.clock() end
        if not _active then sessStart = 0 end
    end

    -- Quick nav shortcuts
    local btnRow = Instance.new("Frame", p)
    btnRow.Size = UDim2.new(1,-16,0,28); btnRow.Position = UDim2.new(0,8,0,86)
    btnRow.BackgroundTransparency = 1

    local function navShortcut(label, col, navKey, x, w)
        local b = mkBtn(btnRow, label, col, C.bg, 8.5)
        b.Size = UDim2.new(w,-(x>0 and 2 or 0),1,0)
        b.Position = UDim2.new(x,2,0,0)
        b.MouseButton1Click:Connect(function() switchNav(navKey) end)
        return b
    end
    navShortcut("🎣 Fishing", C.accent, "Fishing", 0,      0.5)
    navShortcut("⛏️ Mining",  C.blue,   "Mining",  0.5,    0.5)

    -- Stat update task
    task.spawn(function()
        while RuntimeController.alive do
            task.wait(1)
            local sc = RuntimeController.sessionCounters
            fishStatL.Text = string.format("Fish: %d confirmed", sc.fishConfirmed)
            mineStatL.Text = string.format("Mine: %d confirmed", sc.mineConfirmed)
            local el = os.clock() - sessStart
            if el > 0 then
                local h,m,s = math.floor(el/3600), math.floor(el%3600/60), math.floor(el%60)
                sessL.Text = string.format("Session: %02d:%02d:%02d", h, m, s)
            end
            local fps = PerformanceMonitor.frameFPS
            perfL.Text = string.format("FPS: %d%s", fps, PerformanceMonitor.performanceSlow and " ⚠️" or "")
        end
    end)

    -- Export updater so mode switches can call it
    panels["Home"]._updateMode = updateHomeMode
end

---------------------------------------------------------------------------
-- 26. FISHING TAB
---------------------------------------------------------------------------
do
    local p = panels["Fishing"]

    -- Status hero
    local stCard = Instance.new("Frame", p)
    stCard.Size = UDim2.new(1,-16,0,62); stCard.Position = UDim2.new(0,8,0,8)
    stCard.BackgroundColor3 = C.bg; stCard.BorderSizePixel = 0
    rnd(stCard,8); mkStroke(stCard,C.border)

    local stDot = Instance.new("Frame", stCard)
    stDot.Size = UDim2.new(0,7,0,7); stDot.Position = UDim2.new(0,10,0,12)
    stDot.BackgroundColor3 = C.muted; stDot.BorderSizePixel = 0; rnd(stDot,4)

    local stateL = mkLbl(stCard, "Idle", 10, Enum.Font.GothamBold, C.txt)
    stateL.Size = UDim2.new(1,-30,0,14); stateL.Position = UDim2.new(0,22,0,8)

    local cntL = mkLbl(stCard, "Confirmed: 0 | Attempts: 0 | Unknown: 0", 8, Enum.Font.Gotham, C.subtxt)
    cntL.Size = UDim2.new(1,-16,0,12); cntL.Position = UDim2.new(0,10,0,27)
    cntL.TextTruncate = Enum.TextTruncate.AtEnd

    local rodSrcL = mkLbl(stCard, "Rod: — (NONE)", 7.5, Enum.Font.Gotham, C.dim)
    rodSrcL.Size = UDim2.new(1,-16,0,12); rodSrcL.Position = UDim2.new(0,10,0,42)

    -- Phase bar
    local phaseCont = Instance.new("Frame", p)
    phaseCont.Size = UDim2.new(1,-16,0,20); phaseCont.Position = UDim2.new(0,8,0,76)
    phaseCont.BackgroundTransparency = 1

    local barBg = Instance.new("Frame", phaseCont)
    barBg.Size = UDim2.new(1,0,0,3); barBg.Position = UDim2.new(0,0,1,-3)
    barBg.BackgroundColor3 = C.border; barBg.BorderSizePixel = 0; rnd(barBg,2)

    local barFill = Instance.new("Frame", barBg)
    barFill.Size = UDim2.new(0,0,1,0); barFill.BackgroundColor3 = C.accent
    barFill.BorderSizePixel = 0; rnd(barFill,2)

    local phNames = {"Cast","Wait","Reel","Done"}
    for i, pn in ipairs(phNames) do
        local pl = Instance.new("TextLabel", phaseCont)
        pl.BackgroundTransparency = 1
        pl.Size = UDim2.new(1/#phNames,0,0,13)
        pl.Position = UDim2.new((i-1)/#phNames,0,0,0)
        pl.Text = pn; pl.Font = Enum.Font.GothamMedium; pl.TextSize = 7.5
        pl.TextColor3 = C.muted; pl.TextXAlignment = Enum.TextXAlignment.Center
    end

    -- Fishing ON/OFF toggle row
    local fishRow = Instance.new("Frame", p)
    fishRow.Size = UDim2.new(1,-16,0,38); fishRow.Position = UDim2.new(0,8,0,102)
    fishRow.BackgroundColor3 = C.bg; fishRow.BorderSizePixel = 0
    rnd(fishRow,8); mkStroke(fishRow,C.border)

    local fLbl = mkLbl(fishRow, "Auto Fishing Engine", 9.5, Enum.Font.GothamBold, C.txt)
    fLbl.Size = UDim2.new(1,-54,0,14); fLbl.Position = UDim2.new(0,10,0,5)
    local fSub = mkLbl(fishRow, "Client-observable state machine", 7.5, Enum.Font.Gotham, C.dim)
    fSub.Size = UDim2.new(1,-54,0,12); fSub.Position = UDim2.new(0,10,0,20)

    local fishSw, _, fishSetFn, fishGetFn = mkSwitch(fishRow, false)
    fishSw.Position = UDim2.new(1,-46,0.5,-10)

    -- Result confidence note
    local confL = mkLbl(p, "Result confidence: UNKNOWN (requires runtime trace)", 7.5, Enum.Font.Gotham, C.dim)
    confL.Size = UDim2.new(1,-16,0,13); confL.Position = UDim2.new(0,8,0,146)
    confL.TextColor3 = C.dim

    -- Reset button
    local rstBtn = mkBtn(p, "Reset", C.bg, C.dim, 8.5)
    rstBtn.Size = UDim2.new(0,80,0,24); rstBtn.Position = UDim2.new(0,8,0,165)
    rstBtn.MouseButton1Click:Connect(function()
        if RuntimeController.currentMode == "FISH" then
            FishingController.reset("manual")
        end
    end)

    -- State machine callbacks → UI
    FishingController.onStateChange(function(s)
        local stateNames = {
            IDLE="Idle", PREPARING="Preparing", EQUIP_ROD="Equipping Rod",
            CASTING="Casting", WAITING_BITE="Waiting Bite", REELING="Reeling",
            RESULT_PENDING="Result Pending", SUCCESS="Caught!",
            FAILED="Failed", COOLDOWN="Cooldown", STOPPING="Stopping"
        }
        stateL.Text = stateNames[s] or s
        -- Update phase bar
        local phMap = { IDLE=0, CASTING=1, WAITING_BITE=2, REELING=3, SUCCESS=4, RESULT_PENDING=3 }
        local ph = phMap[s] or 0
        TS:Create(barFill, TweenInfo.new(0.2,Enum.EasingStyle.Quart),
            {Size=UDim2.new(ph/#phNames,0,1,0)}):Play()
    end)

    FishingController.onCountChange(function(kind, n)
        local sc = RuntimeController.sessionCounters
        cntL.Text = string.format("Confirmed: %d | Attempts: %d | Unknown: %d",
            sc.fishConfirmed, sc.fishAttempts, sc.fishUnknown)
    end)

    -- Rod source updater
    task.spawn(function()
        while RuntimeController.alive do
            task.wait(2)
            if RuntimeController.currentMode == "FISH" then
                local rod = FishingRodProfileProvider.get()
                rodSrcL.Text = string.format("Rod: %s (src: %s)", rod.name, rod.source)
                local sc = RuntimeController.sessionCounters
                cntL.Text = string.format("Confirmed: %d | Attempts: %d | Unknown: %d",
                    sc.fishConfirmed, sc.fishAttempts, sc.fishUnknown)
            end
        end
    end)

    -- Fishing ON/OFF handler
    fishSw.MouseButton1Click:Connect(function()
        if not RuntimeController.alive then return end
        local newVal = fishSw.BackgroundColor3 ~= C.swOn
        fishSetFn(newVal)

        if newVal then
            -- Switch from Mining if needed
            if RuntimeController.currentMode == "MINE" then
                MiningController.stop()
                if panels["Home"]._updateMode then
                    panels["Home"]._updateMode("Idle", C.muted)
                end
            end

            RuntimeController.currentMode = "FISH"
            FishingController.reset("start")
            stateL.Text = "Idle"
            confL.Text = "Result confidence: UNCONFIRMED until runtime trace"
            LOG("FISH", "Fishing ON")
            if panels["Home"]._updateMode then
                panels["Home"]._updateMode("Fishing Active", C.accent)
            end
        else
            RuntimeController.currentMode = "OFF"
            FishingController.stop()
            stateL.Text = "Idle"
            LOG("FISH", "Fishing OFF")
            if panels["Home"]._updateMode then
                panels["Home"]._updateMode("Idle", C.muted)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- 27. MINING TAB
---------------------------------------------------------------------------
do
    local p = panels["Mining"]

    local stCard = Instance.new("Frame", p)
    stCard.Size = UDim2.new(1,-16,0,62); stCard.Position = UDim2.new(0,8,0,8)
    stCard.BackgroundColor3 = C.bg; stCard.BorderSizePixel = 0
    rnd(stCard,8); mkStroke(stCard,C.border)

    local stDot = Instance.new("Frame", stCard)
    stDot.Size = UDim2.new(0,7,0,7); stDot.Position = UDim2.new(0,10,0,12)
    stDot.BackgroundColor3 = C.muted; stDot.BorderSizePixel = 0; rnd(stDot,4)

    local mStateL = mkLbl(stCard, "Idle", 10, Enum.Font.GothamBold, C.txt)
    mStateL.Size = UDim2.new(1,-30,0,14); mStateL.Position = UDim2.new(0,22,0,8)

    local mCntL = mkLbl(stCard, "Confirmed: 0 | Attempts: 0", 8, Enum.Font.Gotham, C.subtxt)
    mCntL.Size = UDim2.new(1,-16,0,12); mCntL.Position = UDim2.new(0,10,0,27)

    local mTgtL = mkLbl(stCard, "Target: —", 7.5, Enum.Font.Gotham, C.dim)
    mTgtL.Size = UDim2.new(1,-16,0,12); mTgtL.Position = UDim2.new(0,10,0,42)

    -- Mining ON/OFF
    local mineRow = Instance.new("Frame", p)
    mineRow.Size = UDim2.new(1,-16,0,38); mineRow.Position = UDim2.new(0,8,0,76)
    mineRow.BackgroundColor3 = C.bg; mineRow.BorderSizePixel = 0
    rnd(mineRow,8); mkStroke(mineRow,C.border)

    local mLbl = mkLbl(mineRow, "Auto Mining Engine", 9.5, Enum.Font.GothamBold, C.txt)
    mLbl.Size = UDim2.new(1,-54,0,14); mLbl.Position = UDim2.new(0,10,0,5)
    local mSub = mkLbl(mineRow, "Target disappears = confirmed mine", 7.5, Enum.Font.Gotham, C.dim)
    mSub.Size = UDim2.new(1,-54,0,12); mSub.Position = UDim2.new(0,10,0,20)

    local mineSw, _, mineSetFn, _ = mkSwitch(mineRow, false)
    mineSw.Position = UDim2.new(1,-46,0.5,-10)

    -- Callbacks
    MiningController.onStateChange(function(s)
        mStateL.Text = s
        local target = MiningController.getCurrentTarget()
        if target and target.Parent then
            mTgtL.Text = "Target: " .. target.Name
        else
            mTgtL.Text = "Target: —"
        end
    end)

    MiningController.onCountChange(function(kind, n)
        local sc = RuntimeController.sessionCounters
        mCntL.Text = string.format("Confirmed: %d | Attempts: %d", sc.mineConfirmed, sc.mineAttempts)
    end)

    -- Periodic target info updater
    task.spawn(function()
        while RuntimeController.alive do
            task.wait(1.5)
            if RuntimeController.currentMode == "MINE" then
                local sc = RuntimeController.sessionCounters
                mCntL.Text = string.format("Confirmed: %d | Attempts: %d", sc.mineConfirmed, sc.mineAttempts)
                local tgt = MiningController.getCurrentTarget()
                if tgt and tgt.Parent then
                    local ch = me.Character
                    local myP = ch and ch.PrimaryPart and ch.PrimaryPart.Position
                    local dist = myP and string.format("%.0f", (tgt.Position-myP).Magnitude) or "?"
                    mTgtL.Text = string.format("Target: %s | dist: %s", tgt.Name, dist)
                else
                    mTgtL.Text = "Target: —"
                end
            end
        end
    end)

    mineSw.MouseButton1Click:Connect(function()
        if not RuntimeController.alive then return end
        local newVal = mineSw.BackgroundColor3 ~= C.swOn
        mineSetFn(newVal)

        if newVal then
            -- Switch from Fishing if needed
            if RuntimeController.currentMode == "FISH" then
                RuntimeController.currentMode = "OFF"
                FishingController.stop()
            end

            RuntimeController.currentMode = "MINE"
            MiningTargetResolver.invalidateCache()
            MiningController.run()
            mStateL.Text = "Scanning"
            LOG("MINE", "Mining ON")
            if panels["Home"]._updateMode then
                panels["Home"]._updateMode("Mining Active", C.blue)
            end
        else
            RuntimeController.currentMode = "OFF"
            MiningController.stop()
            mStateL.Text = "Idle"
            LOG("MINE", "Mining OFF")
            if panels["Home"]._updateMode then
                panels["Home"]._updateMode("Idle", C.muted)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- 28. AVATAR TAB
---------------------------------------------------------------------------
do
    local p = panels["Avatar"]

    -- Player dropdown
    local dropLabel = mkLbl(p, "SELECT TARGET PLAYER", 7, Enum.Font.GothamBold, C.dim)
    dropLabel.Size = UDim2.new(1,-16,0,12); dropLabel.Position = UDim2.new(0,8,0,8)

    local dropFrame = Instance.new("Frame", p)
    dropFrame.Size = UDim2.new(1,-16,0,120); dropFrame.Position = UDim2.new(0,8,0,24)
    dropFrame.BackgroundColor3 = C.bg; dropFrame.BorderSizePixel = 0
    rnd(dropFrame,7); mkStroke(dropFrame,C.border)

    local dropSF = Instance.new("ScrollingFrame", dropFrame)
    dropSF.Size = UDim2.new(1,0,1,0); dropSF.BackgroundTransparency = 1
    dropSF.BorderSizePixel = 0; dropSF.ScrollBarThickness = 2
    dropSF.ScrollBarImageColor3 = C.border; dropSF.CanvasSize = UDim2.new(0,0,0,0)

    local dropLL = Instance.new("UIListLayout", dropSF)
    dropLL.SortOrder = Enum.SortOrder.LayoutOrder; dropLL.Padding = UDim.new(0,2)

    local function buildPlayerList()
        for _, ch in ipairs(dropSF:GetChildren()) do
            if ch:IsA("TextButton") then ch:Destroy() end
        end
        local plist = PlayerController.getPlayers()
        for i, pl in ipairs(plist) do
            if pl ~= me then
                local b = Instance.new("TextButton", dropSF)
                b.LayoutOrder = i
                b.Size = UDim2.new(1,-4,0,26)
                b.BackgroundColor3 = C.card; b.BorderSizePixel = 0; rnd(b,5)
                b.Text = pl.DisplayName .. " (@" .. pl.Name .. ")"
                b.TextColor3 = C.txt; b.Font = Enum.Font.GothamMedium; b.TextSize = 9
                b.AutoButtonColor = false
                b.MouseButton1Click:Connect(function()
                    AvatarController.setTarget(pl)
                    for _, sib in ipairs(dropSF:GetChildren()) do
                        if sib:IsA("TextButton") then
                            sib.BackgroundColor3 = C.card
                        end
                    end
                    b.BackgroundColor3 = C.accent:Lerp(C.bg, 0.7)
                    LOG("AVATAR", "Selected target: @" .. pl.Name)
                end)
            end
        end
        local canv = math.max(dropLL.AbsoluteContentSize.Y + 4, 0)
        dropSF.CanvasSize = UDim2.new(0,0,0,canv)
    end

    buildPlayerList()

    local refreshBtn = mkBtn(p, "↻ Refresh", C.card, C.dim, 8.5)
    refreshBtn.Size = UDim2.new(0,80,0,24); refreshBtn.Position = UDim2.new(1,-88,0,150)
    refreshBtn.MouseButton1Click:Connect(function() buildPlayerList() end)

    -- Status
    local aStatusL = mkLbl(p, "Status: Ready", 9, Enum.Font.GothamMedium, C.subtxt)
    aStatusL.Size = UDim2.new(1,-16,0,14); aStatusL.Position = UDim2.new(0,8,0,154)

    AvatarController.onStatus(function(s)
        aStatusL.Text = "Status: " .. s
    end)

    -- Action buttons row
    local btnRow = Instance.new("Frame", p)
    btnRow.Size = UDim2.new(1,-16,0,28); btnRow.Position = UDim2.new(0,8,0,174)
    btnRow.BackgroundTransparency = 1

    local copyBtn = mkBtn(btnRow, "Copy Avatar", C.accent, C.bg, 9)
    copyBtn.Size = UDim2.new(0.48,0,1,0); copyBtn.Position = UDim2.new(0,0,0,0)
    copyBtn.MouseButton1Click:Connect(function()
        if not RuntimeController.alive then return end
        AvatarController.copyAvatar()
    end)

    local restoreBtn = mkBtn(btnRow, "Restore Original", C.card, C.dim, 9)
    restoreBtn.Size = UDim2.new(0.48,0,1,0); restoreBtn.Position = UDim2.new(0.52,0,0,0)
    restoreBtn.MouseButton1Click:Connect(function()
        if not RuntimeController.alive then return end
        AvatarController.restoreOriginal()
    end)

    -- Spectate row
    local specRow = Instance.new("Frame", p)
    specRow.Size = UDim2.new(1,-16,0,28); specRow.Position = UDim2.new(0,8,0,208)
    specRow.BackgroundTransparency = 1

    local specBtn = mkBtn(specRow, "Spectate", C.card, C.dim, 9)
    specBtn.Size = UDim2.new(0.48,0,1,0)
    specBtn.MouseButton1Click:Connect(function()
        local target = AvatarController._getTarget and AvatarController._getTarget() or nil
        -- Use the last-selected target via AvatarController
        -- We look it up via PlayerController
        local plName = AvatarController.getTargetName()
        for _, pl in ipairs(PlayerController.getPlayers()) do
            if ("@" .. pl.Name) == plName:match("%((.-)%)") then
                PlayerController.spectate(pl)
                return
            end
        end
        -- Try any selected player
        for _, pl in ipairs(PlayerController.getPlayers()) do
            if pl ~= me then PlayerController.spectate(pl); return end
        end
    end)

    local stopSpecBtn = mkBtn(specRow, "Stop Spectate", C.card, C.dim, 9)
    stopSpecBtn.Size = UDim2.new(0.48,0,1,0); stopSpecBtn.Position = UDim2.new(0.52,0,0,0)
    stopSpecBtn.MouseButton1Click:Connect(function()
        PlayerController.stopSpectate()
    end)

    -- XYZ copy
    local xyzBtn = mkBtn(p, "Copy XYZ to Clipboard", C.card, C.dim, 8.5)
    xyzBtn.Size = UDim2.new(1,-16,0,24); xyzBtn.Position = UDim2.new(0,8,0,242)
    if not Capabilities.clipboard then
        xyzBtn.TextColor3 = C.muted
        xyzBtn.Text = "Copy XYZ (unavailable)"
    end
    xyzBtn.MouseButton1Click:Connect(function()
        PlayerController.copyXYZToClipboard()
    end)

    p.CanvasSize = UDim2.new(0,0,0,278)
end

---------------------------------------------------------------------------
-- 29. SPOTS TAB
---------------------------------------------------------------------------
do
    local p = panels["Spots"]

    local spCntL = mkLbl(p, "0 / 10 spots", 8.5, Enum.Font.GothamMedium, C.dim)
    spCntL.Size = UDim2.new(1,-16,0,14); spCntL.Position = UDim2.new(0,8,0,8)
    spCntL.TextXAlignment = Enum.TextXAlignment.Center

    local nameBox = Instance.new("TextBox", p)
    nameBox.Size = UDim2.new(1,-84,0,28); nameBox.Position = UDim2.new(0,8,0,26)
    nameBox.BackgroundColor3 = C.bg; nameBox.TextColor3 = C.txt
    nameBox.PlaceholderText = "New spot name..."; nameBox.PlaceholderColor3 = C.muted
    nameBox.Text = ""; nameBox.ClearTextOnFocus = false
    nameBox.Font = Enum.Font.Gotham; nameBox.TextSize = 9
    nameBox.TextXAlignment = Enum.TextXAlignment.Left; nameBox.BorderSizePixel = 0
    rnd(nameBox,7); mkStroke(nameBox,C.border)
    Instance.new("UIPadding",nameBox).PaddingLeft = UDim.new(0,8)

    local saveSpotBtn = mkBtn(p, "Save", C.accent, C.bg, 9)
    saveSpotBtn.Size = UDim2.new(0,64,0,28); saveSpotBtn.Position = UDim2.new(1,-72,0,26)

    local spSF = Instance.new("ScrollingFrame", p)
    spSF.Size = UDim2.new(1,-16,1,-62); spSF.Position = UDim2.new(0,8,0,60)
    spSF.BackgroundTransparency = 1; spSF.BorderSizePixel = 0
    spSF.CanvasSize = UDim2.new(0,0,0,0); spSF.ScrollBarThickness = 2
    spSF.ScrollBarImageColor3 = C.border
    local spLL = Instance.new("UIListLayout",spSF)
    spLL.SortOrder = Enum.SortOrder.LayoutOrder; spLL.Padding = UDim.new(0,4)

    local function spawnPlat(pos)
        pcall(function()
            local old = workspace:FindFirstChild("_idh_plat"); if old then old:Destroy() end
            local pt = Instance.new("Part")
            pt.Name = "_idh_plat"; pt.Anchored = true; pt.CanCollide = true
            pt.Size = Vector3.new(14,1,14); pt.Position = pos-Vector3.new(0,3.2,0)
            pt.Material = Enum.Material.SmoothPlastic; pt.Transparency = 0.7
            pt.Color = Color3.fromRGB(100,80,40); pt.Parent = workspace
        end)
    end

    local function doTeleport(pos)
        local ch   = me.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if not root then return end
        spawnPlat(pos); task.wait(0.08); root.CFrame = CFrame.new(pos)
        LOG("SPOTS", "Teleported to " .. tostring(pos))
    end

    local renderSpots
    renderSpots = function()
        for _, ch in ipairs(spSF:GetChildren()) do
            if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
        end
        local all = SpotManager.getAll()
        spCntL.Text = #all .. " / 10 spots"
        if #all == 0 then
            local none = Instance.new("TextLabel", spSF)
            none.LayoutOrder = 0; none.BackgroundTransparency = 1
            none.Size = UDim2.new(1,0,0,40)
            none.Text = "No spots saved yet"; none.TextColor3 = C.muted
            none.Font = Enum.Font.Gotham; none.TextSize = 8.5
            none.TextXAlignment = Enum.TextXAlignment.Center
            return
        end
        for i, sp in ipairs(all) do
            local row = Instance.new("Frame", spSF)
            row.LayoutOrder = i; row.Size = UDim2.new(1,0,0,34)
            row.BackgroundColor3 = C.bg; row.BorderSizePixel = 0
            rnd(row,7); mkStroke(row,C.border)
            local nLbl = mkLbl(row, sp.name, 9, Enum.Font.GothamBold, C.txt)
            nLbl.Size = UDim2.new(1,-95,1,0); nLbl.Position = UDim2.new(0,8,0,0)
            local goBtn = mkBtn(row, "Go", C.accent, C.bg, 8.5)
            goBtn.Size = UDim2.new(0,36,0,22); goBtn.Position = UDim2.new(1,-84,0.5,-11)
            local delBtn = mkBtn(row, "Del", C.card, C.dim, 8.5)
            delBtn.Size = UDim2.new(0,36,0,22); delBtn.Position = UDim2.new(1,-44,0.5,-11)
            mkStroke(delBtn,C.border)

            local ci = i
            local pos = SpotManager.getPosition(sp)
            if pos then
                goBtn.MouseButton1Click:Connect(function() doTeleport(pos) end)
            else
                goBtn.TextColor3 = C.muted
            end
            delBtn.MouseButton1Click:Connect(function()
                SpotManager.remove(ci); renderSpots()
            end)
        end
        spSF.CanvasSize = UDim2.new(0,0,0,#all*38+4)
    end
    renderSpots()

    saveSpotBtn.MouseButton1Click:Connect(function()
        local nm = nameBox.Text:match("^%s*(.-)%s*$")
        local ch = me.Character; local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local ok, err = SpotManager.add(nm, root.Position)
        if ok then
            nameBox.Text = ""; renderSpots()
        else
            LOG("SPOTS", "Save failed: " .. tostring(err))
        end
    end)
end

---------------------------------------------------------------------------
-- 30. SETTINGS TAB
---------------------------------------------------------------------------
do
    local p = panels["Settings"]
    p.CanvasSize = UDim2.new(0,0,0,240)

    local y = 8
    local function sec(label)
        local l = mkLbl(p, label, 7, Enum.Font.GothamBold, C.dim)
        l.Size = UDim2.new(1,-16,0,12); l.Position = UDim2.new(0,8,0,y)
        y = y + 14
    end

    sec("FISHING")
    mkToggleRow(p, y, "Fatigue Break", "Pause every " .. CFG.fishing.fatigueEvery .. " attempts",
        false, function(v)
            if not v then FishingController._fatCount = 0 end
        end); y = y + 40

    sec("MINING")
    mkToggleRow(p, y, "Smooth Movement", "Slightly slower path following",
        true, function(v)
            -- toggleable no-op; pathfinding always enabled
        end); y = y + 40

    sec("SIMULATION (testing only, default OFF)")
    mkToggleRow(p, y, "Timing Jitter", "±10% variation in timing (test only)",
        false, function(v)
            -- simulation variation label – not anti-detection
        end); y = y + 40
    mkToggleRow(p, y, "Coord Jitter", "±12px variation in coordinates (test only)",
        false, function(v) end); y = y + 40

    sec("UTILITIES")
    mkToggleRow(p, y, "Anti-AFK Mouse Sweep", "Periodic mouse move to prevent idle kick",
        false, function(v)
            -- handled below in AFK loop
        end); y = y + 40

    p.CanvasSize = UDim2.new(0,0,0,y+10)
end

---------------------------------------------------------------------------
-- 31. DIAGNOSTICS TAB
---------------------------------------------------------------------------
do
    local p = panels["Diag"]

    local diagLbl = mkLbl(p, "DIAGNOSTICS", 7, Enum.Font.GothamBold, C.dim)
    diagLbl.Size = UDim2.new(1,-16,0,12); diagLbl.Position = UDim2.new(0,8,0,8)

    local diagSF = Instance.new("ScrollingFrame", p)
    diagSF.Size = UDim2.new(1,-16,1,-32); diagSF.Position = UDim2.new(0,8,0,24)
    diagSF.BackgroundColor3 = C.bg; diagSF.BorderSizePixel = 0
    rnd(diagSF,7); mkStroke(diagSF,C.border)
    diagSF.CanvasSize = UDim2.new(0,0,0,0); diagSF.ScrollBarThickness = 2
    diagSF.ScrollBarImageColor3 = C.border

    local diagLL = Instance.new("UIListLayout",diagSF)
    diagLL.SortOrder = Enum.SortOrder.LayoutOrder; diagLL.Padding = UDim.new(0,1)

    local do_inst = Instance.new("UIPadding", diagSF)
    do_inst.PaddingLeft = UDim.new(0,6); do_inst.PaddingTop = UDim.new(0,4)

    local function diagLine(text, color)
        local l = Instance.new("TextLabel", diagSF)
        l.BackgroundTransparency = 1; l.Size = UDim2.new(1,-8,0,13)
        l.Text = text; l.TextColor3 = color or C.dim
        l.Font = Enum.Font.Code; l.TextSize = 8.5
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = false
        return l
    end

    local diagLines = {}
    local function buildDiag()
        for _, l in ipairs(diagLines) do pcall(function() l:Destroy() end) end
        diagLines = {}
        local function add(s, col)
            diagLines[#diagLines+1] = diagLine(s, col)
        end

        local sc = RuntimeController.sessionCounters
        local rod = FishingRodProfileProvider.get()

        add("── Runtime ──", C.dim)
        add("Mode: " .. RuntimeController.currentMode, C.subtxt)
        add("Alive: " .. tostring(RuntimeController.alive), C.subtxt)
        add(string.format("FPS: %d | frameTime: %.1fms | slow: %s",
            PerformanceMonitor.frameFPS,
            PerformanceMonitor.frameTime * 1000,
            tostring(PerformanceMonitor.performanceSlow)), C.subtxt)

        add("── Fishing ──", C.dim)
        add("State: " .. FishingController.getState(), C.subtxt)
        add(string.format("Confirmed: %d | Attempts: %d | Unknown: %d | Failed: %d",
            sc.fishConfirmed, sc.fishAttempts, sc.fishUnknown, sc.fishFailed), C.subtxt)
        add("Rod: " .. rod.name .. " | Source: " .. rod.source, C.subtxt)
        add("FishingUIAdapter: WBar=" .. tostring(FishingUIAdapter.getWhiteBar() ~= nil)
            .. " RBar=" .. tostring(FishingUIAdapter.getRedBar() ~= nil)
            .. " PBar=" .. tostring(FishingUIAdapter.getProgressBar() ~= nil), C.subtxt)

        local trace = FishingResultObserver.getTrace()
        add("── Fishing Trace ──", C.dim)
        add("Result Reason: " .. tostring(trace.lastFishingResultReason), C.subtxt)
        add("Result State: " .. tostring(trace.lastFishingResultState), C.subtxt)
        add(string.format("Last Progress: %.1f%%", (trace.lastFishingProgress or 0) * 100), C.subtxt)
        local guiOpenStr = trace.lastFishingGuiOpenedAt > 0 and string.format("%.1fs ago", os.clock() - trace.lastFishingGuiOpenedAt) or "Never"
        local guiCloseStr = trace.lastFishingGuiClosedAt > 0 and string.format("%.1fs ago", os.clock() - trace.lastFishingGuiClosedAt) or "Never"
        add("GUI Opened: " .. guiOpenStr .. " | Closed: " .. guiCloseStr, C.subtxt)
        add("Tool State: " .. tostring(trace.lastFishingToolState), C.subtxt)

        add("── Mining ──", C.dim)
        add("State: " .. MiningController.getState(), C.subtxt)
        add(string.format("Confirmed: %d | Attempts: %d | Failed: %d",
            sc.mineConfirmed, sc.mineAttempts, sc.mineFailed), C.subtxt)
        local tgt = MiningController.getCurrentTarget()
        add("Target: " .. (tgt and (tgt.Name .. " [" .. tgt.ClassName .. "]") or "—") .. " | Locked: " .. tostring(MiningController.isLocked()), C.subtxt)
        add("Cache entries: " .. #MiningTargetResolver.getCache()
            .. " | age: " .. string.format("%.1f", MiningTargetResolver.getCacheAge()) .. "s", C.subtxt)

        add("── Avatar ──", C.dim)
        add("Status: " .. AvatarController.getStatus(), C.subtxt)
        add("Spectating: " .. tostring(PlayerController.isSpectating()), C.subtxt)

        add("── Capabilities ──", C.dim)
        add("fileIO="  .. tostring(Capabilities.fileIO)
            .. " clipboard=" .. tostring(Capabilities.clipboard)
            .. " httpReq="  .. tostring(Capabilities.httpReq), C.subtxt)
        add("VIM=" .. tostring(Capabilities.vim)
            .. " VU=" .. tostring(Capabilities.vu), C.subtxt)

        add("── Spots ──", C.dim)
        add("Loaded: " .. #SpotManager.getAll() .. " spots", C.subtxt)

        add("── Log (last 5) ──", C.dim)
        local logLines = Logger.getLines()
        local start = math.max(1, #logLines - 4)
        for i = start, #logLines do
            add(logLines[i] or "", C.muted)
        end

        diagSF.CanvasSize = UDim2.new(0,0,0, diagLL.AbsoluteContentSize.Y + 8)
    end

    -- Auto-refresh diagnostics tab when visible
    task.spawn(function()
        while RuntimeController.alive do
            task.wait(2)
            if panels["Diag"].Visible then
                pcall(buildDiag)
            end
        end
    end)

    buildDiag()
end

---------------------------------------------------------------------------
-- 32. ANTI-AFK (optional, off by default)
---------------------------------------------------------------------------
local _antiAFK = false
task.spawn(function()
    while RuntimeController.alive do
        task.wait(math.random(90, 150))
        if not RuntimeController.alive then break end
        if _antiAFK and Capabilities.vu then
            pcall(function()
                local cam = workspace.CurrentCamera; if not cam then return end
                local sz  = cam.ViewportSize
                VU:MouseMoveEvent(
                    Vector2.new(sz.X/2+math.random(-55,55), sz.Y/2+math.random(-40,40)),
                    cam.CFrame)
            end)
        end
    end
end)

RuntimeController.trackConnection(
    me.Idled:Connect(function()
        if not _antiAFK or not Capabilities.vu then return end
        pcall(function()
            local cam = workspace.CurrentCamera; if not cam then return end
            VU:Button2Down(Vector2.new(0,0), cam.CFrame)
            task.wait(0.1)
            VU:Button2Up(Vector2.new(0,0), cam.CFrame)
        end)
    end)
)

---------------------------------------------------------------------------
-- 33. CHARACTER ADDED – clean state restoration
---------------------------------------------------------------------------
RuntimeController.trackConnection(
    me.CharacterAdded:Connect(function(char)
        -- Restore all states on respawn
        FishingInputManager.releaseAll()
        CharacterState.setJumpEnabled(true)
        CharacterState.save(char)   -- save new character's initial state
        FishingUIAdapter.invalidate()
        MiningTargetResolver.invalidateCache()

        -- If fishing was active, reset state machine
        if RuntimeController.currentMode == "FISH" then
            FishingController.reset("respawn")
        end

        -- If mining was active, stop movement
        if RuntimeController.currentMode == "MINE" then
            MiningController.stop()
            task.wait(3)  -- wait for respawn
            if RuntimeController.currentMode == "MINE" then
                MiningController.run()
            end
        end

        LOG("RUNTIME", "CharacterAdded – state restored")
    end)
)

---------------------------------------------------------------------------
-- 34. GUI DESTROY ON RUNTIME CLEANUP
---------------------------------------------------------------------------
local _origDestroy = RuntimeController.destroy
RuntimeController.destroy = function()
    _origDestroy()
    pcall(function()
        if gui and gui.Parent then gui:Destroy() end
    end)
end

---------------------------------------------------------------------------
-- 35. STARTUP LOG
---------------------------------------------------------------------------
LOG("RUNTIME", "NasiHub v3.0 started")
LOG("RUNTIME", string.format(
    "Capabilities: fileIO=%s clipboard=%s VIM=%s VU=%s",
    tostring(Capabilities.fileIO),
    tostring(Capabilities.clipboard),
    tostring(Capabilities.vim),
    tostring(Capabilities.vu)
))
LOG("FISH", "Fishing result: UNCONFIRMED (bar-gone, tool-deactivate, timeout do not count as confirmed success).")
LOG("MINE", "Mine confirmed ONLY when target instance legitimately disappears after swing cycle.")
LOG("MINE", "CRYS_OK name matching is fallback-only (priority 5 of 5). CollectionService tags and Attributes take priority.")
