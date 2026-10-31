--!strict
-- selene: allow(undefined_variable)

return function()
	local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)
	local Result = require(game.ReplicatedStorage.Packages.OmniStore.internal.Result)
	local function makeRecord()
		local adapter = OmniStore.Adapters.Memory.new()
		local store = OmniStore.new({ autoBindToClose = false }):GetStore("Saves", {
			adapter = adapter,
			template = { Value = 0 },
			autosaveInterval = 0,
			wait = function()
				coroutine.yield()
			end,
			retry = { baseDelay = 0, maxDelay = 0, jitter = 0 },
		})
		return store:LoadAsync("record").value, adapter, store
	end
	local function resume(thread)
		local ok, cause = coroutine.resume(thread)
		assert(ok, tostring(cause))
	end

	describe("save concurrency and uncertain responses", function()
		it("keeps mutations made during a save dirty until the next save", function()
			local record, adapter = makeRecord()
			record:Set("Value", 1)
			local original = adapter.Update
			local hold = true
			adapter.Update = function(self, key, transform)
				if hold then
					coroutine.yield()
				end
				return original(self, key, transform)
			end
			local result
			local saving = coroutine.create(function()
				result = record:SaveAsync()
			end)
			resume(saving)
			record:Set("Value", 2)
			hold = false
			resume(saving)
			expect(result.ok).to.equal(true)
			expect(adapter:Peek("record").data.Value).to.equal(1)
			expect(record:IsDirty()).to.equal(true)
			expect(record:SaveAsync().ok).to.equal(true)
			expect(adapter:Peek("record").data.Value).to.equal(2)
			expect(record:IsDirty()).to.equal(false)
			record:CloseAsync()
		end)

		it("coalesces concurrent callers and persists their latest snapshot", function()
			local record, adapter = makeRecord()
			record:Set("Value", 1)
			local original = adapter.Update
			local calls = 0
			adapter.Update = function(self, key, transform)
				calls += 1
				if calls == 1 then
					coroutine.yield()
				end
				return original(self, key, transform)
			end
			local first, second
			local saving = coroutine.create(function()
				first = record:SaveAsync()
			end)
			local joining = coroutine.create(function()
				second = record:SaveAsync()
			end)
			resume(saving)
			record:Set("Value", 2)
			resume(joining)
			resume(saving)
			resume(joining)
			expect(first.ok).to.equal(true)
			expect(second.ok).to.equal(true)
			expect(calls).to.equal(2)
			expect(adapter:Peek("record").data.Value).to.equal(2)
			expect(record:IsDirty()).to.equal(false)
			record:CloseAsync()
		end)

		for _, close in { false, true } do
			it(
				if close
					then "recognizes an already committed close after response loss"
					else "does not advance a save revision twice after response loss",
				function()
					local record, adapter = makeRecord()
					record:Set("Value", 5)
					local original = adapter.Update
					local lost = false
					adapter.Update = function(self, key, transform)
						local result = original(self, key, transform)
						if not lost then
							lost = true
							return Result.err(
								"PersistenceFailed",
								"committed but response lost",
								true
							)
						end
						return result
					end
					local result
					local saving = coroutine.create(function()
						result = if close then record:CloseAsync() else record:SaveAsync()
					end)
					resume(saving)
					resume(saving) -- Retry backoff uses the injected yielding wait.
					expect(result.ok).to.equal(true)
					expect(adapter:Peek("record").revision).to.equal(1)
					expect(adapter:Peek("record").data.Value).to.equal(5)
					if close then
						expect(record.State).to.equal("Closed")
						expect(adapter:Peek("record").lease).to.equal(nil)
					else
						expect(record:IsDirty()).to.equal(false)
						record:CloseAsync()
					end
				end
			)
		end
	end)
end
