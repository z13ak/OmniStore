--!strict

local DeepCopy = require(script.Parent.internal.DeepCopy)
local Migrate = require(script.Parent.internal.Migrate)
local Reconcile = require(script.Parent.internal.Reconcile)
local Record = require(script.Parent.Record)
local Result = require(script.Parent.internal.Result)
local Retry = require(script.Parent.internal.Retry)
local Scheduler = require(script.Parent.internal.Scheduler)
local Serializer = require(script.Parent.internal.Serializer)
local Types = require(script.Parent.Types)

type Result<T> = Types.Result<T>

local Store = {}
Store.__index = Store

local function isOptionalType(value: unknown, expected: string): boolean
	return value == nil or type(value) == expected
end

local function isStoredLease(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local lease = value :: any
	return type(lease.owner) == "string"
		and type(lease.expiresAt) == "number"
		and isOptionalType(lease.sessionId, "string")
		and isOptionalType(lease.jobId, "string")
		and isOptionalType(lease.placeId, "number")
		and isOptionalType(lease.universeId, "number")
		and isOptionalType(lease.acquiredAt, "number")
		and isOptionalType(lease.renewedAt, "number")
end

export type Store = typeof(setmetatable(
	{} :: {
		Name: string,
		_config: Types.StoreConfig,
		_keyPrefix: string,
		_owner: string,
		_session: Types.SessionIdentity,
		_records: { [string]: Record.Record },
		_closed: boolean,
		_scheduler: Scheduler.Scheduler,
	},
	Store
))

function Store.new(
	name: string,
	config: Types.StoreConfig,
	keyPrefix: string,
	session: Types.SessionIdentity
): Store
	local self = setmetatable({
		Name = name,
		_config = config,
		_keyPrefix = keyPrefix,
		_owner = session.owner,
		_session = session,
		_records = {},
		_closed = false,
		_scheduler = nil :: any,
	}, Store)
	self._scheduler = Scheduler.new(
		config.monotonicClock :: () -> number,
		config.backgroundTick :: number,
		config.maxConcurrentBackgroundTasks :: number,
		function()
			self:_metric("background_saturated", 1)
			self:_log(
				"warn",
				"background_saturated",
				"background persistence concurrency limit reached"
			)
		end,
		function(cause)
			self:_metric("background_job_error", 1)
			self:_log("error", "background_job_error", "background persistence job failed", {
				cause = tostring(cause),
			})
		end
	)
	return self
end

function Store:_log(
	level: Types.DiagnosticLevel,
	event: string,
	message: string,
	context: { [string]: unknown }?
)
	local logger = self._config.logger
	if not logger then
		return
	end
	pcall(logger, {
		level = level,
		event = event,
		message = message,
		timestamp = (self._config.clock :: () -> number)(),
		context = context,
	})
end

function Store:_metric(name: string, value: number, tags: { [string]: string }?)
	local metrics = self._config.metrics
	if not metrics then
		return
	end
	local combinedTags: { [string]: string } = { store = self.Name }
	if tags then
		for key, tagValue in tags do
			combinedTags[key] = tagValue
		end
	end
	pcall(metrics, { name = name, value = value, tags = combinedTags })
end

function Store:_scheduleBackground(delay: number, callback: () -> number?): Scheduler.Job
	return self._scheduler:Schedule(delay, callback)
end

function Store:_makeLease(now: number, current: Types.StoredLease?): Types.StoredLease
	local session = self._session
	return {
		owner = session.owner,
		sessionId = session.sessionId,
		jobId = session.jobId,
		placeId = session.placeId,
		universeId = session.universeId,
		acquiredAt = if current and current.owner == session.owner
			then current.acquiredAt or now
			else now,
		renewedAt = now,
		expiresAt = now + (self._config.lease :: Types.LeaseConfig).duration,
	}
end

function Store:_normalizeKey(key: string | number): Result<string>
	local raw = tostring(key)
	local normalized = self._keyPrefix .. raw
	if raw == "" or #normalized > 50 or string.find(normalized, "[%c]") then
		return Result.err(
			"InvalidKey",
			"record key must be non-empty, contain no control characters, and be at most 50 bytes with prefix",
			false
		)
	end
	return Result.ok(normalized)
end

function Store:_waitForBudget(requestType: string, deadline: number?): Result<nil>
	local adapter = self._config.adapter :: Types.Adapter
	local waitFunction = self._config.wait :: (number) -> ()
	local clock = self._config.monotonicClock :: () -> number
	local budgetDeadline = clock() + (self._config.requestBudgetTimeout :: number)
	if deadline then
		budgetDeadline = math.min(budgetDeadline, deadline)
	end
	while true do
		local budget = adapter:GetBudget(requestType)
		if budget == nil or budget >= 1 then
			return Result.ok(nil)
		end
		if clock() >= budgetDeadline then
			self:_metric("request_budget_timeout", 1, { operation = requestType })
			self:_log("warn", "request_budget_timeout", "request budget wait timed out", {
				operation = requestType,
			})
			return Result.err(
				"Timeout",
				`timed out waiting for {requestType} request budget`,
				true,
				nil,
				{ operation = requestType },
				"Throttled"
			)
		end
		waitFunction(math.min(0.25, math.max(0, budgetDeadline - clock())))
	end
end

function Store:_update(
	key: string,
	transform: (Types.StoredEnvelope?) -> Types.StoredEnvelope?,
	deadline: number?
): Result<Types.StoredEnvelope?>
	local monotonicClock = self._config.monotonicClock :: () -> number
	if deadline and monotonicClock() >= deadline then
		return Result.err(
			"Timeout",
			"persistence operation deadline expired",
			true,
			nil,
			nil,
			"Transient"
		)
	end
	local budget = self:_waitForBudget("Update", deadline)
	if not budget.ok then
		return budget :: any
	end
	local adapter = self._config.adapter :: Types.Adapter
	local result = Retry.run(
		function()
			return adapter:Update(key, transform)
		end,
		self._config.retry :: Types.RetryConfig,
		self._config.wait :: (number) -> (),
		self._config.random :: Random,
		{
			clock = self._config.monotonicClock,
			deadline = deadline,
			onRetry = function(errorValue, attempt, delay)
				self:_metric("persistence_retry", 1, {
					category = errorValue.category or "Unknown",
					operation = "Update",
				})
				self:_log("warn", "persistence_retry", "retrying persistence update", {
					attempt = attempt,
					delay = delay,
					errorCode = errorValue.code,
					category = errorValue.category or "Unknown",
				})
			end,
		}
	)
	if not result.ok then
		self:_metric("persistence_failure", 1, {
			category = result.error.category or "Unknown",
			operation = "Update",
		})
		self:_log("error", "persistence_failure", "persistence update failed", {
			errorCode = result.error.code,
			category = result.error.category or "Unknown",
		})
	end
	return result
end

function Store:_read(key: string, deadline: number?): Result<Types.StoredEnvelope?>
	local clock = self._config.monotonicClock :: () -> number
	if deadline and clock() >= deadline then
		return Result.err(
			"Timeout",
			"persistence operation deadline expired",
			true,
			nil,
			nil,
			"Transient"
		)
	end
	local budget = self:_waitForBudget("Read", deadline)
	if not budget.ok then
		return budget :: any
	end
	local adapter = self._config.adapter :: Types.Adapter
	local result = Retry.run(
		function()
			return adapter:Read(key)
		end,
		self._config.retry :: Types.RetryConfig,
		self._config.wait :: (number) -> (),
		self._config.random :: Random,
		{
			clock = clock,
			deadline = deadline,
			onRetry = function(errorValue, attempt, delay)
				self:_metric("persistence_retry", 1, {
					category = errorValue.category or "Unknown",
					operation = "Read",
				})
				self:_log("warn", "persistence_retry", "retrying persistence read", {
					attempt = attempt,
					delay = delay,
					errorCode = errorValue.code,
					category = errorValue.category or "Unknown",
				})
			end,
		}
	)
	if not result.ok then
		self:_metric("persistence_failure", 1, {
			category = result.error.category or "Unknown",
			operation = "Read",
		})
		self:_log("error", "persistence_failure", "persistence read failed", {
			errorCode = result.error.code,
			category = result.error.category or "Unknown",
		})
	end
	return result
end

function Store:_validate(data: unknown): Types.Failure?
	local schema = self._config.schema
	if schema then
		local callOk, valid, message = pcall(schema.Validate, schema, DeepCopy(data), "$")
		if not callOk then
			return Result.err("ValidationFailed", "schema validator threw an error", false, valid)
		end
		if not valid then
			return Result.err("ValidationFailed", message or "schema validation failed", false)
		end
	end
	local validator = self._config.validate
	if validator then
		local callOk, valid, message = pcall(validator, DeepCopy(data))
		if not callOk then
			return Result.err("ValidationFailed", "schema validator threw an error", false, valid)
		end
		if not valid then
			return Result.err("ValidationFailed", message or "schema validation failed", false)
		end
	end
	local encoded = self:_encodeData(data)
	if not encoded.ok then
		return encoded
	end
	local serialization = self:_validateSerialization(encoded.value)
	if not serialization.ok then
		return serialization
	end
	return nil
end

function Store:_encodeData(data: unknown): Result<unknown>
	local codecs = self._config.codecs
	if codecs then
		return codecs:Encode(data)
	end
	return Result.ok(data)
end

function Store:_decodeData(data: unknown): Result<unknown>
	local codecs = self._config.codecs
	if codecs then
		return codecs:Decode(data)
	end
	return Result.ok(data)
end

function Store:_validateSerialization(value: unknown): Types.Result<nil>
	return Serializer.validate(value, {
		maxDepth = self._config.maxSerializationDepth,
		maxPayloadBytes = self._config.maxPayloadBytes,
	})
end

function Store:_prepareData(envelope: Types.StoredEnvelope?): Result<Types.StoredEnvelope>
	local config = self._config
	local clock = config.clock :: () -> number
	local targetVersion = config.schemaVersion :: number
	if config.template ~= nil then
		local templateValidation = self:_validate(config.template)
		if templateValidation then
			return templateValidation
		end
	end
	if envelope == nil then
		local initialData = DeepCopy(if config.template == nil then {} else config.template)
		local initialMetadata = DeepCopy(config.metadata or {}) :: { [string]: unknown }
		local validationError = self:_validate(initialData)
		if validationError then
			return validationError
		end
		local metadataValidation = self:_validateSerialization(initialMetadata)
		if not metadataValidation.ok then
			return metadataValidation :: any
		end
		return Result.ok({
			data = initialData,
			metadata = initialMetadata,
			typeId = if config.model then config.model.typeId else nil,
			schemaVersion = targetVersion,
			revision = 0,
			updatedAt = clock(),
			lease = nil,
		})
	end

	if
		type(envelope.metadata) ~= "table"
		or (envelope.typeId ~= nil and type(envelope.typeId) ~= "string")
		or type(envelope.schemaVersion) ~= "number"
		or type(envelope.revision) ~= "number"
		or type(envelope.updatedAt) ~= "number"
		or (envelope.lease ~= nil and not isStoredLease(envelope.lease))
	then
		return Result.err("InvalidData", "stored envelope is malformed", false)
	end
	local model = config.model
	if model then
		if envelope.typeId == nil and not model.allowLegacy then
			return Result.err("InvalidData", "stored record has no model typeId", false, nil, {
				expectedTypeId = model.typeId,
			})
		end
		if envelope.typeId ~= nil and envelope.typeId ~= model.typeId then
			return Result.err(
				"InvalidData",
				"stored record model typeId does not match",
				false,
				nil,
				{
					expectedTypeId = model.typeId,
					actualTypeId = envelope.typeId,
				}
			)
		end
	elseif envelope.typeId ~= nil then
		return Result.err("InvalidData", "stored record requires a configured model", false, nil, {
			actualTypeId = envelope.typeId,
		})
	end
	if envelope.schemaVersion > targetVersion then
		return Result.err(
			"MigrationFailed",
			`stored schema version {envelope.schemaVersion} is newer than configured version {targetVersion}`,
			false
		)
	end
	local storedDataValidation = self:_validateSerialization(envelope.data)
	if not storedDataValidation.ok then
		return storedDataValidation :: any
	end

	local decoded = self:_decodeData(envelope.data)
	if not decoded.ok then
		return decoded :: any
	end
	local data = DeepCopy(decoded.value)
	if envelope.schemaVersion < targetVersion then
		local migrated = Migrate.run(
			data,
			envelope.schemaVersion,
			targetVersion,
			config.migrations :: { Types.Migration },
			function(stepData)
				local encodedStep = self:_encodeData(stepData)
				if not encodedStep.ok then
					return encodedStep
				end
				local serializedStep = self:_validateSerialization(encodedStep.value)
				if not serializedStep.ok then
					return serializedStep
				end
				return nil
			end
		)
		if not migrated.ok then
			return migrated :: any
		end
		data = migrated.value
	end
	if config.reconcile and config.template ~= nil then
		data = Reconcile(data, config.template)
	end
	local validationError = self:_validate(data)
	if validationError then
		return validationError
	end
	local metadataValidation = self:_validateSerialization(envelope.metadata)
	if not metadataValidation.ok then
		return metadataValidation :: any
	end

	return Result.ok({
		data = data,
		metadata = DeepCopy(envelope.metadata) :: { [string]: unknown },
		typeId = if model then model.typeId else nil,
		schemaVersion = targetVersion,
		revision = envelope.revision,
		updatedAt = envelope.updatedAt,
		lease = envelope.lease,
	})
end

function Store:_loadRecord(
	key: string,
	owner: string,
	operationDeadline: number?,
	staleLeasePolicy: Types.StaleLeasePolicy
): Result<Types.StoredEnvelope>
	local config = self._config
	local lease = config.lease :: Types.LeaseConfig
	local clock = config.clock :: () -> number
	local waitFunction = config.wait :: (number) -> ()
	local leaseDeadline = clock() + lease.acquireTimeout
	local monotonicClock = config.monotonicClock :: () -> number

	repeat
		local blocked = false
		local staleRejected = false
		local staleRecovered = false
		local preparationFailure: Types.Failure? = nil
		local updated = self:_update(key, function(current)
			local now = clock()
			local prepared = self:_prepareData(current)
			if not prepared.ok then
				preparationFailure = prepared
				return nil
			end
			local nextEnvelope = prepared.value
			if lease.enabled and nextEnvelope.lease and nextEnvelope.lease.owner ~= owner then
				if nextEnvelope.lease.expiresAt + lease.stealAfter > now then
					blocked = true
					return nil
				end
				if staleLeasePolicy == "Reject" then
					staleRejected = true
					return nil
				end
				staleRecovered = true
			end
			if lease.enabled then
				nextEnvelope.lease = self:_makeLease(now, nextEnvelope.lease)
			else
				nextEnvelope.lease = nil
			end
			nextEnvelope.updatedAt = now
			local encodedData = self:_encodeData(nextEnvelope.data)
			if not encodedData.ok then
				preparationFailure = encodedData
				return nil
			end
			local storedEnvelope = table.clone(nextEnvelope)
			storedEnvelope.data = encodedData.value
			local envelopeValidation = self:_validateSerialization(storedEnvelope)
			if not envelopeValidation.ok then
				preparationFailure = envelopeValidation
				return nil
			end
			return storedEnvelope
		end, operationDeadline)

		if preparationFailure then
			return preparationFailure
		end
		if not updated.ok then
			return updated :: any
		end
		if staleRejected then
			return Result.err(
				"Locked",
				"record has an expired foreign lease and recovery is disabled",
				false,
				nil,
				{ stale = true, policy = "Reject" }
			)
		end
		if not blocked and updated.value then
			if staleRecovered then
				self:_metric("stale_lease_recovered", 1)
				self:_log("warn", "stale_lease_recovered", "expired foreign lease was recovered")
			end
			return self:_prepareData(updated.value)
		end
		if
			not lease.enabled
			or clock() >= leaseDeadline
			or (operationDeadline ~= nil and monotonicClock() >= operationDeadline)
		then
			if operationDeadline ~= nil and monotonicClock() >= operationDeadline then
				return Result.err(
					"Timeout",
					"record load deadline expired",
					true,
					nil,
					{ operation = "Load" },
					"Transient"
				)
			end
			return Result.err("Locked", "record is owned by another live session", true, nil, {
				key = key,
			})
		end
		local delay = math.min(1, math.max(0.05, leaseDeadline - clock()))
		if operationDeadline ~= nil then
			delay = math.min(delay, math.max(0, operationDeadline - monotonicClock()))
		end
		waitFunction(delay)
	until false
end

function Store:_readRecord(key: string, deadline: number?): Result<Types.StoredEnvelope>
	local read = self:_read(key, deadline)
	if not read.ok then
		return read :: any
	end
	if read.value == nil then
		return Result.err("NotFound", "record does not exist", false)
	end
	return self:_prepareData(read.value)
end

function Store:_saveRecord(
	key: string,
	owner: string,
	data: unknown,
	metadata: { [string]: unknown },
	release: boolean,
	deadline: number?
): Result<Types.StoredEnvelope>
	local config = self._config
	local lease = config.lease :: Types.LeaseConfig
	local clock = config.clock :: () -> number
	local validationError = self:_validate(data)
	if validationError then
		return validationError
	end
	local encodedData = self:_encodeData(data)
	if not encodedData.ok then
		return encodedData :: any
	end
	local envelopeValidation = self:_validateSerialization({
		data = encodedData.value,
		metadata = metadata,
		typeId = if config.model then config.model.typeId else nil,
		schemaVersion = config.schemaVersion,
		revision = 0,
		updatedAt = clock(),
		lease = if lease.enabled and not release then self:_makeLease(clock(), nil) else nil,
	})
	if not envelopeValidation.ok then
		return envelopeValidation :: any
	end
	local lostLease = false
	local missing = false
	local updated = self:_update(key, function(current)
		if not current then
			missing = true
			return nil
		end
		if lease.enabled and (not current.lease or current.lease.owner ~= owner) then
			lostLease = true
			return nil
		end
		local now = clock()
		return {
			data = DeepCopy(encodedData.value),
			metadata = DeepCopy(metadata) :: { [string]: unknown },
			typeId = if config.model then config.model.typeId else nil,
			schemaVersion = config.schemaVersion :: number,
			revision = current.revision + 1,
			updatedAt = now,
			lease = if lease.enabled and not release
				then self:_makeLease(now, current.lease)
				else nil,
		}
	end, deadline)
	if lostLease then
		return Result.err("LeaseLost", "record lease belongs to another session", false)
	end
	if missing then
		return Result.err("Conflict", "record disappeared before save", false)
	end
	if not updated.ok then
		return updated :: any
	end
	if not updated.value then
		return Result.err("PersistenceFailed", "save produced no stored value", true)
	end
	return Result.ok(updated.value)
end

function Store:_renewRecord(key: string, owner: string): Result<Types.StoredEnvelope>
	local lease = self._config.lease :: Types.LeaseConfig
	if not lease.enabled then
		return Result.err("InvalidConfig", "leases are disabled", false)
	end
	local lostLease = false
	local clock = self._config.clock :: () -> number
	local updated = self:_update(key, function(current)
		if not current or not current.lease or current.lease.owner ~= owner then
			lostLease = true
			return nil
		end
		current.lease = self:_makeLease(clock(), current.lease)
		return current
	end)
	if lostLease then
		return Result.err("LeaseLost", "record lease could not be renewed", false)
	end
	if not updated.ok then
		return updated :: any
	end
	if not updated.value then
		return Result.err("PersistenceFailed", "lease renewal produced no value", true)
	end
	return Result.ok(updated.value)
end

function Store:LoadAsync(
	key: string | number,
	options: number | Types.LoadOptions?
): Result<Record.Record>
	if self._closed then
		return Result.err("Closed", "store is closed", false)
	end
	local normalized = self:_normalizeKey(key)
	if not normalized.ok then
		return normalized :: any
	end
	local loadOptions: Types.LoadOptions = if type(options) == "number"
		then { timeout = options }
		else options or {}
	local mode: Types.LoadMode = loadOptions.mode or "Exclusive"
	local staleLeasePolicy = loadOptions.staleLeasePolicy
		or (self._config.lease :: Types.LeaseConfig).staleLeasePolicy
	if mode ~= "Exclusive" and mode ~= "ReadOnly" then
		return Result.err("InvalidConfig", "load mode must be Exclusive or ReadOnly", false)
	end
	if staleLeasePolicy ~= "Recover" and staleLeasePolicy ~= "Reject" then
		return Result.err("InvalidConfig", "stale lease policy must be Recover or Reject", false)
	end
	if loadOptions.timeout ~= nil and loadOptions.timeout < 0 then
		return Result.err("InvalidConfig", "load timeout cannot be negative", false)
	end
	local existing = self._records[normalized.value]
	if existing then
		if existing.State == "Active" and existing:IsReadOnly() == (mode == "ReadOnly") then
			return Result.ok(existing)
		end
		return Result.err(
			"Conflict",
			`record already exists in state {existing.State} or a different load mode`,
			false
		)
	end

	local record = Record.new(self :: any, normalized.value, self._owner, mode == "ReadOnly")
	self._records[normalized.value] = record
	local loaded = record:LoadAsync(loadOptions.timeout, staleLeasePolicy)
	if not loaded.ok then
		self._records[normalized.value] = nil
	end
	if loaded.ok then
		self:_metric("record_loaded", 1)
	else
		self:_log("error", "record_load_failed", "record load failed", {
			errorCode = loaded.error.code,
			category = loaded.error.category or "Unknown",
		})
	end
	return loaded
end

function Store:GetSessionInfo(): Types.SessionIdentity
	return table.clone(self._session)
end

function Store:GetLoadedRecord(key: string | number): Record.Record?
	local normalized = self:_normalizeKey(key)
	if not normalized.ok then
		return nil
	end
	return self._records[normalized.value]
end

function Store:_forgetRecord(key: string)
	self._records[key] = nil
end

function Store:DeleteAsync(key: string | number, timeout: number?): Result<nil>
	if self._closed then
		return Result.err("Closed", "store is closed", false)
	end
	local normalized = self:_normalizeKey(key)
	if not normalized.ok then
		return normalized :: any
	end
	if self._records[normalized.value] then
		return Result.err("Conflict", "close the loaded record before deleting it", false)
	end
	local clock = self._config.monotonicClock :: () -> number
	local deadline = if timeout ~= nil then clock() + math.max(0, timeout) else nil
	local budget = self:_waitForBudget("Remove", deadline)
	if not budget.ok then
		return budget
	end
	local adapter = self._config.adapter :: Types.Adapter
	local result = Retry.run(
		function()
			return adapter:Remove(normalized.value)
		end,
		self._config.retry :: Types.RetryConfig,
		self._config.wait :: (number) -> (),
		self._config.random :: Random,
		{
			clock = clock,
			deadline = deadline,
			onRetry = function(errorValue, attempt, delay)
				self:_metric("persistence_retry", 1, {
					category = errorValue.category or "Unknown",
					operation = "Remove",
				})
				self:_log("warn", "persistence_retry", "retrying persistence removal", {
					attempt = attempt,
					delay = delay,
					errorCode = errorValue.code,
					category = errorValue.category or "Unknown",
				})
			end,
		}
	)
	if not result.ok then
		self:_metric("persistence_failure", 1, {
			category = result.error.category or "Unknown",
			operation = "Remove",
		})
		self:_log("error", "persistence_failure", "persistence removal failed", {
			errorCode = result.error.code,
			category = result.error.category or "Unknown",
		})
	end
	return result
end

function Store:CloseRecordAsync(key: string | number, timeout: number?): Result<nil>
	local record = self:GetLoadedRecord(key)
	if not record then
		return Result.ok(nil)
	end
	return record:CloseAsync(timeout)
end

function Store:CloseAsync(timeout: number?): Result<nil>
	if self._closed then
		return Result.ok(nil)
	end
	local clock = self._config.monotonicClock :: () -> number
	local deadline = clock() + math.max(0, timeout or (self._config.closeTimeout :: number))
	local firstFailure: Types.Failure? = nil
	local records = {}
	for _, record in self._records do
		table.insert(records, record)
	end
	for _, record in records do
		local remaining = math.max(0, deadline - clock())
		local closed = record:CloseAsync(remaining)
		if not closed.ok and not firstFailure then
			firstFailure = closed
		end
	end
	if firstFailure then
		return firstFailure
	end
	self._closed = true
	self._scheduler:Close()
	return Result.ok(nil)
end

return Store
