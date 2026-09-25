--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	describe("retry and dirty-state reliability", function()
		it("retries transient adapter failures", function()
			local adapter = OmniStore.Adapters.Memory.new()
			adapter:SetFailurePlan("Update", 2)
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("Retry", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				wait = function() end,
				retry = { maxAttempts = 3, baseDelay = 0, maxDelay = 0, jitter = 0 },
				lease = { enabled = false },
			})
			expect(store:LoadAsync("eventual-success").ok).to.equal(true)
		end)

		it("keeps a record dirty after an exhausted save", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("DirtyFailure", {
				adapter = adapter,
				template = { Value = 0 },
				autosaveInterval = 0,
				wait = function() end,
				retry = { maxAttempts = 2, baseDelay = 0, maxDelay = 0, jitter = 0 },
				lease = { enabled = false },
			})
			local record = store:LoadAsync("record").value
			record:Set("Value", 1)
			adapter:SetFailurePlan("Update", 2)
			expect(record:SaveAsync().ok).to.equal(false)
			expect(record:IsDirty()).to.equal(true)
			adapter:SetFailurePlan("Update", 0)
			expect(record:SaveAsync().ok).to.equal(true)
			expect(record:IsDirty()).to.equal(false)
		end)

		it("does not retry failures classified as permanent", function()
			local adapter = OmniStore.Adapters.Memory.new()
			adapter:SetFailurePlan("Update", 2, "permanent", false, "Permanent")
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("PermanentFailure", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				wait = function() end,
				retry = { maxAttempts = 3, baseDelay = 0, maxDelay = 0, jitter = 0 },
				lease = { enabled = false },
			})
			local first = store:LoadAsync("record")
			local second = store:LoadAsync("record")
			expect(first.ok).to.equal(false)
			expect(first.error.category).to.equal("Permanent")
			expect(second.ok).to.equal(false)
		end)

		it("preserves an active dirty record when close reaches its deadline", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("CloseDeadline", {
				adapter = adapter,
				template = { Value = 0 },
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local record = store:LoadAsync("record").value
			record:Set("Value", 1)
			local closed = record:CloseAsync(0)
			expect(closed.ok).to.equal(false)
			expect(closed.error.code).to.equal("Timeout")
			expect(record.State).to.equal("Active")
			expect(record:IsDirty()).to.equal(true)
		end)

		it("rejects a load before persistence when its deadline is already exhausted", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("LoadDeadline", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local loaded = store:LoadAsync("record", 0)
			expect(loaded.ok).to.equal(false)
			expect(loaded.error.code).to.equal("Timeout")
			expect(adapter:Peek("record")).to.equal(nil)
		end)

		it("isolates persistence from failing diagnostic callbacks", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local logCalls = 0
			local metricCalls = 0
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("Diagnostics", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				lease = { enabled = false },
				logger = function()
					logCalls += 1
					error("logger failure")
				end,
				metrics = function()
					metricCalls += 1
					error("metrics failure")
				end,
			})
			local record = store:LoadAsync("record").value
			record:Set("Value", true)
			expect(record:SaveAsync().ok).to.equal(true)
			expect(metricCalls > 0).to.equal(true)
			-- A retry produces a log event while the callback still cannot break persistence.
			adapter:SetFailurePlan("Update", 1)
			expect(record:SaveAsync().ok).to.equal(true)
			expect(logCalls > 0).to.equal(true)
		end)

		it("closes a loaded entity through the generic lifecycle helper", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("EntityLifecycle", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			expect(store:LoadAsync("entity").ok).to.equal(true)
			expect(store:CloseRecordAsync("entity", 1).ok).to.equal(true)
			expect(store:GetLoadedRecord("entity")).to.equal(nil)
			expect(store:CloseRecordAsync("missing", 1).ok).to.equal(true)
		end)
	end)
end
