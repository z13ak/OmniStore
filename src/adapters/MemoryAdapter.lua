--!strict

local DeepCopy = require(script.Parent.Parent.internal.DeepCopy)
local Result = require(script.Parent.Parent.internal.Result)
local Types = require(script.Parent.Parent.Types)

type FailurePlan = {
	remaining: number,
	message: string,
	retryable: boolean,
	category: Types.ErrorCategory,
}

local MemoryAdapter = {}
MemoryAdapter.__index = MemoryAdapter

export type MemoryAdapter = typeof(setmetatable(
	{} :: {
		_values: { [string]: Types.StoredEnvelope },
		_failures: { [string]: FailurePlan },
	},
	MemoryAdapter
))

function MemoryAdapter.new(seed: { [string]: Types.StoredEnvelope }?): MemoryAdapter
	return setmetatable({
		_values = (DeepCopy(seed or {}) :: any) :: { [string]: Types.StoredEnvelope },
		_failures = {},
	}, MemoryAdapter)
end

function MemoryAdapter:SetFailurePlan(
	operation: string,
	count: number,
	message: string?,
	retryable: boolean?,
	category: Types.ErrorCategory?
)
	self._failures[operation] = {
		remaining = count,
		message = message or "injected adapter failure",
		retryable = retryable ~= false,
		category = category or if retryable == false then "Permanent" else "Transient",
	}
end

function MemoryAdapter:_shouldFail(operation: string): FailurePlan?
	local plan = self._failures[operation]
	if plan and plan.remaining > 0 then
		plan.remaining -= 1
		return plan
	end
	return nil
end

function MemoryAdapter:Read(key: string): Types.Result<Types.StoredEnvelope?>
	local failure = self:_shouldFail("Read")
	if failure then
		return Result.err(
			"PersistenceFailed",
			failure.message,
			failure.retryable,
			nil,
			nil,
			failure.category
		)
	end
	return Result.ok(DeepCopy(self._values[key]) :: Types.StoredEnvelope?)
end

function MemoryAdapter:Update(
	key: string,
	transform: (Types.StoredEnvelope?) -> Types.StoredEnvelope?
): Types.Result<Types.StoredEnvelope?>
	local failure = self:_shouldFail("Update")
	if failure then
		return Result.err(
			"PersistenceFailed",
			failure.message,
			failure.retryable,
			nil,
			nil,
			failure.category
		)
	end

	local current = DeepCopy(self._values[key]) :: Types.StoredEnvelope?
	local ok, nextValue = pcall(transform, current)
	if not ok then
		return Result.err("PersistenceFailed", "adapter transform failed", false, nextValue)
	end
	if nextValue == nil then
		return Result.ok(current)
	end
	self._values[key] = DeepCopy(nextValue) :: Types.StoredEnvelope
	return Result.ok(DeepCopy(nextValue) :: Types.StoredEnvelope)
end

function MemoryAdapter:Remove(key: string): Types.Result<nil>
	local failure = self:_shouldFail("Remove")
	if failure then
		return Result.err(
			"PersistenceFailed",
			failure.message,
			failure.retryable,
			nil,
			nil,
			failure.category
		)
	end
	self._values[key] = nil
	return Result.ok(nil)
end

function MemoryAdapter:GetBudget(_requestType: string): number?
	return math.huge
end

function MemoryAdapter:Peek(key: string): Types.StoredEnvelope?
	return DeepCopy(self._values[key]) :: Types.StoredEnvelope?
end

return MemoryAdapter
