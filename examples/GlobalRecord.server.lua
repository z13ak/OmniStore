--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame" })
local configuration = database:GetStore("GlobalConfiguration", {
	template = { EventName = "None", Multiplier = 1 },
	autosaveInterval = 30,
})

local loaded = configuration:LoadAsync("live")
if not loaded.ok then
	error(`Global configuration unavailable: {loaded.error.message}`)
end

local global = loaded.value
global:Set("EventName", "DoubleCoinsWeekend")
global:Set("Multiplier", 2)
local saved = global:SaveAsync()
if not saved.ok then
	warn(saved.error.code, saved.error.message)
end
