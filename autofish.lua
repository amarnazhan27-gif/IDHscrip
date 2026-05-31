-- =============================================================================
-- SYSTEM CONSOLE: PREMIUM AUTO-FISHING SYSTEM (v6.0)
-- Optimized for Long-Term AFK | Extremely Lightweight | Anti-Lag
-- Developed by nazhan
-- =============================================================================

if shared.NH_v6 then pcall(shared.NH_v6.kill) end

local M = { c = {}, on = true }
function M.kill()
	M.on = false
	for _, v in ipairs(M.c) do pcall(function() v:Disconnect() end) end
	table.clear(M.c)
	
	-- Clean up local platform if any
	local oldPlat = workspace:FindFirstChild("NH_FishingPlatform")
	if oldPlat then pcall(function() oldPlat:Destroy() end) end
	
	-- Reset space key state
	pcall(function()
		local VIM = game:GetService("VirtualInputManager")
		VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	end)
end
shared.NH_v6 = M

-- Roblox Services
local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local VIM     = game:GetService("VirtualInputManager")
local VU      = game:GetService("VirtualUser")
local TS      = game:GetService("TweenService")
local HTTP    = game:GetService("HttpService")
local me      = Players.LocalPlayer

-- Rod Profiles & Multipliers
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

-- Global Configs & States
local mode = "OFF"
local FISH_TOOLS = {"Fishing Rod","Rod","Pancing","FishingRod"}
local BITE_WAIT  = 15.0
local RECAST_DLY = 1.0
local CAST_HOLD  = 1.8

local CFG = {
	timeJitter   = true,
	coordJitter  = true,
	fatigueBreak = true,
	mouseAFK     = true,
	adminGuard   = true,
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

local fishCount  = 0
local consoleOn  = false
local _clog      = function() end
local fatCount   = 0
local fatNext    = math.random(15, 25)

-- Configuration File Support
local CONFIG_FILE = "nazhan_fish_config.json"
local webhookUrl = ""
local webhookEnabled = false
local autoResetEnabled = true
local customSpots = {} -- Array of Vector3 components

local function safe(fn) xpcall(fn, function(e) warn("[ERR] "..tostring(e)) end) end

-- Teleport & Platform Configuration
local PLATFORM_NAME = "NH_FishingPlatform"
local function createLocalPlatform(pos)
	local old = workspace:FindFirstChild(PLATFORM_NAME)
	if old then pcall(function() old:Destroy() end) end
	
	local part = Instance.new("Part")
	part.Name = PLATFORM_NAME
	part.Size = Vector3.new(12, 1, 12)
	part.Position = pos - Vector3.new(0, 3.2, 0)
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0.5
	part.Color = Color3.fromRGB(0, 170, 255)
	
	-- Rounded corner glow effect
	local box = Instance.new("SelectionBox", part)
	box.Color3 = Color3.fromRGB(0, 240, 255)
	box.Adornee = part
	box.LineThickness = 0.05
	
	part.Parent = workspace
	return part
end

local function teleportTo(pos)
	local char = me.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	createLocalPlatform(pos)
	task.wait(0.1)
	pcall(function()
		root.CFrame = CFrame.new(pos)
	end)
end

-- Preset Teleport Coordinates
local PRESETS = {
	{name = "Tengah Laut (Far Sea)", pos = Vector3.new(1800, 10, 1800)},
	{name = "Ujung Map Barat (West)", pos = Vector3.new(-2200, 10, 200)},
	{name = "Ujung Map Timur (East)", pos = Vector3.new(2200, 10, -200)},
	{name = "Bawah Jembatan (Secret Bridge)", pos = Vector3.new(140, -4, -480)},
	{name = "Pulau Karang (Reef Isle)", pos = Vector3.new(-1500, 8, 1600)},
}

-- Webhook Telemetry
local function getMaskedName(str)
	if #str <= 3 then return str end
	return str:sub(1, 1) .. string.rep("*", #str - 2) .. str:sub(#str, #str)
end

local function sendDiscordWebhook(title, desc, colorHex)
	if not webhookEnabled or webhookUrl == "" or not webhookUrl:find("discord.com/api/webhooks") then return end
	
	local colorCode = tonumber(colorHex:gsub("#", ""), 16) or 65535
	local maskedUser = getMaskedName(me.Name)
	local maskedUserId = getMaskedName(tostring(me.UserId))
	
	local embed = {
		title = title,
		description = desc,
		color = colorCode,
		fields = {
			{name = "👤 Player", value = maskedUser .. " (" .. maskedUserId .. ")", inline = true},
			{name = "🐟 Catches", value = tostring(fishCount) .. " Caught", inline = true},
			{name = "🎣 Equipped", value = RODS[rodIdx].name, inline = true}
		},
		footer = {text = "System Console by nazhan"},
		timestamp = DateTime.now():ToIsoDate()
	}
	
	local payload = { embeds = { embed } }
	local success, json = pcall(function() return HTTP:JSONEncode(payload) end)
	if not success then return end
	
	task.spawn(function()
		local headers = { ["Content-Type"] = "application/json" }
		local req = (syn and syn.request) or (http and http.request) or http_request or request
		if req then
			pcall(function()
				req({
					Url = webhookUrl,
					Method = "POST",
					Headers = headers,
					Body = json
				})
			end)
		else
			pcall(function()
				HTTP:PostAsync(webhookUrl, json, Enum.HttpContentType.ApplicationJson)
			end)
		end
	end)
end

-- Config Loading/Saving
local function saveConfig()
	local data = {
		webhookUrl = webhookUrl,
		webhookEnabled = webhookEnabled,
		selectedRodIndex = rodIdx,
		customSpots = customSpots,
		autoReset = autoResetEnabled,
		adminGuard = CFG.adminGuard,
		antiAFK = CFG.mouseAFK,
	}
	pcall(function()
		if writefile then
			writefile(CONFIG_FILE, HTTP:JSONEncode(data))
		end
	end)
end

local function loadConfig()
	pcall(function()
		if isfile and isfile(CONFIG_FILE) and readfile then
			local raw = readfile(CONFIG_FILE)
			local data = HTTP:JSONDecode(raw)
			if data then
				if data.webhookUrl then webhookUrl = data.webhookUrl end
				if data.webhookEnabled ~= nil then webhookEnabled = data.webhookEnabled end
				if data.selectedRodIndex then rodIdx = data.selectedRodIndex end
				if data.customSpots then customSpots = data.customSpots end
				if data.autoReset ~= nil then autoResetEnabled = data.autoReset end
				if data.adminGuard ~= nil then CFG.adminGuard = data.adminGuard end
				if data.antiAFK ~= nil then CFG.mouseAFK = data.antiAFK end
			end
		end
	end)
end

loadConfig()

-- GUI Cleanup
pcall(function()
	for _, n in ipairs({"NH_v6_GUI", "IH_v5", "NH_v9_GUI"}) do
		local a = game:GetService("CoreGui"):FindFirstChild(n)
		if a then a:Destroy() end
		if me.PlayerGui then
			local b = me.PlayerGui:FindFirstChild(n)
			if b then b:Destroy() end
		end
	end
end)

-- GUI Setup
local gui = Instance.new("ScreenGui")
gui.Name = "NH_v6_GUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = me:WaitForChild("PlayerGui")
end

-- Premium Dark Theme Frame
local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 320, 0, 420)
main.Position = UDim2.new(0.5, -160, 0.5, -210)
main.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

-- Premium Subtle Border Gradient
local mStroke = Instance.new("UIStroke", main)
mStroke.Color = Color3.fromRGB(40, 42, 50)
mStroke.Thickness = 1.5

local gGradient = Instance.new("UIGradient", mStroke)
gGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 240, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 0, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 240, 255))
})

-- Header
local hdr = Instance.new("Frame", main)
hdr.Size = UDim2.new(1, 0, 0, 52)
hdr.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
hdr.BorderSizePixel = 0
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 12)

-- Header separator
local hs = Instance.new("Frame", hdr)
hs.Size = UDim2.new(1, 0, 0, 1)
hs.Position = UDim2.new(0, 0, 1, -1)
hs.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
hs.BorderSizePixel = 0

local title = Instance.new("TextLabel", hdr)
title.Size = UDim2.new(1, -60, 0, 24)
title.Position = UDim2.new(0, 14, 0, 6)
title.BackgroundTransparency = 1
title.Text = "System Console"
title.TextColor3 = Color3.fromRGB(240, 242, 248)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left

local subtitle = Instance.new("TextLabel", hdr)
subtitle.Size = UDim2.new(1, -60, 0, 14)
subtitle.Position = UDim2.new(0, 14, 0, 28)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Premium Fishing Hub • by nazhan"
subtitle.TextColor3 = Color3.fromRGB(0, 200, 255)
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 10
subtitle.TextXAlignment = Enum.TextXAlignment.Left

-- Hide/Minimize Button
local hideBtn = Instance.new("TextButton", hdr)
hideBtn.Size = UDim2.new(0, 48, 0, 24)
hideBtn.Position = UDim2.new(1, -62, 0.5, -12)
hideBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
hideBtn.Text = "Hide"
hideBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextSize = 10
hideBtn.BorderSizePixel = 0
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)
local hbStr = Instance.new("UIStroke", hideBtn)
hbStr.Color = Color3.fromRGB(44, 46, 55)
hbStr.Thickness = 1

-- Hover feedback on Hide
hideBtn.MouseEnter:Connect(function() TS:Create(hideBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(35, 38, 48)}):Play() end)
hideBtn.MouseLeave:Connect(function() TS:Create(hideBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(24, 26, 33)}):Play() end)

-- Float button
local floatBtn = Instance.new("TextButton", gui)
floatBtn.Size = UDim2.new(0, 50, 0, 50)
floatBtn.Position = UDim2.new(1, -65, 0.15, 0)
floatBtn.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
floatBtn.Text = "🎣"
floatBtn.TextSize = 20
floatBtn.BorderSizePixel = 0
floatBtn.Visible = false
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1, 0)
local fbStr = Instance.new("UIStroke", floatBtn)
fbStr.Color = Color3.fromRGB(0, 200, 255)
fbStr.Thickness = 1.5

local isMin = false
local originalPos = main.Position

local function toggleMinimize(min)
	isMin = min
	if min then
		originalPos = main.Position
		TS:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(1, 50, 0.15, 0)}):Play()
		task.delay(0.26, function()
			if isMin then
				main.Visible = false
				floatBtn.Visible = true
			end
		end)
	else
		main.Visible = true
		floatBtn.Visible = false
		TS:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = originalPos}):Play()
	end
end

hideBtn.MouseButton1Click:Connect(function() toggleMinimize(true) end)
floatBtn.MouseButton1Click:Connect(function() toggleMinimize(false) end)

-- Tab Navigation
local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1, 0, 0, 36)
tabBar.Position = UDim2.new(0, 0, 0, 52)
tabBar.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
tabBar.BorderSizePixel = 0

local tLine = Instance.new("Frame", tabBar)
tLine.Size = UDim2.new(1, 0, 0, 1)
tLine.Position = UDim2.new(0, 0, 1, -1)
tLine.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
tLine.BorderSizePixel = 0

local indicator = Instance.new("Frame", tabBar)
indicator.Size = UDim2.new(0.25, 0, 0, 2)
indicator.Position = UDim2.new(0, 0, 1, -2)
indicator.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
indicator.BorderSizePixel = 0

local TABS = {"Main", "Teleports", "Settings", "Webhook"}
local tabBtns = {}
local panels = {}

local container = Instance.new("Frame", main)
container.Size = UDim2.new(1, 0, 1, -88)
container.Position = UDim2.new(0, 0, 0, 88)
container.BackgroundTransparency = 1
container.ClipsDescendants = true

for i, tName in ipairs(TABS) do
	local b = Instance.new("TextButton", tabBar)
	b.Size = UDim2.new(0.25, 0, 1, -2)
	b.Position = UDim2.new((i - 1) * 0.25, 0, 0, 0)
	b.BackgroundTransparency = 1
	b.Text = tName
	b.TextColor3 = i == 1 and Color3.fromRGB(240, 242, 248) or Color3.fromRGB(110, 115, 130)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 10.5
	b.BorderSizePixel = 0
	tabBtns[tName] = b
	
	local p = Instance.new("Frame", container)
	p.Size = UDim2.new(1, 0, 1, 0)
	p.BackgroundTransparency = 1
	p.Visible = (i == 1)
	panels[tName] = p
end

local function switchTab(tName)
	local idx = table.find(TABS, tName)
	TS:Create(indicator, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Position = UDim2.new((idx - 1) * 0.25, 0, 1, -2)}):Play()
	for name, b in pairs(tabBtns) do
		b.TextColor3 = (name == tName) and Color3.fromRGB(240, 242, 248) or Color3.fromRGB(110, 115, 130)
		panels[name].Visible = (name == tName)
	end
end

for tName, b in pairs(tabBtns) do
	b.MouseButton1Click:Connect(function() switchTab(tName) end)
end

-- Dynamic Components Creator Helpers
local function createSeparator(parent, y)
	local sep = Instance.new("Frame", parent)
	sep.Size = UDim2.new(1, -28, 0, 1)
	sep.Position = UDim2.new(0, 14, 0, y)
	sep.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
	sep.BorderSizePixel = 0
	return sep
end

local function createCard(parent, size, pos, bgTrans)
	local card = Instance.new("Frame", parent)
	card.Size = size
	card.Position = pos
	card.BackgroundColor3 = Color3.fromRGB(16, 18, 23)
	card.BackgroundTransparency = bgTrans or 0
	card.BorderSizePixel = 0
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = Color3.fromRGB(30, 32, 42)
	stroke.Thickness = 1
	return card, stroke
end

local function createLabel(parent, text, size, pos, font, sizePt, color)
	local lbl = Instance.new("TextLabel", parent)
	lbl.Size = size
	lbl.Position = pos
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or Color3.fromRGB(170, 175, 190)
	lbl.Font = font or Enum.Font.GothamMedium
	lbl.TextSize = sizePt or 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	return lbl
end

local function createToggle(parent, labelText, yPos, defaultValue, callback)
	local row = Instance.new("Frame", parent)
	row.Size = UDim2.new(1, -28, 0, 32)
	row.Position = UDim2.new(0, 14, 0, yPos)
	row.BackgroundTransparency = 1
	
	local lbl = createLabel(row, labelText, UDim2.new(1, -60, 1, 0), UDim2.new(0, 0, 0, 0), Enum.Font.GothamMedium, 11, Color3.fromRGB(200, 205, 220))
	
	local sw = Instance.new("TextButton", row)
	sw.Size = UDim2.new(0, 38, 0, 20)
	sw.Position = UDim2.new(1, -38, 0.5, -10)
	sw.BackgroundColor3 = defaultValue and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(34, 36, 45)
	sw.Text = ""
	sw.BorderSizePixel = 0
	Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
	local swStroke = Instance.new("UIStroke", sw)
	swStroke.Color = defaultValue and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(48, 50, 62)
	swStroke.Thickness = 1
	
	local th = Instance.new("Frame", sw)
	th.Size = UDim2.new(0, 16, 0, 16)
	th.Position = defaultValue and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
	th.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	th.BorderSizePixel = 0
	Instance.new("UICorner", th).CornerRadius = UDim.new(1, 0)
	
	local val = defaultValue
	sw.MouseButton1Click:Connect(function()
		if not M.on then return end
		val = not val
		TS:Create(th, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)}):Play()
		TS:Create(sw, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {BackgroundColor3 = val and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(34, 36, 45)}):Play()
		TS:Create(swStroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Color = val and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(48, 50, 62)}):Play()
		callback(val)
	end)
	return sw, th
end

-- =============================================================================
-- PANEL 1: MAIN PANEL
-- =============================================================================
local pMain = panels["Main"]

-- Status Card
local statusCard, scStroke = createCard(pMain, UDim2.new(1, -28, 0, 68), UDim2.new(0, 14, 0, 10))
scStroke.Color = Color3.fromRGB(30, 32, 40)

local stDot = Instance.new("Frame", statusCard)
stDot.Size = UDim2.new(0, 8, 0, 8)
stDot.Position = UDim2.new(0, 12, 0, 14)
stDot.BackgroundColor3 = Color3.fromRGB(150, 155, 170)
stDot.BorderSizePixel = 0
Instance.new("UICorner", stDot).CornerRadius = UDim.new(1, 0)

-- Glowing status dot
local stGlow = Instance.new("UIStroke", stDot)
stGlow.Color = Color3.fromRGB(150, 155, 170)
stGlow.Thickness = 2
local dotPulse = TS:Create(stDot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundColor3 = Color3.fromRGB(255, 255, 255)})
dotPulse:Play()

local statusLbl = createLabel(statusCard, "Status: Idle", UDim2.new(1, -40, 0, 18), UDim2.new(0, 26, 0, 9), Enum.Font.GothamBold, 12, Color3.fromRGB(220, 225, 240))
local statsRateLbl = createLabel(statusCard, "Fish Caught: 0 • Rate: 0.0/hr", UDim2.new(1, -24, 0, 16), UDim2.new(0, 12, 0, 28), Enum.Font.GothamMedium, 10.5, Color3.fromRGB(140, 145, 160))
local statsTimeLbl = createLabel(statusCard, "Session Elapsed: 00:00:00", UDim2.new(1, -24, 0, 16), UDim2.new(0, 12, 0, 44), Enum.Font.Gotham, 10, Color3.fromRGB(100, 105, 120))

-- Phase Progress Bar Indicator
local phaseContainer = Instance.new("Frame", pMain)
phaseContainer.Size = UDim2.new(1, -28, 0, 48)
phaseContainer.Position = UDim2.new(0, 14, 0, 88)
phaseContainer.BackgroundTransparency = 1

local pbarBg = Instance.new("Frame", phaseContainer)
pbarBg.Size = UDim2.new(1, 0, 0, 4)
pbarBg.Position = UDim2.new(0, 0, 0, 8)
pbarBg.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
pbarBg.BorderSizePixel = 0
Instance.new("UICorner", pbarBg).CornerRadius = UDim.new(1, 0)

local pbarFill = Instance.new("Frame", pbarBg)
pbarFill.Size = UDim2.new(0, 0, 1, 0)
pbarFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
pbarFill.BorderSizePixel = 0
Instance.new("UICorner", pbarFill).CornerRadius = UDim.new(1, 0)

local phases = {"Cast", "Wait", "Game", "Done"}
local phaseColors = {
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 170, 0),
	Color3.fromRGB(255, 40, 100),
	Color3.fromRGB(0, 204, 100)
}
local phaseLbls = {}

for idx, pName in ipairs(phases) do
	local lbl = Instance.new("TextLabel", phaseContainer)
	lbl.Size = UDim2.new(0.25, 0, 0, 18)
	lbl.Position = UDim2.new((idx - 1) * 0.25, 0, 0, 16)
	lbl.BackgroundTransparency = 1
	lbl.Text = pName
	lbl.TextColor3 = Color3.fromRGB(80, 85, 95)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 9.5
	phaseLbls[idx] = lbl
end

local activePhase = 0
local function setPhaseIndicator(ph)
	activePhase = ph
	for i = 1, 4 do
		if i < ph then
			phaseLbls[i].TextColor3 = Color3.fromRGB(150, 155, 170)
		elseif i == ph then
			phaseLbls[i].TextColor3 = phaseColors[i]
		else
			phaseLbls[i].TextColor3 = Color3.fromRGB(60, 65, 75)
		end
	end
	if ph == 0 then
		TS:Create(pbarFill, TweenInfo.new(0.15), {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 170, 255)}):Play()
	else
		TS:Create(pbarFill, TweenInfo.new(0.15), {
			Size = UDim2.new(math.clamp(ph * 0.25, 0, 1), 0, 1, 0),
			BackgroundColor3 = phaseColors[ph]
		}):Play()
	end
end

local function setPbarPercent(fraction)
	if activePhase <= 0 then return end
	local baseWidth = (activePhase - 1) * 0.25
	pbarFill.Size = UDim2.new(math.clamp(baseWidth + fraction * 0.25, 0, 1), 0, 1, 0)
end

-- Rod Selection Card
local rodCard, rcStroke = createCard(pMain, UDim2.new(1, -28, 0, 56), UDim2.new(0, 14, 0, 146))
rcStroke.Color = Color3.fromRGB(24, 26, 33)

createLabel(rodCard, "Fishing Rod", UDim2.new(1, -20, 0, 16), UDim2.new(0, 12, 0, 6), Enum.Font.GothamBold, 9.5, Color3.fromRGB(100, 105, 120))
local rodNameLbl = createLabel(rodCard, RODS[rodIdx].name, UDim2.new(1, -80, 0, 22), UDim2.new(0, 42, 0, 24), Enum.Font.GothamMedium, 12, Color3.fromRGB(0, 200, 255))
local rodStatsLbl = createLabel(rodCard, "Lure: 100% | Speed Multiplier: 1.00", UDim2.new(1, -24, 0, 14), UDim2.new(0, 12, 0, 40), Enum.Font.Gotham, 8.5, Color3.fromRGB(110, 115, 130))

local prevRod = Instance.new("TextButton", rodCard)
prevRod.Size = UDim2.new(0, 24, 0, 22)
prevRod.Position = UDim2.new(0, 10, 0, 22)
prevRod.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
prevRod.Text = "‹"
prevRod.TextColor3 = Color3.fromRGB(200, 205, 220)
prevRod.Font = Enum.Font.GothamBold
prevRod.TextSize = 14
prevRod.BorderSizePixel = 0
Instance.new("UICorner", prevRod).CornerRadius = UDim.new(0, 5)
local prStr = Instance.new("UIStroke", prevRod)
prStr.Color = Color3.fromRGB(44, 46, 55)

local nextRod = Instance.new("TextButton", rodCard)
nextRod.Size = UDim2.new(0, 24, 0, 22)
nextRod.Position = UDim2.new(1, -34, 0, 22)
nextRod.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
nextRod.Text = "›"
nextRod.TextColor3 = Color3.fromRGB(200, 205, 220)
nextRod.Font = Enum.Font.GothamBold
nextRod.TextSize = 14
nextRod.BorderSizePixel = 0
Instance.new("UICorner", nextRod).CornerRadius = UDim.new(0, 5)
local nrStr = Instance.new("UIStroke", nextRod)
nrStr.Color = Color3.fromRGB(44, 46, 55)

local function updateRodDisplay()
	local r = RODS[rodIdx]
	rodNameLbl.Text = r.name
	rodStatsLbl.Text = string.format("Lure Multiplier: %.2fx  |  Progress Multiplier: %.2fx", r.lure, r.prog)
	saveConfig()
end

prevRod.MouseButton1Click:Connect(function()
	rodIdx = (rodIdx <= 1) and #RODS or rodIdx - 1
	updateRodDisplay()
end)
nextRod.MouseButton1Click:Connect(function()
	rodIdx = (rodIdx >= #RODS) and 1 or rodIdx + 1
	updateRodDisplay()
end)

-- Main Toggle Switch
local toggleCard, tcStroke = createCard(pMain, UDim2.new(1, -28, 0, 50), UDim2.new(0, 14, 0, 212))
tcStroke.Color = Color3.fromRGB(24, 26, 33)

local function updateStatusUI(statusText, isRunning)
	statusLbl.Text = "Status: " .. statusText
	dotPulse:Cancel()
	if isRunning then
		stDot.BackgroundColor3 = Color3.fromRGB(0, 230, 120)
		stGlow.Color = Color3.fromRGB(0, 230, 120)
		dotPulse = TS:Create(stDot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundColor3 = Color3.fromRGB(200, 255, 220)})
		dotPulse:Play()
	else
		stDot.BackgroundColor3 = Color3.fromRGB(150, 155, 170)
		stGlow.Color = Color3.fromRGB(150, 155, 170)
		dotPulse = TS:Create(stDot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundColor3 = Color3.fromRGB(240, 240, 240)})
		dotPulse:Play()
	end
end

-- Watchdog variable definition
local doResetFish

local mainToggle = createToggle(toggleCard, "Auto-Fishing Engine", 9, false, function(on)
	if on then
		mode = "FISH"
		fishState = "IDLE"
		idleAt = os.clock()
		updateStatusUI("Starting...", true)
	else
		mode = "OFF"
		isSpace = false
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		updateStatusUI("Idle", false)
		setPhaseIndicator(0)
	end
end)

-- Reset & Stats Control Panel
local actionCard = createCard(pMain, UDim2.new(1, -28, 0, 50), UDim2.new(0, 14, 0, 272), 1)

local rstBtn = Instance.new("TextButton", actionCard)
rstBtn.Size = UDim2.new(0.5, -6, 1, 0)
rstBtn.Position = UDim2.new(0, 0, 0, 0)
rstBtn.BackgroundColor3 = Color3.fromRGB(26, 18, 22)
rstBtn.Text = "Reset Fishing State"
rstBtn.TextColor3 = Color3.fromRGB(255, 100, 120)
rstBtn.Font = Enum.Font.GothamBold
rstBtn.TextSize = 10.5
rstBtn.BorderSizePixel = 0
Instance.new("UICorner", rstBtn).CornerRadius = UDim.new(0, 6)
local rstSt = Instance.new("UIStroke", rstBtn)
rstSt.Color = Color3.fromRGB(60, 32, 40)

rstBtn.MouseButton1Click:Connect(function()
	if doResetFish then
		doResetFish()
		_clog("Manual reset triggered")
	end
end)

local rstStatsBtn = Instance.new("TextButton", actionCard)
rstStatsBtn.Size = UDim2.new(0.5, -6, 1, 0)
rstStatsBtn.Position = UDim2.new(0.5, 6, 0, 0)
rstStatsBtn.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
rstStatsBtn.Text = "Reset Statistics"
rstStatsBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
rstStatsBtn.Font = Enum.Font.GothamBold
rstStatsBtn.TextSize = 10.5
rstStatsBtn.BorderSizePixel = 0
Instance.new("UICorner", rstStatsBtn).CornerRadius = UDim.new(0, 6)
local rssSt = Instance.new("UIStroke", rstStatsBtn)
rssSt.Color = Color3.fromRGB(38, 40, 50)

local sessionStartTime = os.clock()
rstStatsBtn.MouseButton1Click:Connect(function()
	fishCount = 0
	sessionStartTime = os.clock()
	statsRateLbl.Text = "Fish Caught: 0 • Rate: 0.0/hr"
	_clog("Statistics reset successfully")
end)

-- Session Timer Updater
task.spawn(function()
	while M.on do
		task.wait(1)
		local elapsed = os.clock() - sessionStartTime
		local h = math.floor(elapsed / 3600)
		local m = math.floor((elapsed % 3600) / 60)
		local s = math.floor(elapsed % 60)
		statsTimeLbl.Text = string.format("Session Elapsed: %02d:%02d:%02d", h, m, s)
		
		-- Rate calculator
		if fishCount > 0 then
			local hours = math.max(elapsed / 3600, 0.01)
			local rate = fishCount / hours
			statsRateLbl.Text = string.format("Fish Caught: %d • Rate: %.1f/hr", fishCount, rate)
		end
	end
end)

-- =============================================================================
-- PANEL 2: TELEPORTS PANEL
-- =============================================================================
local pTele = panels["Teleports"]

-- Scrolling Frame for Teleports list
local tSF = Instance.new("ScrollingFrame", pTele)
tSF.Size = UDim2.new(1, 0, 1, 0)
tSF.BackgroundTransparency = 1
tSF.BorderSizePixel = 0
tSF.CanvasSize = UDim2.new(0, 0, 0, 360)
tSF.ScrollBarThickness = 3
tSF.ScrollBarImageColor3 = Color3.fromRGB(38, 40, 50)

-- Header Spot
createLabel(tSF, "MAP SPOTS (INDO HANGOUT)", UDim2.new(1, -28, 0, 16), UDim2.new(0, 14, 0, 8), Enum.Font.GothamBold, 9.5, Color3.fromRGB(100, 105, 120))

local listY = 28

-- Function to build buttons
local function makeTeleportButton(name, pos, y)
	local row = Instance.new("Frame", tSF)
	row.Size = UDim2.new(1, -28, 0, 32)
	row.Position = UDim2.new(0, 14, 0, y)
	row.BackgroundColor3 = Color3.fromRGB(16, 18, 23)
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", row)
	stroke.Color = Color3.fromRGB(30, 32, 42)
	
	local lbl = createLabel(row, name, UDim2.new(0.65, 0, 1, 0), UDim2.new(0, 10, 0, 0), Enum.Font.GothamMedium, 10, Color3.fromRGB(200, 205, 220))
	
	local btn = Instance.new("TextButton", row)
	btn.Size = UDim2.new(0.3, -6, 1, -8)
	btn.Position = UDim2.new(0.7, 0, 0.5, -8)
	btn.BackgroundColor3 = Color3.fromRGB(0, 110, 220)
	btn.Text = "Teleport"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 9
	btn.BorderSizePixel = 0
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
	
	btn.MouseButton1Click:Connect(function()
		teleportTo(pos)
		_clog("Teleported to: " .. name)
	end)
	
	return row
end

-- Draw Presets
for _, pr in ipairs(PRESETS) do
	makeTeleportButton(pr.name, pr.pos, listY)
	listY = listY + 38
end

-- Custom Spots Header
createSeparator(tSF, listY + 2)
listY = listY + 12
createLabel(tSF, "CUSTOM SPOTS", UDim2.new(1, -28, 0, 16), UDim2.new(0, 14, 0, listY), Enum.Font.GothamBold, 9.5, Color3.fromRGB(100, 105, 120))
listY = listY + 20

local customSpotsContainer = Instance.new("Frame", tSF)
customSpotsContainer.Size = UDim2.new(1, 0, 0, 150)
customSpotsContainer.Position = UDim2.new(0, 0, 0, listY)
customSpotsContainer.BackgroundTransparency = 1

local function drawCustomSpots()
	customSpotsContainer:ClearAllChildren()
	local yOffset = 0
	for idx = 1, 3 do
		local val = customSpots[idx]
		local row = Instance.new("Frame", customSpotsContainer)
		row.Size = UDim2.new(1, -28, 0, 32)
		row.Position = UDim2.new(0, 14, 0, yOffset)
		row.BackgroundColor3 = Color3.fromRGB(16, 18, 23)
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		local stroke = Instance.new("UIStroke", row)
		stroke.Color = Color3.fromRGB(30, 32, 42)
		
		local sName = "Custom Spot #" .. idx
		local sLabelStr = val and string.format("Spot %d (%.0f, %.0f, %.0f)", idx, val.x, val.y, val.z) or ("Spot " .. idx .. " (Unregistered)")
		createLabel(row, sLabelStr, UDim2.new(0.5, 0, 1, 0), UDim2.new(0, 10, 0, 0), Enum.Font.GothamMedium, 9.5, val and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(120, 125, 140))
		
		local saveBtn = Instance.new("TextButton", row)
		saveBtn.Size = UDim2.new(0.22, 0, 1, -8)
		saveBtn.Position = UDim2.new(0.52, 0, 0.5, -8)
		saveBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
		saveBtn.Text = "Register"
		saveBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
		saveBtn.Font = Enum.Font.GothamMedium
		saveBtn.TextSize = 8.5
		saveBtn.BorderSizePixel = 0
		Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 4)
		local sS = Instance.new("UIStroke", saveBtn)
		sS.Color = Color3.fromRGB(44, 46, 55)
		
		saveBtn.MouseButton1Click:Connect(function()
			local char = me.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local p = root.Position
				customSpots[idx] = {x = p.X, y = p.Y, z = p.Z}
				saveConfig()
				drawCustomSpots()
				_clog("Saved Custom Spot " .. idx)
			end
		end)
		
		local tpBtn = Instance.new("TextButton", row)
		tpBtn.Size = UDim2.new(0.22, 0, 1, -8)
		tpBtn.Position = UDim2.new(0.76, 0, 0.5, -8)
		tpBtn.BackgroundColor3 = val and Color3.fromRGB(0, 110, 220) or Color3.fromRGB(34, 36, 45)
		tpBtn.Text = "Go"
		tpBtn.TextColor3 = val and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(80, 85, 95)
		tpBtn.Font = Enum.Font.GothamBold
		tpBtn.TextSize = 8.5
		tpBtn.BorderSizePixel = 0
		tpBtn.Active = (val ~= nil)
		Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 4)
		
		if val then
			tpBtn.MouseButton1Click:Connect(function()
				teleportTo(Vector3.new(val.x, val.y, val.z))
				_clog("Teleported to custom Spot " .. idx)
			end)
		end
		
		yOffset = yOffset + 38
	end
	tSF.CanvasSize = UDim2.new(0, 0, 0, listY + yOffset + 20)
end

drawCustomSpots()

-- Dynamic Water Scanner Option
local scanCard = Instance.new("Frame", tSF)
scanCard.Size = UDim2.new(1, -28, 0, 48)
scanCard.Position = UDim2.new(0, 14, 0, listY + 118)
scanCard.BackgroundColor3 = Color3.fromRGB(10, 30, 25)
Instance.new("UICorner", scanCard).CornerRadius = UDim.new(0, 6)
local scSt = Instance.new("UIStroke", scanCard)
scSt.Color = Color3.fromRGB(0, 170, 100)

createLabel(scanCard, "Water Proximity Teleporter", UDim2.new(0.65, 0, 0.5, 0), UDim2.new(0, 10, 0, 4), Enum.Font.GothamBold, 9.5, Color3.fromRGB(200, 255, 220))
createLabel(scanCard, "Scans the map for active water parts", UDim2.new(0.65, 0, 0.5, 0), UDim2.new(0, 10, 0.5, -2), Enum.Font.Gotham, 8.5, Color3.fromRGB(150, 200, 180))

local scanBtn = Instance.new("TextButton", scanCard)
scanBtn.Size = UDim2.new(0.3, -8, 1, -12)
scanBtn.Position = UDim2.new(0.7, 0, 0.5, -18)
scanBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
scanBtn.Text = "Scan & Go"
scanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
scanBtn.Font = Enum.Font.GothamBold
scanBtn.TextSize = 9
scanBtn.BorderSizePixel = 0
Instance.new("UICorner", scanBtn).CornerRadius = UDim.new(0, 4)

scanBtn.MouseButton1Click:Connect(function()
	local waterList = {}
	for _, v in ipairs(workspace:GetDescendants()) do
		if v:IsA("BasePart") then
			local name = v.Name:lower()
			if name:find("water") or name:find("ocean") or name:find("sea") or name:find("danau") or name:find("laut") or name:find("river") then
				table.insert(waterList, v)
			end
		end
	end
	
	if #waterList > 0 then
		-- Choose the largest water part or first one
		table.sort(waterList, function(a, b) return a.Size.Magnitude > b.Size.Magnitude end)
		local wt = waterList[1]
		local targetPos = wt.Position + Vector3.new(0, wt.Size.Y/2 + 3, 0)
		teleportTo(targetPos)
		_clog("Found & teleported to water: " .. wt.Name)
	else
		_clog("Failed: No water parts found in map")
	end
end)

-- =============================================================================
-- PANEL 3: SETTINGS PANEL
-- =============================================================================
local pSett = panels["Settings"]

local sY = 10
local function addSettToggle(lbl, key, def)
	createToggle(pSett, lbl, sY, def, function(val)
		CFG[key] = val
		saveConfig()
		_clog(lbl .. " set to " .. tostring(val))
	end)
	sY = sY + 36
end

addSettToggle("Click Timing Randomization", "timeJitter", CFG.timeJitter)
addSettToggle("Cursor Position Jitter", "coordJitter", CFG.coordJitter)
addSettToggle("AFK Break Simulation", "fatigueBreak", CFG.fatigueBreak)
addSettToggle("Anti-AFK Mouse Sweep", "mouseAFK", CFG.mouseAFK)
addSettToggle("Admin & Staff Auto-Kick", "adminGuard", CFG.adminGuard)

createSeparator(pSett, sY + 4)
sY = sY + 12

createToggle(pSett, "Watchdog Auto-Reset System", sY, autoResetEnabled, function(val)
	autoResetEnabled = val
	saveConfig()
	_clog("Watchdog set to " .. tostring(val))
end)

-- =============================================================================
-- PANEL 4: WEBHOOK & LOGS
-- =============================================================================
local pWeb = panels["Webhook"]

-- Webhook Input Fields
local whCard, whStroke = createCard(pWeb, UDim2.new(1, -28, 0, 78), UDim2.new(0, 14, 0, 10))
whStroke.Color = Color3.fromRGB(24, 26, 33)

createLabel(whCard, "Discord Webhook Integration", UDim2.new(1, -20, 0, 16), UDim2.new(0, 10, 0, 4), Enum.Font.GothamBold, 9.5, Color3.fromRGB(100, 105, 120))

local whBox = Instance.new("TextBox", whCard)
whBox.Size = UDim2.new(1, -20, 0, 24)
whBox.Position = UDim2.new(0, 10, 0, 22)
whBox.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
whBox.TextColor3 = Color3.fromRGB(220, 225, 240)
whBox.PlaceholderText = "Paste Discord webhook link here..."
whBox.PlaceholderColor3 = Color3.fromRGB(70, 75, 90)
whBox.Text = webhookUrl
whBox.ClearTextOnFocus = false
whBox.Font = Enum.Font.Code
whBox.TextSize = 9.5
whBox.TextXAlignment = Enum.TextXAlignment.Left
whBox.BorderSizePixel = 0
Instance.new("UICorner", whBox).CornerRadius = UDim.new(0, 4)
local whbStr = Instance.new("UIStroke", whBox)
whbStr.Color = Color3.fromRGB(36, 38, 48)

whBox.FocusLost:Connect(function()
	webhookUrl = whBox.Text
	saveConfig()
	_clog("Webhook URL updated")
end)

local whEnableBtn = Instance.new("TextButton", whCard)
whEnableBtn.Size = UDim2.new(0.5, -15, 0, 22)
whEnableBtn.Position = UDim2.new(0, 10, 0, 50)
whEnableBtn.BackgroundColor3 = webhookEnabled and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(34, 36, 45)
whEnableBtn.Text = webhookEnabled and "Webhook: ENABLED" or "Webhook: DISABLED"
whEnableBtn.TextColor3 = Color3.fromRGB(240, 242, 248)
whEnableBtn.Font = Enum.Font.GothamBold
whEnableBtn.TextSize = 9.5
whEnableBtn.BorderSizePixel = 0
Instance.new("UICorner", whEnableBtn).CornerRadius = UDim.new(0, 4)

whEnableBtn.MouseButton1Click:Connect(function()
	webhookEnabled = not webhookEnabled
	whEnableBtn.BackgroundColor3 = webhookEnabled and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(34, 36, 45)
	whEnableBtn.Text = webhookEnabled and "Webhook: ENABLED" or "Webhook: DISABLED"
	saveConfig()
	_clog("Webhook status: " .. tostring(webhookEnabled))
end)

local whTestBtn = Instance.new("TextButton", whCard)
whTestBtn.Size = UDim2.new(0.5, -15, 0, 22)
whTestBtn.Position = UDim2.new(0.5, 5, 0, 50)
whTestBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
whTestBtn.Text = "Send Test Ping"
whTestBtn.TextColor3 = Color3.fromRGB(150, 155, 170)
whTestBtn.Font = Enum.Font.GothamBold
whTestBtn.TextSize = 9.5
whTestBtn.BorderSizePixel = 0
Instance.new("UICorner", whTestBtn).CornerRadius = UDim.new(0, 4)
local whtStr = Instance.new("UIStroke", whTestBtn)
whtStr.Color = Color3.fromRGB(44, 46, 55)

whTestBtn.MouseButton1Click:Connect(function()
	if webhookUrl == "" then
		_clog("Error: Webhook link is empty!")
		return
	end
	_clog("Sending test webhook notification...")
	sendDiscordWebhook("🧪 Webhook Verification Ping", "Successfully connected from Roblox client. System telemetry is active and running.", "#00cc66")
end)

-- Logging Console
local consoleCard, cnStroke = createCard(pWeb, UDim2.new(1, -28, 0, 220), UDim2.new(0, 14, 0, 94))
cnStroke.Color = Color3.fromRGB(24, 26, 33)

local cHeader = createLabel(consoleCard, "Realtime System Logs", UDim2.new(0.5, 0, 0, 18), UDim2.new(0, 10, 0, 4), Enum.Font.GothamBold, 9.5, Color3.fromRGB(100, 105, 120))

local logToggle = Instance.new("TextButton", consoleCard)
logToggle.Size = UDim2.new(0, 60, 0, 16)
logToggle.Position = UDim2.new(1, -126, 0, 4)
logToggle.BackgroundColor3 = Color3.fromRGB(34, 36, 45)
logToggle.Text = "Log: OFF"
logToggle.TextColor3 = Color3.fromRGB(150, 155, 170)
logToggle.Font = Enum.Font.GothamBold
logToggle.TextSize = 8.5
logToggle.BorderSizePixel = 0
Instance.new("UICorner", logToggle).CornerRadius = UDim.new(0, 4)

local logClear = Instance.new("TextButton", consoleCard)
logClear.Size = UDim2.new(0, 50, 0, 16)
logClear.Position = UDim2.new(1, -60, 0, 4)
logClear.BackgroundColor3 = Color3.fromRGB(34, 36, 45)
logClear.Text = "Clear"
logClear.TextColor3 = Color3.fromRGB(150, 155, 170)
logClear.Font = Enum.Font.GothamBold
logClear.TextSize = 8.5
logClear.BorderSizePixel = 0
Instance.new("UICorner", logClear).CornerRadius = UDim.new(0, 4)

local logSF = Instance.new("ScrollingFrame", consoleCard)
logSF.Size = UDim2.new(1, -12, 1, -28)
logSF.Position = UDim2.new(0, 6, 0, 24)
logSF.BackgroundTransparency = 1
logSF.CanvasSize = UDim2.new(0, 0, 0, 0)
logSF.ScrollBarThickness = 2
logSF.ScrollBarImageColor3 = Color3.fromRGB(36, 38, 48)
logSF.BorderSizePixel = 0

local logLL = Instance.new("UIListLayout", logSF)
logLL.SortOrder = Enum.SortOrder.LayoutOrder
logLL.Padding = UDim.new(0, 3)

local logCount = 0

local function appendLog(txt)
	if not consoleOn then return end
	logCount = logCount + 1
	
	local l = Instance.new("TextLabel", logSF)
	l.LayoutOrder = logCount
	l.Size = UDim2.new(1, 0, 0, 14)
	l.BackgroundTransparency = 1
	l.Text = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(txt))
	l.TextColor3 = Color3.fromRGB(160, 165, 180)
	l.Font = Enum.Font.Code
	l.TextSize = 9
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	
	task.defer(function()
		logSF.CanvasSize = UDim2.new(0, 0, 0, logLL.AbsoluteContentSize.Y + 4)
		logSF.CanvasPosition = Vector2.new(0, math.huge)
	end)
	
	local items = {}
	for _, child in ipairs(logSF:GetChildren()) do
		if child:IsA("TextLabel") then table.insert(items, child) end
	end
	if #items > 50 then
		items[1]:Destroy()
	end
end
_clog = appendLog

logToggle.MouseButton1Click:Connect(function()
	consoleOn = not consoleOn
	logToggle.Text = consoleOn and "Log: ON" or "Log: OFF"
	logToggle.BackgroundColor3 = consoleOn and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(34, 36, 45)
	logToggle.TextColor3 = consoleOn and Color3.fromRGB(240, 242, 248) or Color3.fromRGB(150, 155, 170)
end)

logClear.MouseButton1Click:Connect(function()
	for _, child in ipairs(logSF:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	logSF.CanvasSize = UDim2.new(0, 0, 0, 0)
	logCount = 0
end)

-- =============================================================================
-- FISHING ENGINE
-- =============================================================================
local function trulyVisible(obj)
	if not obj or typeof(obj) ~= "Instance" or not obj:IsA("GuiObject") then return false end
	if not obj.Visible then return false end
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

local function getEquippedRod()
	local ch = me.Character
	if ch then
		local eq = ch:FindFirstChildWhichIsA("Tool")
		if eq then
			for _, n in ipairs(FISH_TOOLS) do
				if eq.Name:lower():find(n:lower()) then return eq end
			end
		end
		
		-- Try to find in backpack and equip
		local bp = me.Backpack
		for _, n in ipairs(FISH_TOOLS) do
			local t = bp:FindFirstChild(n) or bp:FindFirstChildWhichIsA("Tool")
			if t then
				local hum = ch:FindFirstChildOfClass("Humanoid")
				if hum then
					pcall(function() hum:EquipTool(t) end)
					task.wait(0.5)
					return ch:FindFirstChildWhichIsA("Tool")
				end
			end
		end
	end
	return nil
end

local function toggleSpace(v, force)
	if isSpace == v and not force then return end
	local now = os.clock()
	if not force and (now - lastSpTgl) < 0.03 then return end
	pcall(function() VIM:SendKeyEvent(v, Enum.KeyCode.Space, false, game) end)
	isSpace = v
	lastSpTgl = now
end

local function getBars()
	if wBar and rBar and wBar.Parent and rBar.Parent and trulyVisible(wBar) and trulyVisible(rBar) then
		return wBar, rBar
	end
	local now = os.clock()
	if now - lastScan < 0.08 then return nil, nil end
	lastScan = now
	
	wBar = nil
	rBar = nil
	local pg = me:FindFirstChild("PlayerGui")
	if not pg then return nil, nil end
	
	-- Optimized 1-pass Scan based on color match
	for _, v in ipairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVisible(v) and v.AbsoluteSize.X > 10 then
			local name = v.Name:lower()
			if name == "whitebar" or name == "playerbar" or (name:find("white") and name:find("bar")) then
				local parent = v.Parent
				if parent and parent:IsA("GuiObject") then
					for _, sib in ipairs(parent:GetChildren()) do
						if sib ~= v and sib:IsA("GuiObject") and trulyVisible(sib) then
							local sn = sib.Name:lower()
							if sn:find("red") or sn:find("target") or sn:find("goal") then
								wBar = v
								rBar = sib
								return v, sib
							end
						end
					end
				end
			end
		end
	end
	
	-- Fallback scan based on background color
	for _, v in ipairs(pg:GetDescendants()) do
		if v:IsA("GuiObject") and trulyVisible(v) and v.AbsoluteSize.X > 12 and v.AbsoluteSize.Y > 5 then
			local c = v.BackgroundColor3
			local parent = v.Parent
			if c.R > 0.8 and c.G > 0.8 and c.B > 0.8 and parent and parent:IsA("GuiObject") then
				for _, sib in ipairs(parent:GetChildren()) do
					if sib ~= v and sib:IsA("GuiObject") and trulyVisible(sib) and sib.AbsoluteSize.X > 12 then
						local sc = sib.BackgroundColor3
						if sc.R > 0.45 and sc.G < 0.25 and sc.B < 0.25 then
							wBar = v
							rBar = sib
							return v, sib
						end
					end
				end
			end
		end
	end
	
	return nil, nil
end

local function handleFatigue()
	if not CFG.fatigueBreak then return end
	fatCount = fatCount + 1
	if fatCount < fatNext then return end
	
	local duration = math.random(6, 12)
	_clog(string.format("AFK Simulator: Resting for %d seconds...", duration))
	updateStatusUI("Resting...", true)
	
	toggleSpace(false, true)
	task.wait(duration)
	
	fatCount = 0
	fatNext = math.random(15, 25)
	updateStatusUI("Active", true)
end

local function handleSuccess(reason)
	if successDone then return end
	successDone = true
	toggleSpace(false, true)
	fishState = "DONE"
	setPhaseIndicator(4)
	
	fishCount = fishCount + 1
	updateStatusUI(string.format("Caught #%d", fishCount), true)
	_clog("Caught Fish #" .. fishCount .. " [" .. reason .. "]")
	
	-- Webhook Notification Dispatch
	sendDiscordWebhook("🎣 Fish Caught", string.format("Successfully caught fish **#%d** on current session.", fishCount), "#00aaff")
	
	handleFatigue()
	
	local currentSession = castSess
	task.delay(RECAST_DLY + (CFG.timeJitter and math.random() * 0.2 or 0), function()
		if not M.on or mode ~= "FISH" or castSess ~= currentSession then return end
		doResetFish()
		task.wait(0.05)
		if mode == "FISH" then
			fishState = "IDLE"
			idleAt = os.clock()
		end
	end)
end

doResetFish = function()
	fishState = "IDLE"
	isSpace = false
	isCasting = false
	successDone = false
	mgEverSeen = false
	mgStarted = false
	wBar = nil
	rBar = nil
	lastScan = 0
	lastWC = nil
	wVel = 0
	mgLastSeen = 0
	castSess = castSess + 1
	idleAt = os.clock()
	toggleSpace(false, true)
	setPhaseIndicator(0)
	updateStatusUI("Active", true)
end

-- Minigame controller (RunService Heartbeat for precision tracking)
local hbConnection
hbConnection = RS.Heartbeat:Connect(function()
	if not M.on then
		if hbConnection then pcall(function() hbConnection:Disconnect() end) end
		return
	end
	if mode ~= "FISH" then
		if isSpace then toggleSpace(false, true) end
		return
	end
	
	local now = os.clock()
	safe(function()
		local rod = RODS[rodIdx]
		if fishState == "WAITING" then
			local elapsed = now - biteStart
			setPbarPercent(math.clamp(elapsed / BITE_WAIT, 0, 1))
			if elapsed >= BITE_WAIT then
				fishState = "MINIGAME"
				mgStart = now
				mgEverSeen = false
				mgStarted = false
				mgLastSeen = 0
				successDone = false
				wBar = nil
				rBar = nil
				lastScan = 0
				lastWC = nil
				wVel = 0
				lastWTime = now
				toggleSpace(false, true)
				setPhaseIndicator(3)
				setPbarPercent(0)
				_clog("Minigame detected! Active solver initiated")
			end
			return
		end
		
		if fishState ~= "MINIGAME" then return end
		
		local elapsed = now - mgStart
		local timeout = 12.0 + rod.prog * 3.5
		setPbarPercent(math.clamp(elapsed / timeout, 0, 1))
		
		if elapsed >= timeout then
			toggleSpace(false, true)
			handleSuccess("Timeout Fallback")
			return
		end
		
		local wb, rb = getBars()
		if wb and rb and trulyVisible(wb) and trulyVisible(rb) then
			mgEverSeen = true
			mgLastSeen = now
			
			if not mgStarted then
				mgStarted = true
				toggleSpace(false, true)
				lastWC = nil
				wVel = 0
				lastWTime = now
			end
			
			local wC = wb.AbsolutePosition.X + wb.AbsoluteSize.X * 0.5
			local rL = rb.AbsolutePosition.X
			local rR = rL + rb.AbsoluteSize.X
			local rC = (rL + rR) * 0.5
			
			local rawDt = now - lastWTime
			local dt = math.clamp(rawDt, 0.007, 0.12)
			
			if lastWC then
				local inst = (wC - lastWC) / dt
				local sm = math.clamp(0.25 / rod.lure, 0.08, 0.28)
				wVel = wVel * (1 - sm) + inst * sm
			end
			
			lastWC = wC
			lastWTime = now
			
			local ahead = math.clamp(math.abs(wVel) / 1600, 0.03, 0.18) * math.sqrt(rod.lure)
			local pred = wC + wVel * ahead
			local rw = math.max(rb.AbsoluteSize.X, 1)
			local lag = math.clamp(rawDt / 0.05 - 1, 0, 1.2)
			local tol = math.clamp(rw * (0.16 + lag * 0.14 + rod.lure * 0.02), 4, 25)
			
			local inside = pred >= (rL - tol) and pred <= (rR + tol)
			if inside then
				if wC < rL then toggleSpace(true)
				elseif wC > rR then toggleSpace(false)
				else
					local e = wC - rC
					if math.abs(e) > tol * 0.4 then toggleSpace(e < 0) end
				end
			else
				local e = rC - pred
				if e > tol then toggleSpace(true)
				elseif e < -tol then toggleSpace(false)
				elseif math.abs(wVel) > 130 then toggleSpace(wVel < 0) end
			end
		else
			if mgEverSeen then
				-- If bar vanished for more than 0.18s, minigame has finished
				if mgLastSeen > 0 and (now - mgLastSeen) >= 0.18 then
					toggleSpace(false, true)
					handleSuccess("Bar Cleared")
				end
			else
				-- Sync mode to trigger bite trigger
				local beat = math.floor((now - mgStart) * 3.0) % 2 == 0
				toggleSpace(beat)
			end
		end
	end)
end)
table.insert(M.c, hbConnection)

-- Casting loop thread
task.spawn(function()
	while M.on do
		task.wait(0.12)
		if not M.on or mode ~= "FISH" then continue end
		
		safe(function()
			local tool = getEquippedRod()
			if not tool then
				updateStatusUI("No Rod Found", true)
				return
			end
			
			if fishState == "IDLE" and not isCasting then
				isCasting = true
				castSess = castSess + 1
				local sess = castSess
				
				task.spawn(function()
					if not M.on or mode ~= "FISH" or castSess ~= sess then isCasting = false; return end
					
					local cam = workspace.CurrentCamera
					if not cam then isCasting = false; return end
					
					local rod = RODS[rodIdx]
					local size = cam.ViewportSize
					local center = Vector2.new(
						size.X/2 + (CFG.coordJitter and math.random(-40, 40) or 0),
						size.Y/2 + (CFG.coordJitter and math.random(-30, 30) or 0)
					)
					
					fishState = "CASTING"
					setPhaseIndicator(1)
					setPbarPercent(0)
					
					pcall(function() tool:Activate() end)
					pcall(function() VU:Button1Down(center, cam.CFrame) end)
					
					local holdTime = CAST_HOLD / math.max(1, math.sqrt(rod.lure) * 0.85)
					if CFG.timeJitter then holdTime = holdTime * (1 + (math.random() * 0.16 - 0.08)) end
					
					local t0 = os.clock()
					while os.clock() - t0 < holdTime do
						task.wait(0.04)
						if mode ~= "FISH" or not M.on or castSess ~= sess then
							pcall(function() VU:Button1Up(center, cam.CFrame) end)
							isCasting = false
							return
						end
						setPbarPercent((os.clock() - t0) / holdTime)
					end
					
					pcall(function() VU:Button1Up(center, cam.CFrame) end)
					setPbarPercent(1)
					
					task.wait(0.12)
					if mode ~= "FISH" or not M.on or castSess ~= sess then isCasting = false; return end
					
					fishState = "WAITING"
					biteStart = os.clock()
					setPhaseIndicator(2)
					setPbarPercent(0)
					isCasting = false
				end)
			end
		end)
	end
end)

-- Dynamic Watchdog (Stuck Protection)
task.spawn(function()
	while M.on do
		task.wait(3.0)
		if not M.on or mode ~= "FISH" or not autoResetEnabled then continue end
		
		local now = os.clock()
		if fishState == "IDLE" and not isCasting and (now - idleAt) > 10 then
			_clog("Watchdog: Idle lock detected, cycling recast")
			doResetFish()
		elseif fishState == "WAITING" and (now - biteStart) > (BITE_WAIT + 8) then
			_clog("Watchdog: Bite timeout threshold exceeded, resetting")
			sendDiscordWebhook("⚠️ Watchdog Warning", "Bite trigger timed out. Auto-resetting bobber...", "#ffaa00")
			doResetFish()
		elseif fishState == "CASTING" and not isCasting and (now - idleAt) > 8 then
			_clog("Watchdog: Cast sequence locked, restarting hook")
			doResetFish()
		end
	end
end)

-- Anti-AFK Simulation
task.spawn(function()
	while M.on do
		task.wait(math.random(80, 140))
		if not M.on then break end
		if CFG.mouseAFK then
			pcall(function()
				local cam = workspace.CurrentCamera
				if cam then
					local vSize = cam.ViewportSize
					VU:MouseMoveEvent(Vector2.new(vSize.X/2 + math.random(-60, 60), vSize.Y/2 + math.random(-40, 40)), cam.CFrame)
				end
			end)
		end
	end
end)

local idledConnection
idledConnection = me.Idled:Connect(function()
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam then
			VU:Button2Down(Vector2.new(0, 0), cam.CFrame)
			task.wait(0.1)
			VU:Button2Up(Vector2.new(0, 0), cam.CFrame)
		end
	end)
end)
table.insert(M.c, idledConnection)

-- =============================================================================
-- SECURITY COMPONENT: ADMIN DETECTION
-- =============================================================================
local STAFF_ROLES = {"moderator", "roblox_adm", "rbxadmin", "staffmod", "gamemaster", "game_master", "admin", "helper"}
local GROUP_ID = 1200769

local function checkAdminPresence(playerInstance)
	if playerInstance == me or not playerInstance.Parent or not CFG.adminGuard then return end
	task.wait(2.0)
	if not playerInstance or not playerInstance.Parent then return end
	
	local isAdmin = false
	pcall(function()
		isAdmin = isAdmin or playerInstance:IsInGroup(GROUP_ID)
	end)
	
	if not isAdmin then
		local combinedName = (playerInstance.Name .. playerInstance.DisplayName):lower()
		for _, pattern in ipairs(STAFF_ROLES) do
			if combinedName:find(pattern) then
				isAdmin = true
				break
			end
		end
	end
	
	if not isAdmin then
		pcall(function()
			if game.CreatorType == Enum.CreatorType.Group then
				if playerInstance:GetRankInGroup(game.CreatorId) >= 150 then
					isAdmin = true
				end
			end
		end)
	end
	
	if isAdmin then
		_clog("🚨 CRITICAL: Admin " .. playerInstance.Name .. " detected! Emergency disconnect initiated.")
		sendDiscordWebhook("🚨 Emergency Server Evacuation", string.format("Admin **%s** has joined the server. Automatically disconnected to secure the account.", playerInstance.Name), "#ff0033")
		
		mode = "OFF"
		isSpace = false
		pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		
		task.wait(0.5)
		me:Kick("Secure disconnect triggered.")
	end
end

for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(checkAdminPresence, pl)
end

local playerAddedConnection
playerAddedConnection = Players.PlayerAdded:Connect(function(pl)
	task.spawn(checkAdminPresence, pl)
end)
table.insert(M.c, playerAddedConnection)

-- Initialize Settings Displays
updateRodDisplay()
setPhaseIndicator(0)
_clog("Auto-Fishing initialization complete. Premium profile loaded.")

