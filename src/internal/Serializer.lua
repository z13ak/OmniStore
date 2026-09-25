--!strict

local HttpService = game:GetService("HttpService")

local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Types)

type Result<T> = Types.Result<T>

local Serializer = {}

local DEFAULT_MAX_DEPTH = 64
local DEFAULT_MAX_PAYLOAD_BYTES = 4_000_000

local function validateValue(
	value: unknown,
	path: string,
	ancestors: { [table]: boolean },
	depth: number,
	maxDepth: number
): (boolean, string?)
	if depth > maxDepth then
		return false, `{path} exceeds the maximum serialization depth of {maxDepth}`
	end
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" or kind == "string" then
		return true, nil
	end
	if kind == "number" then
		local numberValue = value :: number
		if numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
			return false, `{path} contains a non-finite number`
		end
		return true, nil
	end
	if kind ~= "table" then
		return false, `{path} contains unsupported Roblox value type {kind}`
	end

	local valueTable = value :: table
	if ancestors[valueTable] then
		return false, `{path} contains a cyclic table`
	end
	ancestors[valueTable] = true

	local hasStringKeys = false
	local numericKeyCount = 0
	local largestNumericKey = 0
	for key, child in valueTable do
		local keyType = type(key)
		if keyType ~= "string" and keyType ~= "number" then
			ancestors[valueTable] = nil
			return false, `{path} has unsupported key type {keyType}`
		end
		if keyType == "number" then
			local numberKey = key :: number
			if numberKey % 1 ~= 0 or numberKey < 1 then
				ancestors[valueTable] = nil
				return false, `{path} has a non-positive or non-integer numeric key`
			end
			numericKeyCount += 1
			largestNumericKey = math.max(largestNumericKey, numberKey)
		else
			hasStringKeys = true
		end
		local childPath = `{path}.{tostring(key)}`
		local ok, message = validateValue(child, childPath, ancestors, depth + 1, maxDepth)
		if not ok then
			ancestors[valueTable] = nil
			return false, message
		end
	end
	if hasStringKeys and numericKeyCount > 0 then
		ancestors[valueTable] = nil
		return false, `{path} mixes string and numeric keys`
	end
	if numericKeyCount > 0 and largestNumericKey ~= numericKeyCount then
		ancestors[valueTable] = nil
		return false, `{path} is a sparse array`
	end

	ancestors[valueTable] = nil
	return true, nil
end

function Serializer.validate(value: unknown, options: Types.SerializationOptions?): Result<nil>
	local settings = options or {}
	local maxDepth = settings.maxDepth or DEFAULT_MAX_DEPTH
	local maxPayloadBytes = settings.maxPayloadBytes or DEFAULT_MAX_PAYLOAD_BYTES
	local ok, message = validateValue(value, "$", {}, 0, maxDepth)
	if not ok then
		return Result.err("InvalidData", message or "data is not serializable", false)
	end
	local encodedOk, encoded = pcall(HttpService.JSONEncode, HttpService, value)
	if not encodedOk then
		return Result.err(
			"InvalidData",
			"Roblox JSON serialization rejected the value",
			false,
			encoded
		)
	end
	if #encoded > maxPayloadBytes then
		return Result.err(
			"InvalidData",
			`serialized value exceeds the configured {maxPayloadBytes}-byte safety limit`,
			false,
			nil,
			{ encodedBytes = #encoded, maxPayloadBytes = maxPayloadBytes }
		)
	end
	return Result.ok(nil)
end

return Serializer
