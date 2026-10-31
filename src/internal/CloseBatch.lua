--!strict

local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Types)

local CloseBatch = {}

function CloseBatch.run<T>(
	items: { T },
	close: (T, number) -> Types.Result<nil>,
	limit: number,
	deadline: number,
	clock: () -> number,
	waitFunction: (number) -> ()
): Types.Result<nil>
	local nextIndex = 1
	local completed = 0
	local workers = math.min(limit, #items)
	local firstFailure: Types.Failure? = nil
	for _ = 1, workers do
		task.spawn(function()
			while nextIndex <= #items do
				local item = items[nextIndex]
				nextIndex += 1
				local ok, result = pcall(close, item, math.max(0, deadline - clock()))
				if not ok then
					result = Result.err("PersistenceFailed", "close callback failed", false, result)
				end
				if not result.ok and not firstFailure then
					firstFailure = result
				end
			end
			completed += 1
		end)
	end
	-- Started platform requests cannot be preempted; each close receives the shared deadline.
	while completed < workers do
		waitFunction(0.03)
	end
	return firstFailure or Result.ok(nil)
end

return CloseBatch
