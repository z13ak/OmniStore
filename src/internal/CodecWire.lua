--!strict

-- In-memory provenance only: never adds fields to the stored wire format.
local preserved: { [table]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local CodecWire = {}

function CodecWire.mark(value: table): table
	preserved[value] = true
	return value
end

function CodecWire.isPreserved(value: table): boolean
	return preserved[value] == true
end

return CodecWire
