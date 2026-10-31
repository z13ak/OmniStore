--!strict
-- selene: allow(undefined_variable)

return function()
	local Retry = require(game.ReplicatedStorage.Packages.OmniStore.internal.Retry)
	local Result = require(game.ReplicatedStorage.Packages.OmniStore.internal.Result)
	local config = { maxAttempts = 3, baseDelay = 2, maxDelay = 2, jitter = 0 }

	describe("retry deadlines", function()
		it("does not start a request when the deadline has already expired", function()
			local calls = 0
			local result = Retry.run(
				function()
					calls += 1
					return Result.ok(nil)
				end,
				config,
				function() end,
				Random.new(1),
				{
					clock = function()
						return 1
					end,
					deadline = 1,
				}
			)
			expect(result.error.code).to.equal("Timeout")
			expect(calls).to.equal(0)
		end)

		it("does not start another request after backoff reaches the deadline", function()
			local now = 0
			local calls = 0
			local result = Retry.run(
				function()
					calls += 1
					return Result.err("PersistenceFailed", "transient", true)
				end,
				config,
				function(delay)
					now += delay
				end,
				Random.new(1),
				{
					clock = function()
						return now
					end,
					deadline = 1,
				}
			)
			expect(result.error.code).to.equal("Timeout")
			expect(calls).to.equal(1)
		end)
	end)
end
