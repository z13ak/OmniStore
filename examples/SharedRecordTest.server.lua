--!strict
-- Place one copy in ServerScriptService in the dedicated test experience.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EXPECTED_UNIVERSE_ID = 10767918920
local NAMESPACE = "OmniStoreSharedKeyTest"
local STORE_NAME = "Records"
local RECORD_KEY = "shared-record"

assert(game.GameId == EXPECTED_UNIVERSE_ID, "Use the dedicated test experience")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
-- Only this adapter instance is affected. No library internals or stored leases are edited.
local backing = OmniStore.Adapters.DataStore.new(`{NAMESPACE}_{STORE_NAME}`)
local paused = false
local function fault()
	return {
		ok = false,
		error = {
			code = "PersistenceFailed",
			message = "Test outage",
			retryable = true,
			category = "Transient",
		},
	}
end
local adapter = {}
function adapter:Read(key)
	if paused then
		return fault()
	end
	return backing:Read(key)
end
function adapter:Update(key, transform)
	if paused then
		return fault()
	end
	return backing:Update(key, transform)
end
function adapter:Remove(key)
	if paused then
		return fault()
	end
	return backing:Remove(key)
end
function adapter:GetBudget(requestType)
	return backing:GetBudget(requestType)
end
local database = OmniStore.new({ namespace = NAMESPACE, autoBindToClose = false })
local store = database:GetStore(STORE_NAME, {
	adapter = adapter,
	template = { Claims = 0, LastOwner = "" },
	autosaveInterval = 0,
	lease = { duration = 30, renewInterval = 10, acquireTimeout = 0 },
})
local serverId = if game.JobId ~= ""
	then game.JobId
	else "Studio:" .. database:GetSessionInfo().sessionId
local labels: { [Player]: TextLabel } = {}
local status = "Loading"
local closing = false
local record = nil
local busy = false
local controls = Instance.new("RemoteEvent")
controls.Name = "OmniStoreSharedKeyControls"
assert(
	not ReplicatedStorage:FindFirstChild(controls.Name),
	"Install only one shared record server script"
)
controls.Parent = ReplicatedStorage

local function displayText(): string
	local value = if record then record:Get("Claims") else nil
	local claims = if value and value.ok then tostring(value.value) else "unavailable"
	return `Shared record test\n{NAMESPACE}/{STORE_NAME}/{RECORD_KEY}\nServer: {serverId}\nClaims: {claims} | writes paused: {paused}\n{status}`
end

local function setStatus(message: string)
	status = message
	print(`Shared record test: {message}`)
	for _, label in labels do
		label.Text = displayText()
	end
end

local function addDisplay(player: Player)
	local playerGui = player:WaitForChild("PlayerGui", 15)
	if not playerGui or not player:IsDescendantOf(Players) then
		return
	end
	local existing = playerGui:FindFirstChild("OmniStoreSharedKeyTest")
	if existing then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "OmniStoreSharedKeyTest"
	screen.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.Size = UDim2.new(0.9, 0, 0, 180)
	label.Position = UDim2.new(0.05, 0, 0, 24)
	label.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextSize = 18
	label.Font = Enum.Font.Code
	label.TextWrapped = true
	label.Text = displayText()
	label.Parent = screen
	labels[player] = label
	screen.Parent = playerGui
end

Players.PlayerAdded:Connect(addDisplay)
Players.PlayerRemoving:Connect(function(player)
	labels[player] = nil
end)
for _, player in Players:GetPlayers() do
	task.spawn(addDisplay, player)
end

game:BindToClose(function()
	closing = true
	local result = database:CloseAsync(20)
	if not result.ok then
		warn(`Shared record close failed: {result.error.code}`)
	end
end)

-- Every player in this dedicated test universe can operate the controls.
-- Server-side serialization prevents overlapping commands; no arbitrary key/value is accepted.
controls.OnServerEvent:Connect(function(player, command)
	if closing or busy or player.Parent ~= Players or typeof(command) ~= "string" then
		return
	end
	busy = true
	local ok, message = pcall(function()
		if command == "Pause" then
			paused = true
			setStatus("WRITES PAUSED — wait for the other server to acquire")
		elseif command == "Restore" then
			paused = false
			setStatus("WRITES RESTORED — try Save; an old owner must be rejected")
		elseif command == "FailLoad" then
			-- A fresh manager bypasses the owner's cached record. Its adapter cannot reach storage.
			local probeAdapter = {}
			function probeAdapter:Read(_key)
				return fault()
			end
			function probeAdapter:Update(_key, _transform)
				return fault()
			end
			function probeAdapter:Remove(_key)
				return fault()
			end
			function probeAdapter:GetBudget(_requestType)
				return math.huge
			end
			local probe = OmniStore.new({ namespace = NAMESPACE, autoBindToClose = false })
			local probeStore = probe:GetStore(
				STORE_NAME,
				{ adapter = probeAdapter, template = { Claims = 0, LastOwner = "" } }
			)
			local result = probeStore:LoadAsync(RECORD_KEY, { timeout = 3 })
			probe:CloseAsync(3)
			setStatus(
				if result.ok
					then "FAIL — faulted load returned a record"
					else `LOAD REJECTED — {result.error.code}; no record returned, no storage requests forwarded`
			)
		elseif not record then
			setStatus("No owned record — wait for ownership")
		elseif command == "Increment" then
			local result = record:Increment("Claims", 1)
			setStatus(
				if result.ok
					then `UNSAVED — Claims = {result.value}; close normally to test shutdown`
					else `UPDATE REJECTED — {result.error.code}`
			)
		elseif command == "Save" or command == "FailSave" then
			local wasPaused = paused
			if command == "FailSave" then
				paused = true
			end
			local result = record:SaveAsync(3)
			paused = wasPaused
			setStatus(
				if result.ok
					then "SAVED"
					else `SAVE REJECTED — {result.error.code}; dirty = {record:IsDirty()}`
			)
		end
	end)
	busy = false
	if not ok then
		warn(message)
		setStatus("CONTROL ERROR — see server Output")
	end
end)

-- Acquire once per server. Players in the same server use the same loaded handle.
while not closing do
	local loaded = store:LoadAsync(RECORD_KEY, { timeout = 8 })
	if closing then
		break
	end
	if loaded.ok then
		record = loaded.value
		record.LifecycleChanged:Connect(function(state)
			if state == "LeaseLost" then
				setStatus("LEASE LOST — this server can no longer save")
			end
		end)
		local changed = record:Increment("Claims", 1)
		local ownerSet = record:Set("LastOwner", serverId)
		if not changed.ok or not ownerSet.ok then
			setStatus("UPDATE FAILED — test data could not be updated")
			break
		end
		local saved = record:SaveAsync(8)
		if saved.ok then
			setStatus(`OWNER — saved claim #{changed.value}`)
		elseif saved.error.code == "LeaseLost" then
			setStatus("LEASE LOST — this server can no longer save")
		else
			setStatus(`OWNER — save failed: {saved.error.code}`)
		end
		break
	elseif loaded.error.code == "Locked" then
		setStatus("LOCKED — another server owns this record; retrying")
	else
		setStatus(`LOAD FAILED — {loaded.error.code}; retrying`)
	end
	task.wait(5)
end
