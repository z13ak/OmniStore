--!strict

local DeepCopy = require(script.Parent.internal.DeepCopy)
local NoYield = require(script.Parent.internal.NoYield)
local Path = require(script.Parent.internal.Path)
local Result = require(script.Parent.internal.Result)
local Serializer = require(script.Parent.internal.Serializer)
local Signal = require(script.Parent.internal.Signal)
local TransactionDraft = require(script.Parent.internal.TransactionDraft)
local Types = require(script.Parent.Types)

type PathValue = Types.Path
type Result<T> = Types.Result<T>
type StoreLike = {
	_config: Types.StoreConfig,
	_validate: (self: StoreLike, data: unknown) -> Types.Failure?,
	_encodeData: (self: StoreLike, data: unknown) -> Result<unknown>,
	_loadRecord: (
		self: StoreLike,
		key: string,
		owner: string,
		deadline: number?,
		staleLeasePolicy: Types.StaleLeasePolicy
	) -> Result<Types.StoredEnvelope>,
	_readRecord: (self: StoreLike, key: string, deadline: number?) -> Result<Types.StoredEnvelope>,
	_saveRecord: (
		self: StoreLike,
		key: string,
		owner: string,
		data: unknown,
		metadata: { [string]: unknown },
		release: boolean,
		deadline: number?
	) -> Result<Types.StoredEnvelope>,
	_renewRecord: (self: StoreLike, key: string, owner: string) -> Result<Types.StoredEnvelope>,
	_forgetRecord: (self: StoreLike, key: string) -> (),
	_scheduleBackground: (
		self: StoreLike,
		delay: number,
		callback: () -> number?
	) -> { Cancel: (self: any) -> () },
	_log: (
		self: StoreLike,
		level: Types.DiagnosticLevel,
		event: string,
		message: string,
		context: { [string]: unknown }?
	) -> (),
	_metric: (
		self: StoreLike,
		name: string,
		value: number,
		tags: { [string]: string }?
	) -> (),
}

export type RecordState = "New" | "Loading" | "Active" | "Closing" | "Closed" | "LeaseLost"

local Record = {}
Record.__index = Record

export type Record = typeof(setmetatable(
	{} :: {
		Key: string,
		State: RecordState,
		Changed: Signal.Signal<PathValue, unknown, unknown>,
		LifecycleChanged: Signal.Signal<RecordState, RecordState>,
		_store: StoreLike,
		_owner: string,
		_data: unknown,
		_metadata: { [string]: unknown },
		_revision: number,
		_dirty: boolean,
		_mutationVersion: number,
		_saving: boolean,
		_saveRequested: boolean,
		_lastSaveResult: Result<nil>?,
		_stopBackground: boolean,
		_backgroundJobs: { { Cancel: (self: any) -> () } },
		_inTransaction: boolean,
		_readOnly: boolean,
	},
	Record
))

local function freezeCopy(value: unknown): unknown
	local copy = DeepCopy(value)
	if type(copy) == "table" then
		table.freeze(copy :: table)
	end
	return copy
end

function Record.new(store: StoreLike, key: string, owner: string, readOnly: boolean?): Record
	return setmetatable({
		Key = key,
		State = "New" :: RecordState,
		Changed = Signal.new(),
		LifecycleChanged = Signal.new(),
		_store = store,
		_owner = owner,
		_data = {},
		_metadata = {},
		_revision = 0,
		_dirty = false,
		_mutationVersion = 0,
		_saving = false,
		_saveRequested = false,
		_lastSaveResult = nil,
		_stopBackground = false,
		_backgroundJobs = {},
		_inTransaction = false,
		_readOnly = readOnly == true,
	}, Record)
end

function Record:_requireWritable(): Types.Failure?
	local stateError = self:_requireActive()
	if stateError then
		return stateError
	end
	if self._readOnly then
		return Result.err("ReadOnly", "record was loaded in read-only mode", false)
	end
	if self._inTransaction then
		return Result.err("Conflict", "record writes are locked during a transaction", false)
	end
	return nil
end

function Record:_setState(nextState: RecordState)
	local previous = self.State
	if previous == nextState then
		return
	end
	self.State = nextState
	self.LifecycleChanged:Fire(nextState, previous)
end

function Record:_requireActive(): Types.Failure?
	if self.State == "LeaseLost" then
		return Result.err("LeaseLost", "record lease is no longer owned by this session", false)
	end
	if self.State ~= "Active" then
		local code: Types.ErrorCode = if self.State == "Closed" then "Closed" else "NotLoaded"
		return Result.err(code, `record is not active (state: {self.State})`, false)
	end
	return nil
end

function Record:_validate(data: unknown): Types.Failure?
	return self._store:_validate(data)
end

function Record:_validateSerialization(value: unknown): Types.Result<nil>
	local encoded = self._store:_encodeData(value)
	if not encoded.ok then
		return encoded :: any
	end
	return Serializer.validate(encoded.value, {
		maxDepth = self._store._config.maxSerializationDepth,
		maxPayloadBytes = self._store._config.maxPayloadBytes,
	})
end

function Record:LoadAsync(
	timeout: number?,
	staleLeasePolicy: Types.StaleLeasePolicy?
): Result<Record>
	if self.State ~= "New" then
		return Result.err("AlreadyLoaded", "record loading has already been attempted", false)
	end
	self:_setState("Loading")
	local clock = self._store._config.monotonicClock :: () -> number
	local deadline = if timeout ~= nil then clock() + math.max(0, timeout) else nil
	local loaded = if self._readOnly
		then self._store:_readRecord(self.Key, deadline)
		else self._store:_loadRecord(
			self.Key,
			self._owner,
			deadline,
			staleLeasePolicy or "Recover"
		)
	if not loaded.ok then
		self:_setState("New")
		return loaded :: any
	end

	local envelope = loaded.value
	self._data = DeepCopy(envelope.data)
	self._metadata = DeepCopy(envelope.metadata) :: { [string]: unknown }
	self._revision = envelope.revision
	self._dirty = false
	self:_setState("Active")
	if not self._readOnly then
		self:_startBackgroundTasks()
	end
	return Result.ok(self)
end

function Record:_startBackgroundTasks()
	local config = self._store._config
	local random = config.random :: Random
	local autosaveInterval = config.autosaveInterval :: number
	local autosaveJitter = config.autosaveJitter :: number
	local lease = config.lease :: Types.LeaseConfig

	self._stopBackground = false
	if autosaveInterval > 0 then
		local function nextAutosaveDelay(): number
			return math.max(
				1,
				autosaveInterval + random:NextNumber(-autosaveJitter, autosaveJitter)
			)
		end
		table.insert(
			self._backgroundJobs,
			self._store:_scheduleBackground(nextAutosaveDelay(), function()
				if self._stopBackground or self.State ~= "Active" then
					return nil
				end
				if self._dirty then
					local saved = self:SaveAsync()
					if not saved.ok then
						self._store:_log("error", "autosave_failed", "background autosave failed", {
							errorCode = saved.error.code,
							category = saved.error.category or "Unknown",
						})
						self._store:_metric("autosave_failure", 1)
					end
				end
				return nextAutosaveDelay()
			end)
		)
	end

	if lease.enabled then
		table.insert(
			self._backgroundJobs,
			self._store:_scheduleBackground(lease.renewInterval, function()
				if self._stopBackground or self.State ~= "Active" then
					return nil
				end
				local renewed = self._store:_renewRecord(self.Key, self._owner)
				if not renewed.ok then
					if renewed.error.code == "LeaseLost" then
						self:_setState("LeaseLost")
						self._store:_metric("lease_lost", 1)
						self._store:_log("error", "lease_lost", "record lease was lost")
						return nil
					end
					self._store:_metric("lease_renewal_failure", 1)
					self._store:_log("warn", "lease_renewal_failed", "lease renewal failed", {
						errorCode = renewed.error.code,
						category = renewed.error.category or "Unknown",
					})
				end
				return lease.renewInterval
			end)
		)
	end
end

function Record:_stopBackgroundTasks()
	self._stopBackground = true
	for _, job in self._backgroundJobs do
		job:Cancel()
	end
	table.clear(self._backgroundJobs)
end

function Record:GetData(): Result<unknown>
	local stateError = self:_requireActive()
	if stateError then
		return stateError
	end
	return Result.ok(freezeCopy(self._data))
end

function Record:Get(path: PathValue): Result<unknown>
	local stateError = self:_requireActive()
	if stateError then
		return stateError
	end
	return Result.ok(freezeCopy(Path.get(self._data, Path.parse(path))))
end

function Record:_markChanged(path: PathValue, newValue: unknown, oldValue: unknown)
	self._dirty = true
	self._mutationVersion += 1
	self.Changed:Fire(path, freezeCopy(newValue), freezeCopy(oldValue))
end

function Record:Set(path: PathValue, value: unknown): Result<unknown>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError
	end
	local segments = Path.parse(path)
	if #segments == 0 then
		local validationError = self:_validate(value)
		if validationError then
			return validationError
		end
		local oldValue = self._data
		self._data = DeepCopy(value)
		self:_markChanged(path, value, oldValue)
		return Result.ok(freezeCopy(value))
	end

	local valueSerialization = self:_validateSerialization(value)
	if not valueSerialization.ok then
		return valueSerialization
	end
	local dataSnapshot = DeepCopy(self._data)
	local parent, key = Path.parent(self._data, segments, value ~= nil)
	if not parent or key == nil then
		self._data = dataSnapshot
		if value == nil then
			return Result.ok(nil)
		end
		return Result.err("InvalidData", "path traverses a non-table value", false)
	end
	local parentAny = parent :: any
	local oldValue = parentAny[key]
	parentAny[key] = DeepCopy(value)
	local validationError = self:_validate(self._data)
	if validationError then
		self._data = dataSnapshot
		return validationError
	end
	self:_markChanged(path, value, oldValue)
	return Result.ok(freezeCopy(value))
end

function Record:Increment(path: PathValue, amount: number?): Result<number>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError :: any
	end
	local current = self:Get(path)
	if not current.ok then
		return current :: any
	end
	if current.value ~= nil and type(current.value) ~= "number" then
		return Result.err("InvalidData", "Increment target must be a number or nil", false)
	end
	local nextValue = ((current.value :: number?) or 0) + (amount or 1)
	local setResult = self:Set(path, nextValue)
	if not setResult.ok then
		return setResult :: any
	end
	return Result.ok(nextValue)
end

function Record:Update(path: PathValue, updater: (unknown) -> unknown): Result<unknown>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError
	end
	local current = self:Get(path)
	if not current.ok then
		return current
	end
	local ok, nextValue = pcall(updater, current.value)
	if not ok then
		return Result.err("InvalidData", "Update callback failed", false, nextValue)
	end
	return self:Set(path, nextValue)
end

function Record:Insert(path: PathValue, value: unknown, index: number?): Result<number>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError :: any
	end
	local current = self:Get(path)
	if not current.ok then
		return current :: any
	end
	if type(current.value) ~= "table" then
		return Result.err("InvalidData", "Insert target must be an array", false)
	end
	local array = DeepCopy(current.value) :: { unknown }
	local insertionIndex = index or (#array + 1)
	if insertionIndex < 1 or insertionIndex > #array + 1 then
		return Result.err("InvalidData", "Insert index is outside the array", false)
	end
	table.insert(array, insertionIndex, DeepCopy(value))
	local setResult = self:Set(path, array)
	if not setResult.ok then
		return setResult :: any
	end
	return Result.ok(insertionIndex)
end

function Record:Remove(path: PathValue, index: number?): Result<unknown>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError
	end
	if index ~= nil then
		local current = self:Get(path)
		if not current.ok then
			return current
		end
		if type(current.value) ~= "table" then
			return Result.err("InvalidData", "indexed Remove target must be an array", false)
		end
		local array = DeepCopy(current.value) :: { unknown }
		if index < 1 or index > #array then
			return Result.err("InvalidData", "Remove index is outside the array", false)
		end
		local removed = table.remove(array, index)
		local setResult = self:Set(path, array)
		if not setResult.ok then
			return setResult
		end
		return Result.ok(freezeCopy(removed))
	end

	local current = self:Get(path)
	if not current.ok then
		return current
	end
	local setResult = self:Set(path, nil)
	if not setResult.ok then
		return setResult
	end
	return Result.ok(current.value)
end

function Record:SetMetadata(key: string, value: unknown): Result<nil>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError
	end
	local candidate = DeepCopy(self._metadata) :: { [string]: unknown }
	candidate[key] = DeepCopy(value)
	local valid = self:_validateSerialization(candidate)
	if not valid.ok then
		return valid
	end
	self._metadata = candidate
	self._dirty = true
	self._mutationVersion += 1
	return Result.ok(nil)
end

function Record:GetMetadata(key: string?): Result<unknown>
	local stateError = self:_requireActive()
	if stateError then
		return stateError
	end
	return Result.ok(freezeCopy(if key then self._metadata[key] else self._metadata))
end

function Record:Transaction(callback: (TransactionDraft.TransactionDraft) -> ()): Result<nil>
	if self._inTransaction then
		return Result.err("Conflict", "nested transactions are not supported", false)
	end
	local stateError = self:_requireWritable()
	if stateError then
		return stateError
	end

	local draft = TransactionDraft.new(self._data, self._metadata, function(value)
		local serialized = self:_validateSerialization(value)
		return if serialized.ok then nil else serialized
	end)
	self._inTransaction = true
	local ok, yielded, cause = NoYield.run(callback, draft)
	self._inTransaction = false
	if not ok then
		return Result.err(
			"TransactionFailed",
			if yielded
				then "transaction callback yielded and was discarded"
				else "transaction callback failed and was discarded",
			false,
			cause
		)
	end
	local draftFailure = draft:_getFailure()
	if draftFailure then
		return draftFailure
	end

	local data, metadata, changes, mutationCount = draft:_commit()
	local validationError = self:_validate(data)
	if validationError then
		return validationError
	end
	local metadataValidation = self:_validateSerialization(metadata)
	if not metadataValidation.ok then
		return metadataValidation
	end

	if mutationCount > 0 then
		self._data = data
		self._metadata = metadata
		self._dirty = true
		self._mutationVersion += mutationCount
		for _, change in changes do
			self.Changed:Fire(change.path, freezeCopy(change.newValue), freezeCopy(change.oldValue))
		end
	end
	return Result.ok(nil)
end

function Record:_saveOnce(release: boolean, deadline: number?): Result<nil>
	local mutationVersion = self._mutationVersion
	local dataSnapshot = DeepCopy(self._data)
	local metadataSnapshot = DeepCopy(self._metadata) :: { [string]: unknown }
	local validationError = self:_validate(dataSnapshot)
	if validationError then
		return validationError
	end
	local saved = self._store:_saveRecord(
		self.Key,
		self._owner,
		dataSnapshot,
		metadataSnapshot,
		release,
		deadline
	)
	if not saved.ok then
		if saved.error.code == "LeaseLost" then
			self:_setState("LeaseLost")
			self._store:_metric("lease_lost", 1)
			self._store:_log("error", "lease_lost", "record lease was lost during save")
		end
		return saved :: any
	end
	self._revision = saved.value.revision
	if self._mutationVersion == mutationVersion then
		self._dirty = false
	end
	self._store:_metric(if release then "record_closed_save" else "record_saved", 1)
	return Result.ok(nil)
end

function Record:SaveAsync(timeout: number?): Result<nil>
	local stateError = self:_requireWritable()
	if stateError then
		return stateError
	end
	if self._saving then
		self._saveRequested = true
		local waitFunction = self._store._config.wait :: (number) -> ()
		local clock = self._store._config.monotonicClock :: () -> number
		local deadline = if timeout ~= nil then clock() + math.max(0, timeout) else nil
		while self._saving do
			if deadline and clock() >= deadline then
				return Result.err(
					"Timeout",
					"timed out waiting for the active save",
					true,
					nil,
					nil,
					"Transient"
				)
			end
			waitFunction(0.03)
		end
		return self._lastSaveResult or Result.err("Cancelled", "save did not complete", true)
	end

	self._saving = true
	local clock = self._store._config.monotonicClock :: () -> number
	local deadline = if timeout ~= nil then clock() + math.max(0, timeout) else nil
	local result: Result<nil>
	repeat
		self._saveRequested = false
		result = self:_saveOnce(false, deadline)
	until not result.ok or not self._saveRequested
	self._lastSaveResult = result
	self._saving = false
	return result
end

function Record:CloseAsync(timeout: number?): Result<nil>
	if self._inTransaction then
		return Result.err("Conflict", "record cannot close during a transaction", false)
	end
	if self.State == "Closed" then
		return Result.ok(nil)
	end
	if self.State ~= "Active" and self.State ~= "LeaseLost" then
		return Result.err("NotLoaded", "only an active record can be closed", false)
	end

	self:_setState("Closing")
	self:_stopBackgroundTasks()
	if self._readOnly then
		self:_setState("Closed")
		self._store:_forgetRecord(self.Key)
		self.Changed:Destroy()
		self.LifecycleChanged:Destroy()
		return Result.ok(nil)
	end
	local clock = self._store._config.monotonicClock :: () -> number
	local deadline = clock() + math.max(0, timeout or (self._store._config.closeTimeout :: number))
	while self._saving do
		if clock() >= deadline then
			self:_setState("Active")
			self:_startBackgroundTasks()
			self._store:_metric("close_timeout", 1)
			return Result.err(
				"Timeout",
				"timed out waiting for the active save during close",
				true,
				nil,
				nil,
				"Transient"
			)
		end
		(self._store._config.wait :: (number) -> ())(0.03)
	end
	local result = self:_saveOnce(true, deadline)
	if not result.ok and result.error.code ~= "LeaseLost" then
		if result.error.code == "Timeout" then
			self._store:_metric("close_timeout", 1)
			self._store:_log("warn", "close_timeout", "record close deadline expired")
		end
		self:_setState("Active")
		self:_startBackgroundTasks()
		return result
	end

	self:_setState("Closed")
	self._store:_forgetRecord(self.Key)
	self.Changed:Destroy()
	self.LifecycleChanged:Destroy()
	return result
end

function Record:IsDirty(): boolean
	return self._dirty
end

function Record:GetRevision(): number
	return self._revision
end

function Record:IsReadOnly(): boolean
	return self._readOnly
end

return Record
