--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame" })
local servers = database:GetStore("Servers", {
	template = { StartedAt = 0, Matches = 0 },
})

local serverKey = if game.JobId ~= "" then game.JobId else "studio-session"
local loaded = servers:LoadAsync(serverKey)
if not loaded.ok then
	warn(loaded.error.code, loaded.error.message)
	return
end

local updated = loaded.value:Transaction(function(server)
	server:Set("StartedAt", os.time())
	server:Increment("Matches")
end)
if not updated.ok then
	warn(updated.error.code, updated.error.message)
end
