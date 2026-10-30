--!strict
-- Runs only with the opt-in Studio multiplayer server harness.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("OmniStoreMultiplayer", 40)
if not root then
	return
end
local control = root:WaitForChild("Control") :: RemoteFunction
local command = root:WaitForChild("Command") :: RemoteEvent
local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
local player = Players.LocalPlayer
local profile, shared
local channel

local function waitUntil(predicate, message)
	local deadline = os.clock() + 20
	repeat
		if predicate() then
			return
		end
		task.wait(0.03)
	until os.clock() >= deadline
	error(message)
end

local function report(phase, callback)
	local ok, result = xpcall(callback, debug.traceback)
	return control:InvokeServer({
		kind = "report",
		phase = phase,
		ok = ok,
		error = if ok then nil else tostring(result):sub(1, 2000),
		details = if ok then result else nil,
	})
end

command.OnClientEvent:Connect(function(phase, payload)
	if phase == "leave" then
		report(phase, function()
			return { canLeave = game:GetService("StudioTestService"):CanLeaveTest() }
		end)
		if game:GetService("StudioTestService"):CanLeaveTest() then
			game:GetService("StudioTestService"):LeaveTest()
		else
			control:InvokeServer({ kind = "requestLeave" })
		end
		return
	end
	report(phase, function()
		if phase == "initial" then
			assert(
				profile:IsSynchronized() and shared:IsSynchronized(),
				"initial mirrors not synchronized"
			)
			assert(profile:Get("Stats.Coins").value == payload.coins, "initial profile differs")
			assert(
				profile:Get("Public.Owner").value == player.UserId,
				"received another player's profile"
			)
			assert(
				profile:Get("Private").value == nil and shared:Get("Private").value == nil,
				"private data leaked"
			)
			local copy = profile:Get("Stats").value
			copy.Coins = 999999
			assert(
				profile:Get("Stats.Coins").value == payload.coins,
				"mirror reads expose mutable state"
			)
			assert(
				profile.Set == nil and profile.SaveAsync == nil,
				"mirror exposes persistence writes"
			)
		elseif phase == "isolation" then
			local snapshot = root.OmniStoreReplication.Snapshot
			assert(
				snapshot:InvokeServer(payload.otherChannel).code == "Unavailable",
				"other profile was exposed"
			)
			root.OmniStoreReplication
				:WaitForChild("Changed")
				:FireServer(channel, "Stats.Coins", 999999, 1000, "change")
			local accepted, limited = 0, 0
			for _ = 1, 16 do
				local result = snapshot:InvokeServer(channel)
				if result.ok then
					accepted += 1
				elseif result.code == "RateLimited" then
					limited += 1
				end
			end
			assert(accepted > 0 and limited > 0, "per-player snapshot limit not exercised")
			return { accepted = accepted, limited = limited }
		elseif phase == "burst" then
			waitUntil(function()
				return shared:Get("Stats.Coins").value == payload.sharedCoins
					and profile:Get("Stats.Coins").value == payload.coins
					and shared:IsSynchronized()
					and profile:IsSynchronized()
			end, "replicated burst did not converge")
			assert(profile:Get("Private.Secret").value == nil, "private change leaked")
			return { sequence = shared:GetRevision(), sharedCoins = shared:Get("Stats.Coins").value }
		elseif phase == "invalidate" then
			waitUntil(function()
				local marker = shared:Get("Public.Marker").value
				return type(marker) == "string"
					and #marker == payload.bytes
					and shared:IsSynchronized()
			end, "oversized-change invalidation did not resynchronize")
		elseif phase == "closeProfile" then
			if player.UserId == payload.closedUserId then
				assert(not profile:ResyncAsync(), "closed profile still exposes snapshots")
				assert(profile:GetStatus() == "Stale", "unavailable channel did not become stale")
				profile:Destroy()
				assert(
					profile:Get("Stats.Coins").error.code == "Closed",
					"destroyed mirror remained readable"
				)
			else
				assert(profile:ResyncAsync(), "closing one profile broke its peer")
			end
			assert(shared:ResyncAsync(), "shared channel was affected by profile teardown")
		elseif phase == "finish" then
			profile:Destroy()
			shared:Destroy()
		else
			error("unknown multiplayer phase")
		end
		return { passed = true }
	end)
end)

report("boot", function()
	local hello
	waitUntil(function()
		hello = control:InvokeServer({ kind = "hello" })
		return hello.ok
	end, "server profile did not become available")
	channel = hello.channel
	profile = OmniStore.Replication.Client.new(channel, { parent = root, resyncCooldown = 0.1 })
	shared = OmniStore.Replication.Client.new("Shared", { parent = root, resyncCooldown = 0.1 })
	return { userId = player.UserId }
end)
