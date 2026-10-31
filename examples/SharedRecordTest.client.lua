--!strict
-- Place in StarterPlayer > StarterPlayerScripts. Requires SharedRecordTest.server.lua.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local controls = ReplicatedStorage:WaitForChild("OmniStoreSharedKeyControls") :: RemoteEvent
local screen =
	Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("OmniStoreSharedKeyTest") :: ScreenGui
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0.9, 0, 0, 170)
panel.Position = UDim2.new(0.05, 0, 0, 210)
panel.BackgroundTransparency = 1
panel.Parent = screen
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.new(0.48, 0, 0, 48)
layout.CellPadding = UDim2.fromOffset(8, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local commands = {
	{ "Increment", "+1 (unsaved)" },
	{ "Save", "Save" },
	{ "FailSave", "Simulate failed save" },
	{ "FailLoad", "Simulate failed load" },
	{ "Pause", "Pause writes + renewal" },
	{ "Restore", "Restore writes" },
}
local nextClick = 0
for index, entry in commands do
	local button = Instance.new("TextButton")
	button.Name = entry[1]
	button.LayoutOrder = index
	button.Text = entry[2]
	button.TextSize = 16
	button.TextWrapped = true
	button.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = panel
	button.Activated:Connect(function()
		if os.clock() < nextClick then
			return
		end
		nextClick = os.clock() + 0.5
		controls:FireServer(entry[1])
	end)
end
