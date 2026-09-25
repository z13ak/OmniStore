--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
	local Schema = OmniStore.Schema

	local function model(typeId, allowLegacy)
		return OmniStore.Model.define({
			typeId = typeId,
			version = 1,
			template = { Coins = 0 },
			schema = Schema.object({ Coins = Schema.number({ integer = true, min = 0 }) }),
			allowLegacy = allowLegacy,
		})
	end

	describe("model definitions", function()
		it("binds type ID, version, template, and schema to a store", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("Profiles", {
				adapter = adapter,
				model = model("game.Profile/v1", true),
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local record = store:LoadAsync("record").value
			expect(record:Get("Coins").value).to.equal(0)
			expect(record:Set("Coins", -2).ok).to.equal(false)
			expect(adapter:Peek("record").typeId).to.equal("game.Profile/v1")
		end)

		it("rejects a stored record belonging to another model", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local firstDatabase = OmniStore.new({ autoBindToClose = false })
			local firstStore = firstDatabase:GetStore("Models", {
				adapter = adapter,
				model = model("game.First/v1", true),
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local first = firstStore:LoadAsync("record").value
			expect(first:CloseAsync().ok).to.equal(true)

			local secondDatabase = OmniStore.new({ autoBindToClose = false })
			local secondStore = secondDatabase:GetStore("Models", {
				adapter = adapter,
				model = model("game.Second/v1", true),
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local loaded = secondStore:LoadAsync("record")
			expect(loaded.ok).to.equal(false)
			expect(loaded.error.code).to.equal("InvalidData")
			expect(loaded.error.context.actualTypeId).to.equal("game.First/v1")
		end)

		it("can forbid adoption of untyped legacy records", function()
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
			local store = database:GetStore("StrictModel", {
				adapter = adapter,
				model = model("game.Strict/v1", false),
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local loaded = store:LoadAsync("legacy")
			expect(loaded.ok).to.equal(false)
			expect(loaded.error.context.expectedTypeId).to.equal("game.Strict/v1")
		end)
	end)
end
