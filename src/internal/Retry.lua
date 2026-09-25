--!strict

local Types = require(script.Parent.Parent.Types)
local Result = require(script.Parent.Result)

local Retry = {}

export type Options = {
	clock: (() -> number)?,
	deadline: number?,
	onRetry: ((error: Types.OmniError, attempt: number, delay: number) -> ())?,
}

function Retry.run<T>(
	callback: () -> Types.Result<T>,
	config: Types.RetryConfig,
	waitFunction: (number) -> (),
	random: Random,
	options: Options?
): Types.Result<T>
	local settings = options or {}
	local clock = settings.clock or os.clock
	local lastResult = callback()
	local attempt = 1
	while not lastResult.ok and lastResult.error.retryable and attempt < config.maxAttempts do
		if settings.deadline and clock() >= settings.deadline then
			return Result.err(
				"Timeout",
				"retry deadline expired",
				true,
				lastResult.error,
				{ attempts = attempt },
				"Transient"
			)
		end
		local exponential = math.min(config.maxDelay, config.baseDelay * (2 ^ (attempt - 1)))
		local jitter = exponential * config.jitter * random:NextNumber(-1, 1)
		local delay = math.max(0, exponential + jitter)
		if settings.deadline then
			delay = math.min(delay, math.max(0, settings.deadline - clock()))
		end
		if settings.onRetry then
			settings.onRetry(lastResult.error, attempt, delay)
		end
		waitFunction(delay)
		attempt += 1
		lastResult = callback()
	end
	return lastResult
end

return Retry
