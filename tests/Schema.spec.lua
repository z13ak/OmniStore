--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
	local Schema = OmniStore.Schema

	describe("composable schemas", function()
		it("reports the nested path of structural failures", function()
			local schema = Schema.object({
				Name = Schema.string({ minLength = 1, maxLength = 12 }),
				Stats = Schema.object({
					Level = Schema.number({ integer = true, min = 1 }),
				}),
				Tags = Schema.array(Schema.string(), { maxLength = 2 }),
			})
			local ok, message = schema:Validate({
				Name = "Example",
				Stats = { Level = 0 },
				Tags = {},
			})
			expect(ok).to.equal(false)
			expect(string.find(message, "$.Stats.Level", 1, true) ~= nil).to.equal(true)
		end)

		it("supports optional, union, map, and unknown-field policy", function()
			local schema = Schema.object({
				Alias = Schema.optional(Schema.string()),
				Choice = Schema.union(Schema.literal("auto"), Schema.number({ min = 0 })),
				Flags = Schema.map(Schema.boolean()),
			}, { allowUnknown = true })
			expect(schema:Validate({ Choice = "auto", Flags = { Enabled = true }, Extra = 1 })).to.equal(
				true
			)
			expect(schema:Validate({ Choice = -1, Flags = {} })).to.equal(false)
		end)

		it("rejects invalid record mutations without changing data", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("SchemaMutation", {
				adapter = adapter,
				template = { Coins = 0 },
				schema = Schema.object({ Coins = Schema.number({ integer = true, min = 0 }) }),
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local record = store:LoadAsync("record").value
			local changed = record:Set("Coins", -1)
			expect(changed.ok).to.equal(false)
			expect(changed.error.code).to.equal("ValidationFailed")
			expect(record:Get("Coins").value).to.equal(0)
		end)
	end)
end
