--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "ExampleGame", autoBindToClose = false })
local profiles = database:GetStore("Profiles")

local loaded = profiles:LoadAsync("user:123", { mode = "ReadOnly", timeout = 10 })
if not loaded.ok then
	warn(loaded.error.code, loaded.error.message)
	return
end

local snapshot = loaded.value:GetData()
if snapshot.ok then
	print(snapshot.value)
end

loaded.value:CloseAsync()
