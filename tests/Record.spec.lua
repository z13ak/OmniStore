--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	local function makeStore(options)
		local adapter = OmniStore.Adapters.Memory.new(options and options.seed)
		local database = OmniStore.new({ autoBindToClose = false })
		local config = {
			adapter = adapter,
			template = { Coins = 0, Inventory = {}, Nested = { Enabled = true } },
			autosaveInterval = 0,
			lease = {
				enabled = false,
				duration = 120,
				renewInterval = 40,
				acquireTimeout = 0,
				stealAfter = 0,
			},
		}
		if options and options.config then
			for key, value in options.config do
				config[key] = value
			end
		end
		return database:GetStore("Test", config), adapter, database
	end

	describe("Record", function()
		it("reconciles and applies path mutations", function()
			local store = makeStore(nil)
			local loaded = store:LoadAsync("alpha")
			expect(loaded.ok).to.equal(true)
			local record = loaded.value
			expect(record:Increment("Coins", 5).value).to.equal(5)
			expect(record:Insert("Inventory", { Id = "Sword" }).value).to.equal(1)
			expect(record:Set("Nested.Enabled", false).ok).to.equal(true)
			expect(record:Get("Nested.Enabled").value).to.equal(false)
			expect(record:IsDirty()).to.equal(true)
		end)

		it("rolls back a failed transaction", function()
			local store = makeStore(nil)
			local record = store:LoadAsync("rollback").value
			local result = record:Transaction(function(active)
				active:Set("Coins", 99)
				error("abort")
			end)
			expect(result.ok).to.equal(false)
			expect(record:Get("Coins").value).to.equal(0)
		end)

		it("rejects cyclic values before mutation", function()
			local store = makeStore(nil)
			local record = store:LoadAsync("cycle").value
			local cyclic = {}
			cyclic.self = cyclic
			local result = record:Set("Cycle", cyclic)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("InvalidData")
		end)

		it("rolls back the whole path when validation fails", function()
			local store = makeStore(nil)
			local record = store:LoadAsync("path-rollback").value
			local result = record:Set("Temporary.Deep.Value", 0 / 0)
			expect(result.ok).to.equal(false)
			expect(record:Get("Temporary").value).to.equal(nil)
		end)

		it("rejects sparse and mixed-key tables", function()
			local store = makeStore(nil)
			local record = store:LoadAsync("table-shapes").value
			local mixed: any = { "value" }
			mixed.Named = true
			expect(record:Set("Sparse", { [2] = "value" }).ok).to.equal(false)
			expect(record:Set("Mixed", mixed).ok).to.equal(false)
		end)

		it("rejects structures deeper than the configured limit", function()
			local store = makeStore({ config = { maxSerializationDepth = 4 } })
			local record = store:LoadAsync("depth").value
			local deep = {}
			local cursor = deep
			for index = 1, 6 do
				local child = { Index = index }
				cursor.Child = child
				cursor = child
			end
			local result = record:Set("Deep", deep)
			expect(result.ok).to.equal(false)
			expect(result.error.code).to.equal("InvalidData")
		end)

		it("enforces a configurable payload limit", function()
			local store = makeStore({ config = { maxPayloadBytes = 512 } })
			local record = store:LoadAsync("payload").value
			local result = record:Set("Blob", string.rep("x", 600))
			expect(result.ok).to.equal(false)
			expect(result.error.context.maxPayloadBytes).to.equal(512)
		end)

		it("persists and releases on close", function()
			local store, adapter = makeStore(nil)
			local record = store:LoadAsync("save").value
			record:Set("Coins", 12)
			expect(record:CloseAsync().ok).to.equal(true)
			local stored = adapter:Peek("save")
			expect(stored.data.Coins).to.equal(12)
			expect(stored.lease).to.equal(nil)
		end)
	end)
end
