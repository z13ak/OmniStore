--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
local Schema = OmniStore.Schema

local codecs = OmniStore.CodecRegistry.new()
OmniStore.Codecs.Roblox.registerAll(codecs)

local WorldModel = OmniStore.Model.define({
	typeId = "example.World",
	version = 1,
	schema = Schema.object({
		Spawn = Schema.custom(function(value)
			return typeof(value) == "Vector3", "Spawn must be a Vector3"
		end),
		Visits = Schema.number({ integer = true, min = 0 }),
	}),
	template = { Spawn = Vector3.zero, Visits = 0 },
	codecs = codecs,
})

local database = OmniStore.new({ namespace = "ExampleGame" })
local worlds = database:GetStore("Worlds", { model = WorldModel })
local loaded = worlds:LoadAsync("overworld")
if not loaded.ok then
	warn(loaded.error.code, loaded.error.message)
	return
end

local changed = loaded.value:Transaction(function(world)
	world:Increment("Visits")
	world:Set("Spawn", Vector3.new(0, 20, 0))
end)
if not changed.ok then
	warn(changed.error.code, changed.error.message)
end
