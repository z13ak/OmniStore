--!strict
-- selene: allow(undefined_variable)

return function()
	local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)
	local function config(adapter, clock)
		return {
			adapter = adapter,
			template = { Value = 0 },
			autosaveInterval = 0,
			clock = clock,
			monotonicClock = function()
				return 0
			end,
			wait = function()
				coroutine.yield()
			end,
			lease = { duration = 10, renewInterval = 5, acquireTimeout = 0 },
		}
	end

	local function resume(thread)
		local ok, cause = coroutine.resume(thread)
		assert(ok, tostring(cause))
	end

	describe("lease-aware deletion", function()
		it(
			"cannot delete a live foreign lease even when the deleting store disables leases",
			function()
				local adapter = OmniStore.Adapters.Memory.new()
				local function clock()
					return 100
				end
				local first = OmniStore.new({ autoBindToClose = false })
					:GetStore("Shared", config(adapter, clock))
				local options = config(adapter, clock)
				options.lease.enabled = false
				local second = OmniStore.new({ autoBindToClose = false })
					:GetStore("Shared", options)
				local record = first:LoadAsync("record").value
				record:Set("Value", 9)
				expect(second:DeleteAsync("record").error.code).to.equal("Locked")
				expect(record:SaveAsync().ok).to.equal(true)
				expect(adapter:Peek("record").data.Value).to.equal(9)
				record:CloseAsync()
			end
		)

		it("clears expired records and recreates only their template", function()
			local now = 100
			local function clock()
				return now
			end
			local adapter = OmniStore.Adapters.Memory.new()
			local first = OmniStore.new({ autoBindToClose = false })
				:GetStore("Shared", config(adapter, clock))
			local second = OmniStore.new({ autoBindToClose = false })
				:GetStore("Shared", config(adapter, clock))
			local old = first:LoadAsync("record").value
			old:Set("Value", 9)
			old:SaveAsync()
			now = 111
			expect(second:DeleteAsync("record").ok).to.equal(true)
			expect(second:DeleteAsync("record").ok).to.equal(true)
			expect(adapter:Peek("record").deleted).to.equal(true)
			expect(adapter:Peek("record").data.Value).to.equal(nil)
			expect(second:LoadAsync("record", { mode = "ReadOnly" }).error.code).to.equal(
				"NotFound"
			)
			expect(old:SaveAsync().error.code).to.equal("LeaseLost")
			local recreated = second:LoadAsync("record").value
			expect(recreated:Get("Value").value).to.equal(0)
			recreated:CloseAsync()
			old:CloseAsync()
		end)

		it("coordinates local deletion with loads and shutdown", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local store = OmniStore.new({ autoBindToClose = false }):GetStore(
				"Shared",
				config(adapter, function()
					return 100
				end)
			)
			local original = adapter.Update
			adapter.Update = function(self, key, transform)
				coroutine.yield()
				return original(self, key, transform)
			end
			local deleted
			local deleting = coroutine.create(function()
				deleted = store:DeleteAsync("record")
			end)
			resume(deleting)
			expect(store:LoadAsync("record").error.code).to.equal("Conflict")
			expect(store:DeleteAsync("record").error.code).to.equal("Conflict")
			local closed
			local closing = coroutine.create(function()
				closed = store:CloseAsync()
			end)
			resume(closing)
			expect(closed).to.equal(nil)
			expect(store:DeleteAsync("late").error.code).to.equal("Closed")
			resume(deleting)
			resume(closing)
			expect(deleted.ok).to.equal(true)
			expect(closed.ok).to.equal(true)
		end)

		it("leaves data intact when deletion cannot start before its deadline", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local store = OmniStore.new({ autoBindToClose = false }):GetStore(
				"Shared",
				config(adapter, function()
					return 100
				end)
			)
			expect(store:DeleteAsync("record", 0).error.code).to.equal("Timeout")
			expect(adapter:Peek("record")).to.equal(nil)
			expect(store:LoadAsync("record").ok).to.equal(true)
			store:CloseAsync()
		end)
	end)
end
