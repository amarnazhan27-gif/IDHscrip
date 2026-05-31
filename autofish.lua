-- ╔══════════════════════════════════════════════════════════╗
-- ║            NAZHAN FISHING SYSTEM — v1.0                 ║
-- ║         khusus fishing | ringan | anti-ngeleg           ║
-- ║              by nazhan • Indo Hangout                   ║
-- ╚══════════════════════════════════════════════════════════╝

if shared._NZH_fish then
	pcall(shared._NZH_fish.destroy)
end

-- ─── Module ──────────────────────────────────────────────
local NF = {
	alive = true,
	conns = {},
}
function NF.destroy()
	NF.alive = false
	for _, c in ipairs(NF.conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(NF.conns)
	-- cleanup ghost platform jika ada
	pcall(function()
		local pt = workspace:FindFirstChild("__nzh_plat")
		if pt then pt:Destroy() end
	end)
	-- lepas semua key virtual
	pcall(function()
		local VIM = game:GetService("VirtualInputManager")
		VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	end)
end
shared._NZH_fish = NF

-- ─── Services ────────────────────────────────────────────
local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local VIM      = game:GetService("VirtualInputManager")
local VU       = game:GetService("VirtualUser")
local TS       = game:GetService("TweenService")
local HTTP     = game:GetService("HttpService")
local me       = Players.LocalPlayer

-- ─── Rod Profiles ─────────────────────────────────────────
local RODS = {
	{ n="Basic Rod",    lure=1.00, prog=1.00 },
	{ n="Party Rod",    lure=1.30, prog=1.08 },
	{ n="Shark Rod",    lure=1.57, prog=1.21 },
	{ n="Piranha Rod",  lure=1.84, prog=1.33 },
	{ n="Thermo Rod",   lure=2.11, prog=1.46 },
	{ n="Flowers Rod",  lure=2.38, prog=1.59 },
	{ n="Trisula Rod",  lure=2.65, prog=1.72 },
	{ n="Feather Rod",  lure=2.92, prog=1.84 },
	{ n="Wave Rod",     lure=3.19, prog=1.97 },
	{ n="Duck Rod",     lure=3.46, prog=2.10 },
	{ n="Planet Rod",   lure=3.73, prog=2.23 },
	{ n="Earth Rod",    lure=4.00, prog=2.35 },
	{ n="Volcano Rod",  lure=4.27, prog=2.48 },
}
local rodIdx = 1

-- ─── Teleport Spots ───────────────────────────────────────
-- Koordinat spot tersembunyi di map Indo Hangout
-- Y sedikit lebih tinggi agar platform spawn dengan benar
local SPOTS = {
	{ label="🌊 Tengah Laut",          pos=Vector3.new(1840, 6, 1760)   },
	{ label="🏔️ Sisi Gunung Utara",   pos=Vector3.new(-420, 68, -1280) },
	{ label="🏝️ Pulau Terpencil",     pos=Vector3.new(-1740, 5, 980)  },
	{ label="⛵ Ujung Barat Laut",     pos=Vector3.new(-2100, 5, -900)  },
	{ label="🌅 Sudut Timur Jauh",     pos=Vector3.new(2250, 5, -180)   },
	{ label="🏞️ Sungai Tersembunyi",  pos=Vector3.new(380, 2, -1540)   },
	{ label="🪨 Balik Tebing Karang",  pos=Vector3.new(-820, 18, 1620)  },
	{ label="💧 Muara Sunyi",          pos=Vector3.new(960, 2, 1340)    },
}

-- ─── Timing Config ───────────────────────────────────────
local CFG = {
	castHold   = 1.8,    -- lama tahan klik saat cast
	biteWait   = 15.0,   -- detik tunggu gigitan
	recastDly  = 1.0,    -- jeda sebelum recast
	jitter     = true,   -- randomisasi kecil timing
	coordJitter= true,   -- geser posisi kursor sedikit
	fatigueOn  = true,   -- istirahat otomatis tiap N tangkapan
	fatEvery   = 20,     -- istirahat tiap 20 tangkapan
	fatDur     = 8,      -- durasi istirahat (detik)
	antiAFK    = true,   -- gerak mouse biar tidak AFK-kicked
	adminGuard = true,   -- kick diri sendiri jika admin masuk
	watchdog   = true,   -- auto reset saat macet
}

local FISH_TOOLS = { "Fishing Rod","Rod","Pancing","FishingRod" }

-- ─── State Variables ─────────────────────────────────────
local active     = false
local fishState  = "IDLE"   -- IDLE / CASTING / WAITING / MINIGAME / DONE
local isSpace    = false
local lastSpTgl  = 0
local biteStart  = 0
local mgStart    = 0
local mgLastSeen = 0
local mgEverSeen = false
local mgStarted  = false
local successDone= false
local isCasting  = false
local wBar,rBar  = nil, nil
local lastScan   = 0
local lastWC     = nil
local lastWTime  = os.clock()
local wVel       = 0
local castSess   = 0
local idleAt     = os.clock()

local fishCount    = 0
local sessionStart = os.clock()
local fatigueCnt   = 0

-- Discord Webhook
local webhookURL   = ""
local webhookOn    = false

-- ─── Helpers ─────────────────────────────────────────────
local function safe(fn)
	xpcall(fn, function(e) warn("[NZH] "..tostring(e)) end)
end

local function jt(base, pct)
	if not CFG.jitter then return base end
	return base * (1 + (math.random() * 2 - 1) * (pct or 0.1))
end

local function jv(v2)
	if not CFG.coordJitter then return v2 end
	return Vector2.new(v2.X + math.random(-14, 14), v2.Y + math.random(-10, 10))
end

-- (visibility check is defined later near the fishing engine for locality)

-- ─── Discord Webhook ──────────────────────────────────────
local function sendWebhook(title, body, color)
	if not webhookOn or webhookURL == "" then return end
	if not webhookURL:find("discord%.com/api/webhooks") then return end
	task.spawn(function()
		local elapsed = os.clock() - sessionStart
		local h,m,s  = math.floor(elapsed/3600), math.floor(elapsed%3600/60), math.floor(elapsed%60)
		local payload = HTTP:JSONEncode({
			embeds = {{
				title       = title,
				description = body,
				color       = color or 0x00aaff,
				fields      = {
					{ name="🎣 Total Tangkapan", value=tostring(fishCount),
					  inline=true },
					{ name="⏱️ Durasi Sesi",
					  value=string.format("%02d:%02d:%02d", h, m, s),
					  inline=true },
					{ name="🪝 Rod Aktif", value=RODS[rodIdx].n, inline=true },
				},
				footer = { text = "Nazhan Fishing System v1.0" },
			}}
		})
		local req = (syn and syn.request)
			or (http and http.request)
			or http_request or request
		if req then
			pcall(function()
				req({
					Url    = webhookURL,
					Method = "POST",
					Headers= { ["Content-Type"] = "application/json" },
					Body   = payload,
				})
			end)
		end
	end)
end

-- ─── GUI Cleanup ──────────────────────────────────────────
pcall(function()
	local names = { "_NZH_UI", "NH_v9_GUI", "IH_v5", "NH_v6_GUI" }
	local cg = game:GetService("CoreGui")
	for _, n in ipairs(names) do
		local a = cg:FindFirstChild(n)
		if a then a:Destroy() end
		if me.PlayerGui then
			local b = me.PlayerGui:FindFirstChild(n)
			if b then b:Destroy() end
		end
	end
end)

-- kecil delay biar tidak ada race condition dengan script lama
task.wait(math.random() * 0.15 + 0.05)

-- ─── ScreenGui ────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name            = "_NZH_UI"
gui.ResetOnSpawn    = false
gui.DisplayOrder    = 20
gui.IgnoreGuiInset  = false
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = me:WaitForChild("PlayerGui")
end

-- ─── Color Palette ───────────────────────────────────────
local C = {
	bg        = Color3.fromRGB(11, 12, 16),
	bg2       = Color3.fromRGB(17, 19, 25),
	card      = Color3.fromRGB(20, 22, 30),
	border    = Color3.fromRGB(34, 37, 50),
	accent    = Color3.fromRGB(0,  160, 255),
	accentGlo = Color3.fromRGB(30, 200, 255),
	green     = Color3.fromRGB(0,  210, 110),
	orange    = Color3.fromRGB(255,165,  40),
	red       = Color3.fromRGB(255, 60,  80),
	txt       = Color3.fromRGB(228, 232, 242),
	txtDim    = Color3.fromRGB(130, 136, 158),
	txtMuted  = Color3.fromRGB(68,  72,  92),
	sw_on     = Color3.fromRGB(0,  180, 100),
	sw_off    = Color3.fromRGB(38,  41,  55),
}

-- ─── GUI Builder Helpers ──────────────────────────────────
local function rnd(obj, r)
	Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r)
end

local function stroke(obj, col, thick)
	local s = Instance.new("UIStroke", obj)
	s.Color     = col or C.border
	s.Thickness = thick or 1
	return s
end

local function lbl(parent, props)
	local l = Instance.new("TextLabel", parent)
	l.BackgroundTransparency = 1
	l.Font     = props.font or Enum.Font.GothamMedium
	l.TextSize = props.size or 12
	l.TextColor3 = props.color or C.txt
	l.TextXAlignment = props.xa or Enum.TextXAlignment.Left
	l.TextTruncate   = Enum.TextTruncate.AtEnd
	l.Text     = props.text or ""
	l.Size     = props.sz   or UDim2.new(1, 0, 0, 18)
	l.Position = props.pos  or UDim2.new(0, 0, 0, 0)
	return l
end

local function btn(parent, props)
	local b = Instance.new("TextButton", parent)
	b.BackgroundColor3 = props.bg   or C.card
	b.Text             = props.text or ""
	b.TextColor3       = props.tc   or C.txt
	b.Font             = props.font or Enum.Font.GothamBold
	b.TextSize         = props.size or 11
	b.BorderSizePixel  = 0
	b.Size             = props.sz   or UDim2.new(0, 80, 0, 26)
	b.Position         = props.pos  or UDim2.new(0, 0, 0, 0)
	rnd(b, props.r or 7)
	if props.border ~= false then stroke(b, props.bColor or C.border) end
	-- hover feedback
	local origBg = b.BackgroundColor3
	local hoverBg = props.hover or origBg:Lerp(Color3.new(1,1,1), 0.06)
	b.MouseEnter:Connect(function()
		TS:Create(b, TweenInfo.new(0.14), {BackgroundColor3 = hoverBg}):Play()
	end)
	b.MouseLeave:Connect(function()
		TS:Create(b, TweenInfo.new(0.14), {BackgroundColor3 = origBg}):Play()
	end)
	return b
end

local function mkToggle(parent, y, label, default, cb)
	local row = Instance.new("Frame", parent)
	row.Size = UDim2.new(1, -24, 0, 30)
	row.Position = UDim2.new(0, 12, 0, y)
	row.BackgroundTransparency = 1

	local ltext = lbl(row, {
		text  = label,
		sz    = UDim2.new(1, -50, 1, 0),
		pos   = UDim2.new(0, 0, 0, 0),
		size  = 11,
		color = C.txtDim,
	})

	local sw = Instance.new("TextButton", row)
	sw.Size = UDim2.new(0, 36, 0, 19)
	sw.Position = UDim2.new(1, -36, 0.5, -9)
	sw.BackgroundColor3 = default and C.sw_on or C.sw_off
	sw.Text = ""; sw.BorderSizePixel = 0
	rnd(sw, 10)

	local knob = Instance.new("Frame", sw)
	knob.Size = UDim2.new(0, 15, 0, 15)
	knob.Position = default and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,2,0.5,-7)
	knob.BackgroundColor3 = Color3.new(1,1,1)
	knob.BorderSizePixel = 0
	rnd(knob, 10)

	local val = default
	sw.MouseButton1Click:Connect(function()
		if not NF.alive then return end
		val = not val
		TS:Create(sw,   TweenInfo.new(0.12), {BackgroundColor3 = val and C.sw_on or C.sw_off}):Play()
		TS:Create(knob, TweenInfo.new(0.12), {
			Position = val and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,2,0.5,-7)
		}):Play()
		cb(val)
	end)
	return row, sw
end

local function sep(parent, y)
	local f = Instance.new("Frame", parent)
	f.Size = UDim2.new(1, -24, 0, 1)
	f.Position = UDim2.new(0, 12, 0, y)
	f.BackgroundColor3 = C.border
	f.BorderSizePixel = 0
	return f
end

-- ─── Main Frame ───────────────────────────────────────────
local main = Instance.new("Frame", gui)
main.Size     = UDim2.new(0, 310, 0, 430)
main.Position = UDim2.new(1, -330, 0.5, -215)
main.BackgroundColor3 = C.bg
main.BackgroundTransparency = 0.04
main.BorderSizePixel = 0
main.Active    = true
main.Draggable = true
rnd(main, 13)
local mainBorder = stroke(main, C.border, 1.2)

-- subtle gradient border glow
local bGrad = Instance.new("UIGradient", mainBorder)
bGrad.Rotation = 90
bGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(0, 180, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 30, 55)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(0, 180, 255)),
})

-- animate border gradient slowly
task.spawn(function()
	local rot = 90
	while NF.alive do
		task.wait(0.04)
		rot = (rot + 0.4) % 360
		bGrad.Rotation = rot
	end
end)

-- Minimize float button
local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size = UDim2.new(0, 48, 0, 48)
floatBtn.Position = UDim2.new(1, -62, 0.5, -215)
floatBtn.BackgroundColor3 = C.bg
floatBtn.Text = "🎣"
floatBtn.TextSize = 20
floatBtn.BorderSizePixel = 0
floatBtn.Visible = false
rnd(floatBtn, 24)
stroke(floatBtn, C.accent, 1.5)

-- ─── Header ───────────────────────────────────────────────
local header = Instance.new("Frame", main)
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundColor3 = C.bg2
header.BorderSizePixel = 0
rnd(header, 13)

-- bottom half flat cover
local hCover = Instance.new("Frame", header)
hCover.Size = UDim2.new(1, 0, 0.5, 0)
hCover.Position = UDim2.new(0, 0, 0.5, 0)
hCover.BackgroundColor3 = C.bg2
hCover.BorderSizePixel = 0

-- divider
local hDiv = Instance.new("Frame", header)
hDiv.Size = UDim2.new(1, 0, 0, 1)
hDiv.Position = UDim2.new(0, 0, 1, -1)
hDiv.BackgroundColor3 = C.border
hDiv.BorderSizePixel = 0

-- accent dot
local dot = Instance.new("Frame", header)
dot.Size = UDim2.new(0, 6, 0, 6)
dot.Position = UDim2.new(0, 14, 0, 16)
dot.BackgroundColor3 = C.accent
dot.BorderSizePixel = 0
rnd(dot, 3)

lbl(header, {
	text  = "Nazhan Fishing",
	sz    = UDim2.new(0, 190, 0, 22),
	pos   = UDim2.new(0, 26, 0, 7),
	font  = Enum.Font.GothamBold,
	size  = 14,
	color = C.txt,
})
lbl(header, {
	text  = "Indo Hangout • Auto Fishing System",
	sz    = UDim2.new(0, 220, 0, 16),
	pos   = UDim2.new(0, 26, 0, 29),
	font  = Enum.Font.Gotham,
	size  = 9.5,
	color = C.txtDim,
})

local hideBtn = btn(header, {
	text  = "—",
	sz    = UDim2.new(0, 28, 0, 22),
	pos   = UDim2.new(1, -38, 0.5, -11),
	bg    = C.card,
	tc    = C.txtDim,
	size  = 14,
	r     = 6,
})

-- hide / show logic
local savedPos = main.Position
local hidden = false
local function setHide(h)
	hidden = h
	if h then
		savedPos = main.Position
		TS:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = UDim2.new(1, 50, 0.5, -215)}):Play()
		task.delay(0.23, function()
			if hidden then main.Visible=false; floatBtn.Visible=true end
		end)
	else
		main.Visible = true; floatBtn.Visible = false
		TS:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = savedPos}):Play()
	end
end
hideBtn.MouseButton1Click:Connect(function() setHide(true) end)
floatBtn.MouseButton1Click:Connect(function() setHide(false) end)

-- ─── Tab Bar ──────────────────────────────────────────────
local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1, 0, 0, 34)
tabBar.Position = UDim2.new(0, 0, 0, 54)
tabBar.BackgroundColor3 = C.bg2
tabBar.BorderSizePixel = 0

local tDiv = Instance.new("Frame", tabBar)
tDiv.Size = UDim2.new(1, 0, 0, 1)
tDiv.Position = UDim2.new(0, 0, 1, -1)
tDiv.BackgroundColor3 = C.border
tDiv.BorderSizePixel = 0

-- sliding indicator pill
local pill = Instance.new("Frame", tabBar)
pill.Size = UDim2.new(0.25, -8, 0, 2)
pill.Position = UDim2.new(0, 4, 1, -2)
pill.BackgroundColor3 = C.accent
pill.BorderSizePixel = 0
rnd(pill, 2)

local TABS    = { "Fishing", "Teleport", "Settings", "Webhook" }
local tabBtns = {}
local panels  = {}

local body = Instance.new("Frame", main)
body.Size = UDim2.new(1, 0, 1, -88)
body.Position = UDim2.new(0, 0, 0, 88)
body.BackgroundTransparency = 1
body.ClipsDescendants = true

for i, name in ipairs(TABS) do
	local tb = Instance.new("TextButton", tabBar)
	tb.Size = UDim2.new(0.25, 0, 1, -2)
	tb.Position = UDim2.new((i-1)*0.25, 0, 0, 0)
	tb.BackgroundTransparency = 1
	tb.BorderSizePixel = 0
	tb.Text = name
	tb.TextColor3 = (i==1) and C.txt or C.txtMuted
	tb.Font = Enum.Font.GothamMedium
	tb.TextSize = 10
	tabBtns[name] = tb

	local p = Instance.new("Frame", body)
	p.Size = UDim2.new(1, 0, 1, 0)
	p.BackgroundTransparency = 1
	p.Visible = (i==1)
	panels[name] = p
end

local activeTab = "Fishing"
local function switchTab(name)
	if activeTab == name then return end
	activeTab = name
	local idx = table.find(TABS, name)
	TS:Create(pill, TweenInfo.new(0.18, Enum.EasingStyle.Quad),
		{Position = UDim2.new((idx-1)*0.25, 4, 1, -2)}):Play()
	for n, tb in pairs(tabBtns) do
		tb.TextColor3 = (n==name) and C.txt or C.txtMuted
		panels[n].Visible = (n==name)
	end
end
for name, tb in pairs(tabBtns) do
	tb.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ═══════════════════════════════════════════════════════════
-- TAB 1: FISHING
-- ═══════════════════════════════════════════════════════════
local pF = panels["Fishing"]

-- ── Status Card ──
local stCard = Instance.new("Frame", pF)
stCard.Size = UDim2.new(1, -24, 0, 64)
stCard.Position = UDim2.new(0, 12, 0, 10)
stCard.BackgroundColor3 = C.card
stCard.BorderSizePixel = 0
rnd(stCard, 8)
stroke(stCard)

-- live indicator dot
local liveDot = Instance.new("Frame", stCard)
liveDot.Size = UDim2.new(0, 7, 0, 7)
liveDot.Position = UDim2.new(0, 11, 0, 12)
liveDot.BackgroundColor3 = C.txtMuted
liveDot.BorderSizePixel = 0
rnd(liveDot, 4)

local statusLbl = lbl(stCard, {
	text  = "Idle",
	sz    = UDim2.new(1, -30, 0, 18),
	pos   = UDim2.new(0, 23, 0, 6),
	font  = Enum.Font.GothamBold,
	size  = 12,
	color = C.txt,
})

local caughtLbl = lbl(stCard, {
	text  = "Tangkapan: 0 ikan",
	sz    = UDim2.new(1, -20, 0, 15),
	pos   = UDim2.new(0, 11, 0, 26),
	size  = 10,
	color = C.txtDim,
})

local rateLbl = lbl(stCard, {
	text  = "Rate: — ikan/jam  •  Sesi: 00:00:00",
	sz    = UDim2.new(1, -20, 0, 15),
	pos   = UDim2.new(0, 11, 0, 44),
	size  = 9.5,
	color = C.txtMuted,
})

-- Live dot pulse animation
local dotPulse = TS:Create(liveDot, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{BackgroundColor3 = Color3.new(1,1,1)})

local function setDot(color)
	dotPulse:Cancel()
	liveDot.BackgroundColor3 = color
	dotPulse = TS:Create(liveDot, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.5)})
	dotPulse:Play()
end
setDot(C.txtMuted)

-- ── Phase Progress Bar ──
local phBar = Instance.new("Frame", pF)
phBar.Size = UDim2.new(1, -24, 0, 38)
phBar.Position = UDim2.new(0, 12, 0, 82)
phBar.BackgroundTransparency = 1

local barBg = Instance.new("Frame", phBar)
barBg.Size = UDim2.new(1, 0, 0, 3)
barBg.Position = UDim2.new(0, 0, 0, 6)
barBg.BackgroundColor3 = C.border
barBg.BorderSizePixel = 0
rnd(barBg, 2)

local barFill = Instance.new("Frame", barBg)
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = C.accent
barFill.BorderSizePixel = 0
rnd(barFill, 2)

local phNames  = {"Cast","Wait","Game","Done"}
local phColors = {C.accent, C.orange, C.red, C.green}
local phLbls   = {}
for i, pn in ipairs(phNames) do
	local pl = lbl(phBar, {
		text  = pn,
		sz    = UDim2.new(0.25, 0, 0, 16),
		pos   = UDim2.new((i-1)*0.25, 0, 0, 14),
		size  = 9.5,
		color = C.txtMuted,
		font  = Enum.Font.GothamBold,
		xa    = Enum.TextXAlignment.Center,
	})
	pl.TextXAlignment = Enum.TextXAlignment.Center
	phLbls[i] = pl
end

local activePh = 0
local function setPhase(ph)
	activePh = ph
	for i=1,4 do
		if i < ph then        phLbls[i].TextColor3 = C.txtDim
		elseif i == ph then   phLbls[i].TextColor3 = phColors[i]
		else                  phLbls[i].TextColor3 = C.txtMuted end
	end
	if ph == 0 then
		TS:Create(barFill, TweenInfo.new(0.14), {Size=UDim2.new(0,0,1,0), BackgroundColor3=C.accent}):Play()
	else
		TS:Create(barFill, TweenInfo.new(0.14), {
			Size=UDim2.new(math.clamp(ph*0.25,0,1),0,1,0),
			BackgroundColor3=phColors[ph],
		}):Play()
	end
end

local function setPct(f)
	if activePh<=0 then return end
	barFill.Size = UDim2.new(math.clamp((activePh-1)*0.25 + f*0.25,0,1),0,1,0)
end

sep(pF, 127)

-- ── Rod Selector ──
local rodCard = Instance.new("Frame", pF)
rodCard.Size = UDim2.new(1, -24, 0, 48)
rodCard.Position = UDim2.new(0, 12, 0, 134)
rodCard.BackgroundColor3 = C.card
rodCard.BorderSizePixel = 0
rnd(rodCard, 8)
stroke(rodCard)

lbl(rodCard, {
	text  = "Rod Selection",
	sz    = UDim2.new(0, 140, 0, 16),
	pos   = UDim2.new(0, 10, 0, 4),
	size  = 9,
	color = C.txtMuted,
	font  = Enum.Font.GothamBold,
})

local prevB = btn(rodCard, {
	text = "‹", sz = UDim2.new(0,22,0,20), pos = UDim2.new(0,8,0,22),
	bg=C.bg, tc=C.txtDim, size=13, r=5, bColor=C.border,
})
local nextB = btn(rodCard, {
	text = "›", sz = UDim2.new(0,22,0,20), pos = UDim2.new(1,-30,0,22),
	bg=C.bg, tc=C.txtDim, size=13, r=5, bColor=C.border,
})
local rodName = lbl(rodCard, {
	text  = RODS[1].n,
	sz    = UDim2.new(1,-64,0,20),
	pos   = UDim2.new(0,34,0,22),
	size  = 11,
	color = C.accent,
	font  = Enum.Font.GothamBold,
	xa    = Enum.TextXAlignment.Center,
})
rodName.TextXAlignment = Enum.TextXAlignment.Center

local rodStat = lbl(rodCard, {
	text  = "",
	sz    = UDim2.new(1,-16,0,12),
	pos   = UDim2.new(0,8,0,36),
	size  = 8.5,
	color = C.txtMuted,
	xa    = Enum.TextXAlignment.Center,
})
rodStat.TextXAlignment = Enum.TextXAlignment.Center
rodStat.Visible = false  -- shown below the card

-- updated: show stat in the card itself bottom row
rodStat.Size = UDim2.new(1,-64,0,12)
rodStat.Position = UDim2.new(0,34,0,36)
rodStat.Visible = true

local function updateRod()
	local r = RODS[rodIdx]
	rodName.Text = r.n
	rodStat.Text = string.format("Lure %.0f%%  |  Prog %.0f%%", r.lure*100, r.prog*100)
end
updateRod()
prevB.MouseButton1Click:Connect(function()
	rodIdx = (rodIdx<=1) and #RODS or rodIdx-1; updateRod()
end)
nextB.MouseButton1Click:Connect(function()
	rodIdx = (rodIdx>=#RODS) and 1 or rodIdx+1; updateRod()
end)

sep(pF, 190)

-- ── Main Toggle ──
mkToggle(pF, 196, "Auto Fishing Aktif", false, function(on)
	active = on
	if on then
		fishState="IDLE"; idleAt=os.clock()
		setDot(C.green)
		setPhase(0)
		statusLbl.Text = "Starting..."
	else
		active = false
		isSpace = false
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		setDot(C.txtMuted)
		setPhase(0)
		statusLbl.Text = "Idle"
		sendWebhook("⏹ Fishing Dihentikan",
			"Sistem auto-fishing dimatikan secara manual.", 0x888888)
	end
end)

-- ── Reset Button ──
local rstBtn = btn(pF, {
	text  = "Reset Session",
	sz    = UDim2.new(1,-24,0,28),
	pos   = UDim2.new(0,12,0,232),
	bg    = Color3.fromRGB(28, 20, 24),
	tc    = Color3.fromRGB(220, 80, 100),
	size  = 10.5,
	r     = 7,
	bColor= Color3.fromRGB(60, 30, 40),
})

-- fishState reset function — declared here but defined later
local doReset

rstBtn.MouseButton1Click:Connect(function()
	if doReset then doReset("manual") end
end)

-- Session timer thread
task.spawn(function()
	while NF.alive do
		task.wait(1)
		local el = os.clock() - sessionStart
		local h  = math.floor(el/3600)
		local m  = math.floor(el%3600/60)
		local s  = math.floor(el%60)
		local rate = fishCount > 0 and (fishCount / math.max(el/3600, 0.01)) or 0
		rateLbl.Text = string.format(
			"Rate: %.1f ikan/jam  •  Sesi: %02d:%02d:%02d",
			rate, h, m, s
		)
	end
end)

-- ═══════════════════════════════════════════════════════════
-- TAB 2: TELEPORT
-- ═══════════════════════════════════════════════════════════
local pT = panels["Teleport"]

lbl(pT, {
	text  = "SPOT TERSEMBUNYI",
	sz    = UDim2.new(1,-24,0,16),
	pos   = UDim2.new(0,12,0,8),
	size  = 9,
	color = C.txtMuted,
	font  = Enum.Font.GothamBold,
})

-- Generate platform to stand on (prevents sinking)
local function spawnPlatform(pos)
	pcall(function()
		local old = workspace:FindFirstChild("__nzh_plat")
		if old then old:Destroy() end
	end)
	local plat = Instance.new("Part")
	plat.Name = "__nzh_plat"
	plat.Anchored = true
	plat.CanCollide = true
	plat.Size = Vector3.new(16, 1, 16)
	plat.Position = pos - Vector3.new(0, 3.5, 0)
	plat.Material = Enum.Material.SmoothPlastic
	plat.Color = Color3.fromRGB(20, 60, 100)
	plat.Transparency = 0.65
	plat.Parent = workspace
	return plat
end

local function doTeleport(pos)
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	spawnPlatform(pos)
	task.wait(0.08)
	root.CFrame = CFrame.new(pos)
end

local tSF = Instance.new("ScrollingFrame", pT)
tSF.Size = UDim2.new(1, 0, 1, -30)
tSF.Position = UDim2.new(0, 0, 0, 28)
tSF.BackgroundTransparency = 1
tSF.BorderSizePixel = 0
tSF.CanvasSize = UDim2.new(0, 0, 0, #SPOTS * 44 + 12)
tSF.ScrollBarThickness = 3
tSF.ScrollBarImageColor3 = C.border

for idx, spot in ipairs(SPOTS) do
	local row = Instance.new("Frame", tSF)
	row.Size = UDim2.new(1, -24, 0, 36)
	row.Position = UDim2.new(0, 12, 0, (idx-1)*42 + 6)
	row.BackgroundColor3 = C.card
	row.BorderSizePixel = 0
	rnd(row, 7)
	stroke(row)

	lbl(row, {
		text  = spot.label,
		sz    = UDim2.new(0.65, 0, 1, 0),
		pos   = UDim2.new(0, 10, 0, 0),
		size  = 10.5,
		color = C.txtDim,
		font  = Enum.Font.GothamMedium,
	})

	local tpBtn = btn(row, {
		text  = "Teleport",
		sz    = UDim2.new(0.3, -4, 0, 24),
		pos   = UDim2.new(0.7, 0, 0.5, -12),
		bg    = C.accent,
		tc    = Color3.new(1,1,1),
		size  = 9.5,
		r     = 6,
		border= false,
	})

	local capturedPos = spot.pos
	tpBtn.MouseButton1Click:Connect(function()
		doTeleport(capturedPos)
		statusLbl.Text = "Pindah ke " .. spot.label:gsub("^%S+%s*", "")
	end)
end

-- ═══════════════════════════════════════════════════════════
-- TAB 3: SETTINGS
-- ═══════════════════════════════════════════════════════════
local pS = panels["Settings"]

local sSF = Instance.new("ScrollingFrame", pS)
sSF.Size = UDim2.new(1, 0, 1, 0)
sSF.BackgroundTransparency = 1
sSF.BorderSizePixel = 0
sSF.CanvasSize = UDim2.new(0, 0, 0, 320)
sSF.ScrollBarThickness = 3
sSF.ScrollBarImageColor3 = C.border

lbl(sSF, {
	text  = "ANTI-DETEKSI",
	sz    = UDim2.new(1,-24,0,14),
	pos   = UDim2.new(0,12,0,8),
	size  = 9, color = C.txtMuted, font = Enum.Font.GothamBold,
})
sep(sSF, 24)

local sY = 30
mkToggle(sSF, sY, "Jitter Timing Cast", CFG.jitter, function(v) CFG.jitter=v end)
sY = sY+33
mkToggle(sSF, sY, "Jitter Posisi Kursor", CFG.coordJitter, function(v) CFG.coordJitter=v end)
sY = sY+33
mkToggle(sSF, sY, "Anti-AFK Mouse Sweep", CFG.antiAFK, function(v) CFG.antiAFK=v end)
sY = sY+33
sep(sSF, sY+3); sY=sY+12

lbl(sSF, {
	text  = "ISTIRAHAT OTOMATIS",
	sz    = UDim2.new(1,-24,0,14),
	pos   = UDim2.new(0,12,0,sY),
	size  = 9, color = C.txtMuted, font = Enum.Font.GothamBold,
})
sY=sY+18
sep(sSF, sY); sY=sY+8
mkToggle(sSF, sY, "Aktifkan Fatigue Break", CFG.fatigueOn, function(v) CFG.fatigueOn=v end)
sY=sY+33
sep(sSF, sY+3); sY=sY+12

lbl(sSF, {
	text  = "KEAMANAN",
	sz    = UDim2.new(1,-24,0,14),
	pos   = UDim2.new(0,12,0,sY),
	size  = 9, color = C.txtMuted, font = Enum.Font.GothamBold,
})
sY=sY+18
sep(sSF, sY); sY=sY+8
mkToggle(sSF, sY, "Admin Guard (Auto-Kick)", CFG.adminGuard, function(v) CFG.adminGuard=v end)
sY=sY+33
mkToggle(sSF, sY, "Watchdog Auto-Reset", CFG.watchdog, function(v) CFG.watchdog=v end)

sSF.CanvasSize = UDim2.new(0, 0, 0, sY+50)

-- ═══════════════════════════════════════════════════════════
-- TAB 4: WEBHOOK & LOG
-- ═══════════════════════════════════════════════════════════
local pW = panels["Webhook"]

-- Webhook input card
local whCard = Instance.new("Frame", pW)
whCard.Size = UDim2.new(1,-24,0,96)
whCard.Position = UDim2.new(0,12,0,10)
whCard.BackgroundColor3 = C.card
whCard.BorderSizePixel = 0
rnd(whCard, 8)
stroke(whCard)

lbl(whCard, {
	text  = "🔔  DISCORD WEBHOOK",
	sz    = UDim2.new(1,-14,0,14),
	pos   = UDim2.new(0,10,0,6),
	size  = 9.5, color = C.txtMuted, font = Enum.Font.GothamBold,
})

local whBox = Instance.new("TextBox", whCard)
whBox.Size = UDim2.new(1,-20,0,22)
whBox.Position = UDim2.new(0,10,0,22)
whBox.BackgroundColor3 = C.bg
whBox.TextColor3 = C.txt
whBox.PlaceholderText = "Paste link webhook Discord kamu..."
whBox.PlaceholderColor3 = C.txtMuted
whBox.Text = webhookURL
whBox.ClearTextOnFocus = false
whBox.Font = Enum.Font.Code
whBox.TextSize = 9.5
whBox.TextXAlignment = Enum.TextXAlignment.Left
whBox.BorderSizePixel = 0
rnd(whBox, 5)
stroke(whBox)

whBox.FocusLost:Connect(function()
	webhookURL = whBox.Text
end)

-- Enable / Disable webhook
local whToggleRow, _ = mkToggle(whCard, 48, "Kirim Notifikasi Discord", false, function(v)
	webhookOn = v
end)

local testBtn = btn(whCard, {
	text  = "Test Ping",
	sz    = UDim2.new(0, 72, 0, 20),
	pos   = UDim2.new(1, -80, 0, 70),
	bg    = C.bg,
	tc    = C.accent,
	size  = 9.5,
	r     = 5,
})
testBtn.MouseButton1Click:Connect(function()
	sendWebhook("🧪 Test Webhook",
		"Koneksi dari Roblox berhasil! Sistem notifikasi aktif.", 0x00ff88)
end)

sep(pW, 112)

-- Console Log
lbl(pW, {
	text  = "CONSOLE LOG",
	sz    = UDim2.new(1,-24,0,14),
	pos   = UDim2.new(0,12,0,118),
	size  = 9, color = C.txtMuted, font = Enum.Font.GothamBold,
})

local consoleEnabled = false
-- Log toggle & clear — placed to the right of the section header
local logBtn = btn(pW, {
	text  = "Log: OFF",
	sz    = UDim2.new(0,56,0,18),
	pos   = UDim2.new(1,-124,0,116),
	bg    = C.card,
	tc    = C.txtMuted,
	size  = 9, r = 4,
})
local clearBtn = btn(pW, {
	text  = "Clear",
	sz    = UDim2.new(0,44,0,18),
	pos   = UDim2.new(1,-68,0,116),
	bg    = C.card,
	tc    = C.txtMuted,
	size  = 9, r = 4,
})

local logSF = Instance.new("ScrollingFrame", pW)
logSF.Size = UDim2.new(1,-24,1,-142)
logSF.Position = UDim2.new(0,12,0,140)
logSF.BackgroundColor3 = C.bg2
logSF.BorderSizePixel = 0
rnd(logSF, 6)
stroke(logSF)
logSF.CanvasSize = UDim2.new(0,0,0,0)
logSF.ScrollBarThickness = 3
logSF.ScrollBarImageColor3 = C.border

local logList = Instance.new("UIListLayout", logSF)
logList.SortOrder = Enum.SortOrder.LayoutOrder
logList.Padding = UDim.new(0,2)

local logN = 0
local function addLog(txt)
	if not consoleEnabled then return end
	logN = logN + 1
	local row = Instance.new("TextLabel", logSF)
	row.LayoutOrder = logN
	row.Size = UDim2.new(1, 0, 0, 14)
	row.BackgroundTransparency = 1
	row.Text = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(txt))
	row.TextColor3 = C.txtDim
	row.Font = Enum.Font.Code
	row.TextSize = 9
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextWrapped = true
	task.defer(function()
		logSF.CanvasSize = UDim2.new(0,0,0, logList.AbsoluteContentSize.Y + 4)
		logSF.CanvasPosition = Vector2.new(0, math.huge)
	end)
	-- trim old logs
	local kids = logSF:GetChildren()
	local count = 0
	for _, k in ipairs(kids) do if k:IsA("TextLabel") then count=count+1 end end
	if count > 60 then
		for _, k in ipairs(kids) do
			if k:IsA("TextLabel") then k:Destroy(); break end
		end
	end
end

logBtn.MouseButton1Click:Connect(function()
	consoleEnabled = not consoleEnabled
	logBtn.Text = consoleEnabled and "Log: ON" or "Log: OFF"
	logBtn.TextColor3 = consoleEnabled and C.green or C.txtMuted
end)
clearBtn.MouseButton1Click:Connect(function()
	for _, k in ipairs(logSF:GetChildren()) do
		if k:IsA("TextLabel") then k:Destroy() end
	end
	logSF.CanvasSize = UDim2.new(0,0,0,0)
	logN = 0
end)

-- ═══════════════════════════════════════════════════════════
-- FISHING ENGINE
-- ═══════════════════════════════════════════════════════════

local function trulyVis(obj)
	if not obj or typeof(obj)~="Instance" then return false end
	if not obj:IsA("GuiObject") or not obj.Visible then return false end
	local ok,sz = pcall(function() return obj.AbsoluteSize end)
	if not ok or sz.X<=0 or sz.Y<=0 then return false end
	local cur = obj.Parent
	while cur and cur~=game do
		if cur:IsA("ScreenGui") then if not cur.Enabled then return false end; break
		elseif cur:IsA("GuiObject") then if not cur.Visible then return false end end
		cur = cur.Parent
	end
	return true
end

local function findTool()
	local ch = me.Character
	local bp = me.Backpack
	if ch then
		for _, n in ipairs(FISH_TOOLS) do
			local t = ch:FindFirstChild(n)
			if t and t:IsA("Tool") then return t end
		end
		local any = ch:FindFirstChildWhichIsA("Tool")
		if any then return any end
	end
	for _, n in ipairs(FISH_TOOLS) do
		local t = bp:FindFirstChild(n)
		if t then return t end
	end
	return bp:FindFirstChildWhichIsA("Tool")
end

local function equipRod()
	local ch = me.Character
	if not ch then return nil end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local eq = ch:FindFirstChildWhichIsA("Tool")
	if eq then return eq end
	local t = findTool()
	if t then
		pcall(function() hum:EquipTool(t) end)
		task.wait(0.55)
		return ch:FindFirstChildWhichIsA("Tool")
	end
	return nil
end

-- Space key control
local function setSpace(v, force)
	if isSpace==v and not force then return end
	local now = os.clock()
	if not force and (now-lastSpTgl)<0.03 then return end
	pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
	isSpace=v; lastSpTgl=now
end

-- Minigame bar detection
local function getBars()
	if wBar and rBar and wBar.Parent and rBar.Parent
		and trulyVis(wBar) and trulyVis(rBar) then
		return wBar, rBar
	end
	local now = os.clock()
	if now-lastScan < 0.05 then return nil,nil end
	lastScan=now; wBar=nil; rBar=nil

	local pg = me:FindFirstChild("PlayerGui")
	if not pg then return nil,nil end

	-- Pass 1: name-based scan
	for _, v in ipairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVis(v) then
			local ln = v.Name:lower()
			local par = v.Parent
			if par and par:IsA("GuiObject") then
				local isW = ln=="whitebar" or ln=="playerbar"
					or (ln:find("white") and ln:find("bar"))
				if isW then
					for _, sib in ipairs(par:GetChildren()) do
						if sib~=v and sib:IsA("GuiObject") and trulyVis(sib) then
							local sn = sib.Name:lower()
							if sn:find("red") or sn:find("target") or sn:find("goal") then
								if v.AbsoluteSize.X > 10 then
									wBar=v; rBar=sib; return v,sib
								end
							end
						end
					end
				end
			end
		end
	end

	-- Pass 2: color-based scan (fallback)
	for _, v in ipairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVis(v)
			and v.AbsoluteSize.X>12 and v.AbsoluteSize.Y>5 then
			local c   = v.BackgroundColor3
			local par = v.Parent
			if c.R>0.78 and c.G>0.78 and c.B>0.78
				and par and par:IsA("GuiObject") then
				for _, sib in ipairs(par:GetChildren()) do
					if sib~=v and sib:IsA("GuiObject") and trulyVis(sib)
						and sib.AbsoluteSize.X>12 then
						local sc = sib.BackgroundColor3
						if sc.R>0.46 and sc.G<0.22 and sc.B<0.22 then
							wBar=v; rBar=sib; return v,sib
						end
					end
				end
			end
		end
	end
	return nil,nil
end

-- Fatigue / rest break
local function checkFatigue()
	if not CFG.fatigueOn then return end
	fatigueCnt = fatigueCnt + 1
	if fatigueCnt < CFG.fatEvery then return end
	fatigueCnt = 0
	addLog("Fatigue break " .. CFG.fatDur .. "s...")
	setSpace(false, true)
	setPhase(0)
	statusLbl.Text = "Istirahat " .. CFG.fatDur .. "s"
	setDot(C.orange)
	task.wait(CFG.fatDur)
	setDot(C.green)
end

-- Reset function
doReset = function(reason)
	fishState  = "IDLE"
	isSpace    = false
	isCasting  = false
	successDone= false
	mgEverSeen = false
	mgStarted  = false
	wBar       = nil
	rBar       = nil
	lastScan   = 0
	lastWC     = nil
	wVel       = 0
	mgLastSeen = 0
	castSess   = castSess + 1
	idleAt     = os.clock()
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
	setPhase(0)
	if active then
		statusLbl.Text = "Idle"
		setDot(C.green)
	end
	if reason then
		addLog("Reset: " .. reason)
	end
end

-- Fish caught handler
local function onCatch(why)
	if successDone then return end
	successDone = true
	setSpace(false, true)
	fishState  = "DONE"
	setPhase(4)
	fishCount  = fishCount + 1

	caughtLbl.Text = "Tangkapan: " .. fishCount .. " ikan"
	statusLbl.Text = "Caught #" .. fishCount
	setDot(C.green)
	addLog("Caught #" .. fishCount .. "  (" .. why .. ")")

	-- Webhook: ikan tertangkap
	if fishCount == 1 or fishCount % 10 == 0 then
		sendWebhook("🐟 Update Tangkapan",
			string.format("Sudah menangkap **%d ikan** dalam sesi ini.", fishCount),
			0x00aaff)
	end

	checkFatigue()

	local sess = castSess
	task.delay(jt(CFG.recastDly, 0.15), function()
		if not NF.alive or not active or castSess~=sess then return end
		doReset(nil)
		task.wait(0.06)
		if active then fishState="IDLE"; idleAt=os.clock() end
	end)
end

-- Heartbeat controller — throttled to ~60fps, very light
local hbLast = 0
local hbConn = RS.Heartbeat:Connect(function()
	if not NF.alive then return end
	if not active then
		if isSpace then setSpace(false,true) end
		return
	end
	local now = os.clock()
	if now - hbLast < 0.016 then return end
	hbLast = now
	safe(function()
		local rod = RODS[rodIdx]

		-- ── WAITING state ──────────────────────────────────
		if fishState == "WAITING" then
			local el = now - biteStart
			setPct(math.clamp(el/CFG.biteWait, 0, 1))
			statusLbl.Text = string.format("Menunggu... %.0fs", math.max(0, CFG.biteWait-el))
			if el >= CFG.biteWait then
				-- Bite time reached → start minigame phase
				fishState   = "MINIGAME"
				mgStart     = now
				mgEverSeen  = false
				mgStarted   = false
				mgLastSeen  = 0
				successDone = false
				wBar=nil; rBar=nil
				lastScan=0; lastWC=nil; wVel=0; lastWTime=now
				setSpace(false, true)
				setPhase(3); setPct(0)
				statusLbl.Text = "Minigame!"
				addLog("Minigame started")
			end
			return
		end

		-- ── MINIGAME state ─────────────────────────────────
		if fishState ~= "MINIGAME" then return end

		local el      = now - mgStart
		local timeout = 11 + rod.prog * 3.2
		setPct(math.clamp(el/timeout, 0, 1))

		if el >= timeout then
			setSpace(false, true)
			onCatch("timeout")
			return
		end

		local wb, rb = getBars()
		if wb and rb and trulyVis(wb) and trulyVis(rb) then
			mgEverSeen = true; mgLastSeen = now
			if not mgStarted then
				mgStarted = true
				setSpace(false, true)
				lastWC=nil; wVel=0; lastWTime=now
			end

			local wC   = wb.AbsolutePosition.X + wb.AbsoluteSize.X*0.5
			local rL   = rb.AbsolutePosition.X
			local rR   = rL + rb.AbsoluteSize.X
			local rC   = (rL+rR)*0.5
			local rawDt= now - lastWTime
			local dt   = math.clamp(rawDt, 0.007, 0.13)

			if lastWC then
				local inst = (wC-lastWC)/dt
				local sm   = math.clamp(0.26/rod.lure, 0.1, 0.30)
				wVel = wVel*(1-sm) + inst*sm
			end
			lastWC=wC; lastWTime=now

			local ahead  = math.clamp(math.abs(wVel)/1650, 0.03, 0.17) * math.sqrt(rod.lure)
			local pred   = wC + wVel*ahead
			local rw     = math.max(rb.AbsoluteSize.X, 1)
			local lag    = math.clamp(rawDt/0.05-1, 0, 1.2)
			local tol    = math.clamp(rw*(0.16 + lag*0.14 + rod.lure*0.025), 4, 25)
			local inside = pred>=(rL-tol) and pred<=(rR+tol)

			if inside then
				if     wC < rL then setSpace(true)
				elseif wC > rR then setSpace(false)
				else
					local e = wC - rC
					if math.abs(e) > tol*0.4 then setSpace(e<0) end
				end
			else
				local e = rC - pred
				if     e >  tol then setSpace(true)
				elseif e < -tol then setSpace(false)
				elseif math.abs(wVel) > 135 then setSpace(wVel<0) end
			end

			statusLbl.Text = string.format("Playing... %.0fs", el)
		else
			if mgEverSeen then
				if mgLastSeen>0 and (now-mgLastSeen)>=0.20 then
					setSpace(false,true)
					onCatch("bar-gone")
				end
			else
				-- pre-bar sync pulse to trigger bite detection
				local beat = math.floor((now-mgStart)*3.0)%2 == 0
				setSpace(beat)
				statusLbl.Text = string.format("Sync... %.0fs", el)
			end
		end
	end)
end)
table.insert(NF.conns, hbConn)

-- Cast loop — controls the rod activation cycle
task.spawn(function()
	while NF.alive do
		task.wait(0.14)
		if not NF.alive or not active then continue end
		safe(function()
			local ch  = me.Character; if not ch then return end
			local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return end

			-- disable jumping so character stays put while fishing
			if hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			end

			local tool = equipRod()
			if not tool then
				statusLbl.Text = "No Rod!"
				setDot(C.red)
				return
			end

			if fishState=="IDLE" and not isCasting then
				isCasting = true
				castSess  = castSess + 1
				local sess = castSess

				task.spawn(function()
					if not NF.alive or not active or castSess~=sess then
						isCasting=false; return
					end
					local cam = workspace.CurrentCamera
					if not cam then isCasting=false; return end

					local rod = RODS[rodIdx]
					local ctr = jv(cam.ViewportSize/2)

					fishState = "CASTING"
					setPhase(1); setPct(0)
					statusLbl.Text = "Casting..."
					setDot(C.accent)

					pcall(function() tool:Activate() end)
					pcall(function() VU:Button1Down(ctr, cam.CFrame) end)

					local dur = jt(CFG.castHold / math.max(1, math.sqrt(rod.lure)*0.85), 0.1)
					local t0  = os.clock()
					while os.clock()-t0 < dur do
						task.wait(0.04)
						if not active or not NF.alive or castSess~=sess then
							pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
							isCasting=false; return
						end
						setPct((os.clock()-t0)/dur)
					end
					pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
					setPct(1)

					task.wait(jt(0.13, 0.08))
					if not active or not NF.alive or castSess~=sess then
						isCasting=false; return
					end

					fishState  = "WAITING"
					biteStart  = os.clock()
					setPhase(2); setPct(0)
					statusLbl.Text = "Menunggu..."
					setDot(C.orange)
					addLog("Cast #" .. castSess)
					isCasting  = false
				end)
			end
		end)
	end
end)

-- Watchdog — runs every 5s, lightweight
task.spawn(function()
	while NF.alive do
		task.wait(5)
		if not NF.alive or not active or not CFG.watchdog then continue end
		local now = os.clock()
		local evt = nil
		if   fishState=="IDLE"    and not isCasting and (now-idleAt)>12 then
			evt = "idle-lock"
		elseif fishState=="WAITING" and (now-biteStart)>(CFG.biteWait+9) then
			evt = "bite-timeout"
		elseif fishState=="CASTING" and not isCasting and (now-idleAt)>10 then
			evt = "cast-stuck"
		end
		if evt then
			addLog("Watchdog: " .. evt .. " — resetting")
			sendWebhook("⚠️ Watchdog Reset",
				"Bot mengalami stuck (" .. evt .. ") dan melakukan reset otomatis.",
				0xffaa00)
			doReset(evt)
		end
	end
end)

-- Anti-AFK mouse sweep
task.spawn(function()
	while NF.alive do
		task.wait(math.random(85, 145))
		if not NF.alive then break end
		if CFG.antiAFK then
			pcall(function()
				local cam = workspace.CurrentCamera
				if cam then
					local sz = cam.ViewportSize
					VU:MouseMoveEvent(
						Vector2.new(sz.X/2 + math.random(-60,60), sz.Y/2 + math.random(-45,45)),
						cam.CFrame)
				end
			end)
		end
	end
end)

-- Anti-AFK idle event
local idleConn = me.Idled:Connect(function()
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam then
			VU:Button2Down(Vector2.new(0,0), cam.CFrame)
			task.wait(0.1)
			VU:Button2Up(Vector2.new(0,0), cam.CFrame)
		end
	end)
end)
table.insert(NF.conns, idleConn)

-- Admin Guard
local ADMIN_PATS = {
	"moderator","roblox_adm","rbxadmin","staffmod",
	"gamemaster","game_master","rblxmod",
}
local STAFF_GRP = 1200769

local function checkPlayer(p)
	if p==me or not p.Parent or not CFG.adminGuard then return end
	task.wait(2.5)
	if not p or not p.Parent then return end
	local isAdmin = false
	pcall(function() isAdmin = isAdmin or p:IsInGroup(STAFF_GRP) end)
	if not isAdmin then
		local ln = (p.Name..p.DisplayName):lower()
		for _, pat in ipairs(ADMIN_PATS) do
			if ln:find(pat) then isAdmin=true; break end
		end
	end
	if not isAdmin then
		pcall(function()
			if game.CreatorType==Enum.CreatorType.Group then
				if p:GetRankInGroup(game.CreatorId)>=200 then isAdmin=true end
			end
		end)
	end
	if isAdmin then
		addLog("Admin detected: " .. p.Name .. " — disconnecting!")
		sendWebhook("🚨 Admin Masuk!",
			string.format("Terdeteksi admin **%s** masuk server. Auto-disconnect dilakukan.", p.Name),
			0xff2244)
		active=false
		setSpace(false,true)
		task.wait(0.8)
		me:Kick("Disconnected.")
	end
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(checkPlayer, p) end
local paConn = Players.PlayerAdded:Connect(function(p) task.spawn(checkPlayer,p) end)
table.insert(NF.conns, paConn)

-- Send startup notification
task.delay(1, function()
	sendWebhook("✅ Script Aktif",
		"Nazhan Fishing System berhasil diinisialisasi dan siap digunakan.", 0x00dd88)
end)

addLog("Nazhan Fishing System v1.0 — Ready")
setPhase(0)
