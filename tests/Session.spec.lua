--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	local function config(adapter, clock, staleLeasePolicy)
		return {
			adapter = adapter,
			template = { Value = 1 },
			autosaveInterval = 0,
			clock = clock,
			lease = {
				enabled = true,
				duration = 10,
				renewInterval = 5,
				acquireTimeout = 0,
				stealAfter = 0,
				staleLeasePolicy = staleLeasePolicy or "Recover",
			},
		}
	end

	describe("session semantics", function()
		it("writes diagnostic identity into new leases", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore(
				"Identity",
				config(adapter, function()
					return 100
				end, nil)
			)
			expect(store:LoadAsync("record").ok).to.equal(true)
			local stored = adapter:Peek("record")
			local session = database:GetSessionInfo()
			expect(stored.lease.owner).to.equal(session.owner)
			expect(stored.lease.sessionId).to.equal(session.sessionId)
			expect(stored.lease.jobId).to.equal(session.jobId)
			expect(stored.lease.placeId).to.equal(session.placeId)
			expect(stored.lease.universeId).to.equal(session.universeId)
			expect(stored.lease.acquiredAt).to.equal(100)
			expect(stored.lease.renewedAt).to.equal(100)
		end)

		it("reads a live locked record without claiming or mutating it", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local ownerDatabase = OmniStore.new({ autoBindToClose = false })
			local readerDatabase = OmniStore.new({ autoBindToClose = false })
			local ownerStore = ownerDatabase:GetStore(
				"Shared",
				config(adapter, function()
					return 100
				end, nil)
			)
			local readerStore = readerDatabase:GetStore(
				"Shared",
				config(adapter, function()
					return 100
				end, nil)
			)
			local owner = ownerStore:LoadAsync("record").value
			owner:Set("Value", 7)
			expect(owner:SaveAsync().ok).to.equal(true)
			local before = adapter:Peek("record")
			local loaded = readerStore:LoadAsync("record", { mode = "ReadOnly" })
			expect(loaded.ok).to.equal(true)
			local reader = loaded.value
			expect(reader:IsReadOnly()).to.equal(true)
			expect(reader:Get("Value").value).to.equal(7)
			local mutation = reader:Set("Value", 9)
			expect(mutation.ok).to.equal(false)
			expect(mutation.error.code).to.equal("ReadOnly")
			expect(reader:SaveAsync().error.code).to.equal("ReadOnly")
			local callbackRan = false
			local transaction = reader:Transaction(function()
				callbackRan = true
			end)
			expect(transaction.error.code).to.equal("ReadOnly")
			expect(callbackRan).to.equal(false)
			expect(reader:CloseAsync().ok).to.equal(true)
			local after = adapter:Peek("record")
			expect(after.lease.owner).to.equal(before.lease.owner)
			expect(after.revision).to.equal(before.revision)
		end)

		it("returns NotFound for a missing read-only record", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("Missing", config(adapter, os.time, nil))
			local loaded = store:LoadAsync("absent", { mode = "ReadOnly" })
			expect(loaded.ok).to.equal(false)
			expect(loaded.error.code).to.equal("NotFound")
			expect(adapter:Peek("absent")).to.equal(nil)
		end)

		it("recovers only expired leases when policy permits", function()
			local now = 100
			local function clock()
				return now
			end
			local adapter = OmniStore.Adapters.Memory.new()
			local firstDatabase = OmniStore.new({ autoBindToClose = false })
			local rejectDatabase = OmniStore.new({ autoBindToClose = false })
			local recoverDatabase = OmniStore.new({ autoBindToClose = false })
			local firstStore = firstDatabase:GetStore("Shared", config(adapter, clock, nil))
			local rejectStore = rejectDatabase:GetStore("Shared", config(adapter, clock, nil))
			local recoverStore = recoverDatabase:GetStore("Shared", config(adapter, clock, nil))
			local first = firstStore:LoadAsync("record").value
			now = 111
			local rejected = rejectStore:LoadAsync("record", { staleLeasePolicy = "Reject" })
			expect(rejected.ok).to.equal(false)
			expect(rejected.error.code).to.equal("Locked")
			expect(rejected.error.context.stale).to.equal(true)
			local recovered = recoverStore:LoadAsync("record")
			expect(recovered.ok).to.equal(true)
			local oldSave = first:SaveAsync()
			expect(oldSave.ok).to.equal(false)
			expect(oldSave.error.code).to.equal("LeaseLost")
		end)

		it("upgrades a legacy expired lease when it is recovered", function()
			local adapter = OmniStore.Adapters.Memory.new({
				legacy = {
					data = { Value = 3 },
					metadata = {},
					schemaVersion = 1,
					revision = 2,
					updatedAt = 40,
					lease = { owner = "legacy-owner", expiresAt = 50 },
				},
			})
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore(
				"Legacy",
				config(adapter, function()
					return 100
				end, nil)
			)
			expect(store:LoadAsync("legacy").ok).to.equal(true)
			local lease = adapter:Peek("legacy").lease
			expect(type(lease.sessionId)).to.equal("string")
			expect(type(lease.jobId)).to.equal("string")
			expect(lease.acquiredAt).to.equal(100)
			expect(lease.renewedAt).to.equal(100)
		end)

		it("allows exactly one winner in a simultaneous exclusive load race", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local firstDatabase = OmniStore.new({ autoBindToClose = false })
			local secondDatabase = OmniStore.new({ autoBindToClose = false })
			local firstStore = firstDatabase:GetStore("Race", config(adapter, os.time, nil))
			local secondStore = secondDatabase:GetStore("Race", config(adapter, os.time, nil))
			local gate = Instance.new("BindableEvent")
			local results = {}
			local function run(store)
				gate.Event:Wait()
				table.insert(results, store:LoadAsync("record"))
			end
			task.spawn(run, firstStore)
			task.spawn(run, secondStore)
			gate:Fire()
			while #results < 2 do
				task.wait()
			end
			local successes = 0
			for _, result in results do
				if result.ok then
					successes += 1
				else
					expect(result.error.code).to.equal("Locked")
				end
			end
			expect(successes).to.equal(1)
			gate:Destroy()
		end)
	end)
end
