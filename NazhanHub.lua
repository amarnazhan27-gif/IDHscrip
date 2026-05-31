
if shared.NH_v9 then pcall(shared.NH_v9.kill) end

local M = { c = {}, on = true }
function M.kill()
	M.on = false
	for _, v in ipairs(M.c) do pcall(function() v:Disconnect() end) end
	table.clear(M.c)
end
shared.NH_v9 = M

local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local VIM     = game:GetService("VirtualInputManager")
local VU      = game:GetService("VirtualUser")
local PFS     = game:GetService("PathfindingService")
local TS      = game:GetService("TweenService")
local me      = Players.LocalPlayer

local RODS = {
	{name="Basic Rod",   lure=1.00, prog=1.00},
	{name="Party Rod",   lure=1.30, prog=1.08},
	{name="Shark Rod",   lure=1.57, prog=1.21},
	{name="Piranha Rod", lure=1.84, prog=1.33},
	{name="Thermo Rod",  lure=2.11, prog=1.46},
	{name="Flowers Rod", lure=2.38, prog=1.59},
	{name="Trisula Rod", lure=2.65, prog=1.72},
	{name="Feather Rod", lure=2.92, prog=1.84},
	{name="Wave Rod",    lure=3.19, prog=1.97},
	{name="Duck Rod",    lure=3.46, prog=2.10},
	{name="Planet Rod",  lure=3.73, prog=2.23},
	{name="Earth Rod",   lure=4.00, prog=2.35},
	{name="Volcano Rod", lure=4.27, prog=2.48},
}
local rodIdx = 1

local mode = "OFF"

local FISH_TOOLS = {"Fishing Rod","Rod","Pancing","FishingRod"}
local MINE_TOOLS = {"Pickaxe","Cangkul","Kapak","Mining","Pick","Hammer"}
local CRYS_OK    = {"8sisi","Crystal","Kristal","Gem","Ore","Batu","Stone","mineral"}
local CRYS_NO    = {
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

local STOP_DIST  = 2.5
local WALK_SPD   = 24
local CAST_HOLD  = 1.8
local BITE_WAIT  = 15.0
local RECAST_DLY = 1.0

local CFG = {
	timeJitter   = true,
	coordJitter  = true,
	pathJitter   = true,
	fatigueBreak = true,
	mouseAFK     = true,
	adminGuard   = true,
	smoothMove   = true,
}

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

local mineActive    = false
local miningLocked  = false
local currentTarget = nil
local failCount     = 0
local hitCount      = 0
local crystalCache  = {}
local cacheAt       = 0

local fishCount  = 0
local mineCount  = 0
local consoleOn  = false
local _clog      = function() end
local fatCount   = 0
local fatNext    = math.random(14, 24)

local _warn = warn
local function lg(s) _warn(s); if consoleOn then _clog(tostring(s)) end end
local function safe(fn) xpcall(fn, function(e) _warn("[ERR] "..tostring(e)) end) end

pcall(function()
	for _, n in ipairs({"NH_v9_GUI","AppleFarmUI","IH_v5"}) do
		local a = game:GetService("CoreGui"):FindFirstChild(n)
		if a then a:Destroy() end
		if me.PlayerGui then
			local b = me.PlayerGui:FindFirstChild(n)
			if b then b:Destroy() end
		end
	end
end)

task.wait(math.random() * 0.18)

local gui = Instance.new("ScreenGui")
gui.Name = "NH_v9_GUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = me:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 308, 0, 368)
main.Position = UDim2.new(1, -324, 0.16, 0)
main.BackgroundColor3 = Color3.fromRGB(17, 17, 21)
main.BackgroundTransparency = 0.07
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local ms = Instance.new("UIStroke", main)
ms.Color = Color3.fromRGB(44, 44, 52)
ms.Thickness = 1

local hdr = Instance.new("Frame", main)
hdr.Size = UDim2.new(1, 0, 0, 56)
hdr.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
hdr.BackgroundTransparency = 0.1
hdr.BorderSizePixel = 0
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 14)
local hLine = Instance.new("Frame", hdr)
hLine.Size = UDim2.new(1, 0, 0, 1)
hLine.Position = UDim2.new(0, 0, 1, -1)
hLine.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
hLine.BorderSizePixel = 0

local titleL = Instance.new("TextLabel", hdr)
titleL.Size = UDim2.new(1, -72, 0, 22)
titleL.Position = UDim2.new(0, 14, 0, 7)
titleL.BackgroundTransparency = 1
titleL.Text = "System Console"
titleL.TextColor3 = Color3.fromRGB(232, 232, 241)
titleL.Font = Enum.Font.GothamBold
titleL.TextSize = 14
titleL.TextXAlignment = Enum.TextXAlignment.Left

local byL = Instance.new("TextLabel", hdr)
byL.Size = UDim2.new(1, -72, 0, 16)
byL.Position = UDim2.new(0, 15, 0, 30)
byL.BackgroundTransparency = 1
byL.Text = "by nazhan"
byL.TextColor3 = Color3.fromRGB(78, 78, 92)
byL.Font = Enum.Font.Gotham
byL.TextSize = 11
byL.TextXAlignment = Enum.TextXAlignment.Left

local hideBtn = Instance.new("TextButton", hdr)
hideBtn.Size = UDim2.new(0, 50, 0, 22)
hideBtn.Position = UDim2.new(1, -58, 0.5, -11)
hideBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
hideBtn.Text = "Hide"
hideBtn.TextColor3 = Color3.fromRGB(145, 145, 156)
hideBtn.Font = Enum.Font.GothamMedium
hideBtn.TextSize = 11
hideBtn.BorderSizePixel = 0
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)

local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size = UDim2.new(0, 52, 0, 52)
floatBtn.Position = UDim2.new(1, -66, 0.16, 0)
floatBtn.BackgroundColor3 = Color3.fromRGB(17, 17, 21)
floatBtn.Text = "IH"
floatBtn.TextColor3 = Color3.fromRGB(216, 216, 228)
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextSize = 14
floatBtn.BorderSizePixel = 0
floatBtn.Visible = false
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1, 0)
local fbs = Instance.new("UIStroke", floatBtn)
fbs.Color = Color3.fromRGB(46, 46, 55)
fbs.Thickness = 1

local mainPos = UDim2.new(1, -324, 0.16, 0)
local hidePos = UDim2.new(1,   56, 0.16, 0)
local isHid   = false

local function setHide(h)
	isHid = h
	if h then
		TS:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=hidePos}):Play()
		task.delay(0.26, function() if isHid then main.Visible=false; floatBtn.Visible=true end end)
	else
		main.Visible=true; floatBtn.Visible=false
		TS:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=mainPos}):Play()
	end
end
hideBtn.MouseButton1Click:Connect(function() setHide(true) end)
floatBtn.MouseButton1Click:Connect(function() setHide(false) end)

local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1, 0, 0, 34)
tabBar.Position = UDim2.new(0, 0, 0, 56)
tabBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
tabBar.BackgroundTransparency = 0.14
tabBar.BorderSizePixel = 0
local tbDiv = Instance.new("Frame", tabBar)
tbDiv.Size = UDim2.new(1, 0, 0, 1)
tbDiv.Position = UDim2.new(0, 0, 1, -1)
tbDiv.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
tbDiv.BorderSizePixel = 0
local tabLine = Instance.new("Frame", tabBar)
tabLine.Size = UDim2.new(0.25, 0, 0, 2)
tabLine.Position = UDim2.new(0, 0, 1, -2)
tabLine.BackgroundColor3 = Color3.fromRGB(0, 114, 255)
tabLine.BorderSizePixel = 0
Instance.new("UICorner", tabLine).CornerRadius = UDim.new(1, 0)

local TABS  = {"Fishing","Mining","Settings","Console"}
local tBtns = {}
local panels = {}

local content = Instance.new("Frame", main)
content.Size = UDim2.new(1, 0, 1, -90)
content.Position = UDim2.new(0, 0, 0, 90)
content.BackgroundTransparency = 1
content.ClipsDescendants = true

for i, n in ipairs(TABS) do
	local b = Instance.new("TextButton", tabBar)
	b.Size = UDim2.new(0.25, 0, 1, -2)
	b.Position = UDim2.new((i-1)*0.25, 0, 0, 0)
	b.BackgroundTransparency = 1
	b.Text = n
	b.TextColor3 = i==1 and Color3.fromRGB(228,228,240) or Color3.fromRGB(118,118,130)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 11
	b.BorderSizePixel = 0
	tBtns[n] = b
	local p = Instance.new("Frame", content)
	p.Size = UDim2.new(1, 0, 1, 0)
	p.BackgroundTransparency = 1
	p.Visible = i==1
	panels[n] = p
end

local function switchTab(n)
	local i = table.find(TABS, n)
	TS:Create(tabLine, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Position=UDim2.new((i-1)*0.25,0,1,-2)}):Play()
	for k,b in pairs(tBtns) do
		b.TextColor3 = k==n and Color3.fromRGB(228,228,240) or Color3.fromRGB(118,118,130)
		panels[k].Visible = k==n
	end
end
for n,b in pairs(tBtns) do b.MouseButton1Click:Connect(function() switchTab(n) end) end

local function mkSep(par, y)
	local s = Instance.new("Frame", par)
	s.Size = UDim2.new(1, -22, 0, 1)
	s.Position = UDim2.new(0, 11, 0, y)
	s.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
	s.BorderSizePixel = 0
	return s
end

local function mkLbl(par, txt, y, sz, col)
	local l = Instance.new("TextLabel", par)
	l.Size = UDim2.new(1, -22, 0, 18)
	l.Position = UDim2.new(0, 11, 0, y)
	l.BackgroundTransparency = 1
	l.Text = txt
	l.TextColor3 = col or Color3.fromRGB(128,128,140)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = sz or 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

local function mkToggle(par, lbl, y, def, cb)
	local row = Instance.new("Frame", par)
	row.Size = UDim2.new(1, -22, 0, 30)
	row.Position = UDim2.new(0, 11, 0, y)
	row.BackgroundTransparency = 1
	local ll = Instance.new("TextLabel", row)
	ll.Size = UDim2.new(1, -52, 1, 0)
	ll.BackgroundTransparency = 1
	ll.Text = lbl
	ll.TextColor3 = Color3.fromRGB(192,192,204)
	ll.Font = Enum.Font.GothamMedium
	ll.TextSize = 12
	ll.TextXAlignment = Enum.TextXAlignment.Left
	ll.TextTruncate = Enum.TextTruncate.AtEnd
	local sw = Instance.new("TextButton", row)
	sw.Size = UDim2.new(0, 40, 0, 21)
	sw.Position = UDim2.new(1, -40, 0.5, -10)
	sw.BackgroundColor3 = def and Color3.fromRGB(42,184,78) or Color3.fromRGB(50,50,58)
	sw.Text = ""; sw.BorderSizePixel = 0
	Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
	local th = Instance.new("Frame", sw)
	th.Size = UDim2.new(0, 17, 0, 17)
	th.Position = def and UDim2.new(1,-19,0.5,-8.5) or UDim2.new(0,2,0.5,-8.5)
	th.BackgroundColor3 = Color3.fromRGB(255,255,255)
	th.BorderSizePixel = 0
	Instance.new("UICorner", th).CornerRadius = UDim.new(1, 0)
	local on = def
	sw.MouseButton1Click:Connect(function()
		if not M.on then return end
		on = not on
		TS:Create(th, TweenInfo.new(0.15), {Position=on and UDim2.new(1,-19,0.5,-8.5) or UDim2.new(0,2,0.5,-8.5)}):Play()
		TS:Create(sw, TweenInfo.new(0.15), {BackgroundColor3=on and Color3.fromRGB(42,184,78) or Color3.fromRGB(50,50,58)}):Play()
		cb(on)
	end)
	return sw, th
end

-- ========== FISHING PANEL ==========
local fp = panels["Fishing"]

local fStatL = mkLbl(fp, "Status: Idle", 10, 12, Color3.fromRGB(135,135,145))
local fCntL  = mkLbl(fp, "Fish Caught: 0", 28, 11)

local pbBg = Instance.new("Frame", fp)
pbBg.Size = UDim2.new(1, -22, 0, 4)
pbBg.Position = UDim2.new(0, 11, 0, 54)
pbBg.BackgroundColor3 = Color3.fromRGB(34,34,42)
pbBg.BorderSizePixel = 0
Instance.new("UICorner", pbBg).CornerRadius = UDim.new(1, 0)
local pbFill = Instance.new("Frame", pbBg)
pbFill.Size = UDim2.new(0, 0, 1, 0)
pbFill.BackgroundColor3 = Color3.fromRGB(0,114,255)
pbFill.BorderSizePixel = 0
Instance.new("UICorner", pbFill).CornerRadius = UDim.new(1, 0)

local phNm = {"Cast","Wait","Game","Done"}
local phCl = {Color3.fromRGB(0,114,255), Color3.fromRGB(255,145,0), Color3.fromRGB(255,46,78), Color3.fromRGB(42,184,78)}
local phLbs = {}
for i = 1, 4 do
	local l = Instance.new("TextLabel", fp)
	l.Size = UDim2.new(0.25, 0, 0, 16)
	l.Position = UDim2.new((i-1)*0.25 + 0.013, 0, 0, 60)
	l.BackgroundTransparency = 1
	l.Text = phNm[i]
	l.TextColor3 = Color3.fromRGB(72,72,82)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 10
	phLbs[i] = l
end

local activePhase = 0
local function setPhase(ph)
	activePhase = ph
	for i = 1, 4 do
		if i < ph then phLbs[i].TextColor3 = Color3.fromRGB(140,140,150)
		elseif i == ph then phLbs[i].TextColor3 = phCl[i]
		else phLbs[i].TextColor3 = Color3.fromRGB(70,70,80) end
	end
	if ph == 0 then
		TS:Create(pbFill, TweenInfo.new(0.16), {Size=UDim2.new(0,0,1,0), BackgroundColor3=Color3.fromRGB(0,114,255)}):Play()
	else
		TS:Create(pbFill, TweenInfo.new(0.16), {
			Size=UDim2.new(math.clamp(ph*0.25,0,1),0,1,0),
			BackgroundColor3=phCl[ph]
		}):Play()
	end
end
local function setPBar(f)
	if activePhase <= 0 then return end
	pbFill.Size = UDim2.new(math.clamp((activePhase-1)*0.25 + f*0.25,0,1), 0, 1, 0)
end

mkSep(fp, 82)

local rodBox = Instance.new("Frame", fp)
rodBox.Size = UDim2.new(1, -22, 0, 50)
rodBox.Position = UDim2.new(0, 11, 0, 88)
rodBox.BackgroundColor3 = Color3.fromRGB(23,23,28)
rodBox.BorderSizePixel = 0
Instance.new("UICorner", rodBox).CornerRadius = UDim.new(0, 9)
local rbSt = Instance.new("UIStroke", rodBox)
rbSt.Color = Color3.fromRGB(38,38,46)
rbSt.Thickness = 1

local rodHdr = Instance.new("TextLabel", rodBox)
rodHdr.Size = UDim2.new(1, 0, 0, 16)
rodHdr.Position = UDim2.new(0, 10, 0, 4)
rodHdr.BackgroundTransparency = 1
rodHdr.Text = "Rod Selection"
rodHdr.TextColor3 = Color3.fromRGB(82,82,94)
rodHdr.Font = Enum.Font.GothamMedium
rodHdr.TextSize = 10
rodHdr.TextXAlignment = Enum.TextXAlignment.Left

local prevRod = Instance.new("TextButton", rodBox)
prevRod.Size = UDim2.new(0, 24, 0, 22)
prevRod.Position = UDim2.new(0, 6, 1, -28)
prevRod.BackgroundColor3 = Color3.fromRGB(28,28,35)
prevRod.Text = "<"; prevRod.TextColor3 = Color3.fromRGB(172,172,182)
prevRod.Font = Enum.Font.GothamBold; prevRod.TextSize = 13
prevRod.BorderSizePixel = 0
Instance.new("UICorner", prevRod).CornerRadius = UDim.new(0, 5)

local nextRod = Instance.new("TextButton", rodBox)
nextRod.Size = UDim2.new(0, 24, 0, 22)
nextRod.Position = UDim2.new(1, -30, 1, -28)
nextRod.BackgroundColor3 = Color3.fromRGB(28,28,35)
nextRod.Text = ">"; nextRod.TextColor3 = Color3.fromRGB(172,172,182)
nextRod.Font = Enum.Font.GothamBold; nextRod.TextSize = 13
nextRod.BorderSizePixel = 0
Instance.new("UICorner", nextRod).CornerRadius = UDim.new(0, 5)

local rodNameL = Instance.new("TextLabel", rodBox)
rodNameL.Size = UDim2.new(1, -64, 0, 22)
rodNameL.Position = UDim2.new(0, 36, 1, -28)
rodNameL.BackgroundTransparency = 1
rodNameL.Text = RODS[1].name
rodNameL.TextColor3 = Color3.fromRGB(215,215,226)
rodNameL.Font = Enum.Font.GothamMedium
rodNameL.TextSize = 12

local rodStatL = mkLbl(fp, "Lure: 100%  |  Progress: 100%", 142, 10, Color3.fromRGB(78,78,92))

local function updateRod()
	local r = RODS[rodIdx]
	rodNameL.Text = r.name
	rodStatL.Text = string.format("Lure: %d%%  |  Progress: %d%%", math.floor(r.lure*100), math.floor(r.prog*100))
end
prevRod.MouseButton1Click:Connect(function() rodIdx = rodIdx<=1 and #RODS or rodIdx-1; updateRod() end)
nextRod.MouseButton1Click:Connect(function() rodIdx = rodIdx>=#RODS and 1 or rodIdx+1; updateRod() end)

mkSep(fp, 162)

local fishSw = mkToggle(fp, "Fishing System", 168, false, function(on)
	if on then
		if mode=="MINE" then mode="OFF" end
		mode="FISH"; fishState="IDLE"; idleAt=os.clock()
		fStatL.Text="Status: Starting"
	else
		mode="OFF"; isSpace=false
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		fStatL.Text="Status: Idle"; setPhase(0)
	end
end)

local rstBtn = Instance.new("TextButton", fp)
rstBtn.Size = UDim2.new(0, 76, 0, 22)
rstBtn.Position = UDim2.new(1, -88, 0, 200)
rstBtn.BackgroundColor3 = Color3.fromRGB(28,28,36)
rstBtn.Text = "Reset"
rstBtn.TextColor3 = Color3.fromRGB(160,160,170)
rstBtn.Font = Enum.Font.GothamMedium
rstBtn.TextSize = 11
rstBtn.BorderSizePixel = 0
Instance.new("UICorner", rstBtn).CornerRadius = UDim.new(0, 6)
local rstSt = Instance.new("UIStroke", rstBtn)
rstSt.Color = Color3.fromRGB(44,44,52); rstSt.Thickness = 1

-- ========== MINING PANEL ==========
local mp = panels["Mining"]

local mStatL = mkLbl(mp, "Status: Idle", 10, 12, Color3.fromRGB(135,135,145))
local mCntL  = mkLbl(mp, "Crystals Mined: 0", 28, 11)

mkSep(mp, 52)

local function mkNumRow(par, label, y, def, mn, mx, cb)
	local row = Instance.new("Frame", par)
	row.Size = UDim2.new(1,-22,0,30)
	row.Position = UDim2.new(0,11,0,y)
	row.BackgroundTransparency = 1
	local ll = Instance.new("TextLabel", row)
	ll.Size = UDim2.new(1,-84,1,0)
	ll.BackgroundTransparency = 1
	ll.Text = label
	ll.TextColor3 = Color3.fromRGB(192,192,204)
	ll.Font = Enum.Font.GothamMedium
	ll.TextSize = 12
	ll.TextXAlignment = Enum.TextXAlignment.Left
	ll.TextTruncate = Enum.TextTruncate.AtEnd
	local box = Instance.new("TextBox", row)
	box.Size = UDim2.new(0, 74, 0, 22)
	box.Position = UDim2.new(1,-78,0.5,-11)
	box.BackgroundColor3 = Color3.fromRGB(24,24,31)
	box.TextColor3 = Color3.fromRGB(225,225,235)
	box.Text = tostring(def)
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.BorderSizePixel = 0
	Instance.new("UICorner", box).CornerRadius = UDim.new(0,6)
	local bs = Instance.new("UIStroke", box)
	bs.Color = Color3.fromRGB(44,44,53); bs.Thickness = 1
	box.FocusLost:Connect(function()
		local v = tonumber(box.Text)
		if v then v=math.clamp(v,mn,mx); box.Text=string.format("%.1f",v); cb(v)
		else box.Text=string.format("%.1f",def) end
	end)
	return box
end

mkNumRow(mp, "Mine Stop Range", 58, STOP_DIST, 1.5, 6.0, function(v) STOP_DIST=v end)

local spRow = Instance.new("Frame", mp)
spRow.Size = UDim2.new(1,-22,0,30)
spRow.Position = UDim2.new(0,11,0,92)
spRow.BackgroundTransparency = 1
local spLbl = Instance.new("TextLabel", spRow)
spLbl.Size = UDim2.new(1,-92,1,0)
spLbl.BackgroundTransparency = 1
spLbl.Text = "Walk / Sprint Speed"
spLbl.TextColor3 = Color3.fromRGB(192,192,204)
spLbl.Font = Enum.Font.GothamMedium
spLbl.TextSize = 12
spLbl.TextXAlignment = Enum.TextXAlignment.Left
spLbl.TextTruncate = Enum.TextTruncate.AtEnd
local spBtn = Instance.new("TextButton", spRow)
spBtn.Size = UDim2.new(0, 84, 0, 22)
spBtn.Position = UDim2.new(1,-88,0.5,-11)
spBtn.BackgroundColor3 = Color3.fromRGB(24,24,31)
spBtn.TextColor3 = Color3.fromRGB(225,225,235)
spBtn.Text = "Sprint: 24"
spBtn.Font = Enum.Font.GothamMedium
spBtn.TextSize = 11
spBtn.BorderSizePixel = 0
Instance.new("UICorner", spBtn).CornerRadius = UDim.new(0,6)
local spSt = Instance.new("UIStroke", spBtn)
spSt.Color = Color3.fromRGB(44,44,53); spSt.Thickness = 1
local spCyc = {{16,"Walk: 16"},{20,"Jog: 20"},{24,"Sprint: 24"}}
local spI = 3
spBtn.MouseButton1Click:Connect(function()
	spI = spI%#spCyc+1; WALK_SPD=spCyc[spI][1]; spBtn.Text=spCyc[spI][2]
end)

mkSep(mp, 128)

mkToggle(mp, "Smooth Movement", 134, true, function(v) CFG.smoothMove=v end)

mkSep(mp, 170)

local mineSw = mkToggle(mp, "Mining System", 176, false, function(on)
	if on then
		if mode=="FISH" then mode="OFF"; setPhase(0); fStatL.Text="Status: Idle" end
		mode="MINE"; currentTarget=nil; failCount=0; hitCount=0; miningLocked=false
		crystalCache={}; cacheAt=0
		mStatL.Text="Status: Active"
		if not mineActive then task.spawn(mineRoutine) end
	else
		mode="OFF"; mStatL.Text="Status: Idle"; miningLocked=false
		pcall(function()
			local h = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
			if h then h:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
			VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
		end)
	end
end)

-- ========== SETTINGS PANEL (ScrollingFrame agar tidak overflow) ==========
local stSF = Instance.new("ScrollingFrame", panels["Settings"])
stSF.Size = UDim2.new(1, 0, 1, 0)
stSF.BackgroundTransparency = 1
stSF.CanvasSize = UDim2.new(0,0,0,340)
stSF.ScrollBarThickness = 2
stSF.ScrollBarImageColor3 = Color3.fromRGB(48,48,58)
stSF.BorderSizePixel = 0

local stY = 10
local function addSet(lbl, key, def)
	CFG[key] = def
	mkToggle(stSF, lbl, stY, def, function(v) CFG[key]=v end)
	stY = stY + 34
end

mkLbl(stSF, "Anti-Detection", 12, 10, Color3.fromRGB(76,76,90))
stY = 32; mkSep(stSF, 30)
addSet("Timing Randomization", "timeJitter",   true)
addSet("Click Coord Jitter",   "coordJitter",  true)
addSet("Path Waypoint Jitter", "pathJitter",   true)
addSet("Fatigue Break",        "fatigueBreak", true)
addSet("Anti-AFK Sweep",       "mouseAFK",     true)
mkSep(stSF, stY); stY=stY+8
mkLbl(stSF, "Security", stY, 10, Color3.fromRGB(76,76,90))
stY=stY+20; mkSep(stSF, stY); stY=stY+8
addSet("Admin / Staff Guard",  "adminGuard",   true)
addSet("Anti-Fingerprint",     "antiFingerp",  true)
stSF.CanvasSize = UDim2.new(0,0,0, stY+20)

-- ========== CONSOLE PANEL ==========
local cp = panels["Console"]

mkToggle(cp, "Console Logging", 10, false, function(v)
	consoleOn = v
end)

mkSep(cp, 46)

local clrBtn = Instance.new("TextButton", cp)
clrBtn.Size = UDim2.new(0, 74, 0, 22)
clrBtn.Position = UDim2.new(1, -86, 0, 52)
clrBtn.BackgroundColor3 = Color3.fromRGB(26,26,33)
clrBtn.Text = "Clear Log"
clrBtn.TextColor3 = Color3.fromRGB(150,150,162)
clrBtn.Font = Enum.Font.GothamMedium
clrBtn.TextSize = 11
clrBtn.BorderSizePixel = 0
Instance.new("UICorner", clrBtn).CornerRadius = UDim.new(0,6)
local clSt = Instance.new("UIStroke", clrBtn)
clSt.Color = Color3.fromRGB(42,42,51); clSt.Thickness = 1

local logSF = Instance.new("ScrollingFrame", cp)
logSF.Size = UDim2.new(1,-22,1,-86)
logSF.Position = UDim2.new(0,11,0,82)
logSF.BackgroundTransparency = 1
logSF.CanvasSize = UDim2.new(0,0,0,0)
logSF.ScrollBarThickness = 2
logSF.ScrollBarImageColor3 = Color3.fromRGB(50,50,60)

local logLL = Instance.new("UIListLayout", logSF)
logLL.SortOrder = Enum.SortOrder.LayoutOrder
logLL.Padding = UDim.new(0,3)
local logOrd = 0

local function appendLog(txt)
	if not consoleOn then return end
	logOrd = logOrd + 1
	local l = Instance.new("TextLabel", logSF)
	l.LayoutOrder = logOrd
	l.Size = UDim2.new(1,0,0,14)
	l.BackgroundTransparency = 1
	l.Text = "["..os.date("%H:%M:%S").."] "..tostring(txt)
	l.TextColor3 = Color3.fromRGB(150,150,162)
	l.Font = Enum.Font.Code
	l.TextSize = 10
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	task.defer(function()
		logSF.CanvasSize = UDim2.new(0,0,0,logLL.AbsoluteContentSize.Y+6)
		logSF.CanvasPosition = Vector2.new(0,math.huge)
	end)
	local kids = {}
	for _, c in ipairs(logSF:GetChildren()) do if c:IsA("TextLabel") then kids[#kids+1]=c end end
	if #kids > 80 then kids[1]:Destroy() end
end
_clog = appendLog

clrBtn.MouseButton1Click:Connect(function()
	for _, c in ipairs(logSF:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	logSF.CanvasSize = UDim2.new(0,0,0,0); logOrd=0
end)

-- ========== HELPERS ==========
local function trulyVis(obj)
	if not obj or typeof(obj)~="Instance" or not obj:IsA("GuiObject") then return false end
	if not obj.Visible then return false end
	local ok, sz = pcall(function() return obj.AbsoluteSize end)
	if not ok or sz.X<=0 or sz.Y<=0 then return false end
	local cur = obj.Parent
	while cur and cur~=game do
		if cur:IsA("ScreenGui") then if not cur.Enabled then return false end; break
		elseif cur:IsA("GuiObject") then if not cur.Visible then return false end end
		cur = cur.Parent
	end
	return true
end

local function findTool(lst)
	local ch = me.Character; local bp = me.Backpack
	if ch then
		for _,n in ipairs(lst) do local t=ch:FindFirstChild(n); if t and t:IsA("Tool") then return t,"char" end end
	end
	for _,n in ipairs(lst) do local t=bp:FindFirstChild(n); if t then return t,"bp" end end
	if ch then local t=ch:FindFirstChildWhichIsA("Tool"); if t then return t,"char" end end
	return bp:FindFirstChildWhichIsA("Tool"),"bp"
end

local function equipTool(lst)
	local ch = me.Character; if not ch then return nil end
	local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return nil end
	local eq = ch:FindFirstChildWhichIsA("Tool")
	for _,n in ipairs(lst) do if eq and eq.Name:lower():find(n:lower()) then return eq end end
	local t, loc = findTool(lst)
	if t and loc=="bp" then
		pcall(function() hum:EquipTool(t) end)
		task.wait(0.55)
		return ch:FindFirstChildWhichIsA("Tool")
	end
	return eq
end

local function jT(base, p) if not CFG.timeJitter then return base end; return base*(1+(math.random()*2-1)*(p or 0.12)) end
local function jV(v) if not CFG.coordJitter then return v end; return Vector2.new(v.X+math.random(-12,12), v.Y+math.random(-10,10)) end

-- ========== ANTI-AFK ==========
task.spawn(function()
	while M.on do
		task.wait(math.random(90,150))
		if not M.on then break end
		if CFG.mouseAFK then
			pcall(function()
				local cam = workspace.CurrentCamera; if not cam then return end
				local sz = cam.ViewportSize
				VU:MouseMoveEvent(Vector2.new(sz.X/2+math.random(-70,70), sz.Y/2+math.random(-50,50)), cam.CFrame)
			end)
		end
	end
end)

local afkC = me.Idled:Connect(function()
	pcall(function()
		local cam = workspace.CurrentCamera
		VU:Button2Down(Vector2.new(0,0), cam.CFrame)
		task.wait(0.12)
		VU:Button2Up(Vector2.new(0,0), cam.CFrame)
	end)
end)
table.insert(M.c, afkC)

local function checkFatigue(statLbl)
	if not CFG.fatigueBreak then return end
	fatCount = fatCount+1
	if fatCount < fatNext then return end
	local sec = math.random(5,11)
	local prev = statLbl.Text
	statLbl.Text = "Status: Resting"
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
	isSpace = false
	task.wait(sec)
	fatCount=0; fatNext=math.random(14,24)
	statLbl.Text = prev
end

-- ========== ADMIN DETECTION ==========
local STAFF_GRP = 1200769
local ADM_PATS  = {"moderator","roblox_adm","rbxadmin","staffmod","gamemaster","game_master"}

local function checkAdmin(p)
	if p==me or not p.Parent or not CFG.adminGuard then return end
	task.wait(2.5)
	if not p or not p.Parent then return end
	local isA = false
	pcall(function() isA = isA or p:IsInGroup(STAFF_GRP) end)
	if not isA then
		local ln = (p.Name..p.DisplayName):lower()
		for _,pat in ipairs(ADM_PATS) do if ln:find(pat) then isA=true; break end end
	end
	if not isA then
		pcall(function()
			if game.CreatorType==Enum.CreatorType.Group then
				if p:GetRankInGroup(game.CreatorId)>=200 then isA=true end
			end
		end)
	end
	if isA then
		mode="OFF"; isSpace=false
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
		task.wait(0.8); me:Kick("Disconnected.")
	end
end

for _,p in ipairs(Players:GetPlayers()) do task.spawn(checkAdmin,p) end
local admC = Players.PlayerAdded:Connect(function(p) task.spawn(checkAdmin,p) end)
table.insert(M.c, admC)

-- ========== FISHING ENGINE ==========
local function doResetFish()
	fishState="IDLE"; isSpace=false; isCasting=false; successDone=false
	mgEverSeen=false; mgStarted=false; wBar=nil; rBar=nil
	lastScan=0; lastWC=nil; wVel=0; mgLastSeen=0
	castSess=castSess+1; idleAt=os.clock()
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
	setPhase(0)
	fStatL.Text="Status: Idle"
end

rstBtn.MouseButton1Click:Connect(function()
	doResetFish()
	lg("[FISH] Manual reset")
end)

local function setSpace(v, force)
	if isSpace==v and not force then return end
	local now = os.clock()
	if not force and (now-lastSpTgl)<0.03 then return end
	pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
	isSpace=v; lastSpTgl=now
end

local function getBars()
	if wBar and rBar and wBar.Parent and rBar.Parent and trulyVis(wBar) and trulyVis(rBar) then
		return wBar, rBar
	end
	local now = os.clock()
	if now-lastScan < 0.04 then return nil,nil end
	lastScan=now; wBar=nil; rBar=nil
	local pg = me:FindFirstChild("PlayerGui"); if not pg then return nil,nil end
	for _,v in pairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVis(v) then
			local ln = v.Name:lower()
			local par = v.Parent
			if par and par:IsA("GuiObject") then
				local isW = ln=="whitebar" or ln=="playerbar" or (ln:find("white") and ln:find("bar"))
				if isW then
					local red
					for _,sib in ipairs(par:GetChildren()) do
						if sib~=v and sib:IsA("GuiObject") and trulyVis(sib) then
							local sn=sib.Name:lower()
							if sn:find("red") or sn:find("target") or sn:find("goal") then red=sib; break end
						end
					end
					if red and trulyVis(red) and v.AbsoluteSize.X>10 then
						wBar=v; rBar=red; return v,red
					end
				end
			end
		end
	end
	for _,v in pairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVis(v) and v.AbsoluteSize.X>12 and v.AbsoluteSize.Y>5 then
			local c=v.BackgroundColor3; local par=v.Parent
			if c.R>0.78 and c.G>0.78 and c.B>0.78 and par and par:IsA("GuiObject") then
				for _,sib in ipairs(par:GetChildren()) do
					if sib~=v and sib:IsA("GuiObject") and trulyVis(sib) and sib.AbsoluteSize.X>12 then
						local sc=sib.BackgroundColor3
						if sc.R>0.46 and sc.G<0.22 and sc.B<0.22 then wBar=v; rBar=sib; return v,sib end
					end
				end
			end
		end
	end
	return nil,nil
end

local function doSuccess(why)
	if successDone then return end
	successDone=true; setSpace(false,true)
	fishState="DONE"; setPhase(4)
	fishCount=fishCount+1
	fCntL.Text="Fish Caught: "..fishCount
	fStatL.Text="Status: Caught"
	lg("[FISH] Caught #"..fishCount.." ("..why..")")
	checkFatigue(fStatL)
	local sess=castSess
	task.delay(jT(RECAST_DLY,0.15), function()
		if not M.on or mode~="FISH" or castSess~=sess then return end
		doResetFish()
		task.wait(0.06)
		if mode=="FISH" then fishState="IDLE"; idleAt=os.clock() end
	end)
end

local hbLast = 0
local hbC = RS.Heartbeat:Connect(function()
	if not M.on then return end
	if mode~="FISH" then if isSpace then setSpace(false,true) end; return end
	local now = os.clock()
	if now-hbLast < 0.016 then return end
	hbLast = now
	safe(function()
		local rod = RODS[rodIdx]
		if fishState=="WAITING" then
			local el = now-biteStart
			setPBar(math.clamp(el/BITE_WAIT,0,1))
			fStatL.Text=string.format("Status: Waiting (%.0fs)", math.max(0,BITE_WAIT-el))
			if el>=BITE_WAIT then
				fishState="MINIGAME"; mgStart=now
				mgEverSeen=false; mgStarted=false; mgLastSeen=0; successDone=false
				wBar=nil; rBar=nil; lastScan=0; lastWC=nil; wVel=0; lastWTime=now
				setSpace(false,true); setPhase(3); setPBar(0)
				fStatL.Text="Status: Minigame"
			end
			return
		end
		if fishState~="MINIGAME" then return end
		local el = now-mgStart
		local timeout = 11+rod.prog*3.2
		setPBar(math.clamp(el/timeout,0,1))
		if el>=timeout then setSpace(false,true); doSuccess("timeout"); return end
		local wb,rb = getBars()
		if wb and rb and trulyVis(wb) and trulyVis(rb) then
			mgEverSeen=true; mgLastSeen=now
			if not mgStarted then
				mgStarted=true; setSpace(false,true); lastWC=nil; wVel=0; lastWTime=now
			end
			local wC = wb.AbsolutePosition.X + wb.AbsoluteSize.X*0.5
			local rL = rb.AbsolutePosition.X
			local rR = rL+rb.AbsoluteSize.X
			local rC = (rL+rR)*0.5
			local rawDt = now-lastWTime
			local dt = math.clamp(rawDt,0.007,0.13)
			if lastWC then
				local inst = (wC-lastWC)/dt
				local sm = math.clamp(0.26/rod.lure,0.1,0.30)
				wVel = wVel*(1-sm)+inst*sm
			end
			lastWC=wC; lastWTime=now
			local ahead = math.clamp(math.abs(wVel)/1650,0.03,0.17)*math.sqrt(rod.lure)
			local pred  = wC+wVel*ahead
			local rw    = math.max(rb.AbsoluteSize.X,1)
			local lag   = math.clamp(rawDt/0.05-1,0,1.2)
			local tol   = math.clamp(rw*(0.16+lag*0.14+rod.lure*0.025),4,25)
			local inside = pred>=(rL-tol) and pred<=(rR+tol)
			if inside then
				if wC<rL then setSpace(true)
				elseif wC>rR then setSpace(false)
				else local e=wC-rC; if math.abs(e)>tol*0.4 then setSpace(e<0) end end
			else
				local e=rC-pred
				if e>tol then setSpace(true)
				elseif e<-tol then setSpace(false)
				elseif math.abs(wVel)>135 then setSpace(wVel<0) end
			end
			fStatL.Text=string.format("Status: Playing (%.0fs)",el)
		else
			if mgEverSeen then
				if mgLastSeen>0 and (now-mgLastSeen)>=0.20 then setSpace(false,true); doSuccess("bar-gone") end
			else
				local beat = math.floor((now-mgStart)*3.0)%2==0
				setSpace(beat)
				fStatL.Text=string.format("Status: Sync (%.0fs)",el)
			end
		end
	end)
end)
table.insert(M.c, hbC)

-- fishing main loop (cast controller)
task.spawn(function()
	while M.on do
		task.wait(0.15)
		if not M.on or mode~="FISH" then continue end
		safe(function()
			local ch = me.Character; if not ch then return end
			local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return end
			if hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
			end
			local tool = equipTool(FISH_TOOLS)
			if not tool then fStatL.Text="Status: No rod"; return end
			if fishState=="IDLE" and not isCasting then
				isCasting=true; castSess=castSess+1; local sess=castSess
				task.spawn(function()
					if not M.on or mode~="FISH" or castSess~=sess then isCasting=false; return end
					local cam = workspace.CurrentCamera; if not cam then isCasting=false; return end
					local rod = RODS[rodIdx]
					local ctr = jV(cam.ViewportSize/2)
					fishState="CASTING"; setPhase(1); setPBar(0)
					fStatL.Text="Status: Casting"
					pcall(function() tool:Activate() end)
					pcall(function() VU:Button1Down(ctr, cam.CFrame) end)
					local dur = jT(CAST_HOLD/math.max(1,math.sqrt(rod.lure)*0.85),0.1)
					local t0 = os.clock()
					while os.clock()-t0<dur do
						task.wait(0.04)
						if mode~="FISH" or not M.on or castSess~=sess then
							pcall(function() VU:Button1Up(ctr,cam.CFrame) end); isCasting=false; return
						end
						setPBar((os.clock()-t0)/dur)
					end
					pcall(function() VU:Button1Up(ctr, cam.CFrame) end)
					setPBar(1); task.wait(jT(0.14,0.08))
					if mode~="FISH" or not M.on or castSess~=sess then isCasting=false; return end
					fishState="WAITING"; biteStart=os.clock()
					setPhase(2); setPBar(0); fStatL.Text="Status: Waiting"
					isCasting=false
				end)
			end
		end)
	end
end)

-- watchdog: auto-reset jika umpan tidak keluar / system macet
task.spawn(function()
	while M.on do
		task.wait(4)
		if not M.on or mode~="FISH" then continue end
		local now = os.clock()
		if fishState=="IDLE" and not isCasting and (now-idleAt)>12 then
			lg("[FISH] Watchdog: idle too long, forcing cast")
			doResetFish()
		elseif fishState=="WAITING" and (now-biteStart)>(BITE_WAIT+8) then
			lg("[FISH] Watchdog: waiting timeout, reset")
			doResetFish()
		elseif fishState=="CASTING" and not isCasting and (now-idleAt)>10 then
			lg("[FISH] Watchdog: cast stuck, reset")
			doResetFish()
		end
	end
end)

-- ========== MINING ENGINE ==========
local function isBL(name)
	local ln = name:lower()
	for _,bl in ipairs(CRYS_NO) do if ln:find(bl,1,true) then return true end end
	return false
end

local function scorePart(p)
	if not (p:IsA("BasePart") or p:IsA("MeshPart")) then return -1 end
	if isBL(p.Name) then return -999 end
	local par = p.Parent
	while par and par~=workspace do if isBL(par.Name) then return -999 end; par=par.Parent end
	local sc=0; local ln=p.Name:lower()
	for _,cn in ipairs(CRYS_OK) do if ln:find(cn:lower(),1,true) then sc=sc+5; break end end
	if p.Material==Enum.Material.Neon then sc=sc+3 end
	if p:IsA("MeshPart") then sc=sc+1 end
	if p.Transparency<0.85 then sc=sc+1 end
	if p.CanCollide then sc=sc+1 end
	local sz=p.Size
	if sz.X>22 or sz.Y>22 or sz.Z>22 then sc=sc-6 end
	if sz.X<0.35 and sz.Y<0.35 and sz.Z<0.35 then sc=sc-5 end
	local pn=(p.Parent and p.Parent.Name or ""):lower()
	for _,cn in ipairs(CRYS_OK) do if pn:find(cn:lower(),1,true) then sc=sc+3; break end end
	return sc
end

-- cache crystal list di background (update setiap 3 detik)
task.spawn(function()
	while M.on do
		task.wait(3)
		if not M.on or mode~="MINE" then continue end
		local nc={}
		for _,obj in pairs(workspace:GetDescendants()) do
			if scorePart(obj)>=6 then nc[#nc+1]=obj end
		end
		crystalCache=nc; cacheAt=os.clock()
	end
end)

local function isOccupied(crystal)
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=me and p.Character then
			local root=p.Character.PrimaryPart
			if root and (root.Position-crystal.Position).Magnitude<10 then
				local t=p.Character:FindFirstChildOfClass("Tool")
				if t then
					local tn=t.Name:lower()
					for _,mn in ipairs(MINE_TOOLS) do if tn:find(mn:lower(),1,true) then return true end end
				end
			end
		end
	end
	return false
end

local function findBestCrystal()
	local ch=me.Character; if not ch or not ch.PrimaryPart then return nil end
	local myP=ch.PrimaryPart.Position

	-- lock: jangan ganti target saat sedang aktif mining
	if miningLocked and currentTarget and currentTarget.Parent then
		return currentTarget
	end

	if currentTarget and currentTarget.Parent and failCount<4
		and (currentTarget.Position-myP).Magnitude<300 then
		return currentTarget
	end

	-- force scan jika cache kosong atau stale
	if os.clock()-cacheAt>5 or #crystalCache==0 then
		local nc={}
		for _,obj in pairs(workspace:GetDescendants()) do
			if scorePart(obj)>=6 then nc[#nc+1]=obj end
		end
		crystalCache=nc; cacheAt=os.clock()
	end

	-- cari yang TERDEKAT dari posisi saat ini
	local best,bestD=nil,math.huge
	for _,obj in ipairs(crystalCache) do
		if obj.Parent and not isOccupied(obj) then
			local d=(obj.Position-myP).Magnitude
			if d<bestD and d<300 then bestD=d; best=obj end
		end
	end

	currentTarget=best; failCount=0
	return best
end

local function groundRay(pos, ign)
	local rp=RaycastParams.new()
	rp.FilterType=Enum.RaycastFilterType.Blacklist
	rp.FilterDescendantsInstances=ign or {}
	rp.IgnoreWater=false
	return workspace:Raycast(pos+Vector3.new(0,16,0), Vector3.new(0,-56,0), rp)
end

local function getStandPoint(crystal)
	local ch=me.Character; if not ch or not ch.PrimaryPart then return nil end
	local origin=crystal.Position
	local cw=math.max(crystal.Size.X,crystal.Size.Z)
	local radius=math.clamp(cw*0.28+1.3,STOP_DIST,3.8)
	local ignore={ch,crystal}
	local best,bestSc=nil,math.huge
	for i=1,24 do
		local a=math.pi*2*(i/24)
		local smp=origin+Vector3.new(math.cos(a)*radius,0,math.sin(a)*radius)
		local gr=groundRay(smp,ignore)
		if gr and gr.Instance and gr.Normal.Y>0.45 then
			local pos=gr.Position+Vector3.new(0,3.1,0)
			if pos.Y<=origin.Y+crystal.Size.Y*0.5 then
				local hd=math.abs(pos.Y-ch.PrimaryPart.Position.Y)
				if hd<14 then
					local dc=(Vector3.new(pos.X,origin.Y,pos.Z)-origin).Magnitude
					local sc=(pos-ch.PrimaryPart.Position).Magnitude+math.abs(dc-radius)*5+hd
					if sc<bestSc then bestSc=sc; best=pos end
				end
			end
		end
	end
	if best then return best end
	local d=ch.PrimaryPart.Position-origin
	local flat=Vector3.new(d.X,0,d.Z)
	if flat.Magnitude<0.4 then flat=Vector3.new(1,0,0) end
	local fb=origin+flat.Unit*radius
	local gr=groundRay(fb,ignore)
	return gr and (gr.Position+Vector3.new(0,3.1,0)) or fb
end

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
	local ch=me.Character; if not ch or not ch.PrimaryPart then return false end
	pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game) end)
	local path=PFS:CreatePath({
		AgentRadius=1.8, AgentHeight=5.0,
		AgentCanJump=true, AgentCanClimb=false,
		WaypointSpacing=CFG.smoothMove and 6 or 3,
		Costs={Water=8},
	})
	local ok=pcall(function() path:ComputeAsync(ch.PrimaryPart.Position, targetPos) end)
	local wps
	if ok and path.Status==Enum.PathStatus.Success then wps=path:GetWaypoints()
	else wps={{Position=targetPos,Action=Enum.PathWaypointAction.Walk}} end

	local origSp=hum.WalkSpeed
	hum.WalkSpeed=WALK_SPD+(CFG.timeJitter and math.random(-1,2) or 0)

	local lastPos=ch.PrimaryPart.Position
	local stuckT=0
	local arrived=false

	-- variasi lompatan: 1-3 titik acak di sepanjang jalur, tidak di awal/akhir
	local jPts={}
	if #wps>4 then
		local n=math.random(1,math.min(3,math.floor(#wps/2)))
		local used={}
		for i=1,n do
			local tries=0
			repeat
				local idx=math.random(2,#wps-2)
				if not used[idx] then used[idx]=true; jPts[idx]=true; break end
				tries=tries+1
			until tries>10
		end
	end

	for i,wp in ipairs(wps) do
		if mode~="MINE" or not M.on then break end
		if targetPart and not targetPart.Parent then break end
		if wp.Action==Enum.PathWaypointAction.Jump then doJump(hum) end

		if jPts[i] then
			doJump(hum)
			-- sedikit belok saat jump agar terlihat natural
			if math.random()<0.45 then
				local sideAngle = (math.random()-0.5)*0.8
				local dir = (targetPos-ch.PrimaryPart.Position)
				local flat = Vector3.new(dir.X,0,dir.Z)
				if flat.Magnitude>0.2 then
					local perp = Vector3.new(-flat.Z,0,flat.X).Unit
					hum:MoveTo(wp.Position + perp*sideAngle)
					task.wait(0.06)
				end
			end
		end

		local step=wp.Position
		if CFG.pathJitter and i<#wps then
			step=wp.Position+Vector3.new((math.random()-0.5)*0.5,0,(math.random()-0.5)*0.5)
		end

		hum:MoveTo(step)
		local t0=os.clock()
		while mode=="MINE" and M.on and os.clock()-t0<5.5 do
			task.wait(CFG.smoothMove and 0.06 or 0.12)
			if not ch.PrimaryPart then break end
			local cur=ch.PrimaryPart.Position
			if targetPart and targetPart.Parent then
				local dc=(cur-targetPart.Position).Magnitude
				local cw=math.max(targetPart.Size.X,targetPart.Size.Z)
				if dc<=(cw*0.5+STOP_DIST+0.3) then arrived=true; break end
			end
			local reach=(CFG.smoothMove and i<#wps) and 5.0 or 1.2
			if (cur-wp.Position).Magnitude<=reach then break end
			if (cur-targetPos).Magnitude<=1.2 then arrived=true; break end
			if (cur-lastPos).Magnitude<0.17 then
				stuckT=stuckT+(CFG.smoothMove and 0.06 or 0.12)
				if stuckT>1.2 then
					doJump(hum)
					local dir=targetPos-cur
					hum:MoveTo(cur+(dir.Magnitude>0.1 and dir.Unit or Vector3.new(1,0,0))*4.5)
					task.wait(0.3); break
				end
			else stuckT=0; lastPos=cur end
		end
		if arrived then break end
	end

	hum.WalkSpeed=origSp
	pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game) end)
	if arrived then return true end
	if not ch.PrimaryPart then return false end
	return (ch.PrimaryPart.Position-targetPos).Magnitude<=2.2
end

local function facePart(part)
	local ch=me.Character; if not ch or not ch.PrimaryPart or not part then return end
	local p=ch.PrimaryPart.Position
	pcall(function()
		ch:SetPrimaryPartCFrame(CFrame.lookAt(p, Vector3.new(part.Position.X,p.Y,part.Position.Z)))
	end)
end

function mineRoutine()
	mineActive=true
	while mode=="MINE" and M.on do
		safe(function()
			local ch=me.Character; if not ch or not ch.PrimaryPart then task.wait(0.5); return end
			local hum=ch:FindFirstChildOfClass("Humanoid"); if not hum then task.wait(0.5); return end

			local crystal=findBestCrystal()
			if not crystal then
				mStatL.Text="Status: Searching"
				task.wait(2.5); return
			end

			-- jangan cek occupied jika sudah locked (sedang mining)
			if not miningLocked and isOccupied(crystal) then
				currentTarget=nil; task.wait(0.3); return
			end

			local tool=equipTool(MINE_TOOLS)
			if not tool then mStatL.Text="Status: No tool"; task.wait(1.5); return end

			local myP=ch.PrimaryPart.Position
			local cw=math.max(crystal.Size.X,crystal.Size.Z)
			local dist=(myP-crystal.Position).Magnitude
			local closeEnough=dist<=(cw*0.5+STOP_DIST+0.5)

			if not closeEnough then
				mStatL.Text="Status: Moving"
				local sp=getStandPoint(crystal)
				if sp and (myP-sp).Magnitude>1.0 then
					local ok2=moveToPos(hum,sp,crystal)
					if not ok2 then
						failCount=failCount+1
						if failCount>=4 then currentTarget=nil; miningLocked=false end
						return
					end
				end
			end

			-- nudge ke arah crystal setelah tiba
			local ch2=me.Character
			if ch2 and ch2.PrimaryPart and crystal.Parent then
				local cur=ch2.PrimaryPart.Position
				local diff=crystal.Position-cur
				local flat=Vector3.new(diff.X,0,diff.Z)
				if flat.Magnitude>0.3 then
					local nudge=math.clamp(cw*0.22,0.35,1.0)
					hum:MoveTo(cur+flat.Unit*nudge)
					task.wait(0.18)
				end
			end

			facePart(crystal)
			local cam=workspace.CurrentCamera; if not cam then return end
			local aimPos=crystal.Position+Vector3.new(0,math.clamp(crystal.Size.Y*0.1,0.25,2.2),0)
			local sPx,onSc=cam:WorldToScreenPoint(aimPos)

			mStatL.Text="Status: Mining"
			miningLocked=true  -- kunci target selama swing berlangsung

			local swings=0
			for s=1,10 do
				if mode~="MINE" or not M.on then break end
				if not crystal.Parent then break end
				facePart(crystal)
				if s%3==1 then
					local sp2,os2=cam:WorldToScreenPoint(aimPos)
					if os2 then sPx=sp2; onSc=os2 end
				end
				if onSc then
					local cx=sPx.X+(CFG.coordJitter and math.random(-7,7) or 0)
					local cy=sPx.Y+(CFG.coordJitter and math.random(-5,6) or 0)
					pcall(function() VU:Button1Down(Vector2.new(cx,cy), cam.CFrame) end)
					task.wait(jT(0.10,0.08))
					pcall(function() VU:Button1Up(Vector2.new(cx,cy), cam.CFrame) end)
				end
				pcall(function() tool:Activate() end)
				swings=swings+1
				task.wait(jT(0.25,0.1))
			end

			miningLocked=false  -- buka lock setelah swing selesai

			if not crystal.Parent or swings>=9 then
				mineCount=mineCount+1
				mCntL.Text="Crystals Mined: "..mineCount
				mStatL.Text="Status: Active"
				currentTarget=nil; failCount=0; hitCount=0
				checkFatigue(mStatL)
			else
				hitCount=hitCount+1
				if hitCount>=5 then
					mineCount=mineCount+1
					mCntL.Text="Crystals Mined: "..mineCount
					hitCount=0; currentTarget=nil
				end
			end
		end)
	end
	mineActive=false
end

-- ========== INIT ==========
setPhase(0)
updateRod()
