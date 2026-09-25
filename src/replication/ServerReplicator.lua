--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DeepCopy = require(script.Parent.Parent.internal.DeepCopy)
local Protocol = require(script.Parent.ReplicationProtocol)
local Result = require(script.Parent.Parent.internal.Result)
local Types = require(script.Parent.Parent.Types)

type Connection = { Disconnect: (self: Connection) -> () }
type ReadableRecord = {
	Changed: {
		Connect: (self: any, callback: (Types.Path, unknown, unknown) -> ()) -> Connection,
	},
	LifecycleChanged: {
		Connect: (self: any, callback: (string) -> ()) -> Connection,
	}?,
	Get: (self: ReadableRecord, path: Types.Path) -> Types.Result<unknown>,
}
type Registration = {
	record: ReadableRecord,
	paths: { Types.Path },
	connection: Connection,
	lifecycleConnection: Connection?,
	sequence: number,
}
type RateState = { startedAt: number, count: number }

export type Config = {
	parent: Instance?,
	maxSnapshotBytes: number?,
	maxChangeBytes: number?,
	maxSnapshotRequests: number?,
	requestWindowSeconds: number?,
	maxChannelsPerPlayer: number?,
	maxAllowedPaths: number?,
	maxChannelLength: number?,
	maxPathSegments: number?,
	maxPayloadDepth: number?,
	clock: (() -> number)?,
	logger: ((string, string) -> ())?,
}

local ServerReplicator = {}
ServerReplicator.__index = ServerReplicator

export type ServerReplicator = typeof(setmetatable(
	{} :: {
		_folder: Folder,
		_snapshot: RemoteFunction,
		_changed: RemoteEvent,
		_registrations: { [Player]: { [string]: Registration } },
		_rateStates: { [Player]: RateState },
		_playerRemoving: RBXScriptConnection,
		_destroyed: boolean,
		_config: {
			maxSnapshotBytes: number,
			maxChangeBytes: number,
			maxSnapshotRequests: number,
			requestWindowSeconds: number,
			maxChannelsPerPlayer: number,
			maxAllowedPaths: number,
			maxChannelLength: number,
			maxPathSegments: number,
			maxPayloadDepth: number,
			clock: () -> number,
			logger: ((string, string) -> ())?,
		},
	},
	ServerReplicator
))

local function positive(value: number?, defaultValue: number): number
	if value == nil then
		return defaultValue
	end
	assert(value > 0, "replication limits must be positive")
	return value
end

local function log(self: ServerReplicator, event: string, message: string)
	if self._config.logger then
		pcall(self._config.logger, event, message)
	end
end

function ServerReplicator:_consumeRequest(player: Player): boolean
	local now = self._config.clock()
	local state = self._rateStates[player]
	if not state or now - state.startedAt >= self._config.requestWindowSeconds then
		self._rateStates[player] = { startedAt = now, count = 1 }
		return true
	end
	if state.count >= self._config.maxSnapshotRequests then
		return false
	end
	state.count += 1
	return true
end

function ServerReplicator:_snapshotResponse(registration: Registration): { [string]: unknown }
	local data = {}
	for _, path in registration.paths do
		local result = registration.record:Get(path)
		if not result.ok then
			return { ok = false, code = "RecordUnavailable" }
		end
		Protocol.assign(data, path, result.value)
	end
	local bytes, measureError =
		Protocol.measure(data, self._config.maxPayloadDepth, self._config.maxSnapshotBytes)
	if not bytes or bytes > self._config.maxSnapshotBytes then
		log(self, "snapshot_rejected", measureError or "snapshot exceeds payload limit")
		return { ok = false, code = "PayloadRejected" }
	end
	return {
		ok = true,
		data = data,
		sequence = registration.sequence,
		revision = registration.sequence,
	}
end

function ServerReplicator:_handleSnapshot(player: Player, channel: unknown): { [string]: unknown }
	if self._destroyed or not self:_consumeRequest(player) then
		return { ok = false, code = "RateLimited" }
	end
	local channelOk = Protocol.validateChannel(channel, self._config.maxChannelLength)
	if not channelOk then
		return { ok = false, code = "Unavailable" }
	end
	local playerRegistrations = self._registrations[player]
	local registration = if playerRegistrations then playerRegistrations[channel :: string] else nil
	if not registration then
		return { ok = false, code = "Unavailable" }
	end
	return self:_snapshotResponse(registration)
end

function ServerReplicator.new(parentOrConfig: (Instance | Config)?): ServerReplicator
	assert(RunService:IsServer(), "ServerReplicator can only run on the server")
	local options: Config = if typeof(parentOrConfig) == "Instance"
		then { parent = parentOrConfig :: Instance }
		else (parentOrConfig :: Config?) or {}
	local container = options.parent or ReplicatedStorage
	assert(
		not container:FindFirstChild("OmniStoreReplication"),
		"replication folder already exists"
	)

	local folder = Instance.new("Folder")
	folder.Name = "OmniStoreReplication"
	folder.Parent = container
	local snapshot = Instance.new("RemoteFunction")
	snapshot.Name = "Snapshot"
	snapshot.Parent = folder
	local changed = Instance.new("RemoteEvent")
	changed.Name = "Changed"
	changed.Parent = folder

	local self = setmetatable({
		_folder = folder,
		_snapshot = snapshot,
		_changed = changed,
		_registrations = {},
		_rateStates = {},
		_playerRemoving = nil :: any,
		_destroyed = false,
		_config = {
			maxSnapshotBytes = positive(options.maxSnapshotBytes, 128_000),
			maxChangeBytes = positive(options.maxChangeBytes, 32_000),
			maxSnapshotRequests = positive(options.maxSnapshotRequests, 8),
			requestWindowSeconds = positive(options.requestWindowSeconds, 10),
			maxChannelsPerPlayer = positive(options.maxChannelsPerPlayer, 8),
			maxAllowedPaths = positive(options.maxAllowedPaths, 32),
			maxChannelLength = positive(options.maxChannelLength, 64),
			maxPathSegments = positive(options.maxPathSegments, 32),
			maxPayloadDepth = positive(options.maxPayloadDepth, 32),
			clock = options.clock or os.clock,
			logger = options.logger,
		},
	}, ServerReplicator)

	snapshot.OnServerInvoke = function(player: Player, channel: unknown)
		return self:_handleSnapshot(player, channel)
	end

	self._playerRemoving = Players.PlayerRemoving:Connect(function(player)
		self:Unregister(player)
		self._rateStates[player] = nil
	end)
	return self
end

function ServerReplicator:Register(
	player: Player,
	channel: string,
	record: ReadableRecord,
	allowedPaths: { Types.Path }
): Types.Result<nil>
	if self._destroyed then
		return Result.err("Closed", "replicator is destroyed", false)
	end
	local channelOk, channelError = Protocol.validateChannel(channel, self._config.maxChannelLength)
	if not channelOk then
		return Result.err("InvalidConfig", channelError or "invalid channel", false)
	end
	if #allowedPaths == 0 or #allowedPaths > self._config.maxAllowedPaths then
		return Result.err("InvalidConfig", "allowed path count is outside configured limits", false)
	end
	for index, path in allowedPaths do
		local pathOk, pathError = Protocol.validatePath(path, self._config.maxPathSegments)
		if not pathOk then
			return Result.err("InvalidConfig", pathError or "invalid allowed path", false)
		end
		for previous = 1, index - 1 do
			if Protocol.pathsOverlap(path, allowedPaths[previous]) then
				return Result.err("InvalidConfig", "allowed paths must not overlap", false)
			end
		end
	end

	local playerRegistrations = self._registrations[player]
	if not playerRegistrations then
		playerRegistrations = {}
		self._registrations[player] = playerRegistrations
	end
	if playerRegistrations[channel] then
		return Result.err("Conflict", "channel is already registered for this player", false)
	end
	local channelCount = 0
	for _ in playerRegistrations do
		channelCount += 1
	end
	if channelCount >= self._config.maxChannelsPerPlayer then
		return Result.err("InvalidConfig", "player exceeds the configured channel limit", false)
	end

	local registration: Registration
	local connection = record.Changed:Connect(function(path, newValue)
		if not Protocol.isAllowed(path, allowedPaths) then
			return
		end
		registration.sequence += 1
		local bytes, measureError =
			Protocol.measure(newValue, self._config.maxPayloadDepth, self._config.maxChangeBytes)
		if not bytes or bytes > self._config.maxChangeBytes then
			log(self, "change_rejected", measureError or "change exceeds payload limit")
			self._changed:FireClient(player, channel, nil, nil, registration.sequence, "invalidate")
			return
		end
		self._changed:FireClient(
			player,
			channel,
			DeepCopy(path),
			DeepCopy(newValue),
			registration.sequence,
			"change"
		)
	end)
	registration = {
		record = record,
		paths = DeepCopy(allowedPaths) :: { Types.Path },
		connection = connection,
		lifecycleConnection = nil,
		sequence = 0,
	}
	if record.LifecycleChanged then
		registration.lifecycleConnection = record.LifecycleChanged:Connect(function(state: string)
			if state == "Closed" or state == "LeaseLost" then
				self:Unregister(player, channel)
			end
		end)
	end
	playerRegistrations[channel] = registration

	local initial = self:_snapshotResponse(registration)
	if initial.ok ~= true then
		self:Unregister(player, channel)
		return Result.err(
			"InvalidData",
			"initial replication snapshot exceeds safety limits",
			false
		)
	end
	return Result.ok(nil)
end

function ServerReplicator:Unregister(player: Player, channel: string?)
	local playerRegistrations = self._registrations[player]
	if not playerRegistrations then
		return
	end
	if channel then
		local registration = playerRegistrations[channel]
		if registration then
			registration.connection:Disconnect()
			if registration.lifecycleConnection then
				registration.lifecycleConnection:Disconnect()
			end
			playerRegistrations[channel] = nil
		end
		if next(playerRegistrations) == nil then
			self._registrations[player] = nil
		end
		return
	end
	for _, registration in playerRegistrations do
		registration.connection:Disconnect()
		if registration.lifecycleConnection then
			registration.lifecycleConnection:Disconnect()
		end
	end
	self._registrations[player] = nil
end

function ServerReplicator:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for player in self._registrations do
		self:Unregister(player)
	end
	table.clear(self._rateStates)
	self._playerRemoving:Disconnect()
	self._snapshot.OnServerInvoke = nil
	self._folder:Destroy()
end

return ServerReplicator
