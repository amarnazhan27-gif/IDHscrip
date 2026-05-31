-- ┌──────────────────────────────────────────────────┐
-- │   Nazhan Fish  v2.0  •  by nazhan               │
-- │   auto fishing | custom spot | webhook notif    │
-- └──────────────────────────────────────────────────┘

if shared._nzh2 then pcall(shared._nzh2.stop) end

local _S = { alive = true, c = {} }
_S.stop = function()
	_S.alive = false
	for _, v in ipairs(_S.c) do pcall(function() v:Disconnect() end) end
	table.clear(_S.c)
	pcall(function()
		local pt = workspace:FindFirstChild("_nzh_p")
		if pt then pt:Destroy() end
		game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	end)
end
shared._nzh2 = _S

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
	jitter           = true,
	coordJitter      = true,
	fatigueOn        = true,
	fatEvery         = 25,
	fatDur           = 8,
	antiAFK          = true,
	adminGuard       = true,
	watchdog         = true,
	netAdapt         = true,
	autoRejoin       = true,
	autoDeclineCarry = true,
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
local lastAFKPos  = nil   -- posisi afk terakhir untuk auto-rejoin

-- Lag detector — rolling average frame time
local lagAvg   = 0.016
local lagSmooth= 0.08
local function updateLag(dt)
	lagAvg = lagAvg * (1 - lagSmooth) + dt * lagSmooth
end
local function lagging() return CFG.netAdapt and lagAvg > 0.05 end

-- Discord Webhook
local webhookURL = ""
local webhookOn  = false

-- ── Custom Spots ────────────────────────────────────
local SPOTS_FILE = "nzh_spots.json"
local spots      = {}   -- { {name="..", x=0, y=0, z=0}, ... }
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

-- ── Webhook ─────────────────────────────────────────
local function sendWebhook(title, body, colorInt)
	if not webhookOn or webhookURL == "" then return end
	if not webhookURL:find("discord%.com/api/webhooks") then return end
	task.spawn(function()
		local el   = os.clock() - sessStart
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
					{ name = "Rod",  value = rod.n, inline = true },
				},
				footer = { text = "Nazhan Fish v2.0" },
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

task.wait(math.random() * 0.12 + 0.04)

-- ── ScreenGui ───────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "_NZH2"
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 25
gui.IgnoreGuiInset = false
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = me:WaitForChild("PlayerGui")
end

-- ── Palette: Warm Charcoal + Gold (satu warna aksen)
local C = {
	bg     = Color3.fromRGB(13,  12,  11),
	bg2    = Color3.fromRGB(19,  18,  15),
	card   = Color3.fromRGB(24,  22,  19),
	border = Color3.fromRGB(44,  40,  33),
	gold   = Color3.fromRGB(176, 140,  76),
	txt    = Color3.fromRGB(232, 226, 213),
	dim    = Color3.fromRGB(148, 140, 124),
	muted  = Color3.fromRGB( 72,  67,  57),
	swOn   = Color3.fromRGB(176, 140,  76),
	swOff  = Color3.fromRGB( 32,  30,  25),
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
	l.TextSize       = size or 11
	l.Font           = font or Enum.Font.Gotham
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
	rnd(b, 5)
	local orig = b.BackgroundColor3
	local hi   = orig:Lerp(C.gold, 0.18)
	b.MouseEnter:Connect(function()
		TS:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = hi}):Play()
	end)
	b.MouseLeave:Connect(function()
		TS:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = orig}):Play()
	end)
	return b
end

local function mkToggle(parent, y, labelText, defVal, callback)
	local row = Instance.new("Frame", parent)
	row.Size              = UDim2.new(1, -24, 0, 28)
	row.Position          = UDim2.new(0, 12, 0, y)
	row.BackgroundTransparency = 1

	local lbl = mkLbl(row, labelText, 10, Enum.Font.Gotham, C.dim)
	lbl.Size     = UDim2.new(1, -50, 1, 0)
	lbl.Position = UDim2.new(0, 0, 0, 0)

	local sw = Instance.new("TextButton", row)
	sw.Size              = UDim2.new(0, 34, 0, 18)
	sw.Position          = UDim2.new(1, -34, 0.5, -9)
	sw.BackgroundColor3  = defVal and C.swOn or C.swOff
	sw.Text              = ""
	sw.BorderSizePixel   = 0
	sw.AutoButtonColor   = false
	rnd(sw, 9)

	local knob = Instance.new("Frame", sw)
	knob.Size              = UDim2.new(0, 14, 0, 14)
	knob.Position          = defVal and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
	knob.BackgroundColor3  = C.txt
	knob.BorderSizePixel   = 0
	rnd(knob, 7)

	local val = defVal
	sw.MouseButton1Click:Connect(function()
		if not _S.alive then return end
		val = not val
		TS:Create(sw,   TweenInfo.new(0.1), {BackgroundColor3 = val and C.swOn or C.swOff}):Play()
		TS:Create(knob, TweenInfo.new(0.1), {
			Position = val and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
		}):Play()
		callback(val)
	end)
	return sw
end

local function mkSep(parent, y)
	local f = Instance.new("Frame", parent)
	f.Size              = UDim2.new(1, -24, 0, 1)
	f.Position          = UDim2.new(0, 12, 0, y)
	f.BackgroundColor3  = C.border
	f.BorderSizePixel   = 0
	return f
end

-- ── Main Frame ───────────────────────────────────────
local main = Instance.new("Frame", gui)
main.Size             = UDim2.new(0, 268, 0, 384)
main.Position         = UDim2.new(1, -286, 0.5, -192)
main.BackgroundColor3 = C.bg
main.BackgroundTransparency = 0.03
main.BorderSizePixel  = 0
main.Active           = true
main.Draggable        = true
rnd(main, 11)
mkStroke(main, C.border, 1)

-- Float button (visible when hidden, draggable)
local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size             = UDim2.new(0, 42, 0, 42)
floatBtn.Position         = UDim2.new(1, -56, 0.5, -21)
floatBtn.BackgroundColor3 = C.bg2
floatBtn.Text             = "NF"
floatBtn.TextColor3       = C.gold
floatBtn.Font             = Enum.Font.GothamBold
floatBtn.TextSize         = 11
floatBtn.BorderSizePixel  = 0
floatBtn.Active           = true
floatBtn.Draggable        = true
floatBtn.Visible          = false
rnd(floatBtn, 21)
mkStroke(floatBtn, C.gold, 1)

-- ── Header ───────────────────────────────────────────
local hdr = Instance.new("Frame", main)
hdr.Size             = UDim2.new(1, 0, 0, 48)
hdr.BackgroundColor3 = C.bg2
hdr.BorderSizePixel  = 0
rnd(hdr, 11)

-- Cover lower-half corner rounding
local hdrFlat = Instance.new("Frame", hdr)
hdrFlat.Size             = UDim2.new(1, 0, 0.5, 0)
hdrFlat.Position         = UDim2.new(0, 0, 0.5, 0)
hdrFlat.BackgroundColor3 = C.bg2
hdrFlat.BorderSizePixel  = 0

local hdrDiv = Instance.new("Frame", hdr)
hdrDiv.Size             = UDim2.new(1, 0, 0, 1)
hdrDiv.Position         = UDim2.new(0, 0, 1, -1)
hdrDiv.BackgroundColor3 = C.border
hdrDiv.BorderSizePixel  = 0

-- Gold accent mark
local mark = Instance.new("Frame", hdr)
mark.Size             = UDim2.new(0, 3, 0, 20)
mark.Position         = UDim2.new(0, 10, 0.5, -10)
mark.BackgroundColor3 = C.gold
mark.BorderSizePixel  = 0
rnd(mark, 2)

local titleL = mkLbl(hdr, "NazhanHub(free)", 12, Enum.Font.GothamBold, C.txt)
titleL.Size     = UDim2.new(0, 214, 0, 16)
titleL.Position = UDim2.new(0, 17, 0, 9)

local subL = mkLbl(hdr, "Auto Fishing System", 9, Enum.Font.Gotham, C.muted)
subL.Size     = UDim2.new(0, 214, 0, 13)
subL.Position = UDim2.new(0, 17, 0, 27)

local hideBtn = mkBtn(hdr, "—", C.bg, C.muted, 12)
hideBtn.Size     = UDim2.new(0, 26, 0, 20)
hideBtn.Position = UDim2.new(1, -34, 0.5, -10)

-- ── Hide / Show ──────────────────────────────────────
local savedPos = main.Position
local isHid    = false

local function doHide(h)
	isHid = h
	if h then
		savedPos = main.Position
		TS:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = UDim2.new(1, 10, 0.5, -192)}):Play()
		task.delay(0.21, function()
			if isHid then main.Visible = false; floatBtn.Visible = true end
		end)
	else
		main.Visible = true; floatBtn.Visible = false
		main.Position = UDim2.new(1, 10, 0.5, -192)
		TS:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = savedPos}):Play()
	end
end
hideBtn.MouseButton1Click:Connect(function() doHide(true) end)
floatBtn.MouseButton1Click:Connect(function() doHide(false) end)

-- ── Tab Bar ─────────────────────────────────────────
local tabBar = Instance.new("Frame", main)
tabBar.Size             = UDim2.new(1, 0, 0, 28)
tabBar.Position         = UDim2.new(0, 0, 0, 48)
tabBar.BackgroundColor3 = C.bg2
tabBar.BorderSizePixel  = 0

local tDiv = Instance.new("Frame", tabBar)
tDiv.Size = UDim2.new(1, 0, 0, 1); tDiv.Position = UDim2.new(0, 0, 1, -1)
tDiv.BackgroundColor3 = C.border; tDiv.BorderSizePixel = 0

local TABS    = { "Mancing", "Spot", "Seting", "Notif", "Log" }
local tabBtns = {}
local panels  = {}
local numTabs = #TABS

-- pill indicator
local pill = Instance.new("Frame", tabBar)
pill.Size             = UDim2.new(1/numTabs, -6, 0, 2)
pill.Position         = UDim2.new(0, 3, 1, -2)
pill.BackgroundColor3 = C.gold
pill.BorderSizePixel  = 0
rnd(pill, 1)

local body = Instance.new("Frame", main)
body.Size             = UDim2.new(1, 0, 1, -76)
body.Position         = UDim2.new(0, 0, 0, 76)
body.BackgroundTransparency = 1
body.ClipsDescendants = true

for i, tname in ipairs(TABS) do
	local tb = Instance.new("TextButton", tabBar)
	tb.Size             = UDim2.new(1/numTabs, 0, 1, -2)
	tb.Position         = UDim2.new((i-1)/numTabs, 0, 0, 0)
	tb.BackgroundTransparency = 1
	tb.BorderSizePixel  = 0
	tb.Text             = tname
	tb.TextColor3       = (i==1) and C.txt or C.muted
	tb.Font             = Enum.Font.Gotham
	tb.TextSize         = 9
	tabBtns[tname]      = tb

	local p = Instance.new("Frame", body)
	p.Size              = UDim2.new(1, 0, 1, 0)
	p.BackgroundTransparency = 1
	p.Visible           = (i==1)
	panels[tname]       = p
end

local activeTab = "Mancing"
local function switchTab(name)
	if activeTab == name then return end
	activeTab = name
	local idx = table.find(TABS, name)
	TS:Create(pill, TweenInfo.new(0.15, Enum.EasingStyle.Quad),
		{Position = UDim2.new((idx-1)/numTabs, 3, 1, -2)}):Play()
	for n, tb in pairs(tabBtns) do
		tb.TextColor3    = (n==name) and C.txt or C.muted
		panels[n].Visible = (n==name)
	end
end
for name, tb in pairs(tabBtns) do
	tb.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ════════════════════════════════════════════════════
-- TAB 1 — MANCING
-- ════════════════════════════════════════════════════
local pM = panels["Mancing"]

-- Status card
local stCard = Instance.new("Frame", pM)
stCard.Size             = UDim2.new(1, -20, 0, 60)
stCard.Position         = UDim2.new(0, 10, 0, 10)
stCard.BackgroundColor3 = C.card
stCard.BorderSizePixel  = 0
rnd(stCard, 7)
mkStroke(stCard, C.border)

-- State indicator dot
local stateDot = Instance.new("Frame", stCard)
stateDot.Size             = UDim2.new(0, 6, 0, 6)
stateDot.Position         = UDim2.new(0, 10, 0, 11)
stateDot.BackgroundColor3 = C.muted
stateDot.BorderSizePixel  = 0
rnd(stateDot, 3)

local stateL = mkLbl(stCard, "Idle", 11, Enum.Font.GothamBold, C.txt)
stateL.Size     = UDim2.new(1, -24, 0, 16)
stateL.Position = UDim2.new(0, 20, 0, 5)

local fishCountL = mkLbl(stCard, "Tangkapan: 0 ikan", 9.5, Enum.Font.Gotham, C.dim)
fishCountL.Size     = UDim2.new(1, -16, 0, 14)
fishCountL.Position = UDim2.new(0, 10, 0, 24)

local rateL = mkLbl(stCard, "Rate  —  |  Sesi  00:00:00", 9, Enum.Font.Gotham, C.muted)
rateL.Size     = UDim2.new(1, -16, 0, 13)
rateL.Position = UDim2.new(0, 10, 0, 40)

-- Dot pulse animation
local dotPulse
local function setDot(col)
	if dotPulse then dotPulse:Cancel() end
	stateDot.BackgroundColor3 = col
	dotPulse = TS:Create(stateDot,
		TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{BackgroundColor3 = col:Lerp(C.txt, 0.42)})
	dotPulse:Play()
end
setDot(C.muted)

-- Phase progress bar
local phCont = Instance.new("Frame", pM)
phCont.Size             = UDim2.new(1, -20, 0, 30)
phCont.Position         = UDim2.new(0, 10, 0, 76)
phCont.BackgroundTransparency = 1

local barBg = Instance.new("Frame", phCont)
barBg.Size             = UDim2.new(1, 0, 0, 2)
barBg.Position         = UDim2.new(0, 0, 0, 5)
barBg.BackgroundColor3 = C.border
barBg.BorderSizePixel  = 0
rnd(barBg, 1)

local barFill = Instance.new("Frame", barBg)
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = C.gold
barFill.BorderSizePixel  = 0
rnd(barFill, 1)

local phNames  = { "Cast", "Wait", "Game", "Done" }
local phColors = { C.gold, C.gold, C.gold, C.gold }
local phLbls   = {}
for i, pn in ipairs(phNames) do
	local pl = Instance.new("TextLabel", phCont)
	pl.BackgroundTransparency = 1
	pl.Size     = UDim2.new(0.25, 0, 0, 14)
	pl.Position = UDim2.new((i-1)*0.25, 0, 0, 12)
	pl.Text     = pn
	pl.TextColor3 = C.muted
	pl.Font     = Enum.Font.GothamBold
	pl.TextSize = 9
	phLbls[i]   = pl
end

local activePh = 0
local function setPhase(ph)
	activePh = ph
	for i = 1, 4 do
		if i < ph then        phLbls[i].TextColor3 = C.dim
		elseif i == ph then   phLbls[i].TextColor3 = phColors[i]
		else                  phLbls[i].TextColor3 = C.muted end
	end
	if ph == 0 then
		TS:Create(barFill, TweenInfo.new(0.12),
			{Size = UDim2.new(0,0,1,0), BackgroundColor3 = C.gold}):Play()
	else
		TS:Create(barFill, TweenInfo.new(0.12), {
			Size             = UDim2.new(math.clamp(ph*0.25,0,1),0,1,0),
			BackgroundColor3 = phColors[ph],
		}):Play()
	end
end

local function setPct(f)
	if activePh <= 0 then return end
	barFill.Size = UDim2.new(math.clamp((activePh-1)*0.25 + f*0.25, 0, 1), 0, 1, 0)
end

mkSep(pM, 112)

-- Rod selector
local rodCard = Instance.new("Frame", pM)
rodCard.Size             = UDim2.new(1, -20, 0, 42)
rodCard.Position         = UDim2.new(0, 10, 0, 118)
rodCard.BackgroundColor3 = C.card
rodCard.BorderSizePixel  = 0
rnd(rodCard, 7)
mkStroke(rodCard, C.border)

local rodHdrL = mkLbl(rodCard, "ROD", 8, Enum.Font.GothamBold, C.muted)
rodHdrL.Size     = UDim2.new(0, 40, 0, 12)
rodHdrL.Position = UDim2.new(0, 10, 0, 5)

local prevB = mkBtn(rodCard, "<", C.bg, C.dim, 10)
prevB.Size     = UDim2.new(0, 20, 0, 18)
prevB.Position = UDim2.new(0, 8, 0, 19)

local nextB = mkBtn(rodCard, ">", C.bg, C.dim, 10)
nextB.Size     = UDim2.new(0, 20, 0, 18)
nextB.Position = UDim2.new(1, -28, 0, 19)

local rodNameL = Instance.new("TextLabel", rodCard)
rodNameL.BackgroundTransparency = 1
rodNameL.Size     = UDim2.new(1, -64, 0, 18)
rodNameL.Position = UDim2.new(0, 32, 0, 19)
rodNameL.Text     = RODS[1].n
rodNameL.TextColor3 = C.gold
rodNameL.Font     = Enum.Font.GothamBold
rodNameL.TextSize = 10
rodNameL.TextXAlignment = Enum.TextXAlignment.Center

local rodStatL = mkLbl(rodCard, "", 8, Enum.Font.Gotham, C.muted)
rodStatL.Size     = UDim2.new(1, -16, 0, 12)
rodStatL.Position = UDim2.new(0, 8, 0, 5)
rodStatL.TextXAlignment = Enum.TextXAlignment.Right

local function updateRod()
	local r = RODS[rodIdx]
	rodNameL.Text = r.n
	rodStatL.Text = string.format("lure %.0f%%  prog %.0f%%", r.lure*100, r.prog*100)
end
updateRod()
prevB.MouseButton1Click:Connect(function()
	rodIdx = (rodIdx <= 1) and #RODS or rodIdx - 1; updateRod()
end)
nextB.MouseButton1Click:Connect(function()
	rodIdx = (rodIdx >= #RODS) and 1 or rodIdx + 1; updateRod()
end)

mkSep(pM, 167)

-- Main toggle
local doReset   -- forward declare
local mainToggle= mkToggle(pM, 173, "Auto Fishing", false, function(on)
	active = on
	if on then
		fishState = "IDLE"; idleAt = os.clock()
		setDot(C.gold); setPhase(0); stateL.Text = "Memulai..."
	else
		active = false; isSpace = false
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		setDot(C.muted); setPhase(0); stateL.Text = "Idle"
		sendWebhook("Fishing Dihentikan", "Sistem auto-fishing dimatikan secara manual.", 0x888888)
	end
end)

-- Reset button
local rstBtn = mkBtn(pM, "Reset", C.card, C.dim, 10)
rstBtn.Size     = UDim2.new(1, -20, 0, 24)
rstBtn.Position = UDim2.new(0, 10, 0, 208)
mkStroke(rstBtn, C.border)

rstBtn.MouseButton1Click:Connect(function()
	if doReset then doReset("manual") end
end)

mkSep(pM, 240)

-- Session stats row (kecil di bawah)
local sessRateL = mkLbl(pM, "Rate  —  ikan/jam", 8.5, Enum.Font.Gotham, C.muted)
sessRateL.Size     = UDim2.new(0.5, -14, 0, 12)
sessRateL.Position = UDim2.new(0, 10, 0, 248)

local sessTimeL = mkLbl(pM, "00:00:00", 8.5, Enum.Font.Gotham, C.muted)
sessTimeL.Size             = UDim2.new(0.5, -6, 0, 12)
sessTimeL.Position         = UDim2.new(0.5, 4, 0, 248)
sessTimeL.TextXAlignment   = Enum.TextXAlignment.Right

-- Network lag hint
local lagL = mkLbl(pM, "Jaringan: normal", 8, Enum.Font.Gotham, C.muted)
lagL.Size     = UDim2.new(1, -20, 0, 12)
lagL.Position = UDim2.new(0, 10, 0, 264)

-- Session timer thread
task.spawn(function()
	while _S.alive do
		task.wait(1)
		local el = os.clock() - sessStart
		local h, m, s = math.floor(el/3600), math.floor(el%3600/60), math.floor(el%60)
		local rate = fishCount > 0 and fishCount / math.max(el/3600, 0.01) or 0
		sessRateL.Text = string.format("Rate  %.1f ikan/jam", rate)
		sessTimeL.Text = string.format("%02d:%02d:%02d", h, m, s)
		rateL.Text     = string.format("Rate %.1f/jam  |  Sesi %02d:%02d:%02d", rate, h, m, s)
		-- lag indicator update
		if lagAvg > 0.10 then
			lagL.Text = "Jaringan: sangat lambat"
			lagL.TextColor3 = C.dim
		elseif lagAvg > 0.05 then
			lagL.Text = "Jaringan: sedikit lag"
			lagL.TextColor3 = C.dim
		else
			lagL.Text = "Jaringan: normal"
			lagL.TextColor3 = C.muted
		end
	end
end)

-- ════════════════════════════════════════════════════
-- TAB 2 — SPOT (Custom Locations)
-- ════════════════════════════════════════════════════
local pT = panels["Spot"]

-- Info label
local spHdrL = mkLbl(pT, "LOKASI TERSIMPAN", 8, Enum.Font.GothamBold, C.muted)
spHdrL.Size     = UDim2.new(0, 160, 0, 12)
spHdrL.Position = UDim2.new(0, 10, 0, 10)

local spCountL = mkLbl(pT, "0 / 10", 8, Enum.Font.Gotham, C.muted)
spCountL.Size              = UDim2.new(1, -20, 0, 12)
spCountL.Position          = UDim2.new(0, 10, 0, 10)
spCountL.TextXAlignment    = Enum.TextXAlignment.Right

mkSep(pT, 26)

-- Name input row
local nameBox = Instance.new("TextBox", pT)
nameBox.Size              = UDim2.new(1, -84, 0, 24)
nameBox.Position          = UDim2.new(0, 10, 0, 32)
nameBox.BackgroundColor3  = C.card
nameBox.TextColor3        = C.txt
nameBox.PlaceholderText   = "Nama lokasi..."
nameBox.PlaceholderColor3 = C.muted
nameBox.Text              = ""
nameBox.ClearTextOnFocus  = false
nameBox.Font              = Enum.Font.Gotham
nameBox.TextSize          = 10
nameBox.TextXAlignment    = Enum.TextXAlignment.Left
nameBox.BorderSizePixel   = 0
rnd(nameBox, 5)
mkStroke(nameBox, C.border)

-- Padding inside textbox
local nbPad = Instance.new("UIPadding", nameBox)
nbPad.PaddingLeft = UDim.new(0, 8)

local saveSpotBtn = mkBtn(pT, "Simpan", C.gold, Color3.fromRGB(20,18,14), 10)
saveSpotBtn.Size     = UDim2.new(0, 62, 0, 24)
saveSpotBtn.Position = UDim2.new(1, -72, 0, 32)
saveSpotBtn.TextColor3 = Color3.fromRGB(20, 18, 14)

mkSep(pT, 62)

-- Scrollable spot list
local spSF = Instance.new("ScrollingFrame", pT)
spSF.Size                  = UDim2.new(1, 0, 1, -68)
spSF.Position              = UDim2.new(0, 0, 0, 68)
spSF.BackgroundTransparency = 1
spSF.BorderSizePixel       = 0
spSF.CanvasSize            = UDim2.new(0, 0, 0, 0)
spSF.ScrollBarThickness    = 2
spSF.ScrollBarImageColor3  = C.border
spSF.AutomaticCanvasSize   = Enum.AutomaticSize.Y

local spList = Instance.new("UIListLayout", spSF)
spList.SortOrder  = Enum.SortOrder.LayoutOrder
spList.Padding    = UDim.new(0, 4)

local spPad = Instance.new("UIPadding", spSF)
spPad.PaddingTop    = UDim.new(0, 6)
spPad.PaddingLeft   = UDim.new(0, 10)
spPad.PaddingRight  = UDim.new(0, 10)
spPad.PaddingBottom = UDim.new(0, 6)

-- Platform spawner for teleport
local function spawnPlat(pos)
	pcall(function()
		local old = workspace:FindFirstChild("_nzh_p")
		if old then old:Destroy() end
		local p = Instance.new("Part")
		p.Name = "_nzh_p"; p.Anchored = true; p.CanCollide = true
		p.Size = Vector3.new(14, 1, 14)
		p.Position = pos - Vector3.new(0, 3.2, 0)
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 0.7
		p.Color = Color3.fromRGB(100, 80, 40)
		p.Parent = workspace
	end)
end

local function doTeleport(pos)
	local ch   = me.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	lastAFKPos = pos   -- simpan untuk auto-rejoin
	spawnPlat(pos)
	task.wait(0.08)
	root.CFrame = CFrame.new(pos)
end

local renderSpots  -- forward declare

renderSpots = function()
	-- clear existing rows (Frame dan TextLabel)
	for _, ch in ipairs(spSF:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
	end

	spCountL.Text = string.format("%d / %d", #spots, MAX_SPOTS)

	if #spots == 0 then
		local none = Instance.new("TextLabel", spSF)
		none.LayoutOrder  = 0
		none.BackgroundTransparency = 1
		none.Size         = UDim2.new(1, 0, 0, 36)
		none.Text         = "Belum ada lokasi tersimpan."
		none.TextColor3   = C.muted
		none.Font         = Enum.Font.Gotham
		none.TextSize     = 9.5
		none.TextXAlignment = Enum.TextXAlignment.Center
		return
	end

	for i, sp in ipairs(spots) do
		local row = Instance.new("Frame", spSF)
		row.LayoutOrder       = i
		row.Size              = UDim2.new(1, 0, 0, 32)
		row.BackgroundColor3  = C.card
		row.BorderSizePixel   = 0
		rnd(row, 5)
		mkStroke(row, C.border)

		local nameLbl = mkLbl(row, sp.name, 10, Enum.Font.Gotham, C.txt)
		nameLbl.Size     = UDim2.new(1, -110, 1, 0)
		nameLbl.Position = UDim2.new(0, 10, 0, 0)

		local coordLbl = mkLbl(row, string.format("%.0f, %.0f, %.0f", sp.x, sp.y, sp.z), 7.5, Enum.Font.Gotham, C.muted)
		coordLbl.Size     = UDim2.new(1, -110, 0, 10)
		coordLbl.Position = UDim2.new(0, 10, 1, -12)

		local goBtn = mkBtn(row, "Pergi", C.gold, Color3.fromRGB(18,16,12), 9)
		goBtn.Size     = UDim2.new(0, 46, 0, 20)
		goBtn.Position = UDim2.new(1, -100, 0.5, -10)

		local delBtn = mkBtn(row, "Hapus", C.card, C.dim, 9)
		delBtn.Size     = UDim2.new(0, 44, 0, 20)
		delBtn.Position = UDim2.new(1, -50, 0.5, -10)

		-- capture i for closures
		local capturedIdx = i
		local capturedPos = Vector3.new(sp.x, sp.y, sp.z)

		goBtn.MouseButton1Click:Connect(function()
			doTeleport(capturedPos)
			stateL.Text = "Pindah ke " .. sp.name
		end)

		delBtn.MouseButton1Click:Connect(function()
			table.remove(spots, capturedIdx)
			saveSpots()
			renderSpots()
		end)
	end
end

renderSpots()

-- Save current position
saveSpotBtn.MouseButton1Click:Connect(function()
	local name = nameBox.Text:match("^%s*(.-)%s*$")  -- trim
	if name == "" then name = "Spot " .. (#spots + 1) end
	if #spots >= MAX_SPOTS then
		stateL.Text = "Maksimal " .. MAX_SPOTS .. " spot"
		return
	end
	local ch   = me.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local p = root.Position
	table.insert(spots, { name=name, x=p.X, y=p.Y, z=p.Z })
	saveSpots()
	nameBox.Text = ""
	renderSpots()
end)

-- ════════════════════════════════════════════════════
-- TAB 3 — SETING
-- ════════════════════════════════════════════════════
local pS = panels["Seting"]

local sScroll = Instance.new("ScrollingFrame", pS)
sScroll.Size               = UDim2.new(1, 0, 1, 0)
sScroll.BackgroundTransparency = 1
sScroll.BorderSizePixel    = 0
sScroll.CanvasSize         = UDim2.new(0, 0, 0, 400)
sScroll.ScrollBarThickness = 2
sScroll.ScrollBarImageColor3 = C.border

local function sSection(lbl, y)
	local l = mkLbl(sScroll, lbl, 8, Enum.Font.GothamBold, C.muted)
	l.Size = UDim2.new(1, -24, 0, 12)
	l.Position = UDim2.new(0, 12, 0, y)
	mkSep(sScroll, y + 14)
	return l
end

local sy = 10
sSection("PEMANCIAN", sy); sy = sy + 20
mkToggle(sScroll, sy, "Jitter Timing Cast",   CFG.jitter,      function(v) CFG.jitter=v end);      sy=sy+32
mkToggle(sScroll, sy, "Jitter Posisi Kursor", CFG.coordJitter, function(v) CFG.coordJitter=v end); sy=sy+32
mkToggle(sScroll, sy, "Istirahat Otomatis",   CFG.fatigueOn,   function(v) CFG.fatigueOn=v end);   sy=sy+32

sSection("JARINGAN", sy); sy=sy+20
mkToggle(sScroll, sy, "Adaptasi Lag Jaringan", CFG.netAdapt, function(v) CFG.netAdapt=v end); sy=sy+32

local lagHintL = mkLbl(sScroll, "Toleransi minigame dan watchdog otomatis diperlebar saat jaringan lambat.", 8.5, Enum.Font.Gotham, C.muted)
lagHintL.Size = UDim2.new(1, -24, 0, 24); lagHintL.Position = UDim2.new(0, 12, 0, sy)
lagHintL.TextWrapped = true; sy = sy + 30

sSection("KARAKTER", sy); sy=sy+20
mkToggle(sScroll, sy, "Auto Kembali ke Spot (Rejoin)", CFG.autoRejoin, function(v) CFG.autoRejoin=v end); sy=sy+32

local rejoinHintL = mkLbl(sScroll, "Setelah mati atau respawn, otomatis teleport ke spot AFK terakhir.", 8.5, Enum.Font.Gotham, C.muted)
rejoinHintL.Size = UDim2.new(1, -24, 0, 24); rejoinHintL.Position = UDim2.new(0, 12, 0, sy)
rejoinHintL.TextWrapped = true; sy = sy + 30

mkToggle(sScroll, sy, "Tolak Carry Otomatis", CFG.autoDeclineCarry, function(v) CFG.autoDeclineCarry=v end); sy=sy+32

local carryHintL = mkLbl(sScroll, "Carry request dari pemain lain otomatis ditolak saat sedang mancing.", 8.5, Enum.Font.Gotham, C.muted)
carryHintL.Size = UDim2.new(1, -24, 0, 24); carryHintL.Position = UDim2.new(0, 12, 0, sy)
carryHintL.TextWrapped = true; sy = sy + 30

sSection("KEAMANAN", sy); sy=sy+20
mkToggle(sScroll, sy, "Anti-AFK Mouse Sweep",   CFG.antiAFK,    function(v) CFG.antiAFK=v end);    sy=sy+32
mkToggle(sScroll, sy, "Admin Guard (Auto-Kick)", CFG.adminGuard, function(v) CFG.adminGuard=v end); sy=sy+32
mkToggle(sScroll, sy, "Watchdog Auto-Reset",    CFG.watchdog,   function(v) CFG.watchdog=v end);   sy=sy+32

sScroll.CanvasSize = UDim2.new(0, 0, 0, sy + 10)

-- ════════════════════════════════════════════════════
-- TAB 4 — NOTIF (Webhook)
-- ════════════════════════════════════════════════════
local pN = panels["Notif"]

local nSF = Instance.new("ScrollingFrame", pN)
nSF.Size               = UDim2.new(1, 0, 1, 0)
nSF.BackgroundTransparency = 1
nSF.BorderSizePixel    = 0
nSF.CanvasSize         = UDim2.new(0, 0, 0, 340)
nSF.ScrollBarThickness = 2
nSF.ScrollBarImageColor3 = C.border

-- Tutorial
local function nLabel(txt, y, size, col)
	local l = mkLbl(nSF, txt, size or 9, Enum.Font.Gotham, col or C.dim)
	l.Size = UDim2.new(1, -24, 0, (size or 9) + 5)
	l.Position = UDim2.new(0, 12, 0, y)
	return l
end

local nHdr = mkLbl(nSF, "CARA MENAMBAHKAN WEBHOOK", 8, Enum.Font.GothamBold, C.muted)
nHdr.Size = UDim2.new(1, -24, 0, 12); nHdr.Position = UDim2.new(0, 12, 0, 10)
mkSep(nSF, 26)

local tutLines = {
	"1.  Buka server Discord kamu",
	"2.  Klik Edit Channel pada channel tujuan",
	"3.  Pilih tab Integrations, klik Webhooks",
	"4.  Klik New Webhook dan beri nama bebas",
	"5.  Klik Copy Webhook URL",
	"6.  Paste URL di kolom di bawah ini",
	"7.  Aktifkan toggle, lalu klik Test",
}
local ny = 32
for _, ln in ipairs(tutLines) do
	local tl = mkLbl(nSF, ln, 9, Enum.Font.Gotham, C.dim)
	tl.Size = UDim2.new(1, -24, 0, 14); tl.Position = UDim2.new(0, 12, 0, ny)
	ny = ny + 15
end
mkSep(nSF, ny + 4); ny = ny + 14

-- Konfigurasi
local nCfgH = mkLbl(nSF, "KONFIGURASI", 8, Enum.Font.GothamBold, C.muted)
nCfgH.Size = UDim2.new(1, -24, 0, 12); nCfgH.Position = UDim2.new(0, 12, 0, ny)
ny = ny + 16; mkSep(nSF, ny); ny = ny + 8

-- URL label
nLabel("Webhook URL", ny, 9, C.dim); ny = ny + 16

local wBox = Instance.new("TextBox", nSF)
wBox.Size = UDim2.new(1, -24, 0, 26); wBox.Position = UDim2.new(0, 12, 0, ny)
wBox.BackgroundColor3 = C.card; wBox.TextColor3 = C.txt
wBox.PlaceholderText = "https://discord.com/api/webhooks/..."
wBox.PlaceholderColor3 = C.muted; wBox.Text = webhookURL
wBox.ClearTextOnFocus = false; wBox.Font = Enum.Font.Gotham
wBox.TextSize = 8.5; wBox.TextXAlignment = Enum.TextXAlignment.Left
wBox.BorderSizePixel = 0
rnd(wBox, 5); mkStroke(wBox, C.border)
local wbP = Instance.new("UIPadding", wBox); wbP.PaddingLeft = UDim.new(0, 8)
wBox.FocusLost:Connect(function() webhookURL = wBox.Text end)
ny = ny + 32

mkToggle(nSF, ny, "Aktifkan Notifikasi Discord", false, function(v) webhookOn = v end); ny = ny + 32

local testBtn = mkBtn(nSF, "Kirim Test Notifikasi", C.card, C.dim, 9.5)
testBtn.Size = UDim2.new(1, -24, 0, 26); testBtn.Position = UDim2.new(0, 12, 0, ny)
mkStroke(testBtn, C.border)
testBtn.MouseButton1Click:Connect(function()
	sendWebhook("Test Notifikasi", "Webhook berhasil terhubung dari Roblox.", 0xb49352)
end)
ny = ny + 32

mkSep(nSF, ny + 2); ny = ny + 12
local nInfo = mkLbl(nSF, "Notif dikirim saat: setiap 10 ikan tertangkap, watchdog reset, admin terdeteksi di server.", 8.5, Enum.Font.Gotham, C.muted)
nInfo.Size = UDim2.new(1, -24, 0, 28); nInfo.Position = UDim2.new(0, 12, 0, ny)
nInfo.TextWrapped = true; ny = ny + 32

nSF.CanvasSize = UDim2.new(0, 0, 0, ny + 8)


-- ════════════════════════════════════════════════════
-- TAB 5 — LOG (Console)
-- ════════════════════════════════════════════════════
local pL = panels["Log"]

local logEnabled = false

-- Header
local logHdrL = mkLbl(pL, "CONSOLE LOG", 8, Enum.Font.GothamBold, C.muted)
logHdrL.Size = UDim2.new(1, -20, 0, 12); logHdrL.Position = UDim2.new(0, 10, 0, 10)
mkSep(pL, 26)

local logToggle = mkBtn(pL, "Log: OFF", C.card, C.muted, 9.5)
logToggle.Size = UDim2.new(0, 68, 0, 22); logToggle.Position = UDim2.new(0, 10, 0, 32)
mkStroke(logToggle, C.border)

local logClear = mkBtn(pL, "Hapus Semua", C.card, C.muted, 9.5)
logClear.Size = UDim2.new(0, 84, 0, 22); logClear.Position = UDim2.new(0, 84, 0, 32)
mkStroke(logClear, C.border)

mkSep(pL, 60)

local logSF = Instance.new("ScrollingFrame", pL)
logSF.Size             = UDim2.new(1, -20, 1, -68)
logSF.Position         = UDim2.new(0, 10, 0, 66)
logSF.BackgroundColor3 = C.card
logSF.BorderSizePixel  = 0
rnd(logSF, 6)
mkStroke(logSF, C.border)
logSF.CanvasSize          = UDim2.new(0, 0, 0, 0)
logSF.ScrollBarThickness  = 2
logSF.ScrollBarImageColor3= C.border

local logPad = Instance.new("UIPadding", logSF)
logPad.PaddingTop    = UDim.new(0, 5)
logPad.PaddingLeft   = UDim.new(0, 8)
logPad.PaddingRight  = UDim.new(0, 4)
logPad.PaddingBottom = UDim.new(0, 5)

local logLL = Instance.new("UIListLayout", logSF)
logLL.SortOrder = Enum.SortOrder.LayoutOrder
logLL.Padding   = UDim.new(0, 1)

local logN = 0
local function addLog(txt)
	if not logEnabled then return end
	logN = logN + 1
	local row = Instance.new("TextLabel", logSF)
	row.LayoutOrder  = logN
	row.Size         = UDim2.new(1, 0, 0, 13)
	row.BackgroundTransparency = 1
	row.Text         = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(txt))
	row.TextColor3   = C.dim
	row.Font         = Enum.Font.Gotham
	row.TextSize     = 8.5
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextWrapped  = true
	task.defer(function()
		logSF.CanvasSize     = UDim2.new(0, 0, 0, logLL.AbsoluteContentSize.Y + 8)
		logSF.CanvasPosition = Vector2.new(0, math.huge)
	end)
	local kids = {}
	for _, k in ipairs(logSF:GetChildren()) do
		if k:IsA("TextLabel") then kids[#kids+1] = k end
	end
	if #kids > 80 then kids[1]:Destroy() end
end

logToggle.MouseButton1Click:Connect(function()
	logEnabled = not logEnabled
	logToggle.Text       = logEnabled and "Log: ON" or "Log: OFF"
	logToggle.TextColor3 = logEnabled and C.gold or C.muted
end)
logClear.MouseButton1Click:Connect(function()
	for _, k in ipairs(logSF:GetChildren()) do
		if k:IsA("TextLabel") then k:Destroy() end
	end
	logSF.CanvasSize = UDim2.new(0, 0, 0, 0); logN = 0
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

local function findAndEquipRod()
	local ch = me.Character; if not ch then return nil end
	local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return nil end
	local eq  = ch:FindFirstChildWhichIsA("Tool")
	if eq then return eq end
	local bp = me.Backpack
	for _, n in ipairs(FISH_TOOLS) do
		local t = bp:FindFirstChild(n) or ch:FindFirstChild(n)
		if t then
			pcall(function() hum:EquipTool(t) end)
			task.wait(0.5)
			return ch:FindFirstChildWhichIsA("Tool")
		end
	end
	local any = bp:FindFirstChildWhichIsA("Tool")
	if any then
		pcall(function() hum:EquipTool(any) end)
		task.wait(0.5)
		return ch:FindFirstChildWhichIsA("Tool")
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
	-- adaptive scan interval: lebih jarang saat lag
	local scanInterval = lagging() and 0.10 or 0.05
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
	setDot(C.gold)
	task.wait(CFG.fatDur)
	setDot(C.gold)
end

doReset = function(reason)
	fishState   = "IDLE"
	isSpace     = false
	isCasting   = false
	successDone = false
	mgEverSeen  = false
	mgStarted   = false
	wBar        = nil; rBar = nil
	lastScan    = 0; lastWC = nil; wVel = 0; mgLastSeen = 0
	castSess    = castSess + 1
	idleAt      = os.clock()
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
	setPhase(0)
	if active then stateL.Text = "Idle"; setDot(C.gold) end
	if reason then addLog("Reset: " .. reason) end
end

local function onCatch(why)
	if successDone then return end
	successDone = true
	setSpace(false, true)
	fishState = "DONE"; setPhase(4)
	fishCount = fishCount + 1
	fishCountL.Text = "Tangkapan: " .. fishCount .. " ikan"
	stateL.Text     = "Caught #" .. fishCount
	setDot(C.gold)
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

-- Heartbeat — presisi tinggi, throttled 60fps
local hbLast = 0
local hbConn = RS.Heartbeat:Connect(function(dt)
	updateLag(dt)
	if not _S.alive then return end
	if not active then
		if isSpace then setSpace(false, true) end; return
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
				fishState   = "MINIGAME"; mgStart = now
				mgEverSeen  = false; mgStarted = false
				mgLastSeen  = 0; successDone = false
				wBar = nil; rBar = nil
				lastScan = 0; lastWC = nil; wVel = 0; lastWTime = now
				setSpace(false, true); setPhase(3); setPct(0)
				stateL.Text = "Minigame"; addLog("Minigame started")
			end
			return
		end

		if fishState ~= "MINIGAME" then return end

		local el = now - mgStart
		-- Adaptasi timeout saat lag: beri waktu lebih
		local timeout = (11 + rod.prog * 3.2) * (lagging() and 1.4 or 1.0)
		setPct(math.clamp(el / timeout, 0, 1))
		if el >= timeout then
			setSpace(false, true); onCatch("timeout"); return
		end

		local wb, rb = getBars()
		if wb and rb and trulyVis(wb) and trulyVis(rb) then
			mgEverSeen = true; mgLastSeen = now
			if not mgStarted then
				mgStarted = true; setSpace(false, true)
				lastWC = nil; wVel = 0; lastWTime = now
			end

			local wC    = wb.AbsolutePosition.X + wb.AbsoluteSize.X * 0.5
			local rL    = rb.AbsolutePosition.X
			local rR    = rL + rb.AbsoluteSize.X
			local rC    = (rL + rR) * 0.5
			local rawDt = now - lastWTime
			local dt    = math.clamp(rawDt, 0.007, 0.16)  -- 0.16 toleransi lebih besar saat lag

			if lastWC then
				local inst = (wC - lastWC) / dt
				local sm   = math.clamp(0.26 / rod.lure, 0.10, 0.30)
				wVel = wVel * (1 - sm) + inst * sm
			end
			lastWC = wC; lastWTime = now

			-- Extrapolation ahead diperbesar saat lag
			local lagFactor = lagging() and 1.5 or 1.0
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
			if mgEverSeen then
				-- bar hilang = minigame selesai
				if mgLastSeen > 0 and (now - mgLastSeen) >= 0.20 then
					setSpace(false, true); onCatch("bar-gone")
				end
			else
				-- pre-bar sync
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
		if not _S.alive or not active then continue end
		safe(function()
			local ch  = me.Character; if not ch then return end
			local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return end
			if hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			end
			local tool = findAndEquipRod()
			if not tool then
				stateL.Text = "Tidak ada rod!"; setDot(C.gold); return
			end
			if fishState == "IDLE" and not isCasting then
				isCasting = true; castSess = castSess + 1
				local sess = castSess
				task.spawn(function()
					if not _S.alive or not active or castSess ~= sess then
						isCasting = false; return
					end
					local cam = workspace.CurrentCamera
					if not cam then isCasting = false; return end
					local rod = RODS[rodIdx]
					local ctr = jv(cam.ViewportSize / 2)
					fishState = "CASTING"; setPhase(1); setPct(0)
					stateL.Text = "Casting..."; setDot(C.gold)
					pcall(function() tool:Activate() end)
					pcall(function() VU:Button1Down(ctr, cam.CFrame) end)
					-- Perpanjang durasi cast saat lag
					local lagMult = lagging() and 1.2 or 1.0
					local dur = jt(CFG.castHold / math.max(1, math.sqrt(rod.lure) * 0.85), 0.09) * lagMult
					local t0  = os.clock()
					while os.clock() - t0 < dur do
						task.wait(0.04)
						if not active or not _S.alive or castSess ~= sess then
							pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
							isCasting = false; return
						end
						setPct((os.clock() - t0) / dur)
					end
					pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
					setPct(1)
					task.wait(jt(0.12, 0.08))
					if not active or not _S.alive or castSess ~= sess then
						isCasting = false; return
					end
					fishState = "WAITING"; biteStart = os.clock()
					setPhase(2); setPct(0)
					stateL.Text = "Menunggu..."; setDot(C.gold)
					addLog("Cast #" .. castSess)
					isCasting = false
				end)
			end
		end)
	end
end)

-- Watchdog — 5 detik sekali, sangat ringan
task.spawn(function()
	while _S.alive do
		task.wait(5)
		if not _S.alive or not active or not CFG.watchdog then continue end
		local now = os.clock()
		-- Threshold diperlebar saat lag
		local idleThresh = lagging() and 18 or 12
		local waitThresh = CFG.biteWait + (lagging() and 14 or 9)
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
	pcall(function()
		local cam = workspace.CurrentCamera; if not cam then return end
		VU:Button2Down(Vector2.new(0,0), cam.CFrame)
		task.wait(0.1)
		VU:Button2Up(Vector2.new(0,0), cam.CFrame)
	end)
end)
table.insert(_S.c, idledConn)

-- Admin Guard
local ADMIN_PATS = { "moderator","roblox_adm","rbxadmin","staffmod","gamemaster","game_master","rblxmod" }
local STAFF_GRP  = 1200769

local function checkPlayer(p)
	if p == me or not p.Parent or not CFG.adminGuard then return end
	task.wait(2.5)
	if not p or not p.Parent then return end
	local isAdm = false
	pcall(function() isAdm = isAdm or p:IsInGroup(STAFF_GRP) end)
	if not isAdm then
		local ln = (p.Name .. p.DisplayName):lower()
		for _, pat in ipairs(ADMIN_PATS) do
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
		addLog("Admin terdeteksi: " .. p.Name)
		sendWebhook("Admin Terdeteksi",
			string.format("**%s** masuk server. Keluar otomatis.", p.Name), 0xa04040)
		active = false; setSpace(false, true)
		task.wait(0.8); me:Kick("Disconnected.")
	end
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(checkPlayer, p) end
local paConn = Players.PlayerAdded:Connect(function(p) task.spawn(checkPlayer, p) end)
table.insert(_S.c, paConn)

-- Auto-rejoin: teleport ke spot terakhir setelah respawn
local function onCharAdded(char)
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

-- Auto-decline carry request
pcall(function()
	local pg = me:FindFirstChild("PlayerGui")
	if not pg then return end
	local conn = pg.ChildAdded:Connect(function(child)
		if not CFG.autoDeclineCarry then return end
		task.wait(0.7)
		if not child or not child.Parent then return end
		for _, v in ipairs(child:GetDescendants()) do
			if v:IsA("TextButton") then
				local t = v.Text:lower()
				if t == "decline" or t == "tolak" or t == "no"
					or t:find("decline") or t:find("tolak") or t:find("reject") then
					pcall(function() v.MouseButton1Click:Fire() end)
					addLog("Carry request ditolak otomatis")
					return
				end
			end
		end
	end)
	table.insert(_S.c, conn)
end)

-- Startup notification
task.delay(1.2, function()
	sendWebhook("NazhanHub Aktif", "NazhanHub(free) v2.0 berhasil dijalankan.", 0xb49352)
end)

addLog("NazhanHub(free) v2.0 siap.")
setPhase(0)
