-- ┌──────────────────────────────────────────────────┐
-- │   Nazhan Fish  v2.0  •  by nazhan               │
-- │   auto fishing | custom spot | webhook notif    │
-- └──────────────────────────────────────────────────┘

if shared._nzh2 then pcall(shared._nzh2.stop) end

-- ── Services ────────────────────────────────────────
local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local VIM     = game:GetService("VirtualInputManager")
local VU      = game:GetService("VirtualUser")
local TS      = game:GetService("TweenService")
local HTTP    = game:GetService("HttpService")
local me      = Players.LocalPlayer

-- ── Rod Profiles ────────────────────────────────────
local RODS = {
	{ n="Basic Rod",   lure=1.00, prog=1.00 }, { n="Party Rod",   lure=1.30, prog=1.08 },
	{ n="Shark Rod",   lure=1.57, prog=1.21 }, { n="Piranha Rod", lure=1.84, prog=1.33 },
	{ n="Thermo Rod",  lure=2.11, prog=1.46 }, { n="Flowers Rod", lure=2.38, prog=1.59 },
	{ n="Trisula Rod", lure=2.65, prog=1.72 }, { n="Feather Rod", lure=2.92, prog=1.84 },
	{ n="Wave Rod",    lure=3.19, prog=1.97 }, { n="Duck Rod",    lure=3.46, prog=2.10 },
	{ n="Planet Rod",  lure=3.73, prog=2.23 }, { n="Earth Rod",   lure=4.00, prog=2.35 },
	{ n="Volcano Rod", lure=4.27, prog=2.48 },
}
local rodIdx = 1

-- ── Timing & Feature Config ──────────────────────────
local CFG = {
	castHold         = 1.8,
	biteWait         = 15.0,
	recastDly        = 0.9,
	jitter           = false,
	coordJitter      = false,
	fatigueOn        = true,
	fatEvery         = 25,
	fatDur           = 8,
	antiAFK          = false,
	watchdog         = true,
	netAdapt         = true,
	autoRejoin       = false,
}

local FISH_TOOLS = { "Fishing Rod", "Rod", "Pancing", "FishingRod" }

-- ── State ───────────────────────────────────────────
local active      = false
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
local castSess    = 0
local idleAt      = os.clock()
local fishCount   = 0
local sessStart   = os.clock()
local fatCnt      = 0
local lastAFKPos  = nil

-- Performance monitor — rolling average frame time
local frameAvg    = 0.016
local frameSmooth = 0.08
local function updateFrameTime(dt)
	frameAvg = frameAvg * (1 - frameSmooth) + dt * frameSmooth
end
local function frameSlow()
	return CFG.netAdapt and frameAvg > 0.05
end

-- Discord Webhook
local webhookURL = ""
local webhookOn  = false

-- ── Custom Spots ────────────────────────────────────
local SPOTS_FILE = "nzh_spots.json"
local spots      = {}
local MAX_SPOTS  = 10

local function saveSpots()
	pcall(function()
		if writefile then writefile(SPOTS_FILE, HTTP:JSONEncode(spots)) end
	end)
end

local function loadSpots()
	pcall(function()
		if isfile and readfile and isfile(SPOTS_FILE) then
			local ok, data = pcall(HTTP.JSONDecode, HTTP, readfile(SPOTS_FILE))
			if ok and type(data) == "table" then spots = data end
		end
	end)
end
loadSpots()

-- ── Helpers ─────────────────────────────────────────
local function safe(fn) xpcall(fn, function(e) warn("[NF] "..tostring(e)) end) end

local function jt(base, p)
	if not CFG.jitter then return base end
	return base * (1 + (math.random() * 2 - 1) * (p or 0.09))
end

local function jv(v2)
	if not CFG.coordJitter then return v2 end
	return Vector2.new(v2.X + math.random(-12, 12), v2.Y + math.random(-8, 8))
end

local function setJumpSuppressed(suppressed)
	pcall(function()
		local ch = me.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:SetStateEnabled(
				Enum.HumanoidStateType.Jumping,
				not suppressed
			)
		end
	end)
end

local function restoreCharacterState()
	isSpace = false
	isCasting = false

	pcall(function()
		VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
		VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
	end)

	setJumpSuppressed(false)
end

-- ── Forward Declarations ─────────────────────────────
local doReset
local addLog
local updateRodUI
local gui

-- ── Script Lifecycle Controller ──────────────────────
local _S = { alive = true, c = {} }
_S.stop = function()
	_S.alive = false
	active = false
	castSess = castSess + 1
	restoreCharacterState()

	for _, v in ipairs(_S.c) do pcall(function() v:Disconnect() end) end
	table.clear(_S.c)

	pcall(function()
		local pt = workspace:FindFirstChild("_nzh_p")
		if pt then pt:Destroy() end
		if gui and gui.Parent then gui:Destroy() end
	end)
end
shared._nzh2 = _S

-- ── Webhook ─────────────────────────────────────────
local function sendWebhook(title, body, colorInt)
	if not webhookOn or webhookURL == "" then return end
	if not webhookURL:find("discord%.com/api/webhooks") then return end
	task.spawn(function()
		local el   = active and (os.clock() - sessStart) or 0
		local h, m, s = math.floor(el/3600), math.floor(el%3600/60), math.floor(el%60)
		local rod  = RODS[rodIdx]
		local ok, payload = pcall(HTTP.JSONEncode, HTTP, {
			embeds = {{
				title       = title,
				description = body,
				color       = colorInt or 0xb49352,
				fields      = {
					{ name = "Tangkapan",  value = tostring(fishCount),
					  inline = true },
					{ name = "Durasi",
					  value = string.format("%02d:%02d:%02d", h, m, s),
					  inline = true },
					{ name = "Rod",  value = rod and rod.n or "—", inline = true },
				},
				footer = { text = "NasiHub v2.0" },
			}},
		})
		if not ok then return end
		local req = (syn and syn.request) or (http and http.request) or http_request or request
		if req then
			pcall(req, {
				Url     = webhookURL, Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body    = payload,
			})
		end
	end)
end

-- ── GUI Cleanup ──────────────────────────────────────
pcall(function()
	local cg = game:GetService("CoreGui")
	for _, n in ipairs({ "_NZH2", "_NZH_UI", "NH_v9_GUI", "IH_v5", "NH_v6_GUI" }) do
		local a = cg:FindFirstChild(n); if a then a:Destroy() end
		if me.PlayerGui then
			local b = me.PlayerGui:FindFirstChild(n); if b then b:Destroy() end
		end
	end
end)

task.wait(0.05)

-- ── ScreenGui ───────────────────────────────────────
gui = Instance.new("ScreenGui")
gui.Name           = "_NZH2"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 25
gui.IgnoreGuiInset = false
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = me:WaitForChild("PlayerGui")
end

-- ── Palette: NasiHub Modern Dark + Crimson Coral Accent
local C = {
	bg        = Color3.fromRGB(15,  15,  18),
	card      = Color3.fromRGB(22,  22,  27),
	cardHover = Color3.fromRGB(28,  28,  35),
	border    = Color3.fromRGB(38,  38,  46),
	borderHi  = Color3.fromRGB(55,  55,  68),
	accent    = Color3.fromRGB(225,  48,  48),
	gold      = Color3.fromRGB(225,  48,  48),
	txt       = Color3.fromRGB(240, 240, 246),
	subtxt    = Color3.fromRGB(170, 170, 185),
	dim       = Color3.fromRGB(115, 115, 130),
	muted     = Color3.fromRGB( 65,  65,  78),
	navActive = Color3.fromRGB( 25,  25,  32),
	swOn      = Color3.fromRGB(225,  48,  48),
	swOff     = Color3.fromRGB( 40,  40,  48),
}

-- ── GUI Builder Helpers ──────────────────────────────
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
	l.TextSize       = size or 10.5
	l.Font           = font or Enum.Font.GothamMedium
	l.TextColor3     = color or C.txt
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate   = Enum.TextTruncate.AtEnd
	l.Size           = UDim2.new(1, 0, 0, size and size + 4 or 15)
	return l
end

local function mkBtn(parent, text, bg, tc, textSize)
	local b = Instance.new("TextButton", parent)
	b.BackgroundColor3 = bg or C.card
	b.Text             = text or ""
	b.TextColor3       = tc or C.txt
	b.Font             = Enum.Font.GothamBold
	b.TextSize         = textSize or 10
	b.BorderSizePixel  = 0
	b.AutoButtonColor  = false
	rnd(b, 6)
	mkStroke(b, C.border, 1)

	local orig = b.BackgroundColor3
	local hi   = orig:Lerp(C.accent, 0.16)
	b.MouseEnter:Connect(function()
		TS:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = hi}):Play()
	end)
	b.MouseLeave:Connect(function()
		TS:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = orig}):Play()
	end)
	return b
end

local function mkToggle(parent, y, labelText, subText, defVal, callback)
	local row = Instance.new("Frame", parent)
	row.Size              = UDim2.new(1, -16, 0, 36)
	row.Position          = UDim2.new(0, 8, 0, y)
	row.BackgroundColor3  = C.card
	row.BorderSizePixel   = 0
	rnd(row, 8)
	mkStroke(row, C.border)

	local lbl = mkLbl(row, labelText, 9.5, Enum.Font.GothamBold, C.txt)
	lbl.Size     = UDim2.new(1, -54, 0, 14)
	lbl.Position = UDim2.new(0, 10, 0, subText and 4 or 10)

	if subText then
		local sub = mkLbl(row, subText, 7.5, Enum.Font.Gotham, C.dim)
		sub.Size     = UDim2.new(1, -54, 0, 12)
		sub.Position = UDim2.new(0, 10, 0, 19)
	end

	local sw = Instance.new("TextButton", row)
	sw.Size              = UDim2.new(0, 36, 0, 20)
	sw.Position          = UDim2.new(1, -46, 0.5, -10)
	sw.BackgroundColor3  = defVal and C.swOn or C.swOff
	sw.Text              = ""
	sw.BorderSizePixel   = 0
	sw.AutoButtonColor   = false
	rnd(sw, 10)

	local knob = Instance.new("Frame", sw)
	knob.Size              = UDim2.new(0, 16, 0, 16)
	knob.Position          = defVal and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
	knob.BackgroundColor3  = C.txt
	knob.BorderSizePixel   = 0
	rnd(knob, 8)

	local val = defVal
	sw.MouseButton1Click:Connect(function()
		if not _S.alive then return end
		val = not val
		TS:Create(sw,   TweenInfo.new(0.12), {BackgroundColor3 = val and C.swOn or C.swOff}):Play()
		TS:Create(knob, TweenInfo.new(0.12), {
			Position = val and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
		}):Play()
		callback(val)
	end)
	return sw
end

-- ══════════════════════════════════════════════════
-- LAYOUT: NasiHub Modern Floating Hub
-- Window 440x310 | Sidebar 125px | Content 315px
-- ══════════════════════════════════════════════════
local main = Instance.new("Frame", gui)
main.Size             = UDim2.new(0, 440, 0, 310)
main.Position         = UDim2.new(1, -455, 0.5, -155)
main.BackgroundColor3 = C.bg
main.BackgroundTransparency = 0
main.BorderSizePixel  = 0
main.Active           = true
main.Draggable        = true
rnd(main, 12)
mkStroke(main, C.border, 1)

local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size             = UDim2.new(0, 38, 0, 38)
floatBtn.Position         = UDim2.new(1, -48, 0.5, -19)
floatBtn.BackgroundColor3 = C.card
floatBtn.Text             = "NH"
floatBtn.TextColor3       = C.accent
floatBtn.Font             = Enum.Font.GothamBold
floatBtn.TextSize         = 11
floatBtn.BorderSizePixel  = 0
floatBtn.Active           = true
floatBtn.Draggable        = true
floatBtn.Visible          = false
rnd(floatBtn, 19)
mkStroke(floatBtn, C.border, 1)

-- ─ TOP BAR ──────────────────────────────────────────────────
local topBar = Instance.new("Frame", main)
topBar.Size             = UDim2.new(1, 0, 0, 38)
topBar.BackgroundColor3 = C.bg
topBar.BorderSizePixel  = 0

do
	local td = Instance.new("Frame", topBar)
	td.Size=UDim2.new(1,0,0,1); td.Position=UDim2.new(0,0,1,-1)
	td.BackgroundColor3=C.border; td.BorderSizePixel=0
end

local function mkDot(x,col)
	local d=Instance.new("Frame",topBar)
	d.Size=UDim2.new(0,9,0,9); d.Position=UDim2.new(0,x,0.5,-4.5)
	d.BackgroundColor3=col; d.BorderSizePixel=0; rnd(d,5)
end
mkDot(12, Color3.fromRGB(255, 95, 87))
mkDot(26, Color3.fromRGB(254,188, 47))
mkDot(40, Color3.fromRGB( 40,200, 64))

local hubN=mkLbl(topBar,"NasiHub",11.5,Enum.Font.GothamBold,C.txt)
hubN.Size=UDim2.new(0,80,0,16); hubN.Position=UDim2.new(0,58,0,5)

local hubS=mkLbl(topBar,"Auto Fishing",8,Enum.Font.GothamMedium,C.dim)
hubS.Size=UDim2.new(0,80,0,12); hubS.Position=UDim2.new(0,58,0,21)

local verBadge=mkBtn(topBar,"v2.0",C.card,C.dim,8)
verBadge.Size=UDim2.new(0,42,0,18); verBadge.Position=UDim2.new(0,146,0.5,-9)
rnd(verBadge,9); mkStroke(verBadge,C.border)

local hideBtn=mkBtn(topBar,"×",C.bg,C.dim,15)
hideBtn.Size=UDim2.new(0,22,0,22); hideBtn.Position=UDim2.new(1,-30,0.5,-11)

-- ─ SIDEBAR ─────────────────────────────────────────────────
local sidebar=Instance.new("Frame",main)
sidebar.Size=UDim2.new(0,125,1,-38); sidebar.Position=UDim2.new(0,0,0,38)
sidebar.BackgroundColor3=C.bg; sidebar.BorderSizePixel=0

do
	local sd=Instance.new("Frame",sidebar)
	sd.Size=UDim2.new(0,1,1,0); sd.Position=UDim2.new(1,-1,0,0)
	sd.BackgroundColor3=C.border; sd.BorderSizePixel=0
end

-- ─ CONTENT AREA ───────────────────────────────────────────
local contentBg=Instance.new("Frame",main)
contentBg.Size=UDim2.new(1,-125,1,-38); contentBg.Position=UDim2.new(0,125,0,38)
contentBg.BackgroundColor3=C.card; contentBg.BorderSizePixel=0
contentBg.ClipsDescendants=true

-- ─ NAV ITEMS ───────────────────────────────────────────────
local NAV={
	{key="Mancing",label="Mancing",  icon="🎣"},
	{key="Spot",   label="Spot",     icon="📍"},
	{key="Seting", label="Seting",   icon="⚙️"},
	{key="Notif",  label="Notif",    icon="🔔"},
	{key="Log",    label="Console",  icon="📜"},
}
local navBtns={}; local panels={}

for i,item in ipairs(NAV) do
	local ny=8+(i-1)*40
	local btn=Instance.new("TextButton",sidebar)
	btn.Size=UDim2.new(1,-12,0,34); btn.Position=UDim2.new(0,6,0,ny)
	btn.BackgroundColor3=C.bg; btn.BorderSizePixel=0
	btn.Text=""; btn.AutoButtonColor=false; rnd(btn,7)

	local ico=Instance.new("TextLabel",btn)
	ico.BackgroundTransparency=1
	ico.Size=UDim2.new(0,20,1,0); ico.Position=UDim2.new(0,8,0,0)
	ico.Text=item.icon; ico.Font=Enum.Font.Gotham
	ico.TextSize=10; ico.TextColor3=C.dim
	ico.TextXAlignment=Enum.TextXAlignment.Center

	local lbl=mkLbl(btn,item.label,9.5,Enum.Font.GothamMedium,C.dim)
	lbl.Size=UDim2.new(1,-34,1,0); lbl.Position=UDim2.new(0,32,0,0)

	navBtns[item.key]={btn=btn,ico=ico,lbl=lbl}

	local p=Instance.new("ScrollingFrame",contentBg)
	p.Size=UDim2.new(1,0,1,0)
	p.BackgroundTransparency=1; p.BorderSizePixel=0
	p.ScrollBarThickness=2; p.ScrollBarImageColor3=C.border
	p.CanvasSize=UDim2.new(0,0,0,0); p.Visible=(i==1)
	panels[item.key]=p
end

local activeNav="Mancing"
local function switchNav(name)
	if activeNav==name then return end
	local old=navBtns[activeNav]
	if old then
		TS:Create(old.btn,TweenInfo.new(0.12),{BackgroundColor3=C.bg}):Play()
		old.lbl.TextColor3=C.dim; old.lbl.Font=Enum.Font.GothamMedium
	end
	activeNav=name
	local nb=navBtns[name]
	if nb then
		TS:Create(nb.btn,TweenInfo.new(0.12),{BackgroundColor3=C.navActive}):Play()
		nb.lbl.TextColor3=C.txt; nb.lbl.Font=Enum.Font.GothamBold
	end
	for n,p in pairs(panels) do p.Visible=(n==name) end
end
for name,nb in pairs(navBtns) do
	nb.btn.MouseButton1Click:Connect(function() switchNav(name) end)
end
do
	local nb=navBtns["Mancing"]
	nb.btn.BackgroundColor3=C.navActive
	nb.lbl.TextColor3=C.txt; nb.lbl.Font=Enum.Font.GothamBold
end

-- ─ HIDE/SHOW ────────────────────────────────────────────────
local savedPos=main.Position; local isHid=false
local function doHide(h)
	isHid=h
	if h then
		savedPos=main.Position
		TS:Create(main,TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.In),
			{Position=UDim2.new(1,10,0.5,-155)}):Play()
		task.delay(0.19,function()
			if isHid then main.Visible=false; floatBtn.Visible=true end
		end)
	else
		main.Visible=true; floatBtn.Visible=false
		main.Position=UDim2.new(1,10,0.5,-155)
		TS:Create(main,TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
			{Position=savedPos}):Play()
	end
end
hideBtn.MouseButton1Click:Connect(function() doHide(true) end)
floatBtn.MouseButton1Click:Connect(function() doHide(false) end)

-- ══ TAB 1: MANCING (AESTHETIC & PERFECT FIT) ═════════
local pM=panels["Mancing"]
pM.CanvasSize = UDim2.new(0,0,0,0) -- Fits seamlessly without scrollbar

-- 1. Status Hero Card (y=8, height=64)
local stCard=Instance.new("Frame",pM)
stCard.Size=UDim2.new(1,-16,0,64); stCard.Position=UDim2.new(0,8,0,8)
stCard.BackgroundColor3=C.bg; stCard.BorderSizePixel=0
rnd(stCard,8); mkStroke(stCard,C.border)

local stateDot=Instance.new("Frame",stCard)
stateDot.Size=UDim2.new(0,7,0,7); stateDot.Position=UDim2.new(0,10,0,12)
stateDot.BackgroundColor3=C.muted; stateDot.BorderSizePixel=0; rnd(stateDot,4)

local stateL=mkLbl(stCard,"Idle",10,Enum.Font.GothamBold,C.txt)
stateL.Size=UDim2.new(1,-24,0,14); stateL.Position=UDim2.new(0,22,0,8)

local fishCountL=mkLbl(stCard,"Tangkapan: 0 ikan",9,Enum.Font.GothamMedium,C.subtxt)
fishCountL.Size=UDim2.new(0.55,0,0,13); fishCountL.Position=UDim2.new(0,10,0,26)

local rateL=mkLbl(stCard,"Rate 0/jam",8.5,Enum.Font.Gotham,C.dim)
rateL.Size=UDim2.new(0.45,-10,0,13); rateL.Position=UDim2.new(0.55,0,0,26)
rateL.TextXAlignment=Enum.TextXAlignment.Right

local sessTimeL=mkLbl(stCard,"Sesi 00:00:00",8,Enum.Font.Gotham,C.muted)
sessTimeL.Size=UDim2.new(0.5,0,0,12); sessTimeL.Position=UDim2.new(0,10,0,44)

local perfL=mkLbl(stCard,"Performa: normal",8,Enum.Font.Gotham,C.muted)
perfL.Size=UDim2.new(0.5,-10,0,12); perfL.Position=UDim2.new(0.5,0,0,44)
perfL.TextXAlignment=Enum.TextXAlignment.Right

local dotPulse
local function setDot(col)
	if dotPulse then dotPulse:Cancel() end
	stateDot.BackgroundColor3=col
	dotPulse=TS:Create(stateDot,
		TweenInfo.new(0.65,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),
		{BackgroundColor3=col:Lerp(C.txt,0.42)})
	dotPulse:Play()
end
setDot(C.muted)

-- 2. Phase Progress Tracker (y=78, height=22)
local phCont=Instance.new("Frame",pM)
phCont.Size=UDim2.new(1,-16,0,22); phCont.Position=UDim2.new(0,8,0,78)
phCont.BackgroundTransparency=1; phCont.BorderSizePixel=0

local barBg=Instance.new("Frame",phCont)
barBg.Size=UDim2.new(1,0,0,3); barBg.Position=UDim2.new(0,0,1,-3)
barBg.BackgroundColor3=C.border; barBg.BorderSizePixel=0; rnd(barBg,2)

local barFill=Instance.new("Frame",barBg)
barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=C.accent
barFill.BorderSizePixel=0; rnd(barFill,2)

local phNames={"Lempar","Tunggu","Minigame","Selesai"}; local phLbls={}
for i,pn in ipairs(phNames) do
	local pl=Instance.new("TextLabel",phCont)
	pl.BackgroundTransparency=1
	pl.Size=UDim2.new(1/#phNames,0,0,14)
	pl.Position=UDim2.new((i-1)/#phNames,0,0,0)
	pl.Text=pn; pl.Font=Enum.Font.GothamMedium; pl.TextSize=7.5
	pl.TextColor3=C.muted; pl.TextXAlignment=Enum.TextXAlignment.Center; phLbls[i]=pl
end

local curPhase=0
local function setPhase(n)
	curPhase=n
	for i,pl in ipairs(phLbls) do
		pl.TextColor3=(i<=n) and C.accent or C.muted
		pl.Font=(i==n) and Enum.Font.GothamBold or Enum.Font.GothamMedium
	end
	TS:Create(barFill,TweenInfo.new(0.2,Enum.EasingStyle.Quart),
		{Size=UDim2.new(n/#phNames,0,1,0)}):Play()
end

local function setPct(pct)
	pct = math.clamp(tonumber(pct) or 0, 0, 1)
	local value = curPhase / #phNames + pct * (1 / #phNames)
	value = math.clamp(value, 0, 1)
	TS:Create(
		barFill,
		TweenInfo.new(0.1, Enum.EasingStyle.Linear),
		{Size = UDim2.new(value, 0, 1, 0)}
	):Play()
end

-- 3. Auto Fishing Row Card (y=106, height=38)
local fishRow=Instance.new("Frame",pM)
fishRow.Size=UDim2.new(1,-16,0,38); fishRow.Position=UDim2.new(0,8,0,106)
fishRow.BackgroundColor3=C.bg; fishRow.BorderSizePixel=0
rnd(fishRow,8); mkStroke(fishRow,C.border)

local fishLbl=mkLbl(fishRow,"Auto Fishing Engine",9.5,Enum.Font.GothamBold,C.txt)
fishLbl.Size=UDim2.new(1,-54,0,14); fishLbl.Position=UDim2.new(0,10,0,5)

local fishSub=mkLbl(fishRow,"Otomatis lempar & tangkap ikan",7.5,Enum.Font.Gotham,C.dim)
fishSub.Size=UDim2.new(1,-54,0,12); fishSub.Position=UDim2.new(0,10,0,20)

local fishSw=Instance.new("TextButton",fishRow)
fishSw.Size=UDim2.new(0,36,0,20); fishSw.Position=UDim2.new(1,-46,0.5,-10)
fishSw.BackgroundColor3=C.swOff; fishSw.Text=""; fishSw.BorderSizePixel=0
fishSw.AutoButtonColor=false; rnd(fishSw,10)

local fishKnob=Instance.new("Frame",fishSw)
fishKnob.Size=UDim2.new(0,16,0,16); fishKnob.Position=UDim2.new(0,2,0.5,-8)
fishKnob.BackgroundColor3=C.txt; fishKnob.BorderSizePixel=0; rnd(fishKnob,8)

local fishOn=false
fishSw.MouseButton1Click:Connect(function()
	if not _S.alive then return end
	fishOn=not fishOn
	TS:Create(fishSw,TweenInfo.new(0.12),{BackgroundColor3=fishOn and C.swOn or C.swOff}):Play()
	TS:Create(fishKnob,TweenInfo.new(0.12),
		{Position=fishOn and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}):Play()
	active=fishOn
	if fishOn then
		sessStart=os.clock()
		fishCount=0
		fishCountL.Text="Tangkapan: 0 ikan"
		fishState="IDLE"; idleAt=os.clock()
		setDot(C.accent); setPhase(0); stateL.Text="Memulai..."
		pcall(function()
			local root=me.Character and me.Character:FindFirstChild("HumanoidRootPart")
			if root then lastAFKPos=root.Position end
		end)
	else
		active=false
		castSess=castSess+1
		isCasting=false
		isSpace=false
		pcall(function() VIM:SendKeyEvent(false,Enum.KeyCode.Space,false,game) end)
		setJumpSuppressed(false)
		setDot(C.muted); setPhase(0); stateL.Text="Idle"
		sendWebhook("Fishing Dihentikan","Sistem dimatikan.",0x888888)
	end
end)

-- 4. Rod Status Card (y=150, height=32)
local rodRow=Instance.new("Frame",pM)
rodRow.Size=UDim2.new(1,-16,0,32); rodRow.Position=UDim2.new(0,8,0,150)
rodRow.BackgroundColor3=C.bg; rodRow.BorderSizePixel=0
rnd(rodRow,8); mkStroke(rodRow,C.border)

local rodIco=mkLbl(rodRow,"🎣",9,Enum.Font.Gotham,C.dim)
rodIco.Size=UDim2.new(0,16,1,0); rodIco.Position=UDim2.new(0,8,0,0)

local rodName=mkLbl(rodRow,"—",9.5,Enum.Font.GothamBold,C.txt)
rodName.Size=UDim2.new(0.5,-26,1,0); rodName.Position=UDim2.new(0,26,0,0)

local rodStat=mkLbl(rodRow,"—",8,Enum.Font.GothamMedium,C.subtxt)
rodStat.Size=UDim2.new(0.5,-8,1,0); rodStat.Position=UDim2.new(0.5,0,0,0)
rodStat.TextXAlignment=Enum.TextXAlignment.Right

updateRodUI = function()
	local rod = RODS[rodIdx]
	if not rod then
		rodName.Text = "—"
		rodStat.Text = "—"
		return
	end
	rodName.Text = rod.n
	rodStat.Text = string.format("Lure %.0f%% | Progress %.0f%%", rod.lure * 100, rod.prog * 100)
end
updateRodUI()

-- 5. Action Row: Reset & Spot Teleport (y=188, height=30)
local actRow=Instance.new("Frame",pM)
actRow.Size=UDim2.new(1,-16,0,30); actRow.Position=UDim2.new(0,8,0,188)
actRow.BackgroundTransparency=1; actRow.BorderSizePixel=0

local rstBtn=mkBtn(actRow,"Reset Sesi",C.bg,C.dim,9)
rstBtn.Size=UDim2.new(0.48,0,1,0); rstBtn.Position=UDim2.new(0,0,0,0)
rstBtn.MouseButton1Click:Connect(function() if doReset then doReset("manual") end end)

local spotNavBtn=mkBtn(actRow,"Kelola Spot 📍",C.bg,C.dim,9)
spotNavBtn.Size=UDim2.new(0.48,0,1,0); spotNavBtn.Position=UDim2.new(0.52,0,0,0)
spotNavBtn.MouseButton1Click:Connect(function() switchNav("Spot") end)

-- Live Stat Updater Loop
task.spawn(function()
	while _S.alive do
		task.wait(1)
		local el=active and (os.clock()-sessStart) or 0
		local h,m,s=math.floor(el/3600),math.floor(el%3600/60),math.floor(el%60)
		local rate=(active and fishCount>0) and (fishCount/math.max(el/3600,0.01)) or 0
		rateL.Text=string.format("Rate %.0f/jam",rate)
		sessTimeL.Text=string.format("Sesi %02d:%02d:%02d",h,m,s)
		if frameAvg>0.10 then
			perfL.Text="Performa: rendah"
			perfL.TextColor3=C.dim
		elseif frameAvg>0.05 then
			perfL.Text="Performa: lag"
			perfL.TextColor3=C.dim
		else
			perfL.Text="Performa: normal"
			perfL.TextColor3=C.muted
		end
	end
end)

-- ══ TAB 2: SPOT ══════════════════════════════════════
local pT=panels["Spot"]
local spCountL=mkLbl(pT,"0 / 10 spot tersimpan",8.5,Enum.Font.GothamMedium,C.dim)
spCountL.Size=UDim2.new(1,-16,0,14); spCountL.Position=UDim2.new(0,8,0,8)
spCountL.TextXAlignment=Enum.TextXAlignment.Center

local nameBox=Instance.new("TextBox",pT)
nameBox.Size=UDim2.new(1,-84,0,28); nameBox.Position=UDim2.new(0,8,0,26)
nameBox.BackgroundColor3=C.bg; nameBox.TextColor3=C.txt
nameBox.PlaceholderText="Nama spot baru..."; nameBox.PlaceholderColor3=C.muted
nameBox.Text=""; nameBox.ClearTextOnFocus=false
nameBox.Font=Enum.Font.Gotham; nameBox.TextSize=9
nameBox.TextXAlignment=Enum.TextXAlignment.Left; nameBox.BorderSizePixel=0
rnd(nameBox,7); mkStroke(nameBox,C.border)
Instance.new("UIPadding",nameBox).PaddingLeft=UDim.new(0,8)

local saveSpotBtn=mkBtn(pT,"Simpan",C.accent,C.bg,9)
saveSpotBtn.Size=UDim2.new(0,64,0,28); saveSpotBtn.Position=UDim2.new(1,-72,0,26)
rnd(saveSpotBtn,7)

local spSF=Instance.new("ScrollingFrame",pT)
spSF.Size=UDim2.new(1,-16,1,-64); spSF.Position=UDim2.new(0,8,0,60)
spSF.BackgroundTransparency=1; spSF.BorderSizePixel=0
spSF.CanvasSize=UDim2.new(0,0,0,0); spSF.ScrollBarThickness=2
spSF.ScrollBarImageColor3=C.border

local spLL=Instance.new("UIListLayout",spSF)
spLL.SortOrder=Enum.SortOrder.LayoutOrder; spLL.Padding=UDim.new(0,4)

local function spawnPlat(pos)
	pcall(function()
		local old=workspace:FindFirstChild("_nzh_p"); if old then old:Destroy() end
		local p=Instance.new("Part")
		p.Name="_nzh_p"; p.Anchored=true; p.CanCollide=true
		p.Size=Vector3.new(14,1,14); p.Position=pos-Vector3.new(0,3.2,0)
		p.Material=Enum.Material.SmoothPlastic; p.Transparency=0.7
		p.Color=Color3.fromRGB(100,80,40); p.Parent=workspace
	end)
end

local function doTeleport(pos)
	local ch=me.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	lastAFKPos=pos; spawnPlat(pos); task.wait(0.08); root.CFrame=CFrame.new(pos)
end

local renderSpots
renderSpots=function()
	for _,ch in ipairs(spSF:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
	end
	spCountL.Text=string.format("%d / %d spot tersimpan",#spots,MAX_SPOTS)
	if #spots==0 then
		local none=Instance.new("TextLabel",spSF)
		none.LayoutOrder=0; none.BackgroundTransparency=1; none.Size=UDim2.new(1,0,0,40)
		none.Text="Belum ada spot tersimpan"; none.TextColor3=C.muted
		none.Font=Enum.Font.Gotham; none.TextSize=8.5
		none.TextXAlignment=Enum.TextXAlignment.Center; return
	end
	for i,sp in ipairs(spots) do
		local row=Instance.new("Frame",spSF)
		row.LayoutOrder=i; row.Size=UDim2.new(1,0,0,34)
		row.BackgroundColor3=C.bg; row.BorderSizePixel=0
		rnd(row,7); mkStroke(row,C.border)

		local nLbl=mkLbl(row,sp.name,9,Enum.Font.GothamBold,C.txt)
		nLbl.Size=UDim2.new(1,-95,1,0); nLbl.Position=UDim2.new(0,8,0,0)

		local goBtn=mkBtn(row,"Pergi",C.accent,C.bg,8.5)
		goBtn.Size=UDim2.new(0,40,0,22); goBtn.Position=UDim2.new(1,-88,0.5,-11)

		local delBtn=mkBtn(row,"Hapus",C.card,C.dim,8.5)
		delBtn.Size=UDim2.new(0,40,0,22); delBtn.Position=UDim2.new(1,-44,0.5,-11)
		mkStroke(delBtn,C.border)

		local ci=i; local cp=Vector3.new(sp.x,sp.y,sp.z)
		goBtn.MouseButton1Click:Connect(function()
			doTeleport(cp); stateL.Text="Pindah ke "..sp.name
		end)
		delBtn.MouseButton1Click:Connect(function()
			table.remove(spots,ci); saveSpots(); renderSpots()
		end)
	end
	spSF.CanvasSize=UDim2.new(0,0,0,#spots*38+4)
end
renderSpots()

saveSpotBtn.MouseButton1Click:Connect(function()
	local nm=nameBox.Text:match("^%s*(.-)%s*$")
	if nm=="" then nm="Spot "..(#spots+1) end
	if #spots>=MAX_SPOTS then stateL.Text="Max "..MAX_SPOTS.." spot"; return end
	local ch=me.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local p=root.Position
	table.insert(spots,{name=nm,x=p.X,y=p.Y,z=p.Z})
	saveSpots(); nameBox.Text=""; renderSpots()
end)

-- ══ TAB 3: SETING ═══════════════════════════════════
local pS=panels["Seting"]
local function sSec(lbl,y)
	local l=mkLbl(pS,lbl,7,Enum.Font.GothamBold,C.dim)
	l.Size=UDim2.new(1,-16,0,12); l.Position=UDim2.new(0,8,0,y); return l
end
local sy=8
sSec("PEMANCIAN",sy); sy=sy+14
mkToggle(pS,sy,"Jitter Timing Cast","Variasi durasi lempar pancing",CFG.jitter,function(v) CFG.jitter=v end); sy=sy+40
mkToggle(pS,sy,"Jitter Posisi Kursor","Variasi posisi koordinat klik",CFG.coordJitter,function(v) CFG.coordJitter=v end); sy=sy+40
mkToggle(pS,sy,"Istirahat Otomatis","Jeda otomatis setiap 25 ikan",CFG.fatigueOn,function(v) CFG.fatigueOn=v end); sy=sy+40
sSec("PERFORMA & UTILITAS",sy); sy=sy+14
mkToggle(pS,sy,"Adaptasi Frame Time","Toleransi saat FPS rendah",CFG.netAdapt,function(v) CFG.netAdapt=v end); sy=sy+40
mkToggle(pS,sy,"Auto Kembali ke Spot","Teleport otomatis setelah respawn",CFG.autoRejoin,function(v) CFG.autoRejoin=v end); sy=sy+40
mkToggle(pS,sy,"Anti-AFK Mouse Sweep","Simulasi gerakan mouse anti-idle",CFG.antiAFK,function(v) CFG.antiAFK=v end); sy=sy+40
mkToggle(pS,sy,"Watchdog Auto-Reset","Reset otomatis jika sistem macet",CFG.watchdog,function(v) CFG.watchdog=v end); sy=sy+40
pS.CanvasSize=UDim2.new(0,0,0,sy+10)

-- ══ TAB 4: NOTIF ═══════════════════════════════════
local pN=panels["Notif"]
local ny=8
local wLbl=mkLbl(pN,"DISCORD WEBHOOK NOTIFIKASI",7.5,Enum.Font.GothamBold,C.dim)
wLbl.Size=UDim2.new(1,-16,0,12); wLbl.Position=UDim2.new(0,8,0,ny)
ny=ny+16

local wBox=Instance.new("TextBox",pN)
wBox.Size=UDim2.new(1,-16,0,28); wBox.Position=UDim2.new(0,8,0,ny)
wBox.BackgroundColor3=C.bg; wBox.TextColor3=C.txt
wBox.PlaceholderText="https://discord.com/api/webhooks/..."
wBox.PlaceholderColor3=C.muted; wBox.Text=webhookURL
wBox.ClearTextOnFocus=false; wBox.Font=Enum.Font.Gotham
wBox.TextSize=8.5; wBox.TextXAlignment=Enum.TextXAlignment.Left
wBox.BorderSizePixel=0; rnd(wBox,7); mkStroke(wBox,C.border)
Instance.new("UIPadding",wBox).PaddingLeft=UDim.new(0,8)
wBox.FocusLost:Connect(function() webhookURL=wBox.Text end); ny=ny+34

mkToggle(pN,ny,"Aktifkan Notifikasi","Kirim update hasil tangkapan ke Discord",false,function(v) webhookOn=v end); ny=ny+42

local testBtn=mkBtn(pN,"Kirim Test Notifikasi",C.bg,C.dim,9)
testBtn.Size=UDim2.new(1,-16,0,28); testBtn.Position=UDim2.new(0,8,0,ny)
rnd(testBtn,7); mkStroke(testBtn,C.border)
testBtn.MouseButton1Click:Connect(function()
	sendWebhook("Test Notifikasi","Webhook terhubung dari NasiHub.",0xb49352)
end); ny=ny+34

local nInfo=mkLbl(pN,"Notifikasi otomatis dikirim setiap kelipatan 10 ikan.",7.5,Enum.Font.Gotham,C.muted)
nInfo.Size=UDim2.new(1,-16,0,16); nInfo.Position=UDim2.new(0,8,0,ny)
pN.CanvasSize=UDim2.new(0,0,0,ny+24)

-- ══ TAB 5: LOG ══════════════════════════════════════
local pL=panels["Log"]
local logEnabled=false

local logToggle=mkBtn(pL,"Log: OFF",C.bg,C.muted,8.5)
logToggle.Size=UDim2.new(0,68,0,24); logToggle.Position=UDim2.new(0,8,0,8)
mkStroke(logToggle,C.border)

local logClear=mkBtn(pL,"Clear",C.bg,C.muted,8.5)
logClear.Size=UDim2.new(0,54,0,24); logClear.Position=UDim2.new(0,80,0,8)
mkStroke(logClear,C.border)

local logSF=Instance.new("ScrollingFrame",pL)
logSF.Size=UDim2.new(1,-16,1,-42); logSF.Position=UDim2.new(0,8,0,36)
logSF.BackgroundColor3=C.bg; logSF.BorderSizePixel=0
rnd(logSF,7); mkStroke(logSF,C.border)
logSF.CanvasSize=UDim2.new(0,0,0,0); logSF.ScrollBarThickness=2
logSF.ScrollBarImageColor3=C.border
do
	local lp=Instance.new("UIPadding",logSF)
	lp.PaddingTop=UDim.new(0,4); lp.PaddingLeft=UDim.new(0,6)
	lp.PaddingRight=UDim.new(0,4); lp.PaddingBottom=UDim.new(0,4)
end
local logLL=Instance.new("UIListLayout",logSF)
logLL.SortOrder=Enum.SortOrder.LayoutOrder; logLL.Padding=UDim.new(0,1)
local logN=0
addLog = function(txt)
	if not logEnabled then return end
	logN=logN+1
	local row=Instance.new("TextLabel",logSF)
	row.LayoutOrder=logN; row.Size=UDim2.new(1,0,0,13)
	row.BackgroundTransparency=1
	row.Text=string.format("[%s] %s",os.date("%H:%M:%S"),tostring(txt))
	row.TextColor3=C.dim; row.Font=Enum.Font.Gotham
	row.TextSize=8; row.TextXAlignment=Enum.TextXAlignment.Left
	row.TextWrapped=true
	task.defer(function()
		logSF.CanvasSize=UDim2.new(0,0,0,logLL.AbsoluteContentSize.Y+8)
		logSF.CanvasPosition=Vector2.new(0,math.huge)
	end)
	local kids={}
	for _,k in ipairs(logSF:GetChildren()) do if k:IsA("TextLabel") then kids[#kids+1]=k end end
	if #kids>80 then kids[1]:Destroy() end
end
logToggle.MouseButton1Click:Connect(function()
	logEnabled=not logEnabled
	logToggle.Text=logEnabled and "Log: ON" or "Log: OFF"
	logToggle.TextColor3=logEnabled and C.accent or C.muted
end)
logClear.MouseButton1Click:Connect(function()
	for _,k in ipairs(logSF:GetChildren()) do if k:IsA("TextLabel") then k:Destroy() end end
	logSF.CanvasSize=UDim2.new(0,0,0,0); logN=0
end)

-- ════════════════════════════════════════════════════
-- FISHING ENGINE
-- ════════════════════════════════════════════════════

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

local function normalizeToolName(name)
	return tostring(name or ""):lower():gsub("%s+", "")
end

local function isFishingTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local n = normalizeToolName(tool.Name)

	for _, genericName in ipairs(FISH_TOOLS) do
		local g = normalizeToolName(genericName)
		if n == g or n:find(g, 1, true) then
			return true
		end
	end

	for _, rod in ipairs(RODS) do
		local rn = normalizeToolName(rod.n)
		if n == rn then
			return true
		end
	end

	return false
end

local function syncRodProfile(tool)
	if not tool then
		return
	end

	local n = normalizeToolName(tool.Name)

	for i, rod in ipairs(RODS) do
		if n == normalizeToolName(rod.n) then
			rodIdx = i
			if updateRodUI then updateRodUI() end
			return
		end
	end
end

local function findAndEquipRod()
	local ch = me.Character
	if not ch then return nil end

	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end

	local equipped = ch:FindFirstChildWhichIsA("Tool")
	if isFishingTool(equipped) then
		syncRodProfile(equipped)
		return equipped
	end

	local bp = me:FindFirstChild("Backpack")
	if not bp then return nil end

	for _, item in ipairs(bp:GetChildren()) do
		if isFishingTool(item) then
			local ok = pcall(function()
				hum:EquipTool(item)
			end)

			if ok then
				task.wait(0.35)
				local newTool = ch:FindFirstChildWhichIsA("Tool")
				if isFishingTool(newTool) then
					syncRodProfile(newTool)
					return newTool
				end
			end
		end
	end

	return nil
end

local function setSpace(v, force)
	if isSpace == v and not force then return end
	local now = os.clock()
	if not force and (now - lastSpTgl) < 0.03 then return end
	pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
	isSpace = v; lastSpTgl = now
end

local function getBars()
	if wBar and rBar and wBar.Parent and rBar.Parent
		and trulyVis(wBar) and trulyVis(rBar) then
		return wBar, rBar
	end
	local now = os.clock()
	local scanInterval = frameSlow() and 0.10 or 0.05
	if now - lastScan < scanInterval then return nil, nil end
	lastScan = now; wBar = nil; rBar = nil

	local pg = me:FindFirstChild("PlayerGui")
	if not pg then return nil, nil end

	-- Pass 1: nama
	for _, v in ipairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVis(v) then
			local ln  = v.Name:lower()
			local par = v.Parent
			if par and par:IsA("GuiObject") then
				local isW = ln == "whitebar" or ln == "playerbar"
					or (ln:find("white") and ln:find("bar"))
				if isW then
					for _, sib in ipairs(par:GetChildren()) do
						if sib ~= v and sib:IsA("GuiObject") and trulyVis(sib) then
							local sn = sib.Name:lower()
							if sn:find("red") or sn:find("target") or sn:find("goal") then
								if v.AbsoluteSize.X > 10 then
									wBar = v; rBar = sib; return v, sib
								end
							end
						end
					end
				end
			end
		end
	end

	-- Pass 2: warna
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
							wBar = v; rBar = sib; return v, sib
						end
					end
				end
			end
		end
	end
	return nil, nil
end

local function doFatigue()
	if not CFG.fatigueOn then return end
	fatCnt = fatCnt + 1
	if fatCnt < CFG.fatEvery then return end
	fatCnt = 0
	addLog("Istirahat " .. CFG.fatDur .. "s")
	setSpace(false, true)
	setPhase(0)
	stateL.Text = "Istirahat " .. CFG.fatDur .. "s"
	setDot(C.accent)
	task.wait(CFG.fatDur)
	setDot(C.accent)
end

doReset = function(reason)
	castSess = castSess + 1

	fishState = "IDLE"
	isSpace = false
	isCasting = false
	successDone = false
	mgEverSeen = false
	mgStarted = false
	mgLastSeen = 0

	wBar = nil
	rBar = nil
	lastScan = 0
	lastWC = nil
	wVel = 0
	idleAt = os.clock()

	pcall(function()
		VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	end)

	setPhase(0)

	if active then
		stateL.Text = "Idle"
		setDot(C.accent)
	end

	if reason then
		addLog("Reset: " .. tostring(reason))
	end
end

local function onCatch(why)
	if successDone then return end
	successDone = true
	setSpace(false, true)
	fishState = "DONE"; setPhase(4)
	fishCount = fishCount + 1
	fishCountL.Text = "Tangkapan: " .. fishCount .. " ikan"
	stateL.Text     = "Caught #" .. fishCount
	setDot(C.accent)
	addLog("Caught #" .. fishCount .. "  (" .. why .. ")")

	if fishCount == 1 or fishCount % 10 == 0 then
		sendWebhook("Update Tangkapan",
			string.format("Sudah menangkap **%d ikan** dalam sesi ini.", fishCount),
			0xb49352)
	end

	doFatigue()

	local sess = castSess
	task.delay(jt(CFG.recastDly, 0.12), function()
		if not _S.alive or not active or castSess ~= sess then return end
		doReset(nil)
		task.wait(0.06)
		if active then fishState = "IDLE"; idleAt = os.clock() end
	end)
end

-- Heartbeat — frame time update & minigame tracker
local hbLast = 0
local hbConn = RS.Heartbeat:Connect(function(dt)
	updateFrameTime(dt)
	if not _S.alive then return end
	if not active then
		if isSpace then setSpace(false, true) end
		return
	end
	local now = os.clock()
	if now - hbLast < 0.016 then return end
	hbLast = now
	safe(function()
		local rod = RODS[rodIdx]

		if fishState == "WAITING" then
			local el = now - biteStart
			setPct(math.clamp(el / CFG.biteWait, 0, 1))
			stateL.Text = string.format("Menunggu... %.0fs", math.max(0, CFG.biteWait - el))
			if el >= CFG.biteWait then
				fishState   = "MINIGAME"
				mgStart     = now
				mgEverSeen  = false
				mgStarted   = false
				mgLastSeen  = 0
				successDone = false
				wBar        = nil
				rBar        = nil
				lastScan    = 0
				lastWC      = nil
				wVel        = 0
				lastWTime   = now
				setSpace(false, true)
				setPhase(3)
				setPct(0)
				stateL.Text = "Minigame"
				addLog("Minigame started")
			end
			return
		end

		if fishState ~= "MINIGAME" then return end

		local el = now - mgStart
		local timeout = (11 + rod.prog * 3.2) * (frameSlow() and 1.4 or 1.0)
		setPct(math.clamp(el / timeout, 0, 1))
		if el >= timeout then
			setSpace(false, true)
			stateL.Text = "Minigame timeout"
			addLog("Minigame timeout")
			doReset("minigame-timeout")
			return
		end

		local wb, rb = getBars()
		if wb and rb and trulyVis(wb) and trulyVis(rb) then
			mgEverSeen = true
			mgLastSeen = now
			if not mgStarted then
				mgStarted = true
				setSpace(false, true)
				lastWC = nil
				wVel = 0
				lastWTime = now
			end

			local wC    = wb.AbsolutePosition.X + wb.AbsoluteSize.X * 0.5
			local rL    = rb.AbsolutePosition.X
			local rR    = rL + rb.AbsoluteSize.X
			local rC    = (rL + rR) * 0.5
			local rawDt = now - lastWTime
			local dt    = math.clamp(rawDt, 0.007, 0.16)

			if lastWC then
				local inst = (wC - lastWC) / dt
				local sm   = math.clamp(0.26 / rod.lure, 0.10, 0.30)
				wVel = wVel * (1 - sm) + inst * sm
			end
			lastWC = wC
			lastWTime = now

			local lagFactor = frameSlow() and 1.5 or 1.0
			local ahead  = math.clamp(math.abs(wVel) / 1650, 0.03, 0.17) * math.sqrt(rod.lure) * lagFactor
			local pred   = wC + wVel * ahead
			local rw     = math.max(rb.AbsoluteSize.X, 1)
			local lag    = math.clamp(rawDt / 0.05 - 1, 0, 1.5)
			local tol    = math.clamp(rw * (0.16 + lag * 0.14 + rod.lure * 0.025), 4, 28)
			local inside = pred >= (rL - tol) and pred <= (rR + tol)

			if inside then
				if     wC < rL then setSpace(true)
				elseif wC > rR then setSpace(false)
				else
					local e = wC - rC
					if math.abs(e) > tol * 0.4 then setSpace(e < 0) end
				end
			else
				local e = rC - pred
				if     e >  tol then setSpace(true)
				elseif e < -tol then setSpace(false)
				elseif math.abs(wVel) > 130 then setSpace(wVel < 0) end
			end
			stateL.Text = string.format("Playing... %.0fs", el)
		else
			if mgStarted and mgEverSeen and mgLastSeen > 0 and not successDone and (now - mgLastSeen) >= 0.20 then
				setSpace(false, true)
				onCatch("bar-gone")
			elseif not mgEverSeen then
				local beat = math.floor((now - mgStart) * 3.0) % 2 == 0
				setSpace(beat)
				stateL.Text = string.format("Sync... %.0fs", el)
			end
		end
	end)
end)
table.insert(_S.c, hbConn)

-- Cast loop
task.spawn(function()
	while _S.alive do
		task.wait(0.14)
		if _S.alive and active then
			safe(function()
				local ch  = me.Character
				if not ch then return end
				local hum = ch:FindFirstChildOfClass("Humanoid")
				if not hum then return end

				local tool = findAndEquipRod()
				if not tool then
					setJumpSuppressed(false)
					stateL.Text = "Tidak ada rod!"
					setDot(C.accent)
					return
				end

				setJumpSuppressed(true)

				if fishState == "IDLE" and not isCasting then
					isCasting = true
					castSess = castSess + 1
					local sess = castSess
					task.spawn(function()
						if not _S.alive or not active or castSess ~= sess then
							isCasting = false
							return
						end
						local cam = workspace.CurrentCamera
						if not cam then
							isCasting = false
							return
						end
						local rod = RODS[rodIdx]
						local ctr = jv(cam.ViewportSize / 2)
						fishState = "CASTING"
						setPhase(1)
						setPct(0)
						stateL.Text = "Casting..."
						setDot(C.accent)
						pcall(function() tool:Activate() end)
						pcall(function() VU:Button1Down(ctr, cam.CFrame) end)

						local lagMult = frameSlow() and 1.2 or 1.0
						local dur = jt(CFG.castHold / math.max(1, math.sqrt(rod.lure) * 0.85), 0.09) * lagMult
						local t0  = os.clock()
						while os.clock() - t0 < dur do
							task.wait(0.04)
							if not active or not _S.alive or castSess ~= sess then
								pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
								isCasting = false
								return
							end
							setPct((os.clock() - t0) / dur)
						end
						pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
						setPct(1)
						task.wait(jt(0.12, 0.08))
						if not active or not _S.alive or castSess ~= sess then
							isCasting = false
							return
						end
						fishState = "WAITING"
						biteStart = os.clock()
						setPhase(2)
						setPct(0)
						stateL.Text = "Menunggu..."
						setDot(C.accent)
						addLog("Cast #" .. castSess)
						isCasting = false
					end)
				end
			end)
		end
	end
end)

-- Watchdog — 5 detik sekali
task.spawn(function()
	while _S.alive do
		task.wait(5)
		if _S.alive and active and CFG.watchdog then
			local now = os.clock()
			local idleThresh = frameSlow() and 18 or 12
			local waitThresh = CFG.biteWait + (frameSlow() and 14 or 9)
			local evt = nil
			if   fishState == "IDLE"    and not isCasting and (now - idleAt)    > idleThresh then
				evt = "idle-lock"
			elseif fishState == "WAITING" and (now - biteStart) > waitThresh then
				evt = "bite-timeout"
			elseif fishState == "CASTING" and not isCasting and (now - idleAt)  > 10 then
				evt = "cast-stuck"
			end
			if evt then
				addLog("Watchdog: " .. evt)
				sendWebhook("Watchdog Reset",
					"Bot mengalami stuck (" .. evt .. ") dan melakukan reset otomatis.", 0xc47830)
				doReset(evt)
			end
		end
	end
end)

-- Anti-AFK
task.spawn(function()
	while _S.alive do
		task.wait(math.random(88, 148))
		if not _S.alive then break end
		if CFG.antiAFK then
			pcall(function()
				local cam = workspace.CurrentCamera; if not cam then return end
				local sz = cam.ViewportSize
				VU:MouseMoveEvent(
					Vector2.new(sz.X/2 + math.random(-55,55), sz.Y/2 + math.random(-40,40)),
					cam.CFrame)
			end)
		end
	end
end)

local idledConn = me.Idled:Connect(function()
	if not CFG.antiAFK then return end
	pcall(function()
		local cam = workspace.CurrentCamera; if not cam then return end
		VU:Button2Down(Vector2.new(0,0), cam.CFrame)
		task.wait(0.1)
		VU:Button2Up(Vector2.new(0,0), cam.CFrame)
	end)
end)
table.insert(_S.c, idledConn)

-- Character Added lifecycle handler
local function onCharAdded(char)
	setJumpSuppressed(false)
	if not CFG.autoRejoin or not lastAFKPos then return end
	task.spawn(function()
		local root = char:WaitForChild("HumanoidRootPart", 8)
		if not root then return end
		task.wait(2.5)
		if not _S.alive or not lastAFKPos then return end
		spawnPlat(lastAFKPos)
		task.wait(0.12)
		root.CFrame = CFrame.new(lastAFKPos)
		addLog("Auto-kembali ke spot terakhir")
		task.wait(0.5)
		if active and doReset then doReset("auto-rejoin") end
	end)
end
local charConn = me.CharacterAdded:Connect(onCharAdded)
table.insert(_S.c, charConn)

-- Startup notification
task.delay(1.2, function()
	sendWebhook("NasiHub Aktif", "NasiHub v2.0 berhasil dijalankan.", 0xb49352)
end)

addLog("NasiHub v2.0 siap.")
setPhase(0)
