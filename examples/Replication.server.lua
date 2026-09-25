--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame" })
local profiles = database:GetStore("Profiles", {
	template = { Coins = 0, Level = 1, PrivateReceiptState = {} },
})
local replicator = OmniStore.Replication.Server.new()

Players.PlayerAdded:Connect(function(player)
	local loaded = profiles:LoadAsync(player.UserId)
	if loaded.ok then
		local registered =
			replicator:Register(player, "Profile", loaded.value, { "Coins", "Level" })
		if not registered.ok then
			warn(registered.error.code, registered.error.message)
			profiles:CloseRecordAsync(player.UserId, 10)
			player:Kick("Profile replication is unavailable.")
		end
	else
		player:Kick("Data is unavailable.")
	end
end)
