--!strict

local DeepCopy = require(script.Parent.Parent.internal.DeepCopy)
local Path = require(script.Parent.Parent.internal.Path)
local Types = require(script.Parent.Parent.Types)

local Protocol = {}

local FIXED_ROBLOX_TYPE_BYTES: { [string]: number } = {
	BrickColor = 8,
	CFrame = 96,
	Color3 = 24,
	ColorSequence = 128,
	ColorSequenceKeypoint = 32,
	DateTime = 16,
	EnumItem = 32,
	Font = 64,
	NumberRange = 16,
	NumberSequence = 128,
	NumberSequenceKeypoint = 24,
	Ray = 48,
	Rect = 32,
	UDim = 16,
	UDim2 = 32,
	Vector2 = 16,
	Vector2int16 = 8,
	Vector3 = 24,
	Vector3int16 = 12,
}

function Protocol.validateChannel(channel: unknown, maxLength: number): (boolean, string?)
	if type(channel) ~= "string" or channel == "" then
		return false, "channel must be a non-empty string"
	end
	if #channel > maxLength then
		return false, `channel exceeds {maxLength} bytes`
	end
	return true, nil
end

function Protocol.validatePath(path: Types.Path, maxSegments: number): (boolean, string?)
	if type(path) ~= "string" and type(path) ~= "table" then
		return false, "path must be a string or segment array"
	end
	local segments = Path.parse(path)
	if #segments == 0 then
		return false, "root replication paths are not allowed"
	end
	if #segments > maxSegments then
		return false, `path exceeds {maxSegments} segments`
	end
	for _, segment in segments do
		if type(segment) == "string" then
			if segment == "" or #segment > 100 then
				return false, "path contains an empty or oversized string segment"
			end
		elseif type(segment) == "number" then
			if segment % 1 ~= 0 or segment < 1 then
				return false, "numeric path segments must be positive integers"
			end
		else
			return false, "path contains an unsupported segment"
		end
	end
	return true, nil
end

local function segmentsEqualPrefix(
	shorter: { string | number },
	longer: { string | number }
): boolean
	if #shorter > #longer then
		return false
	end
	for index, segment in shorter do
		if longer[index] ~= segment then
			return false
		end
	end
	return true
end

function Protocol.pathsOverlap(left: Types.Path, right: Types.Path): boolean
	local leftSegments = Path.parse(left)
	local rightSegments = Path.parse(right)
	return segmentsEqualPrefix(leftSegments, rightSegments)
		or segmentsEqualPrefix(rightSegments, leftSegments)
end

function Protocol.isAllowed(path: Types.Path, allowed: { Types.Path }): boolean
	local candidate = Path.parse(path)
	for _, value in allowed do
		if segmentsEqualPrefix(Path.parse(value), candidate) then
			return true
		end
	end
	return false
end

function Protocol.assign(root: table, path: Types.Path, value: unknown): boolean
	local parent, key = Path.parent(root, Path.parse(path), true)
	if not parent or key == nil then
		return false
	end
	local parentAny = parent :: any
	parentAny[key] = DeepCopy(value)
	return true
end

local function measure(
	value: unknown,
	ancestors: { [table]: boolean },
	depth: number,
	maxDepth: number,
	limit: number
): (number?, string?)
	if depth > maxDepth then
		return nil, "payload exceeds the maximum depth"
	end
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" then
		return 1, nil
	elseif kind == "number" then
		return 8, nil
	elseif kind == "string" then
		return #(value :: string) + 4, nil
	elseif kind ~= "table" then
		local fixed = FIXED_ROBLOX_TYPE_BYTES[kind]
		if fixed then
			return fixed, nil
		end
		return nil, `payload contains unsupported remote value type {kind}`
	end

	local valueTable = value :: table
	if ancestors[valueTable] then
		return nil, "payload contains a cyclic table"
	end
	ancestors[valueTable] = true
	local total = 8
	for key, child in valueTable do
		local keyType = type(key)
		if keyType ~= "string" and keyType ~= "number" then
			ancestors[valueTable] = nil
			return nil, "payload contains an unsupported table key"
		end
		total += if keyType == "string" then #(key :: string) + 4 else 8
		local childBytes, childError = measure(child, ancestors, depth + 1, maxDepth, limit)
		if not childBytes then
			ancestors[valueTable] = nil
			return nil, childError
		end
		total += childBytes
		if total > limit then
			ancestors[valueTable] = nil
			return total, nil
		end
	end
	ancestors[valueTable] = nil
	return total, nil
end

function Protocol.measure(value: unknown, maxDepth: number, limit: number): (number?, string?)
	return measure(value, {}, 0, maxDepth, limit)
end

return Protocol
