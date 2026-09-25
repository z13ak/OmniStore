--!strict

local Path = {}

export type Segment = string | number

function Path.parse(path: string | { Segment }): { Segment }
	if type(path) == "table" then
		return table.clone(path)
	end
	if path == "" then
		return {}
	end

	local result: { Segment } = {}
	for segment in string.gmatch(path, "[^.]+") do
		local numeric = tonumber(segment)
		table.insert(result, numeric or segment)
	end
	return result
end

function Path.get(root: unknown, segments: { Segment }): unknown
	local current = root
	for _, segment in segments do
		if type(current) ~= "table" then
			return nil
		end
		current = (current :: any)[segment]
	end
	return current
end

function Path.parent(root: unknown, segments: { Segment }, create: boolean): (table?, Segment?)
	if #segments == 0 then
		return nil, nil
	end
	if type(root) ~= "table" then
		return nil, nil
	end

	local current = root :: table
	for index = 1, #segments - 1 do
		local segment = segments[index]
		local currentAny = current :: any
		local child = currentAny[segment]
		if child == nil and create then
			child = {}
			currentAny[segment] = child
		end
		if type(child) ~= "table" then
			return nil, nil
		end
		current = child :: table
	end
	return current, segments[#segments]
end

return Path
