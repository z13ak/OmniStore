--!strict
-- Opt-in integration test. Uses synthetic data and refuses non-Studio execution.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local StudioTestService = game:GetService("StudioTestService")
local encodedArgs = script:GetAttribute("TestArgs")
local args = if type(encodedArgs) == "string"
	then game:GetService("HttpService"):JSONDecode(encodedArgs)
	else StudioTestService:GetTestArgs()
if type(args) ~= "table" or args.kind ~= "OmniStoreTwoClient" then
	return
end
assert(
	game.GameId == args.expectedUniverseId and args.expectedUniverseId > 0,
	"test universe mismatch"
)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
local namespace = "OmniMP_"
	.. game:GetService("HttpService"):GenerateGUID(false):gsub("%-", ""):sub(1, 20)
local live = args.liveDataStores == true
local recordCount = args.recordCount or (if live then 12 else 96)
assert(
	recordCount >= 1 and recordCount % 1 == 0 and recordCount <= (if live then 16 else 128),
	"invalid load size"
)
local base = if live
	then OmniStore.Adapters.DataStore.new(namespace)
	else OmniStore.Adapters.Memory.new()
local inFlight, peak = 0, 0
local measure = false
local adapter = {
	Read = function(_, key)
		return base:Read(key)
	end,
	Remove = function(_, key)
		return base:Remove(key)
	end,
	GetBudget = function(_, requestType)
		return base:GetBudget(requestType)
	end,
	Update = function(_, key, transform)
		local tracked = measure and key:sub(1, 5) == "bulk:"
		if tracked then
			inFlight += 1
			peak = math.max(peak, inFlight)
			if not live then
				task.wait(0.02)
			end
		end
		local result = base:Update(key, transform)
		if tracked then
			inFlight -= 1
		end
		return result
	end,
}
local manager = OmniStore.new({ namespace = namespace, autoBindToClose = false })
local profiles = manager:GetStore("Profiles", {
	adapter = adapter,
	autosaveInterval = 0,
	template = {
		Stats = { Coins = 0 },
		Public = { Owner = 0, Marker = "" },
		Private = { Secret = "synthetic" },
	},
})
local bulk = manager:GetStore("Bulk", {
	adapter = adapter,
	template = { Value = 0 },
	autosaveInterval = 0,
	maxConcurrentBackgroundTasks = 4,
})
assert(not ReplicatedStorage:FindFirstChild("OmniStoreMultiplayer"), "test folder already exists")
local root = Instance.new("Folder")
root.Name = "OmniStoreMultiplayer"
local control = Instance.new("RemoteFunction")
control.Name = "Control"
control.Parent = root
local command = Instance.new("RemoteEvent")
command.Name = "Command"
command.Parent = root
root.Parent = ReplicatedStorage
local replicator = OmniStore.Replication.Server.new({
	parent = root,
	maxChangeBytes = 256,
	maxSnapshotBytes = 16000,
	maxSnapshotRequests = 8,
	requestWindowSeconds = 2,
})
local records, channels, reports = {}, {}, {}
local keys = { "shared" }
local checks, connections = {}, {}
local fatal
local finished = false
local currentPhase = "boot"
local leavingPlayer
local summary = {
	mode = if live then "StudioLiveDataStore" else "StudioMemory",
	namespace = namespace,
	clientsStarted = 2,
	recordCount = recordCount,
	checks = checks,
	reports = reports,
}

local function value(result)
	assert(
		result.ok,
		if result.error
			then result.error.code .. ": " .. result.error.message
			else "operation failed"
	)
	return result.value
end
local function waitUntil(predicate, message)
	local deadline = os.clock() + 45
	repeat
		assert(not fatal, fatal or "background failure")
		if predicate() then
			return
		end
		task.wait(0.03)
	until os.clock() >= deadline
	error(message)
end
local shared = value(profiles:LoadAsync("shared", 15))
control.OnServerInvoke = function(player, request)
	if type(request) ~= "table" then
		return { ok = false }
	end
	if request.kind == "hello" then
		return { ok = records[player] ~= nil, channel = channels[player] }
	end
	if request.kind == "requestLeave" and currentPhase == "leave" and player == leavingPlayer then
		task.defer(function()
			player:Kick("OmniStore Studio lifecycle test complete")
		end)
		return { ok = true }
	end
	if request.kind ~= "report" or (request.phase ~= "boot" and request.phase ~= currentPhase) then
		return { ok = false }
	end
	local phaseReports = reports[request.phase] or {}
	reports[request.phase] = phaseReports
	phaseReports[tostring(player.UserId)] =
		{ ok = request.ok == true, error = request.error, details = request.details }
	if request.ok ~= true then
		fatal = tostring(request.error)
	end
	return { ok = true }
end
local function addPlayer(player)
	local ok, cause = xpcall(function()
		local key = "player:" .. player.UserId
		table.insert(keys, key)
		local record = value(profiles:LoadAsync(key, 15))
		value(record:Set("Public.Owner", player.UserId))
		records[player] = record
		channels[player] = "Profile:" .. player.UserId
		value(
			replicator:Register(player, channels[player], record, { "Stats.Coins", "Public.Owner" })
		)
		value(replicator:Register(player, "Shared", shared, { "Stats.Coins", "Public.Marker" }))
	end, debug.traceback)
	if not ok then
		fatal = tostring(cause)
	end
end
table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
table.insert(
	connections,
	Players.PlayerRemoving:Connect(function(player)
		if reports.boot then
			reports.boot[tostring(player.UserId)] = nil
		end
		local closed = profiles:CloseRecordAsync("player:" .. player.UserId, 15)
		if not closed.ok then
			fatal = closed.error.message
		end
		records[player] = nil
		channels[player] = nil
	end)
)
for _, player in Players:GetPlayers() do
	task.spawn(addPlayer, player)
end

local function phase(name, players, payloadFor)
	currentPhase = name
	reports[name] = {}
	for _, player in players do
		command:FireClient(player, name, payloadFor(player))
	end
	waitUntil(function()
		for _, player in players do
			local report = reports[name][tostring(player.UserId)]
			if not report or not report.ok then
				return false
			end
		end
		return true
	end, "clients did not complete phase " .. name)
	table.insert(checks, name)
end
local function finish(ok, cause)
	if finished then
		return
	end
	finished = true
	for _, connection in connections do
		connection:Disconnect()
	end
	replicator:Destroy()
	if not ok then
		pcall(manager.CloseAsync, manager, 10)
	end
	summary.ok = ok
	summary.error = if ok then nil else tostring(cause)
	local result = game.ServerStorage:FindFirstChild("OmniStoreMultiplayerResult")
	if not result then
		result = Instance.new("StringValue")
		result.Name = "OmniStoreMultiplayerResult"
		result.Parent = game.ServerStorage
	end
	result.Value = game:GetService("HttpService"):JSONEncode(summary)
	if args.autoEnd ~= false then
		StudioTestService:EndTest(summary)
	end
end
task.delay(180, function()
	finish(false, "multiplayer watchdog expired")
end)
task.spawn(function()
	local ok, cause = xpcall(function()
		local unit = game.ServerScriptService:FindFirstChild("OmniStoreTests")
		if unit then
			waitUntil(function()
				return unit:GetAttribute("Complete") == true
			end, "unit gate did not complete")
			assert(unit:GetAttribute("GatePassed") == true, "unit release gate failed")
			summary.unitPassed = unit:GetAttribute("Passed")
		end
		waitUntil(function()
			local players = Players:GetPlayers()
			if #players ~= 2 then
				return false
			end
			for _, player in players do
				if not (reports.boot and reports.boot[tostring(player.UserId)]) then
					return false
				end
			end
			return true
		end, "two clients did not join and synchronize")
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return a.UserId < b.UserId
		end)
		phase("initial", players, function(player)
			return { coins = records[player]:Get("Stats.Coins").value }
		end)
		phase("isolation", players, function(player)
			return {
				otherChannel = channels[if player == players[1] then players[2] else players[1]],
			}
		end)
		for _, player in players do
			assert(records[player]:Get("Stats.Coins").value == 0, "client changed server data")
		end
		table.insert(checks, "server-authority")
		task.wait(2.1)
		for index, player in players do
			value(records[player]:Set("Stats.Coins", index * 7))
			value(records[player]:Set("Private.Secret", "still private"))
		end
		for _ = 1, 200 do
			value(shared:Increment("Stats.Coins", 1))
		end
		phase("burst", players, function(player)
			return { sharedCoins = 200, coins = records[player]:Get("Stats.Coins").value }
		end)
		task.wait(2.1)
		value(shared:Set("Public.Marker", string.rep("x", 2048)))
		phase("invalidate", players, function()
			return { bytes = 2048 }
		end)
		task.wait(2.1)
		value(profiles:CloseRecordAsync("player:" .. players[1].UserId, 15))
		phase("closeProfile", players, function()
			return { closedUserId = players[1].UserId }
		end)
		leavingPlayer = players[2]
		phase("leave", { players[2] }, function()
			return {}
		end)
		waitUntil(function()
			return players[2].Parent == nil and records[players[2]] == nil
		end, "leaving profile did not close")
		assert(
			value(base:Read("player:" .. players[2].UserId)).data.Stats.Coins == 14,
			"player leave lost data"
		)
		table.insert(checks, "leave-persistence")
		if args.replaceClient ~= false then
			StudioTestService:AddPlayers(1)
			local replacement
			waitUntil(function()
				for _, player in Players:GetPlayers() do
					if
						player ~= players[1]
						and records[player]
						and reports.boot[tostring(player.UserId)]
					then
						replacement = player
						return true
					end
				end
				return false
			end, "replacement client did not synchronize")
			phase("initial", { replacement }, function(player)
				return { coins = records[player]:Get("Stats.Coins").value }
			end)
			table.insert(checks, "replacement-join")
		else
			summary.replacementJoin = "not run: existing manual Studio session"
		end
		phase("finish", Players:GetPlayers(), function()
			return {}
		end)
		for index = 1, recordCount do
			local key = "bulk:" .. index
			table.insert(keys, key)
			value(value(bulk:LoadAsync(key, 15)):Set("Value", index))
		end
		measure = true
		local started = os.clock()
		value(manager:CloseAsync(25))
		summary.closeSeconds = os.clock() - started
		summary.peakConcurrentBulkWrites = peak
		assert(
			peak <= 4 and summary.closeSeconds <= 25,
			"shutdown concurrency/deadline gate failed"
		)
		for index = 1, recordCount do
			local saved = value(base:Read("bulk:" .. index))
			assert(
				saved.data.Value == index and saved.lease == nil,
				"shutdown lost a record or retained a lease"
			)
		end
		table.insert(checks, "bounded-shutdown-persistence")
		if live then
			local cleanup = OmniStore.new({ autoBindToClose = false })
				:GetStore("Cleanup", { adapter = base, autosaveInterval = 0 })
			for _, key in keys do
				value(cleanup:DeleteAsync(key, 15))
			end
			value(cleanup:CloseAsync(15))
			summary.tombstones = #keys
		end
	end, debug.traceback)
	finish(ok, cause)
end)
