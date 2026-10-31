--!strict
-- selene: allow(undefined_variable)

return function()
	local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)
	local Result = require(game.ReplicatedStorage.Packages.OmniStore.internal.Result)
	local function makeStore(adapter)
		return OmniStore.new({ autoBindToClose = false }):GetStore("RetryTransform", {
			adapter = adapter,
			template = { Value = 0 },
			autosaveInterval = 0,
			wait = function() end,
			retry = { baseDelay = 0, maxDelay = 0, jitter = 0 },
		})
	end

	describe("retried transform decisions", function()
		it("does not retain a rejected envelope from an earlier failed request", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local original = adapter.Update
			local calls = 0
			adapter.Update = function(self, key, transform)
				calls += 1
				if calls == 1 then
					transform({
						data = {},
						metadata = {},
						schemaVersion = 999,
						revision = 0,
						updatedAt = 0,
					})
					return Result.err("PersistenceFailed", "response failed", true)
				end
				return original(self, key, transform)
			end
			local store = makeStore(adapter)
			local loaded = store:LoadAsync("record")
			expect(loaded.ok).to.equal(true)
			expect(store:GetLoadedRecord("record")).to.equal(loaded.value)
			expect(loaded.value:CloseAsync().ok).to.equal(true)
		end)

		it("uses the final save decision after a transient failed request", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local store = makeStore(adapter)
			local record = store:LoadAsync("record").value
			record:Set("Value", 3)
			local original = adapter.Update
			local calls = 0
			adapter.Update = function(self, key, transform)
				calls += 1
				if calls == 1 then
					transform(nil)
					return Result.err("PersistenceFailed", "response failed", true)
				end
				return original(self, key, transform)
			end
			expect(record:SaveAsync().ok).to.equal(true)
			expect(record:IsDirty()).to.equal(false)
			expect(adapter:Peek("record").data.Value).to.equal(3)
			record:CloseAsync()
		end)
	end)
end
