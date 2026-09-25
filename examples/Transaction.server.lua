--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "TransactionExample" })
local profiles = database:GetStore("Profiles", {
	template = {
		Coins = 100,
		Inventory = {},
	},
})

local loaded = profiles:LoadAsync("example-player")
if not loaded.ok then
	warn(loaded.error.code, loaded.error.message)
	return
end

local profile = loaded.value
local changed = profile:Transaction(function(draft)
	local debit = draft:Increment("Coins", -50)
	assert(debit.ok, debit.error and debit.error.message)

	local grant = draft:Insert("Inventory", { Id = "HealthPotion" })
	assert(grant.ok, grant.error and grant.error.message)
end)

if not changed.ok then
	warn(changed.error.code, changed.error.message)
	return
end

-- The transaction is a local commit. Saving is the separate durability boundary.
local saved = profile:SaveAsync(10)
if not saved.ok then
	warn(saved.error.code, saved.error.message)
end
