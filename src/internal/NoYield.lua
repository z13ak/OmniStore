--!strict

local NoYield = {}

function NoYield.run(callback: (...any) -> ...any, ...: any): (boolean, boolean, unknown)
	local thread = coroutine.create(callback)
	local resumed = table.pack(coroutine.resume(thread, ...))
	if not resumed[1] then
		return false, false, resumed[2]
	end
	if coroutine.status(thread) ~= "dead" then
		pcall(coroutine.close, thread)
		return false, true, "callback yielded"
	end
	return true, false, resumed[2]
end

return NoYield
