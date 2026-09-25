--!strict

local Types = require(script.Parent.Parent.Types)

local Config = {}

local DEFAULT_RETRY: Types.RetryConfig = {
	maxAttempts = 5,
	baseDelay = 0.5,
	maxDelay = 8,
	jitter = 0.25,
}

local DEFAULT_LEASE: Types.LeaseConfig = {
	enabled = true,
	duration = 120,
	renewInterval = 40,
	acquireTimeout = 30,
	stealAfter = 0,
	staleLeasePolicy = "Recover",
}

local function mergeRetry(
	base: Types.RetryOptions?,
	override: Types.RetryOptions?
): Types.RetryConfig
	local baseValue = base or {}
	local value = override or {}
	return {
		maxAttempts = value.maxAttempts or baseValue.maxAttempts or DEFAULT_RETRY.maxAttempts,
		baseDelay = value.baseDelay or baseValue.baseDelay or DEFAULT_RETRY.baseDelay,
		maxDelay = value.maxDelay or baseValue.maxDelay or DEFAULT_RETRY.maxDelay,
		jitter = value.jitter or baseValue.jitter or DEFAULT_RETRY.jitter,
	}
end

local function mergeLease(
	base: Types.LeaseOptions?,
	override: Types.LeaseOptions?
): Types.LeaseConfig
	local baseValue = base or {}
	local value = override or {}
	return {
		enabled = if value.enabled ~= nil
			then value.enabled
			else if baseValue.enabled ~= nil then baseValue.enabled else DEFAULT_LEASE.enabled,
		duration = value.duration or baseValue.duration or DEFAULT_LEASE.duration,
		renewInterval = value.renewInterval
			or baseValue.renewInterval
			or DEFAULT_LEASE.renewInterval,
		acquireTimeout = value.acquireTimeout
			or baseValue.acquireTimeout
			or DEFAULT_LEASE.acquireTimeout,
		stealAfter = value.stealAfter or baseValue.stealAfter or DEFAULT_LEASE.stealAfter,
		staleLeasePolicy = value.staleLeasePolicy
			or baseValue.staleLeasePolicy
			or DEFAULT_LEASE.staleLeasePolicy,
	}
end

function Config.store(defaults: Types.StoreConfig?, override: Types.StoreConfig?): Types.StoreConfig
	local base = defaults or {}
	local value = override or {}
	local model = value.model or base.model
	return {
		adapter = value.adapter or base.adapter,
		model = model,
		schema = value.schema or if model then model.schema else base.schema,
		codecs = value.codecs or if model then model.codecs else base.codecs,
		template = if value.template ~= nil
			then value.template
			else if model and model.template ~= nil then model.template else base.template,
		validate = value.validate or base.validate,
		reconcile = if value.reconcile ~= nil
			then value.reconcile
			else if base.reconcile ~= nil then base.reconcile else true,
		schemaVersion = value.schemaVersion
			or if model then model.version else base.schemaVersion or 1,
		migrations = value.migrations or if model then model.migrations else base.migrations or {},
		autosaveInterval = value.autosaveInterval or base.autosaveInterval or 60,
		autosaveJitter = value.autosaveJitter or base.autosaveJitter or 10,
		maxConcurrentBackgroundTasks = value.maxConcurrentBackgroundTasks
			or base.maxConcurrentBackgroundTasks
			or 4,
		backgroundTick = value.backgroundTick or base.backgroundTick or 0.25,
		requestBudgetTimeout = value.requestBudgetTimeout or base.requestBudgetTimeout or 10,
		closeTimeout = value.closeTimeout or base.closeTimeout or 25,
		maxSerializationDepth = value.maxSerializationDepth or base.maxSerializationDepth or 64,
		maxPayloadBytes = value.maxPayloadBytes or base.maxPayloadBytes or 4_000_000,
		retry = mergeRetry(base.retry, value.retry),
		lease = mergeLease(base.lease, value.lease),
		metadata = value.metadata or base.metadata or {},
		clock = value.clock or base.clock or os.time,
		monotonicClock = value.monotonicClock or base.monotonicClock or os.clock,
		wait = value.wait or base.wait or task.wait,
		random = value.random or base.random or Random.new(),
		logger = value.logger or base.logger,
		metrics = value.metrics or base.metrics,
	}
end

function Config.validateStore(config: Types.StoreConfig): (boolean, string?)
	if not config.adapter then
		return false, "an adapter is required"
	end
	local adapter = config.adapter :: any
	if
		type(adapter.Read) ~= "function"
		or type(adapter.Update) ~= "function"
		or type(adapter.Remove) ~= "function"
		or type(adapter.GetBudget) ~= "function"
	then
		return false, "adapter must implement Read, Update, Remove, and GetBudget"
	end
	if config.schema and type((config.schema :: any).Validate) ~= "function" then
		return false, "schema must implement Validate"
	end
	if
		config.codecs
		and (
			type((config.codecs :: any).Encode) ~= "function"
			or type((config.codecs :: any).Decode) ~= "function"
		)
	then
		return false, "codecs must implement Encode and Decode"
	end
	if config.model and config.schemaVersion ~= config.model.version then
		return false, "schemaVersion cannot differ from model version"
	end
	if (config.schemaVersion :: number) < 1 then
		return false, "schemaVersion must be at least 1"
	end
	if (config.schemaVersion :: number) % 1 ~= 0 then
		return false, "schemaVersion must be an integer"
	end
	if (config.autosaveInterval :: number) < 0 or (config.autosaveJitter :: number) < 0 then
		return false, "autosave interval and jitter cannot be negative"
	end
	if
		(config.maxConcurrentBackgroundTasks :: number) < 1
		or (config.maxConcurrentBackgroundTasks :: number) % 1 ~= 0
	then
		return false, "maxConcurrentBackgroundTasks must be a positive integer"
	end
	if
		(config.backgroundTick :: number) <= 0
		or (config.requestBudgetTimeout :: number) < 0
		or (config.closeTimeout :: number) < 0
	then
		return false, "backgroundTick must be positive and timeout values cannot be negative"
	end
	if
		(config.maxSerializationDepth :: number) < 1
		or (config.maxSerializationDepth :: number) % 1 ~= 0
	then
		return false, "maxSerializationDepth must be a positive integer"
	end
	if (config.maxPayloadBytes :: number) < 1 then
		return false, "maxPayloadBytes must be positive"
	end
	local lease = config.lease :: Types.LeaseConfig
	if
		lease.enabled
		and (
			lease.duration <= 0
			or lease.renewInterval <= 0
			or lease.acquireTimeout < 0
			or lease.stealAfter < 0
		)
	then
		return false, "lease duration and renewInterval must be positive"
	end
	if lease.enabled and lease.renewInterval >= lease.duration then
		return false, "lease renewInterval must be shorter than duration"
	end
	if lease.staleLeasePolicy ~= "Recover" and lease.staleLeasePolicy ~= "Reject" then
		return false, "lease staleLeasePolicy must be Recover or Reject"
	end
	local retry = config.retry :: Types.RetryConfig
	if
		retry.maxAttempts < 1
		or retry.maxAttempts % 1 ~= 0
		or retry.baseDelay < 0
		or retry.maxDelay < retry.baseDelay
		or retry.jitter < 0
		or retry.jitter > 1
	then
		return false, "retry configuration is invalid"
	end
	for _, migration in config.migrations :: { Types.Migration } do
		if
			migration.from < 1
			or migration.to <= migration.from
			or migration.from % 1 ~= 0
			or migration.to % 1 ~= 0
		then
			return false, "migration versions must be positive increasing integers"
		end
	end
	return true, nil
end

return Config
