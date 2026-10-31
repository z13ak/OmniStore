--!strict

local Gate = {}

function Gate.check(results: any): (boolean, string)
	local function countErrors(node): number
		local count = #(node.errors or {})
		for _, child in node.children or {} do
			count += countErrors(child)
		end
		return count
	end
	local errors = countErrors(results)
	local failures = results.failureCount or 0
	local executed = (results.successCount or 0) + failures
	local ok = failures == 0 and errors == 0 and executed > 0
	return ok,
		`OmniStore tests: {executed} executed, {failures} failure(s), {errors} planning/runtime error(s)`
end

return Gate
