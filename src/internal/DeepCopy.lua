--!strict

local function deepCopy(value: unknown, seen: { [table]: table }?): unknown
	if type(value) ~= "table" then
		return value
	end

	local source = value :: table
	local visited = seen or {}
	if visited[source] then
		return visited[source]
	end

	local copy = {}
	visited[source] = copy
	local copyAny = copy :: any
	for key, child in source do
		copyAny[deepCopy(key, visited)] = deepCopy(child, visited)
	end
	return copy
end

return deepCopy
