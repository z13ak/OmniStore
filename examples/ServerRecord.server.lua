--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame" })
local servers = database:GetStore("Servers", {
	template = { StartedAt = 0, Matches = 0 },
})

local serverKey = if game.JobId ~= "" then game.JobId else "studio-session"
local loaded = servers:LoadAsync(serverKey)
if loaded.ok then
	loaded.value:Set("StartedAt", os.time())
	loaded.value:Increment("Matches")
end
