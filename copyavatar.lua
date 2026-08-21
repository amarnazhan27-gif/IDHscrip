-- IDH Copy Avatar
-- Usage: shared.IDHCopyAvatar("PlayerName")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer
local applyRemote = ReplicatedStorage:WaitForChild("BloxbizRemotes")
	:WaitForChild("CatalogOnApplyToRealHumanoid")

local assetProperties = {
	"Shirt", "Pants", "GraphicTShirt", "Face", "Head", "Torso",
	"LeftArm", "RightArm", "LeftLeg", "RightLeg",
}

local scaleProperties = {
	"BodyTypeScale", "DepthScale", "HeadScale", "HeightScale",
	"ProportionScale", "WidthScale",
}

local colorProperties = {
	"HeadColor", "LeftArmColor", "RightArmColor", "LeftLegColor",
	"RightLegColor", "TorsoColor",
}

local function findPlayer(query)
	query = tostring(query or ""):lower()
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= localPlayer and
			(candidate.Name:lower() == query or candidate.DisplayName:lower() == query) then
			return candidate
		end
	end
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= localPlayer and
			(candidate.Name:lower():find(query, 1, true) == 1 or
			 candidate.DisplayName:lower():find(query, 1, true) == 1) then
			return candidate
		end
	end
end

function shared.IDHCopyAvatar(query)
	local target = findPlayer(query)
	local humanoid = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Player atau Humanoid tidak ditemukan"
	end

	local description = humanoid:GetAppliedDescription()
	for _, property in ipairs(assetProperties) do
		applyRemote:FireServer({ Property = property, AssetId = description[property] })
		task.wait(0.08)
	end

	local colors = {}
	for _, property in ipairs(colorProperties) do
		colors[property] = description[property]
	end
	applyRemote:FireServer({ BodyColor = colors })

	local scales = {}
	for _, property in ipairs(scaleProperties) do
		scales[property] = description[property]
	end
	applyRemote:FireServer({ BodyScale = scales })

	for _, accessory in ipairs(description:GetAccessories(true)) do
		applyRemote:FireServer({ AccessoryData = accessory })
		task.wait(0.08)
	end

	return true, target.Name
end
