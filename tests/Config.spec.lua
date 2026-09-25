--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	describe("configuration", function()
		it("merges partial retry and lease overrides with manager defaults", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({
				autoBindToClose = false,
				defaultStoreConfig = {
					adapter = adapter,
					autosaveInterval = 0,
					retry = { maxAttempts = 7, baseDelay = 2, maxDelay = 9 },
					lease = {
						enabled = false,
						duration = 90,
						renewInterval = 30,
						acquireTimeout = 4,
						stealAfter = 3,
					},
				},
			})
			local store = database:GetStore("Merged", {
				retry = { jitter = 0 },
				lease = { acquireTimeout = 2 },
			})
			local config = (store :: any)._config
			expect(config.retry.maxAttempts).to.equal(7)
			expect(config.retry.baseDelay).to.equal(2)
			expect(config.retry.jitter).to.equal(0)
			expect(config.lease.enabled).to.equal(false)
			expect(config.lease.duration).to.equal(90)
			expect(config.lease.acquireTimeout).to.equal(2)
		end)

		it("rejects adapters that cannot perform read-only loads", function()
			local database = OmniStore.new({ autoBindToClose = false })
			local ok = pcall(function()
				database:GetStore("Incomplete", {
					adapter = {
						Update = function() end,
						Remove = function() end,
						GetBudget = function() end,
					} :: any,
				})
			end)
			expect(ok).to.equal(false)
		end)
	end)
end
