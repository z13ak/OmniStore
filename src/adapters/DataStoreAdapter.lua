--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Result = require(script.Parent.Parent.internal.Result)
local Types = require(script.Parent.Parent.Types)

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

local PERMANENT_PATTERNS = {
	"studio access to api services is not allowed",
	"api services rejected request",
	"not authorized",
	"permission denied",
	"http 403",
	"invalid argument",
}

local THROTTLED_PATTERNS = {
	"throttl",
	"too many requests",
	"http 429",
	"request was discarded",
}

local TRANSIENT_PATTERNS = {
	"timed out",
	"timeout",
	"http 500",
	"http 502",
	"http 503",
	"http 504",
	"connect fail",
	"service unavailable",
}

local function matchesAny(message: string, patterns: { string }): boolean
	for _, pattern in patterns do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	return false
end

function DataStoreAdapter.ClassifyError(cause: unknown): (Types.ErrorCategory, boolean)
	local message = string.lower(tostring(cause))
	if matchesAny(message, PERMANENT_PATTERNS) then
		return "Permanent", false
	end
	if matchesAny(message, THROTTLED_PATTERNS) then
		return "Throttled", true
	end
	if matchesAny(message, TRANSIENT_PATTERNS) then
		return "Transient", true
	end
	-- Roblox does not expose a stable structured error type for every DataStore failure. Unknown
	-- request failures remain retryable, but are bounded by the configured attempt/deadline policy.
	return "Unknown", true
end

export type DataStoreAdapter = typeof(setmetatable(
	{} :: {
		_dataStore: GlobalDataStore,
	},
	DataStoreAdapter
))

function DataStoreAdapter.new(name: string, scope: string?): DataStoreAdapter
	assert(RunService:IsServer(), "DataStoreAdapter can only be constructed on the server")
	assert(name ~= "", "DataStore name cannot be empty")
	return setmetatable({
		_dataStore = DataStoreService:GetDataStore(name, scope),
	}, DataStoreAdapter)
end

function DataStoreAdapter:Read(key: string): Types.Result<Types.StoredEnvelope?>
	local ok, value = pcall(function()
		return self._dataStore:GetAsync(key)
	end)
	if not ok then
		local category, retryable = DataStoreAdapter.ClassifyError(value)
		return Result.err(
			"PersistenceFailed",
			"DataStore GetAsync failed",
			retryable,
			value,
			nil,
			category
		)
	end
	return Result.ok(value :: Types.StoredEnvelope?)
end

function DataStoreAdapter:Update(
	key: string,
	transform: (Types.StoredEnvelope?) -> Types.StoredEnvelope?
): Types.Result<Types.StoredEnvelope?>
	local transformFailure: unknown? = nil
	local ok, value = pcall(function()
		return self._dataStore:UpdateAsync(key, function(current)
			local transformOk, transformed = pcall(transform, current)
			if not transformOk then
				transformFailure = transformed
				return nil
			end
			return transformed
		end)
	end)
	if transformFailure ~= nil then
		return Result.err(
			"PersistenceFailed",
			"persistence transform failed",
			false,
			transformFailure,
			nil,
			"Permanent"
		)
	end
	if not ok then
		local category, retryable = DataStoreAdapter.ClassifyError(value)
		return Result.err(
			"PersistenceFailed",
			"DataStore UpdateAsync failed",
			retryable,
			value,
			nil,
			category
		)
	end
	return Result.ok(value :: Types.StoredEnvelope?)
end

function DataStoreAdapter:Remove(key: string): Types.Result<nil>
	local ok, cause = pcall(function()
		self._dataStore:RemoveAsync(key)
	end)
	if not ok then
		local category, retryable = DataStoreAdapter.ClassifyError(cause)
		return Result.err(
			"PersistenceFailed",
			"DataStore RemoveAsync failed",
			retryable,
			cause,
			nil,
			category
		)
	end
	return Result.ok(nil)
end

function DataStoreAdapter:GetBudget(requestType: string): number?
	local enumValue = if requestType == "Remove"
		then Enum.DataStoreRequestType.SetIncrementAsync
		else if requestType == "Read"
			then Enum.DataStoreRequestType.GetAsync
			else Enum.DataStoreRequestType.UpdateAsync
	return DataStoreService:GetRequestBudgetForRequestType(enumValue)
end

return DataStoreAdapter
