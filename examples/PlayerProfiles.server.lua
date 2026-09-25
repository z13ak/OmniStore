--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame" })
local profiles = database:GetStore("Profiles", {
	template = {
		Coins = 0,
		Inventory = {},
		Settings = { Music = true, Effects = true },
	},
	schemaVersion = 1,
	validate = function(data)
		if type(data) ~= "table" or type(data.Coins) ~= "number" or data.Coins < 0 then
			return false, "Coins must be a non-negative number"
		end
		return true
	end,
})

Players.PlayerAdded:Connect(function(player)
	local loaded = profiles:LoadAsync(player.UserId)
	if not loaded.ok then
		warn(`Profile load failed for {player.UserId}: {loaded.error.code}`)
		player:Kick("Data is temporarily unavailable. Please rejoin.")
		return
	end

	local record = loaded.value
	record:SetMetadata("lastServer", game.JobId)
end)

Players.PlayerRemoving:Connect(function(player)
	local closed = profiles:CloseRecordAsync(player.UserId, 10)
	if not closed.ok then
		warn(`Profile close failed for {player.UserId}: {closed.error.code}`)
	end
end)
