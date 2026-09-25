--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

local profile = OmniStore.Replication.Client.new("Profile")
local coins = profile:Get("Coins")
if coins.ok then
	print("Initial coins", coins.value)
end

profile.Changed:Connect(function(path, value)
	print("Replicated profile change", path, value)
end)

profile.StatusChanged:Connect(function(status)
	if status == "Stale" then
		warn("Profile mirror is temporarily stale")
	end
end)
