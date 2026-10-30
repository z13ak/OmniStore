--!strict

local Result = require(script.Parent.internal.Result)
local Types = require(script.Parent.Types)
local CodecWire = require(script.Parent.internal.CodecWire)
local DeepCopy = require(script.Parent.internal.DeepCopy)

export type Codec = Types.Codec
export type UnknownTypePolicy = Types.UnknownTypePolicy

local TAG = "__omniCodec"
local TYPE_ID = "typeId"
local PAYLOAD = "value"
local PLAIN_TABLE = "omnistore.PlainTable/v1"

local CodecRegistry = {}
CodecRegistry.__index = CodecRegistry

export type CodecRegistry = typeof(setmetatable(
	{} :: {
		_codecs: { Codec },
		_byTypeId: { [string]: Codec },
		_unknownTypePolicy: UnknownTypePolicy,
	},
	CodecRegistry
))

local function validTypeId(typeId: string): boolean
	return #typeId > 0 and #typeId <= 100 and string.match(typeId, "^[%w%._:/%-]+$") ~= nil
end

function CodecRegistry.new(options: { unknownTypePolicy: UnknownTypePolicy? }?): CodecRegistry
	local policy = if options then options.unknownTypePolicy or "Reject" else "Reject"
	assert(
		policy == "Reject" or policy == "Preserve",
		"unknownTypePolicy must be Reject or Preserve"
	)
	return setmetatable({
		_codecs = {},
		_byTypeId = {},
		_unknownTypePolicy = policy,
	}, CodecRegistry)
end

function CodecRegistry:Register(codec: Codec): CodecRegistry
	assert(type(codec) == "table", "codec must be a table")
	assert(type(codec.typeId) == "string" and validTypeId(codec.typeId), "codec typeId is invalid")
	assert(codec.typeId ~= PLAIN_TABLE, "codec typeId is reserved for plain-table escaping")
	assert(type(codec.isType) == "function", "codec isType must be a function")
	assert(type(codec.encode) == "function", "codec encode must be a function")
	assert(type(codec.decode) == "function", "codec decode must be a function")
	assert(self._byTypeId[codec.typeId] == nil, `codec typeId {codec.typeId} is already registered`)
	self._byTypeId[codec.typeId] = codec
	table.insert(self._codecs, codec)
	return self
end

function CodecRegistry:GetUnknownTypePolicy(): UnknownTypePolicy
	return self._unknownTypePolicy
end

function CodecRegistry:Encode(value: unknown): Types.Result<unknown>
	local visiting: { [table]: boolean } = {}
	local function encode(current: unknown, path: string, wire: boolean?): Types.Result<unknown>
		local preserveWire = wire == true
			or (type(current) == "table" and CodecWire.isPreserved(current))
		for _, codec in if preserveWire then {} else self._codecs do
			local matchedOk, matched = pcall(codec.isType, current)
			if not matchedOk then
				return Result.err(
					"InvalidData",
					`codec {codec.typeId} matcher failed at {path}`,
					false,
					matched
				)
			end
			if matched then
				local encodedOk, payload = pcall(codec.encode, current)
				if not encodedOk then
					return Result.err(
						"InvalidData",
						`codec {codec.typeId} encode failed at {path}`,
						false,
						payload
					)
				end
				local encodedPayload = encode(payload, `{path}<{codec.typeId}>`)
				if not encodedPayload.ok then
					return encodedPayload
				end
				return Result.ok({
					[TAG] = 1,
					[TYPE_ID] = codec.typeId,
					[PAYLOAD] = encodedPayload.value,
				})
			end
		end
		if type(current) ~= "table" then
			return Result.ok(current)
		end
		if visiting[current] then
			return Result.err(
				"InvalidData",
				`cyclic value encountered while encoding {path}`,
				false
			)
		end
		visiting[current] = true
		local output = {}
		for key, child in current do
			local encodedChild = encode(child, `{path}.{tostring(key)}`, preserveWire)
			if not encodedChild.ok then
				visiting[current] = nil
				return encodedChild
			end
			output[key] = encodedChild.value
		end
		visiting[current] = nil
		-- Escape an ordinary table that could otherwise be interpreted as a codec on load.
		if not preserveWire and output[TAG] == 1 and type(output[TYPE_ID]) == "string" then
			return Result.ok({ [TAG] = 1, [TYPE_ID] = PLAIN_TABLE, [PAYLOAD] = output })
		end
		return Result.ok(output)
	end
	return encode(value, "$")
end

function CodecRegistry:Decode(value: unknown): Types.Result<unknown>
	local visiting: { [table]: boolean } = {}
	local function decode(
		current: unknown,
		path: string,
		plainTable: boolean?
	): Types.Result<unknown>
		if type(current) ~= "table" then
			return Result.ok(current)
		end
		if visiting[current] then
			return Result.err(
				"InvalidData",
				`cyclic value encountered while decoding {path}`,
				false
			)
		end
		visiting[current] = true
		if
			not plainTable
			and (current :: any)[TAG] == 1
			and type((current :: any)[TYPE_ID]) == "string"
		then
			local typeId = (current :: any)[TYPE_ID] :: string
			if typeId == PLAIN_TABLE then
				local payload = (current :: any)[PAYLOAD]
				if type(payload) ~= "table" then
					visiting[current] = nil
					return Result.err("InvalidData", `invalid escaped table at {path}`, false)
				end
				local result = decode(payload, `{path}<table>`, true)
				visiting[current] = nil
				return result
			end
			local codec = self._byTypeId[typeId]
			if not codec then
				visiting[current] = nil
				if self._unknownTypePolicy == "Preserve" then
					return Result.ok(CodecWire.mark(DeepCopy(current) :: table))
				end
				return Result.err(
					"InvalidData",
					`unknown codec typeId {typeId} at {path}`,
					false,
					nil,
					{
						typeId = typeId,
					}
				)
			end
			local decodedPayload = decode((current :: any)[PAYLOAD], `{path}<{typeId}>`)
			if not decodedPayload.ok then
				visiting[current] = nil
				return decodedPayload
			end
			local decodedOk, decoded = pcall(codec.decode, decodedPayload.value)
			visiting[current] = nil
			if not decodedOk then
				return Result.err(
					"InvalidData",
					`codec {typeId} decode failed at {path}`,
					false,
					decoded
				)
			end
			return Result.ok(decoded)
		end
		local output = {}
		for key, child in current do
			local decodedChild = decode(child, `{path}.{tostring(key)}`)
			if not decodedChild.ok then
				visiting[current] = nil
				return decodedChild
			end
			output[key] = decodedChild.value
		end
		visiting[current] = nil
		return Result.ok(output)
	end
	return decode(value, "$")
end

return CodecRegistry
