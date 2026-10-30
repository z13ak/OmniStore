--!strict
-- selene: allow(undefined_variable)

return function()
	local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)

	local function makeStore()
		local adapter = OmniStore.Adapters.Memory.new()
		local database = OmniStore.new({ autoBindToClose = false })
		local store = database:GetStore("Shutdown", {
			adapter = adapter,
			template = { Value = 0 },
			autosaveInterval = 0,
			maxConcurrentBackgroundTasks = 2,
			monotonicClock = function()
				return 0
			end,
			wait = function()
				coroutine.yield()
			end,
			lease = { enabled = false },
		})
		return store, adapter, database
	end

	local function resume(thread)
		local ok, cause = coroutine.resume(thread)
		assert(ok, tostring(cause))
	end

	describe("shutdown coordination", function()
		it("gates every store before manager close begins persistence", function()
			local database = OmniStore.new({ autoBindToClose = false })
			local adapter = OmniStore.Adapters.Memory.new()
			local first = database:GetStore(
				"First",
				{ adapter = adapter, autosaveInterval = 0, lease = { enabled = false } }
			)
			local second = database:GetStore(
				"Second",
				{ adapter = adapter, autosaveInterval = 0, lease = { enabled = false } }
			)
			first:LoadAsync("one")
			second:LoadAsync("two")
			local original = adapter.Update
			adapter.Update = function(self, key, transform)
				expect(first:LoadAsync("late").error.code).to.equal("Closed")
				expect(second:LoadAsync("late").error.code).to.equal("Closed")
				expect(pcall(function()
					database:GetStore("Late")
				end)).to.equal(false)
				return original(self, key, transform)
			end
			expect(database:CloseAsync().ok).to.equal(true)
		end)

		it("bounds the number of simultaneous close requests", function()
			local store, adapter = makeStore()
			for _, key in { "one", "two", "three" } do
				store:LoadAsync(key)
			end
			local original = adapter.Update
			local blocked = {}
			local running = 0
			local peak = 0
			adapter.Update = function(self, key, transform)
				running += 1
				peak = math.max(peak, running)
				table.insert(blocked, coroutine.running())
				coroutine.yield()
				running -= 1
				return original(self, key, transform)
			end
			local result
			local closing = coroutine.create(function()
				result = store:CloseAsync()
			end)
			resume(closing)
			expect(#blocked).to.equal(2)
			resume(blocked[1])
			expect(#blocked).to.equal(3)
			resume(blocked[2])
			resume(blocked[3])
			resume(closing)
			expect(result.ok).to.equal(true)
			expect(peak).to.equal(2)
		end)

		it("saves other records while one close is blocked and rejects new loads", function()
			local store, adapter = makeStore()
			local slow = store:LoadAsync("slow").value
			local fast = store:LoadAsync("fast").value
			slow:Set("Value", 1)
			fast:Set("Value", 2)
			local original = adapter.Update
			local blocked
			adapter.Update = function(self, key, transform)
				if key == "slow" then
					blocked = coroutine.running()
					coroutine.yield()
				end
				return original(self, key, transform)
			end
			local result
			local closing = coroutine.create(function()
				result = store:CloseAsync()
			end)
			resume(closing)
			expect(blocked ~= nil).to.equal(true)
			expect(adapter:Peek("fast").data.Value).to.equal(2)
			expect(store:LoadAsync("late").error.code).to.equal("Closed")
			resume(blocked)
			resume(closing)
			expect(result.ok).to.equal(true)
			expect(slow.State).to.equal("Closed")
			expect(fast.State).to.equal("Closed")
		end)

		it("drains a load that started before close", function()
			local store, adapter = makeStore()
			local original = adapter.Update
			local hold = true
			adapter.Update = function(self, key, transform)
				if hold then
					coroutine.yield()
				end
				return original(self, key, transform)
			end
			local loaded
			local loading = coroutine.create(function()
				loaded = store:LoadAsync("loading")
			end)
			resume(loading)
			local result
			local closing = coroutine.create(function()
				result = store:CloseAsync()
			end)
			resume(closing)
			expect(result).to.equal(nil)
			expect(store:LoadAsync("late").error.code).to.equal("Closed")
			hold = false
			resume(loading)
			resume(closing)
			expect(result.ok).to.equal(true)
			expect(loaded.value.State).to.equal("Closed")
			expect(store:GetLoadedRecord("loading")).to.equal(nil)
		end)

		it("can retry close after timing out on an in-flight load", function()
			local store, adapter = makeStore()
			local original = adapter.Update
			local hold = true
			adapter.Update = function(self, key, transform)
				if hold then
					coroutine.yield()
				end
				return original(self, key, transform)
			end
			local loading = coroutine.create(function()
				store:LoadAsync("loading")
			end)
			resume(loading)
			expect(store:CloseAsync(0).error.code).to.equal("Timeout")
			hold = false
			resume(loading)
			expect(store:CloseAsync().ok).to.equal(true)
		end)

		it("coalesces overlapping record closes", function()
			local store, adapter = makeStore()
			local record = store:LoadAsync("record").value
			local original = adapter.Update
			local calls = 0
			adapter.Update = function(self, key, transform)
				calls += 1
				coroutine.yield()
				return original(self, key, transform)
			end
			local first, second
			local closing = coroutine.create(function()
				first = record:CloseAsync()
			end)
			local joining = coroutine.create(function()
				second = record:CloseAsync()
			end)
			resume(closing)
			resume(joining)
			resume(closing)
			resume(joining)
			expect(first.ok).to.equal(true)
			expect(second.ok).to.equal(true)
			expect(calls).to.equal(1)
		end)
	end)
end
