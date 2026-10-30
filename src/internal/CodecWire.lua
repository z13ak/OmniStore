--!strict

-- In-memory provenance only: never adds fields to the stored wire format.
local preserved: { [table]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local CodecWire = {}

function CodecWire.mark(value: table): table
	preserved[value] = true
	return value
end

function CodecWire.markTree(value: table): table
	local seen: { [table]: boolean } = {}
	local function visit(current: table)
		if seen[current] then
			return
		end
		seen[current] = true
		CodecWire.mark(current)
		for _, child in current do
			if type(child) == "table" then
				visit(child)
			end
		end
	end
	visit(value)
	return value
end

function CodecWire.isPreserved(value: table): boolean
	return preserved[value] == true
end

return CodecWire
