--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
	local Schema = OmniStore.Schema

	describe("migrations", function()
		it("migrates then reconciles", function()
			local adapter = OmniStore.Adapters.Memory.new({
				legacy = {
					data = { Money = 8 },
					metadata = {},
					schemaVersion = 1,
					revision = 3,
					updatedAt = 1,
					lease = nil,
				},
			})
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("Migration", {
				adapter = adapter,
				template = { Coins = 0, Settings = { Music = true } },
				schemaVersion = 2,
				autosaveInterval = 0,
				lease = {
					enabled = false,
					duration = 120,
					renewInterval = 40,
					acquireTimeout = 0,
					stealAfter = 0,
				},
				migrations = {
					{
						from = 1,
						to = 2,
						migrate = function(data)
							data.Coins = data.Money
							data.Money = nil
							return data
						end,
					},
				},
			})
			local loaded = store:LoadAsync("legacy")
			expect(loaded.ok).to.equal(true)
			expect(loaded.value:Get("Coins").value).to.equal(8)
			expect(loaded.value:Get("Settings.Music").value).to.equal(true)
		end)

		it("validates the declared schema after every migration step", function()
			local adapter = OmniStore.Adapters.Memory.new({
				legacy = {
					data = { Coins = 1 },
					metadata = {},
					schemaVersion = 1,
					revision = 1,
					updatedAt = 1,
					lease = nil,
				},
			})
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("StepSchema", {
				adapter = adapter,
				template = { Coins = 0 },
				schemaVersion = 3,
				autosaveInterval = 0,
				lease = { enabled = false },
				migrations = {
					{
						from = 1,
						to = 2,
						schema = Schema.object({ Coins = Schema.number() }),
						migrate = function(data)
							data.Coins = "invalid intermediate value"
							return data
						end,
					},
					{
						from = 2,
						to = 3,
						migrate = function(data)
							data.Coins = 2
							return data
						end,
					},
				},
			})
			local loaded = store:LoadAsync("legacy")
			expect(loaded.ok).to.equal(false)
			expect(loaded.error.code).to.equal("MigrationFailed")
			expect(loaded.error.context.to).to.equal(2)
		end)

		it("rejects non-serializable intermediate migration output", function()
			local adapter = OmniStore.Adapters.Memory.new({
				legacy = {
					data = {},
					metadata = {},
					schemaVersion = 1,
					revision = 1,
					updatedAt = 1,
					lease = nil,
				},
			})
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("StepSerialization", {
				adapter = adapter,
				template = {},
				schemaVersion = 2,
				autosaveInterval = 0,
				lease = { enabled = false },
				migrations = {
					{
						from = 1,
						to = 2,
						migrate = function(data)
							data.Self = data
							return data
						end,
					},
				},
			})
			local loaded = store:LoadAsync("legacy")
			expect(loaded.ok).to.equal(false)
			expect(loaded.error.code).to.equal("MigrationFailed")
		end)
	end)
end
