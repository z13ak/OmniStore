--!strict

local DeepCopy = require(script.Parent.DeepCopy)
local NoYield = require(script.Parent.NoYield)
local Path = require(script.Parent.Path)
local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Types)

type PathValue = Types.Path
type Result<T> = Types.Result<T>

export type Change = {
	path: PathValue,
	newValue: unknown,
	oldValue: unknown,
}

local TransactionDraft = {}
TransactionDraft.__index = TransactionDraft

export type TransactionDraft = typeof(setmetatable(
	{} :: {
		_data: unknown,
		_metadata: { [string]: unknown },
		_changes: { Change },
		_mutationCount: number,
		_validateValue: (unknown) -> Types.Failure?,
		_failure: Types.Failure?,
	},
	TransactionDraft
))

local function freezeCopy(value: unknown): unknown
	local copy = DeepCopy(value)
	if type(copy) == "table" then
		table.freeze(copy :: table)
	end
	return copy
end

function TransactionDraft.new(
	data: unknown,
	metadata: { [string]: unknown },
	validateValue: (unknown) -> Types.Failure?
): TransactionDraft
	return setmetatable({
		_data = DeepCopy(data),
		_metadata = DeepCopy(metadata) :: { [string]: unknown },
		_changes = {},
		_mutationCount = 0,
		_validateValue = validateValue,
		_failure = nil,
	}, TransactionDraft)
end

function TransactionDraft:_fail(failure: Types.Failure): Types.Failure
	if not self._failure then
		self._failure = failure
	end
	return failure
end

function TransactionDraft:GetData(): Result<unknown>
	return Result.ok(freezeCopy(self._data))
end

function TransactionDraft:Get(path: PathValue): Result<unknown>
	return Result.ok(freezeCopy(Path.get(self._data, Path.parse(path))))
end

function TransactionDraft:_markChanged(path: PathValue, newValue: unknown, oldValue: unknown)
	self._mutationCount += 1
	table.insert(self._changes, {
		path = DeepCopy(path) :: PathValue,
		newValue = DeepCopy(newValue),
		oldValue = DeepCopy(oldValue),
	})
end

function TransactionDraft:Set(path: PathValue, value: unknown): Result<unknown>
	local valueFailure = self._validateValue(value)
	if valueFailure then
		return self:_fail(valueFailure)
	end
	local segments = Path.parse(path)
	if #segments == 0 then
		local oldValue = self._data
		self._data = DeepCopy(value)
		self:_markChanged(path, value, oldValue)
		return Result.ok(freezeCopy(value))
	end

	local dataSnapshot = DeepCopy(self._data)
	local parent, key = Path.parent(self._data, segments, value ~= nil)
	if not parent or key == nil then
		self._data = dataSnapshot
		if value == nil then
			return Result.ok(nil)
		end
		return self:_fail(Result.err("InvalidData", "path traverses a non-table value", false))
	end
	local parentAny = parent :: any
	local oldValue = parentAny[key]
	parentAny[key] = DeepCopy(value)
	self:_markChanged(path, value, oldValue)
	return Result.ok(freezeCopy(value))
end

function TransactionDraft:Increment(path: PathValue, amount: number?): Result<number>
	local current = self:Get(path)
	if current.value ~= nil and type(current.value) ~= "number" then
		return self:_fail(
			Result.err("InvalidData", "Increment target must be a number or nil", false)
		) :: any
	end
	local nextValue = ((current.value :: number?) or 0) + (amount or 1)
	local setResult = self:Set(path, nextValue)
	if not setResult.ok then
		return setResult :: any
	end
	return Result.ok(nextValue)
end

function TransactionDraft:Update(path: PathValue, updater: (unknown) -> unknown): Result<unknown>
	local current = self:Get(path)
	local ok, yielded, nextValue = NoYield.run(updater, current.value)
	if not ok then
		return self:_fail(
			Result.err(
				"TransactionFailed",
				if yielded then "Update callback yielded" else "Update callback failed",
				false,
				nextValue
			)
		)
	end
	return self:Set(path, nextValue)
end

function TransactionDraft:Insert(path: PathValue, value: unknown, index: number?): Result<number>
	local current = self:Get(path)
	if type(current.value) ~= "table" then
		return self:_fail(Result.err("InvalidData", "Insert target must be an array", false)) :: any
	end
	local array = DeepCopy(current.value) :: { unknown }
	local insertionIndex = index or (#array + 1)
	if insertionIndex < 1 or insertionIndex > #array + 1 then
		return self:_fail(
				Result.err("InvalidData", "Insert index is outside the array", false)
			) :: any
	end
	table.insert(array, insertionIndex, DeepCopy(value))
	local setResult = self:Set(path, array)
	if not setResult.ok then
		return setResult :: any
	end
	return Result.ok(insertionIndex)
end

function TransactionDraft:Remove(path: PathValue, index: number?): Result<unknown>
	if index ~= nil then
		local current = self:Get(path)
		if type(current.value) ~= "table" then
			return self:_fail(
				Result.err("InvalidData", "indexed Remove target must be an array", false)
			)
		end
		local array = DeepCopy(current.value) :: { unknown }
		if index < 1 or index > #array then
			return self:_fail(Result.err("InvalidData", "Remove index is outside the array", false))
		end
		local removed = table.remove(array, index)
		local setResult = self:Set(path, array)
		if not setResult.ok then
			return setResult
		end
		return Result.ok(freezeCopy(removed))
	end

	local current = self:Get(path)
	local setResult = self:Set(path, nil)
	if not setResult.ok then
		return setResult
	end
	return Result.ok(current.value)
end

function TransactionDraft:SetMetadata(key: string, value: unknown): Result<nil>
	local candidate = DeepCopy(self._metadata) :: { [string]: unknown }
	candidate[key] = DeepCopy(value)
	local validationFailure = self._validateValue(candidate)
	if validationFailure then
		return self:_fail(validationFailure)
	end
	self._metadata = candidate
	self._mutationCount += 1
	return Result.ok(nil)
end

function TransactionDraft:GetMetadata(key: string?): Result<unknown>
	return Result.ok(freezeCopy(if key then self._metadata[key] else self._metadata))
end

function TransactionDraft:IsDirty(): boolean
	return self._mutationCount > 0
end

function TransactionDraft:_getFailure(): Types.Failure?
	return self._failure
end

function TransactionDraft:_commit(): (unknown, { [string]: unknown }, { Change }, number)
	return DeepCopy(self._data),
		DeepCopy(self._metadata) :: { [string]: unknown },
		DeepCopy(self._changes) :: { Change },
		self._mutationCount
end

return TransactionDraft
