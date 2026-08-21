-- IDH Auto Mining
-- Grounded against IDH_COMPLETE_CLIENT_DUMP.rbxlx (2026-08-17):
-- ReplicatedStorage.Events.RemoteEvent.Pickaxe:FireServer("Hit")

if shared.IDHAutoMining then
	shared.IDHAutoMining.stop()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Events")
	:WaitForChild("RemoteEvent"):WaitForChild("Pickaxe")

local state = { running = true }
shared.IDHAutoMining = state

local function findPickaxe()
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ character, backpack }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item.Name:lower():find("pickaxe", 1, true) then
					return item
				end
			end
		end
	end
end

local function equip(tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and tool and tool.Parent ~= character then
		humanoid:EquipTool(tool)
		task.wait(0.25)
	end
	return tool and tool.Parent == character
end

function state.stop()
	state.running = false
end

task.spawn(function()
	while state.running do
		local tool = findPickaxe()
		if tool and equip(tool) then
			-- Stock PickaxeLocalScript uses a 1.5 second debounce.
			remote:FireServer("Hit")
			task.wait(1.55)
		else
			warn("[IDH AutoMining] Pickaxe tidak ditemukan")
			task.wait(2)
		end
	end
end)
