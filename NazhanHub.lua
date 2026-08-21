--!nocheck
-- IDH Hub | Indo Hangout client helper

local BUILD = "0.3.0"
local StarterGui = game:GetService("StarterGui")
local env = _G
if type(getgenv)=="function" then
	local ok,result=pcall(getgenv)
	if ok and type(result)=="table" then env=result end
elseif type(shared)=="table" then env=shared end

local function report(message,isError)
	local line="[IDH Hub "..BUILD.."] "..tostring(message)
	if isError then warn(line) else print(line) end
	if type(rconsoleprint)=="function" then pcall(rconsoleprint,line.."\n") end
end
local function notify(title,text)
	pcall(function() StarterGui:SetCore("SendNotification",{Title=title,Text=text,Duration=7}) end)
end
local function trace(message)
	if debug and type(debug.traceback)=="function" then return debug.traceback(tostring(message),2) end
	return tostring(message)
end

report("starting")
local bootOk,bootResult=xpcall(function()
if env.IDHHub and env.IDHHub.destroy then pcall(env.IDHHub.destroy) end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VIM; pcall(function() VIM=game:GetService("VirtualInputManager") end)
local TS = game:GetService("TweenService")
local PFS = game:GetService("PathfindingService")
local VU = game:GetService("VirtualUser")
local me = Players.LocalPlayer

local S = {
	alive=true, fishing=false, fastCatch=false, reeling=false, mining=false,
	antiAfk=true, lowGraphics=false, spaceDown=false, lastCast=0, lastReel=0,
	casts=0, targets=0, connections={}, version=BUILD, miningBlocked={}
}
env.IDHHub = S

local function on(signal, callback)
	local c = signal:Connect(callback)
	table.insert(S.connections, c)
	return c
end

local function path(root, ...)
	local node = root
	for i=1,select("#", ...) do
		local childName=select(i, ...)
		node=node and node:FindFirstChild(childName)
	end
	return node
end

local events = RS:FindFirstChild("Events")
local re = events and events:FindFirstChild("RemoteEvent")
local rf = events and events:FindFirstChild("RemoteFunction")
local rodRemote = re and re:FindFirstChild("Rod")
local pickaxeRemote = re and re:FindFirstChild("Pickaxe")
local sellFishRemote = rf and rf:FindFirstChild("SellFish")
local sellCrystalRemote = rf and rf:FindFirstChild("SellCrystal")
local applyAvatarRemote = path(RS, "BloxbizRemotes", "CatalogOnApplyToRealHumanoid")

local C = {
	base=Color3.fromRGB(15,17,21), surface=Color3.fromRGB(22,25,30),
	raised=Color3.fromRGB(29,33,40), line=Color3.fromRGB(43,48,57),
	text=Color3.fromRGB(235,238,243), muted=Color3.fromRGB(139,147,160),
	accent=Color3.fromRGB(70,156,255), good=Color3.fromRGB(61,190,126),
	warn=Color3.fromRGB(238,178,72)
}

local function make(class, props, parent)
	local x=Instance.new(class)
	for k,v in pairs(props or {}) do x[k]=v end
	x.Parent=parent
	return x
end
local function round(x,r) make("UICorner",{CornerRadius=UDim.new(0,r or 8)},x) end
local function stroke(x) make("UIStroke",{Color=C.line,Thickness=1,Transparency=.1},x) end

local gui=make("ScreenGui",{Name="IDHHub",ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local guiParent
if type(gethui)=="function" then local ok,res=pcall(gethui); if ok and typeof(res)=="Instance" then guiParent=res end end
guiParent=guiParent or me:WaitForChild("PlayerGui")
if type(syn)=="table" and type(syn.protect_gui)=="function" then pcall(syn.protect_gui,gui) end
gui.Parent=guiParent

local window=make("Frame",{
	Size=UDim2.fromOffset(356,438),Position=UDim2.new(.5,-178,.5,-219),
	BackgroundColor3=C.base,BorderSizePixel=0,ClipsDescendants=true
},gui); round(window,12); stroke(window)
local uiScale=make("UIScale",{Scale=1},window)
local cam=workspace.CurrentCamera
if cam and cam.ViewportSize.X<500 then uiScale.Scale=math.clamp(cam.ViewportSize.X/390,.78,1) end

local header=make("Frame",{Size=UDim2.new(1,0,0,54),BackgroundColor3=C.surface,BorderSizePixel=0},window)
make("TextLabel",{
	Size=UDim2.new(1,-100,0,22),Position=UDim2.fromOffset(16,9),BackgroundTransparency=1,
	Text="IDH Hub",TextColor3=C.text,TextSize=15,Font=Enum.Font.GothamBold,
	TextXAlignment=Enum.TextXAlignment.Left
},header)
local subtitle=make("TextLabel",{
	Size=UDim2.new(1,-100,0,16),Position=UDim2.fromOffset(16,29),BackgroundTransparency=1,
	Text="Indo Hangout  •  build "..BUILD,TextColor3=C.muted,TextSize=10,
	Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left
},header)
local function headerBtn(text,x)
	local b=make("TextButton",{
		Size=UDim2.fromOffset(30,30),Position=UDim2.new(1,x,0,12),BackgroundColor3=C.raised,
		BorderSizePixel=0,Text=text,TextColor3=C.muted,TextSize=13,Font=Enum.Font.GothamMedium,
		AutoButtonColor=false
	},header); round(b,7); return b
end
local hideBtn=headerBtn("–",-72)
local closeBtn=headerBtn("×",-38)

local tabBar=make("Frame",{
	Size=UDim2.new(1,0,0,38),Position=UDim2.fromOffset(0,54),BackgroundColor3=C.surface,BorderSizePixel=0
},window)
local host=make("Frame",{
	Size=UDim2.new(1,0,1,-92),Position=UDim2.fromOffset(0,92),BackgroundTransparency=1
},window)
local names={"Farm","Player","System"}; local pages={}; local tabs={}
for i,name in ipairs(names) do
	local b=make("TextButton",{
		Size=UDim2.new(1/#names,0,1,0),Position=UDim2.new((i-1)/#names,0,0,0),
		BackgroundTransparency=1,Text=name,TextColor3=i==1 and C.text or C.muted,
		TextSize=11,Font=Enum.Font.GothamMedium,AutoButtonColor=false
	},tabBar); tabs[name]=b
	local p=make("ScrollingFrame",{
		Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,
		ScrollBarImageColor3=C.line,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,
		Visible=i==1
	},host)
	make("UIPadding",{PaddingTop=UDim.new(0,12),PaddingBottom=UDim.new(0,12),PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},p)
	make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},p)
	pages[name]=p
end
local tabLine=make("Frame",{
	Size=UDim2.new(1/#names,-24,0,2),Position=UDim2.new(0,12,1,-2),BackgroundColor3=C.accent,BorderSizePixel=0
},tabBar); round(tabLine,2)
local function selectTab(name)
	local index=table.find(names,name) or 1
	for n,p in pairs(pages) do p.Visible=n==name; tabs[n].TextColor3=n==name and C.text or C.muted end
	TS:Create(tabLine,TweenInfo.new(.16,Enum.EasingStyle.Quad),{Position=UDim2.new((index-1)/#names,12,1,-2)}):Play()
end
for n,b in pairs(tabs) do on(b.MouseButton1Click,function() selectTab(n) end) end

local function title(page,text)
	return make("TextLabel",{
		Size=UDim2.new(1,0,0,20),BackgroundTransparency=1,Text=string.upper(text),TextColor3=C.muted,
		TextSize=9,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left
	},page)
end
local function card(page,height)
	local f=make("Frame",{Size=UDim2.new(1,0,0,height),BackgroundColor3=C.surface,BorderSizePixel=0},page)
	round(f,9); stroke(f); return f
end
local function statusCard(page)
	local f=card(page,62)
	local dot=make("Frame",{Size=UDim2.fromOffset(8,8),Position=UDim2.fromOffset(14,17),BackgroundColor3=C.good,BorderSizePixel=0},f); round(dot,8)
	local a=make("TextLabel",{
		Size=UDim2.new(1,-42,0,18),Position=UDim2.fromOffset(30,11),BackgroundTransparency=1,Text="Ready",
		TextColor3=C.text,TextSize=12,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left
	},f)
	local b=make("TextLabel",{
		Size=UDim2.new(1,-28,0,18),Position=UDim2.fromOffset(14,34),BackgroundTransparency=1,
		Text="Remotes checked from current client",TextColor3=C.muted,TextSize=9,Font=Enum.Font.Gotham,
		TextXAlignment=Enum.TextXAlignment.Left
	},f)
	return a,b,dot
end
local status,detail,dot=statusCard(pages.Farm)
local function setStatus(a,b,color) status.Text=a; detail.Text=b or ""; dot.BackgroundColor3=color or C.good end

local function toggle(page,label,desc,default,callback)
	local f=card(page,56)
	make("TextLabel",{
		Size=UDim2.new(1,-74,0,18),Position=UDim2.fromOffset(14,9),BackgroundTransparency=1,Text=label,
		TextColor3=C.text,TextSize=11,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left
	},f)
	make("TextLabel",{
		Size=UDim2.new(1,-74,0,16),Position=UDim2.fromOffset(14,29),BackgroundTransparency=1,Text=desc,
		TextColor3=C.muted,TextSize=9,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left
	},f)
	local sw=make("TextButton",{
		Size=UDim2.fromOffset(42,24),Position=UDim2.new(1,-56,.5,-12),BackgroundColor3=default and C.accent or C.raised,
		BorderSizePixel=0,Text="",AutoButtonColor=false
	},f); round(sw,12)
	local knob=make("Frame",{
		Size=UDim2.fromOffset(18,18),Position=default and UDim2.fromOffset(21,3) or UDim2.fromOffset(3,3),
		BackgroundColor3=Color3.fromRGB(245,247,250),BorderSizePixel=0
	},sw); round(knob,9)
	local value=default
	on(sw.MouseButton1Click,function()
		value=not value
		TS:Create(sw,TweenInfo.new(.12),{BackgroundColor3=value and C.accent or C.raised}):Play()
		TS:Create(knob,TweenInfo.new(.12),{Position=value and UDim2.fromOffset(21,3) or UDim2.fromOffset(3,3)}):Play()
		callback(value)
	end)
end
local function button(page,text,callback)
	local b=make("TextButton",{
		Size=UDim2.new(1,0,0,40),BackgroundColor3=C.surface,BorderSizePixel=0,Text=text,
		TextColor3=C.text,TextSize=11,Font=Enum.Font.GothamMedium,AutoButtonColor=false
	},page); round(b,9); stroke(b)
	on(b.MouseEnter,function() b.BackgroundColor3=C.raised end)
	on(b.MouseLeave,function() b.BackgroundColor3=C.surface end)
	on(b.MouseButton1Click,callback); return b
end
local function input(page,label,placeholder)
	local f=card(page,68)
	make("TextLabel",{
		Size=UDim2.new(1,-28,0,16),Position=UDim2.fromOffset(14,8),BackgroundTransparency=1,Text=label,
		TextColor3=C.muted,TextSize=9,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left
	},f)
	local box=make("TextBox",{
		Size=UDim2.new(1,-28,0,30),Position=UDim2.fromOffset(14,28),BackgroundColor3=C.raised,BorderSizePixel=0,
		PlaceholderText=placeholder,PlaceholderColor3=Color3.fromRGB(105,112,124),Text="",TextColor3=C.text,
		TextSize=10,Font=Enum.Font.Gotham,ClearTextOnFocus=false
	},f); round(box,7); return box
end

local function char()
	local c=me.Character
	return c,c and c:FindFirstChildOfClass("Humanoid"),c and c:FindFirstChild("HumanoidRootPart")
end
local function findTool(word)
	word=word:lower(); local backpack=me:FindFirstChildOfClass("Backpack")
	for _,container in ipairs({me.Character,backpack}) do
		if container then
			for _,item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item.Name:lower():find(word,1,true) then return item end
			end
		end
	end
	return nil
end
local function equip(tool)
	local c,hum=char(); if not c or not hum or not tool then return false end
	if tool.Parent~=c then hum:EquipTool(tool); task.wait(.2) end
	return tool.Parent==c
end
local function setSpace(value)
	if S.spaceDown==value then return end; S.spaceDown=value
	local fn=value and keypress or keyrelease
	if type(fn)=="function" then pcall(fn,0x20)
	elseif VIM then pcall(function() VIM:SendKeyEvent(value,Enum.KeyCode.Space,false,game) end) end
end
local function reelGui()
	local screen=path(me,"PlayerGui","Reeling"); local main=screen and screen:FindFirstChild("MainFrame")
	local frame=main and main:FindFirstChild("Frame")
	return screen,frame and frame:FindFirstChild("WhiteBar"),frame and frame:FindFirstChild("RedBar"),main and path(main,"ProgressBg","ProgressBar")
end
local function cast()
	if not rodRemote then setStatus("Rod remote missing","Game client may have changed",C.warn); return end
	local tool=findTool("rod")
	if not tool or not equip(tool) then setStatus("Rod not found","Equip or buy a fishing rod first",C.warn); return end
	S.rodTool=tool; S.lastCast=os.clock(); S.waitingBite=true; S.casts=S.casts+1
	setStatus("Fishing","Cast "..S.casts.." • waiting for reel",C.accent)
	local ok=pcall(function() tool:Activate() end)
	if not ok then pcall(function() rodRemote:FireServer("Throw") end) end
end
if rodRemote then
	on(rodRemote.OnClientEvent,function(action,eventTool)
		if eventTool~=S.rodTool then return end
		if action=="StartReeling" and S.fishing then
			S.waitingBite=false; S.reeling=true; S.fastCatchSent=false; S.lastReel=os.clock()
			setStatus("Reeling",S.fastCatch and "Fast catch request" or "Input assist active",C.good)
			if S.fastCatch then task.delay(.12,function()
				if S.alive and S.fishing and S.reeling and not S.fastCatchSent then
					S.fastCatchSent=true; pcall(function() rodRemote:FireServer("Catch","Catch") end)
				end
			end) end
		elseif action=="StopShake" then S.waitingBite=false; S.reeling=false; setSpace(false) end
	end)
end
on(RunService.RenderStepped,function()
	if not S.alive or not S.fishing or not S.reeling or S.fastCatch then if S.spaceDown then setSpace(false) end; return end
	local screen,white,red,progress=reelGui()
	if not screen or not screen.Enabled then
		if os.clock()-S.lastReel>.5 then
			setSpace(false); S.reeling=false; setStatus("Reeling selesai","Menunggu cast berikutnya",C.good)
		end
		return
	end
	if not white or not red then return end
	local wc=white.AbsolutePosition.X+white.AbsoluteSize.X*.5
	local rc=red.AbsolutePosition.X+red.AbsoluteSize.X*.5
	setSpace(wc<rc)
	if progress and progress.Size.X.Scale>=.99 then setStatus("Finishing catch","Menunggu konfirmasi client",C.good) end
end)
task.spawn(function()
	while S.alive do
		task.wait(.35)
		if S.fishing and not S.reeling and (S.lastCast==0 or os.clock()-S.lastCast>20) then cast()
		elseif S.reeling and os.clock()-S.lastReel>25 then
			S.waitingBite=false; S.reeling=false; setSpace(false); setStatus("Reel timeout","Casting again",C.warn)
		end
	end
end)

local function crystalFolder() return path(workspace,"MapContent","Decoration","Crystals") end
local function nearestCrystal(pos)
	local folder=crystalFolder(); if not folder then return end
	local best,dist
	for _,x in ipairs(folder:GetChildren()) do
		local blockedUntil=S.miningBlocked[x] or 0
		if x:IsA("BasePart") and x.Transparency<1 and blockedUntil<os.clock() then
			local d=(x.Position-pos).Magnitude
			local vertical=math.abs(x.Position.Y-pos.Y)
			if d<=90 and vertical<=16 and (not dist or d<dist) then best,dist=x,d end
		end
	end
	return best,dist
end
local function walkNear(target)
	local c,hum,root=char(); if not c or not hum or not root or not target then return false end
	local delta=root.Position-target.Position; local flat=Vector3.new(delta.X,0,delta.Z)
	if flat.Magnitude<.1 then flat=Vector3.new(1,0,0) end
	local goal=target.Position+flat.Unit*5
	local p=PFS:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=6})
	local ok=pcall(function() p:ComputeAsync(root.Position,goal) end)
	if not ok or p.Status~=Enum.PathStatus.Success then return false,"path unavailable" end
	local points=p:GetWaypoints()
	for _,point in ipairs(points) do
		if not S.alive or not S.mining or not target.Parent then return false end
		if point.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end
		hum:MoveTo(point.Position); local started=os.clock()
		repeat task.wait(.1) until not S.mining or not target.Parent or (root.Position-point.Position).Magnitude<3 or os.clock()-started>3
		if S.mining and target.Parent and (root.Position-point.Position).Magnitude>=3 then return false,"waypoint timeout" end
	end
	return target.Parent and (root.Position-target.Position).Magnitude<=9,"target not reached"
end
task.spawn(function()
	local lastTarget
	while S.alive do
		if not S.mining then task.wait(.3) else
			local _,_,root=char(); local tool=findTool("pickaxe")
			if not tool or not equip(tool) then setStatus("Pickaxe not found","Equip or buy a pickaxe first",C.warn); task.wait(1.5)
			elseif not pickaxeRemote or not root then setStatus("Mining unavailable","Remote or character is missing",C.warn); task.wait(1)
			else
				local target,dist=nearestCrystal(root.Position); local distance=dist or 0
				if not target then setStatus("No safe crystal nearby","Range 90 • vertical limit 16 studs",C.warn); task.wait(2)
				else
					if target~=lastTarget then lastTarget=target; S.targets=S.targets+1 end
					if distance>9 then
						setStatus("Moving to crystal",target.Name.." • "..math.floor(distance).." studs",C.accent)
						local reached,reason=walkNear(target)
						if not reached and S.mining then
							S.miningBlocked[target]=os.clock()+15
							setStatus("Crystal skipped",reason or "unreachable",C.warn); task.wait(.5)
						end
					else
						root.CFrame=CFrame.lookAt(root.Position,Vector3.new(target.Position.X,root.Position.Y,target.Position.Z))
						setStatus("Mining",target.Name.." • target "..S.targets,C.good)
						local activated=pcall(function() tool:Activate() end)
						if not activated then pcall(function() pickaxeRemote:FireServer("Hit") end) end
						task.wait(1.55)
					end
				end
			end
		end
	end
end)

local function sellAll(remote,guiName,checkAction,sellAction)
	if not remote then return false,"Remote tidak ditemukan" end
	local list=path(me,"PlayerGui",guiName,"MainFrame","SellList")
	if not list then return false,"Buka menu "..guiName.." sekali, lalu coba lagi" end
	local sold,checked,errors=0,0,0
	for _,item in ipairs(list:GetChildren()) do
		if item:IsA("GuiButton") then
			checked=checked+1
			local ok,cash,bonus,total=pcall(function() return remote:InvokeServer(checkAction,item.Name) end)
			if ok and cash and bonus and total and tonumber(total) and tonumber(total)>0 then
				local sellOk=pcall(function() remote:InvokeServer(sellAction,item.Name) end)
				if sellOk then sold=sold+1 else errors=errors+1 end; task.wait(.15)
			elseif not ok then errors=errors+1 end
		end
	end
	if checked==0 then return false,"Kategori jual belum dimuat" end
	if errors==checked then return false,"Semua request gagal" end
	return true,sold.." dari "..checked.." kategori dikirim"..(errors>0 and " • "..errors.." error" or "")
end

local assetProps={"Shirt","Pants","GraphicTShirt","Face","Head","Torso","LeftArm","RightArm","LeftLeg","RightLeg","ClimbAnimation","FallAnimation","IdleAnimation","JumpAnimation","RunAnimation","SwimAnimation","WalkAnimation"}
local scaleProps={"BodyTypeScale","DepthScale","HeadScale","HeightScale","ProportionScale","WidthScale"}
local colorProps={"HeadColor","LeftArmColor","RightArmColor","LeftLegColor","RightLegColor","TorsoColor"}
local function findPlayer(query)
	query=tostring(query or ""):lower():gsub("^%s+",""):gsub("%s+$","")
	if query=="" then
		local _,_,root=char(); local best,dist
		for _,p in ipairs(Players:GetPlayers()) do
			local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if p~=me and root and r then local d=(root.Position-r.Position).Magnitude; if not dist or d<dist then best,dist=p,d end end
		end
		return best
	end
	for _,p in ipairs(Players:GetPlayers()) do
		local a,b=p.Name:lower(),p.DisplayName:lower()
		if p~=me and (a==query or b==query or a:find(query,1,true)==1 or b:find(query,1,true)==1) then return p end
	end
	return nil
end
local function copyAvatar(query)
	if S.copying then return false,"Copy avatar masih berjalan" end
	if not applyAvatarRemote then return false,"Bloxbiz apply remote tidak ditemukan" end
	local target=findPlayer(query); local hum=target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	local own=me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if not hum or not own then return false,"Player atau Humanoid tidak ditemukan" end
	S.copying=true
	local sent,failed=0,0
	local function send(payload)
		local ok=pcall(function() applyAvatarRemote:FireServer(payload) end)
		if ok then sent=sent+1 else failed=failed+1 end
		task.wait(.1)
	end
	local ok,err=xpcall(function()
		local d=hum:GetAppliedDescription(); local old=own:GetAppliedDescription()
		for _,a in ipairs(old:GetAccessories(true)) do send({AssetId=a.AssetId}) end
		for _,p in ipairs(assetProps) do send({Property=p,AssetId=d[p]}) end
		local colors={}; for _,p in ipairs(colorProps) do colors[p]=d[p] end; send({BodyColor=colors})
		local scales={}; for _,p in ipairs(scaleProps) do scales[p]=d[p] end; send({BodyScale=scales})
		for _,a in ipairs(d:GetAccessories(true)) do send({AccessoryData=a}) end
	end,trace)
	S.copying=false
	if not ok then return false,"Copy avatar error: "..tostring(err):match("^[^\n]+") end
	if failed>0 then return false,sent.." request terkirim • "..failed.." gagal" end
	return true,sent.." request avatar "..target.DisplayName.." terkirim"
end

function S.setFishing(value, fastCatch)
	S.fishing=value==true; S.fastCatch=fastCatch==true
	if S.fishing then S.lastCast=0; S.lastReel=0 end
	S.waitingBite=false; S.reeling=false; S.fastCatchSent=false; setSpace(false)
	setStatus(S.fishing and "Auto Fishing on" or "Ready",S.fishing and "Preparing rod" or "Automation stopped",S.fishing and C.good or C.muted)
end
function S.setMining(value)
	S.mining=value==true
	if not S.mining then
		local _,hum,root=char()
		if hum and root then hum:MoveTo(root.Position) end
	end
	setStatus(S.mining and "Auto Mining on" or "Ready",S.mining and "Looking for nearest crystal" or "Automation stopped",S.mining and C.good or C.muted)
end
S.copyAvatar=copyAvatar
S.sellFish=function() return sellAll(sellFishRemote,"SellFish","CheckFish","SellFish") end
S.sellCrystal=function() return sellAll(sellCrystalRemote,"SellCrystal","CheckCrystal","SellCrystal") end

title(pages.Farm,"Automation")
toggle(pages.Farm,"Auto Fishing","Cast dan selesaikan reeling otomatis",false,function(v)
	S.setFishing(v,S.fastCatch)
end)
toggle(pages.Farm,"Fast Catch","Direct request; matikan jika server menolak",false,function(v) S.fastCatch=v end)
toggle(pages.Farm,"Auto Mining","Target aman ≤90 studs; hit setiap 1.55s",false,function(v)
	S.setMining(v)
end)
title(pages.Farm,"Inventory")
button(pages.Farm,"Sell all fish",function()
	local ok,msg=sellAll(sellFishRemote,"SellFish","CheckFish","SellFish"); setStatus(ok and "Fish sale complete" or "Fish sale failed",msg,ok and C.good or C.warn)
end)
button(pages.Farm,"Sell all crystal",function()
	local ok,msg=sellAll(sellCrystalRemote,"SellCrystal","CheckCrystal","SellCrystal"); setStatus(ok and "Crystal sale complete" or "Crystal sale failed",msg,ok and C.good or C.warn)
end)

title(pages.Player,"Avatar")
local playerBox=input(pages.Player,"PLAYER NAME","Kosongkan untuk pemain terdekat")
local avatarResult=make("TextLabel",{
	Size=UDim2.new(1,0,0,28),BackgroundTransparency=1,Text="Copy memakai HumanoidDescription dan Bloxbiz remote.",
	TextColor3=C.muted,TextSize=9,Font=Enum.Font.Gotham,TextWrapped=true
},pages.Player)
button(pages.Player,"Copy avatar",function()
	avatarResult.Text="Applying avatar..."
	task.spawn(function() local ok,msg=copyAvatar(playerBox.Text); avatarResult.Text=msg; avatarResult.TextColor3=ok and C.good or C.warn end)
end)

title(pages.System,"Client")
toggle(pages.System,"Anti AFK","VirtualUser saat event Idled",true,function(v) S.antiAfk=v end)
local graphicsOriginal={}
local function setLowGraphics(v)
	S.lowGraphics=v; S.graphicsEpoch=(S.graphicsEpoch or 0)+1; local epoch=S.graphicsEpoch
	task.spawn(function()
		if v then
			for i,x in ipairs(workspace:GetDescendants()) do
				if epoch~=S.graphicsEpoch or not S.alive then return end
				if x:IsA("ParticleEmitter") or x:IsA("Trail") or x:IsA("Beam") then
					if graphicsOriginal[x]==nil then graphicsOriginal[x]=x.Enabled end; x.Enabled=false
				elseif x:IsA("BasePart") then
					if graphicsOriginal[x]==nil then graphicsOriginal[x]=x.CastShadow end; x.CastShadow=false
				end
				if i%250==0 then task.wait() end
			end
		else
			for x,original in pairs(graphicsOriginal) do
				if x.Parent then
					if x:IsA("ParticleEmitter") or x:IsA("Trail") or x:IsA("Beam") then x.Enabled=original
					elseif x:IsA("BasePart") then x.CastShadow=original end
				end
				graphicsOriginal[x]=nil
			end
		end
	end)
end
S.setLowGraphics=setLowGraphics
toggle(pages.System,"Low Graphics","Kurangi efek visual lokal",false,setLowGraphics)
local compat=card(pages.System,118)
make("TextLabel",{
	Size=UDim2.new(1,-28,0,18),Position=UDim2.fromOffset(14,10),BackgroundTransparency=1,Text="Client compatibility",
	TextColor3=C.text,TextSize=11,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left
},compat)
local checks={{"Rod remote",rodRemote},{"Pickaxe remote",pickaxeRemote},{"Crystal folder",crystalFolder()},{"Avatar remote",applyAvatarRemote}}
for i,check in ipairs(checks) do
	make("TextLabel",{
		Size=UDim2.new(1,-28,0,17),Position=UDim2.fromOffset(14,29+(i-1)*19),BackgroundTransparency=1,
		Text=(check[2] and "OK   " or "MISS ")..check[1],TextColor3=check[2] and C.good or C.warn,
		TextSize=9,Font=Enum.Font.Code,TextXAlignment=Enum.TextXAlignment.Left
	},compat)
end
local diagnostic=card(pages.System,64)
local diagnosticText=make("TextLabel",{
	Size=UDim2.new(1,-28,1,-16),Position=UDim2.fromOffset(14,8),BackgroundTransparency=1,
	Text="Compatibility scan belum dijalankan.",TextColor3=C.muted,TextSize=10,Font=Enum.Font.Gotham,
	TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center
},diagnostic)
button(pages.System,"Run compatibility scan",function()
	local ok,msg=S.runSelfTest()
	if not ok then diagnosticText.Text=msg; diagnosticText.TextColor3=C.warn end
end)

local bubble=make("TextButton",{
	Size=UDim2.fromOffset(46,46),Position=UDim2.new(1,-58,.5,-23),BackgroundColor3=C.surface,BorderSizePixel=0,
	Text="IDH",TextColor3=C.text,TextSize=11,Font=Enum.Font.GothamBold,Visible=false,AutoButtonColor=false
},gui); round(bubble,23); stroke(bubble)
local dragging=false; local dragStart; local startPos
on(header.InputBegan,function(x)
	if x.UserInputType==Enum.UserInputType.MouseButton1 or x.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=x.Position; startPos=window.Position end
end)
on(UIS.InputChanged,function(x)
	if dragging and (x.UserInputType==Enum.UserInputType.MouseMovement or x.UserInputType==Enum.UserInputType.Touch) then
		local d=x.Position-dragStart; window.Position=startPos+UDim2.fromOffset(d.X/uiScale.Scale,d.Y/uiScale.Scale)
	end
end)
on(UIS.InputEnded,function(x) if x.UserInputType==Enum.UserInputType.MouseButton1 or x.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
on(hideBtn.MouseButton1Click,function() window.Visible=false; bubble.Visible=true end)
on(bubble.MouseButton1Click,function() bubble.Visible=false; window.Visible=true end)
on(me.Idled,function() if S.antiAfk then pcall(function() VU:CaptureController(); VU:ClickButton2(Vector2.new()) end) end end)

local function testOutput(status,name,detail)
	local line="[IDH Test] "..status.." | "..name..(detail and " | "..tostring(detail) or "")
	print(line)
	if type(rconsoleprint)=="function" then pcall(rconsoleprint,line.."\n") end
end

function S.runSelfTest(options)
	if S.testing then return false,"Self-test masih berjalan" end
	options=type(options)=="table" and options or {}
	S.testing=true; S.testResults={}; diagnosticText.Text="Scanning client paths..."; diagnosticText.TextColor3=C.muted
	task.spawn(function()
		local function add(status,name,detail)
			table.insert(S.testResults,{status=status,name=name,detail=detail})
			testOutput(status,name,detail)
		end
		local ok,err=xpcall(function()
			add(gui.Parent and "PASS" or "FAIL","GUI parent",gui.Parent and gui.Parent:GetFullName() or "nil")
			add(rodRemote and "PASS" or "FAIL","Rod remote",rodRemote and rodRemote:GetFullName() or "missing")
			add(pickaxeRemote and "PASS" or "FAIL","Pickaxe remote",pickaxeRemote and pickaxeRemote:GetFullName() or "missing")
			add(crystalFolder() and "PASS" or "FAIL","Crystal folder",crystalFolder() and #crystalFolder():GetChildren().." children" or "missing")
			add(applyAvatarRemote and "PASS" or "FAIL","Avatar remote",applyAvatarRemote and applyAvatarRemote:GetFullName() or "missing")
			add(findTool("rod") and "PASS" or "MISS","Fishing rod",findTool("rod") and findTool("rod").Name or "not in Backpack/Character")
			add(findTool("pickaxe") and "PASS" or "MISS","Pickaxe",findTool("pickaxe") and findTool("pickaxe").Name or "not in Backpack/Character")
			local screen,white,red,progress=reelGui()
			add(screen and white and red and progress and "PASS" or "MISS","Reeling GUI",screen and "loaded" or "appears after a bite")

			if options.active==true then
				local rod=findTool("rod"); local castBefore=S.casts; local reelBefore=S.lastReel
				if rodRemote and rod then
					S.setFishing(true,options.fastCatch==true); task.wait(options.fishingWait or 15); S.setFishing(false,false)
					add(S.casts>castBefore and "PASS" or "FAIL","Auto Fishing cast",S.casts-castBefore.." cast")
					add(S.lastReel>reelBefore and "PASS" or "SKIP","Reeling event",S.lastReel>reelBefore and "StartReeling received" or "no bite during test window")
				else add("FAIL","Auto Fishing","rod atau remote tidak tersedia") end

				local targetBefore=S.targets
				if pickaxeRemote and findTool("pickaxe") and crystalFolder() then
					S.setMining(true); task.wait(options.miningWait or 8); S.setMining(false)
					add(S.targets>targetBefore and "PASS" or "SKIP","Auto Mining",S.targets-targetBefore.." safe target acquired")
				else add("FAIL","Auto Mining","pickaxe, remote, atau folder tidak tersedia") end
			else
				add("SKIP","Active automation","gunakan runSelfTest({active=true})")
			end

			if options.avatar then
				local callOk,avatarOk,avatarMsg=pcall(copyAvatar,options.player or "")
				add(callOk and avatarOk and "PASS" or "FAIL","Copy Avatar",callOk and avatarMsg or avatarOk)
			else add("SKIP","Copy Avatar","aktifkan options.avatar untuk mengubah avatar") end

			if options.inventory then
				local fishCall,fishOk,fishMsg=pcall(S.sellFish); add(fishCall and fishOk and "PASS" or "FAIL","Sell Fish",fishCall and fishMsg or fishOk)
				local crystalCall,crystalOk,crystalMsg=pcall(S.sellCrystal); add(crystalCall and crystalOk and "PASS" or "FAIL","Sell Crystal",crystalCall and crystalMsg or crystalOk)
			else
				add("SKIP","Sell Fish","aktifkan options.inventory untuk menjual")
				add("SKIP","Sell Crystal","aktifkan options.inventory untuk menjual")
			end
		end,trace)
		S.setFishing(false,false); S.setMining(false)
		if not ok then add("FAIL","Self-test runtime",err) end
		local passed,failed,skipped=0,0,0
		for _,result in ipairs(S.testResults) do
			if result.status=="PASS" then passed=passed+1 elseif result.status=="FAIL" then failed=failed+1 else skipped=skipped+1 end
		end
		S.testing=false
		local summary=passed.." pass, "..failed.." fail, "..skipped.." skip"
		diagnosticText.Text=summary.." • detail ada di console [IDH Test]"
		diagnosticText.TextColor3=failed==0 and C.good or C.warn
		testOutput(failed==0 and "DONE" or "CHECK","Summary",summary)
		notify("IDH Self-test",summary)
	end)
	return true,"Self-test dimulai"
end

function S.destroy()
	if not S.alive then return end
	if S.lowGraphics then setLowGraphics(false) end
	S.alive=false; S.fishing=false; S.mining=false; setSpace(false)
	for _,c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
	table.clear(S.connections); pcall(function() gui:Destroy() end)
end
on(closeBtn.MouseButton1Click,S.destroy)

local missing=0
for _,x in ipairs({rodRemote,pickaxeRemote,crystalFolder(),applyAvatarRemote}) do if not x then missing=missing+1 end end
if missing>0 then subtitle.Text="Compatibility check: "..missing.." dependency missing"; subtitle.TextColor3=C.warn end

return S
end,trace)

if not bootOk then
	env.IDHBootError=bootResult
	report(bootResult,true)
	notify("IDH Hub gagal dimuat",tostring(bootResult):sub(1,180))
	error("IDH Hub startup failed; buka Delta/Roblox console",0)
end

env.IDHBootError=nil
report("loaded")
notify("IDH Hub","Build "..BUILD.." berhasil dimuat")
return bootResult
