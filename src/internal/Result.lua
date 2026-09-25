--!strict

local Types = require(script.Parent.Parent.Types)

type ErrorCode = Types.ErrorCode
type OmniError = Types.OmniError
type Result<T> = Types.Result<T>

local Result = {}

function Result.ok<T>(value: T): Result<T>
	return { ok = true, value = value }
end

function Result.err(
	code: ErrorCode,
	message: string,
	retryable: boolean?,
	cause: unknown?,
	context: { [string]: unknown }?,
	category: Types.ErrorCategory?
): Types.Failure
	local errorValue: OmniError = {
		code = code,
		message = message,
		retryable = retryable == true,
		category = category,
		cause = cause,
		context = context,
	}
	return { ok = false, error = errorValue }
end

return Result
