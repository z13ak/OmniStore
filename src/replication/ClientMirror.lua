--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DeepCopy = require(script.Parent.Parent.internal.DeepCopy)
local Path = require(script.Parent.Parent.internal.Path)
local Protocol = require(script.Parent.ReplicationProtocol)
local Result = require(script.Parent.Parent.internal.Result)
local Signal = require(script.Parent.Parent.internal.Signal)
local Types = require(script.Parent.Parent.Types)

export type Status = "Synchronizing" | "Synchronized" | "Stale" | "Destroyed"
export type Config = {
	parent: Instance?,
	waitTimeout: number?,
	maxSnapshotBytes: number?,
	maxChangeBytes: number?,
	maxPayloadDepth: number?,
	maxPathSegments: number?,
	maxPendingChanges: number?,
	resyncCooldown: number?,
}
type Packet = {
	path: Types.Path?,
	value: unknown,
	sequence: number,
	kind: string,
}

local ClientMirror = {}
ClientMirror.__index = ClientMirror

export type ClientMirror = typeof(setmetatable(
	{} :: {
		Channel: string,
		Changed: Signal.Signal<Types.Path, unknown>,
		Resynced: Signal.Signal<number>,
		StatusChanged: Signal.Signal<Status, Status>,
		_data: unknown,
		_sequence: number,
		_connection: RBXScriptConnection,
		_snapshotRemote: RemoteFunction,
		_pending: { Packet },
		_status: Status,
		_ready: boolean,
		_resyncing: boolean,
		_resyncScheduled: boolean,
		_lastResyncAt: number,
		_config: {
			maxSnapshotBytes: number,
			maxChangeBytes: number,
			maxPayloadDepth: number,
			maxPathSegments: number,
			maxPendingChanges: number,
			resyncCooldown: number,
		},
	},
	ClientMirror
))

local function positive(value: number?, defaultValue: number): number
	if value == nil then
		return defaultValue
	end
	assert(value > 0, "replication limits must be positive")
	return value
end

function ClientMirror:_setStatus(status: Status)
	if self._status == status then
		return
	end
	local previous = self._status
	self._status = status
	self.StatusChanged:Fire(status, previous)
end

function ClientMirror:_queue(packet: Packet)
	if #self._pending >= self._config.maxPendingChanges then
		table.clear(self._pending)
		self:_setStatus("Stale")
		return
	end
	table.insert(self._pending, packet)
end

function ClientMirror:_apply(packet: Packet): boolean
	if packet.kind ~= "change" or packet.path == nil then
		return false
	end
	if packet.sequence ~= self._sequence + 1 then
		return false
	end
	local pathOk = Protocol.validatePath(packet.path, self._config.maxPathSegments)
	if not pathOk then
		return false
	end
	local bytes =
		Protocol.measure(packet.value, self._config.maxPayloadDepth, self._config.maxChangeBytes)
	if not bytes or bytes > self._config.maxChangeBytes then
		return false
	end
	if not Protocol.assign(self._data :: table, packet.path, packet.value) then
		return false
	end
	self._sequence = packet.sequence
	self.Changed:Fire(packet.path, DeepCopy(packet.value))
	return true
end

function ClientMirror:_applyPending()
	table.sort(self._pending, function(left, right)
		return left.sequence < right.sequence
	end)
	local pending = self._pending
	self._pending = {}
	for _, packet in pending do
		if packet.sequence > self._sequence and not self:_apply(packet) then
			self:_queue(packet)
			self:_setStatus("Stale")
		end
	end
end

function ClientMirror:_requestSnapshot(): boolean
	if self._resyncing or self._status == "Destroyed" then
		return false
	end
	self._resyncing = true
	self:_setStatus("Synchronizing")
	local invoked, response =
		pcall(self._snapshotRemote.InvokeServer, self._snapshotRemote, self.Channel)
	if not invoked or type(response) ~= "table" or response.ok == false then
		self._resyncing = false
		self:_setStatus("Stale")
		return false
	end
	local sequence = response.sequence or response.revision
	if type(sequence) ~= "number" or sequence % 1 ~= 0 or sequence < self._sequence then
		self._resyncing = false
		self:_setStatus("Stale")
		return false
	end
	local bytes =
		Protocol.measure(response.data, self._config.maxPayloadDepth, self._config.maxSnapshotBytes)
	if type(response.data) ~= "table" or not bytes or bytes > self._config.maxSnapshotBytes then
		self._resyncing = false
		self:_setStatus("Stale")
		return false
	end

	self._data = DeepCopy(response.data)
	self._sequence = sequence
	self._lastResyncAt = os.clock()
	self._ready = true
	self._resyncing = false
	self:_applyPending()
	if #self._pending == 0 then
		self:_setStatus("Synchronized")
		self.Resynced:Fire(self._sequence)
	else
		self:_setStatus("Stale")
	end
	return self._status == "Synchronized"
end

function ClientMirror:_scheduleResync()
	if self._resyncing or self._status == "Destroyed" then
		return
	end
	local elapsed = os.clock() - self._lastResyncAt
	if elapsed < self._config.resyncCooldown then
		self:_setStatus("Stale")
		if not self._resyncScheduled then
			self._resyncScheduled = true
			task.delay(self._config.resyncCooldown - elapsed, function()
				self._resyncScheduled = false
				self:_requestSnapshot()
			end)
		end
		return
	end
	task.spawn(function()
		self:_requestSnapshot()
	end)
end

function ClientMirror:_receive(
	changedChannel: unknown,
	path: unknown,
	value: unknown,
	sequence: unknown,
	kind: unknown
)
	if changedChannel ~= self.Channel or type(sequence) ~= "number" or sequence % 1 ~= 0 then
		return
	end
	if sequence <= self._sequence then
		return
	end
	local packet: Packet = {
		path = if type(path) == "string" or type(path) == "table" then path :: Types.Path else nil,
		value = value,
		sequence = sequence,
		kind = if type(kind) == "string" then kind else "change",
	}
	if not self._ready or self._resyncing then
		self:_queue(packet)
		return
	end
	if
		packet.kind == "change"
		and packet.sequence == self._sequence + 1
		and self:_apply(packet)
	then
		return
	end
	self:_queue(packet)
	self:_setStatus("Stale")
	self:_scheduleResync()
end

function ClientMirror.new(channel: string, parentOrConfig: (Instance | Config)?): ClientMirror
	assert(RunService:IsClient(), "ClientMirror can only run on the client")
	local options: Config = if typeof(parentOrConfig) == "Instance"
		then { parent = parentOrConfig :: Instance }
		else (parentOrConfig :: Config?) or {}
	local channelOk, channelError = Protocol.validateChannel(channel, 64)
	assert(channelOk, channelError)
	local waitTimeout = positive(options.waitTimeout, 10)
	local folder = (options.parent or ReplicatedStorage):WaitForChild(
		"OmniStoreReplication",
		waitTimeout
	)
	assert(folder, "replication remotes were not available before the timeout")
	local snapshotRemote = folder:WaitForChild("Snapshot", waitTimeout) :: RemoteFunction?
	local changedRemote = folder:WaitForChild("Changed", waitTimeout) :: RemoteEvent?
	assert(
		snapshotRemote and snapshotRemote:IsA("RemoteFunction"),
		"Snapshot remote is unavailable"
	)
	assert(changedRemote and changedRemote:IsA("RemoteEvent"), "Changed remote is unavailable")

	local self = setmetatable({
		Channel = channel,
		Changed = Signal.new(),
		Resynced = Signal.new(),
		StatusChanged = Signal.new(),
		_data = {},
		_sequence = -1,
		_connection = nil :: any,
		_snapshotRemote = snapshotRemote,
		_pending = {},
		_status = "Synchronizing" :: Status,
		_ready = false,
		_resyncing = false,
		_resyncScheduled = false,
		_lastResyncAt = -math.huge,
		_config = {
			maxSnapshotBytes = positive(options.maxSnapshotBytes, 128_000),
			maxChangeBytes = positive(options.maxChangeBytes, 32_000),
			maxPayloadDepth = positive(options.maxPayloadDepth, 32),
			maxPathSegments = positive(options.maxPathSegments, 32),
			maxPendingChanges = positive(options.maxPendingChanges, 128),
			resyncCooldown = positive(options.resyncCooldown, 1),
		},
	}, ClientMirror)
	self._connection = changedRemote.OnClientEvent:Connect(function(...)
		self:_receive(...)
	end)
	if not self:_requestSnapshot() then
		self:Destroy()
		error("replication channel is unavailable or its snapshot was rejected", 2)
	end
	return self
end

function ClientMirror:Get(path: Types.Path): Types.Result<unknown>
	if self._status == "Destroyed" then
		return Result.err("Closed", "client mirror is destroyed", false)
	end
	return Result.ok(DeepCopy(Path.get(self._data, Path.parse(path))))
end

function ClientMirror:GetRevision(): number
	return self._sequence
end

function ClientMirror:GetStatus(): Status
	return self._status
end

function ClientMirror:IsSynchronized(): boolean
	return self._status == "Synchronized"
end

function ClientMirror:ResyncAsync(): boolean
	return self:_requestSnapshot()
end

function ClientMirror:Destroy()
	if self._status == "Destroyed" then
		return
	end
	self._connection:Disconnect()
	table.clear(self._pending)
	self:_setStatus("Destroyed")
	self.Changed:Destroy()
	self.Resynced:Destroy()
	self.StatusChanged:Destroy()
end

return ClientMirror
