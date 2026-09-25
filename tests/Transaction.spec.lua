--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
	local Schema = OmniStore.Schema

	local function makeRecord(name)
		local adapter = OmniStore.Adapters.Memory.new()
		local database = OmniStore.new({ autoBindToClose = false })
		local store = database:GetStore(name, {
			adapter = adapter,
			template = { Coins = 0, Label = "valid", Inventory = {} },
			schema = Schema.object({
				Coins = Schema.number({ integer = true, min = 0 }),
				Label = Schema.string(),
				Inventory = Schema.array(Schema.string()),
			}),
			autosaveInterval = 0,
			lease = { enabled = false },
		})
		return store:LoadAsync("record").value, adapter
	end

	describe("isolated transactions", function()
		it("keeps draft changes invisible until commit", function()
			local record = makeRecord("TransactionIsolation")
			local result = record:Transaction(function(draft)
				expect(draft:Set("Coins", 10).ok).to.equal(true)
				expect(draft:Get("Coins").value).to.equal(10)
				expect(record:Get("Coins").value).to.equal(0)
			end)
			expect(result.ok).to.equal(true)
			expect(record:Get("Coins").value).to.equal(10)
		end)

		it("fires buffered observers only after committed data is visible", function()
			local record = makeRecord("TransactionObservers")
			local eventCount = 0
			local observersSawCommittedData = true
			record.Changed:Connect(function()
				eventCount += 1
				observersSawCommittedData = observersSawCommittedData
					and record:Get("Coins").value == 2
			end)
			local result = record:Transaction(function(draft)
				draft:Set("Coins", 1)
				draft:Set("Coins", 2)
				expect(eventCount).to.equal(0)
			end)
			expect(result.ok).to.equal(true)
			task.wait()
			expect(eventCount).to.equal(2)
			expect(observersSawCommittedData).to.equal(true)
		end)

		it("discards callback errors without observer leakage", function()
			local record = makeRecord("TransactionError")
			local eventCount = 0
			record.Changed:Connect(function()
				eventCount += 1
			end)
			local result = record:Transaction(function(draft)
				draft:Set("Coins", 10)
				error("abort")
			end)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("TransactionFailed")
			expect(record:Get("Coins").value).to.equal(0)
			task.wait()
			expect(eventCount).to.equal(0)
		end)

		it("rejects yielding callbacks and discards their drafts", function()
			local record = makeRecord("TransactionYield")
			local result = record:Transaction(function(draft)
				draft:Set("Coins", 10)
				task.wait()
				draft:Set("Coins", 20)
			end)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("TransactionFailed")
			expect(record:Get("Coins").value).to.equal(0)
		end)

		it("locks live-record writes while the draft callback runs", function()
			local record = makeRecord("TransactionLock")
			local liveWrite: any = nil
			local result = record:Transaction(function(draft)
				liveWrite = record:Set("Coins", 99)
				draft:Set("Coins", 3)
			end)
			expect(result.ok).to.equal(true)
			expect(liveWrite.ok).to.equal(false)
			expect(liveWrite.error.code).to.equal("Conflict")
			expect(record:Get("Coins").value).to.equal(3)
		end)

		it("allows temporary schema violations but validates the final draft", function()
			local record = makeRecord("TransactionFinalSchema")
			local valid = record:Transaction(function(draft)
				draft:Set("Coins", "temporary")
				draft:Set("Coins", 4)
			end)
			expect(valid.ok).to.equal(true)
			expect(record:Get("Coins").value).to.equal(4)

			local invalid = record:Transaction(function(draft)
				draft:Set("Coins", -1)
			end)
			expect(invalid.ok).to.equal(false)
			expect(invalid.error.code).to.equal("ValidationFailed")
			expect(record:Get("Coins").value).to.equal(4)
		end)

		it("aborts when a draft mutation failure is ignored", function()
			local record = makeRecord("TransactionStickyFailure")
			local result = record:Transaction(function(draft)
				draft:Set("Coins", 2)
				draft:Increment("Label", 1)
			end)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("InvalidData")
			expect(record:Get("Coins").value).to.equal(0)
		end)

		it("commits metadata locally but remains non-durable until save", function()
			local record, adapter = makeRecord("TransactionDurability")
			local result = record:Transaction(function(draft)
				draft:Set("Coins", 8)
				draft:SetMetadata("reason", "test")
			end)
			expect(result.ok).to.equal(true)
			expect(record:GetMetadata("reason").value).to.equal("test")
			expect(adapter:Peek("record").data.Coins).to.equal(0)
			expect(record:SaveAsync().ok).to.equal(true)
			expect(adapter:Peek("record").data.Coins).to.equal(8)
		end)
	end)
end
