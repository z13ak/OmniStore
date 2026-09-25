--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame", keyPrefix = "guild:" })
local entities = database:GetStore("Entities", {
	template = { Name = "Untitled", Members = {}, Treasury = 0 },
	schemaVersion = 2,
	migrations = {
		{
			from = 1,
			to = 2,
			migrate = function(data)
				data.Treasury = data.Bank or 0
				data.Bank = nil
				return data
			end,
		},
	},
})

local loaded = entities:LoadAsync("knights-of-luau")
if loaded.ok then
	local guild = loaded.value
	local transaction = guild:Transaction(function(record)
		record:Increment("Treasury", 100)
		record:Insert("Members", { UserId = 12345, Role = "Member" })
	end)
	if not transaction.ok then
		warn(transaction.error.message)
	end
end
