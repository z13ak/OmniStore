--!strict
-- selene: allow(undefined_variable)

return function()
	local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)
	local Config = require(game.ReplicatedStorage.Packages.OmniStore.internal.Config)
	local LegacyStore = require(script.Parent.fixtures.LegacyStore)
	local LegacyCodecs = require(script.Parent.fixtures.LegacyCodecRegistry)
	local function stores(leaseEnabled)
		local adapter = OmniStore.Adapters.Memory.new()
		local options = {
			adapter = adapter,
			template = { Value = 0 },
			autosaveInterval = 0,
			lease = { enabled = leaseEnabled, acquireTimeout = 0 },
		}
		local currentDatabase = OmniStore.new({ autoBindToClose = false })
		local legacyDatabase = OmniStore.new({ autoBindToClose = false })
		local current = currentDatabase:GetStore("Current", options)
		local legacy = LegacyStore.new(
			"Legacy",
			Config.store(nil, options),
			"",
			legacyDatabase:GetSessionInfo()
		)
		return current, legacy, adapter
	end

	describe("release-candidate persistence compatibility", function()
		it("current readers accept ordinary records written by rc.3", function()
			local current, legacy = stores(false)
			local record = legacy:LoadAsync("record").value
			record:Set("Value", 7)
			expect(record:CloseAsync().ok).to.equal(true)
			local read = current:LoadAsync("record", { mode = "ReadOnly" })
			expect(read.ok).to.equal(true)
			expect(read.value:Get("Value").value).to.equal(7)
			current:CloseAsync()
			legacy:CloseAsync()
		end)

		it("rc.3 readers accept ordinary records with the new write token", function()
			local current, legacy, adapter = stores(false)
			local record = current:LoadAsync("record").value
			record:Set("Value", 8)
			expect(record:CloseAsync().ok).to.equal(true)
			expect(type(adapter:Peek("record").writeId)).to.equal("string")
			local read = legacy:LoadAsync("record", { mode = "ReadOnly" })
			expect(read.ok).to.equal(true)
			expect(read.value:Get("Value").value).to.equal(8)
			current:CloseAsync()
			legacy:CloseAsync()
		end)

		it("demonstrates why rc.3 readers must be drained before tombstone writes", function()
			local current, legacy = stores(false)
			expect(current:DeleteAsync("deleted").ok).to.equal(true)
			expect(current:LoadAsync("deleted", { mode = "ReadOnly" }).error.code).to.equal(
				"NotFound"
			)
			local oldRead = legacy:LoadAsync("deleted", { mode = "ReadOnly" })
			expect(oldRead.ok).to.equal(true)
			expect(oldRead.value:Get("Value").value).to.equal(0)
			current:CloseAsync()
			legacy:CloseAsync()
		end)

		it("demonstrates why rc.3 readers cannot read escaped marker tables", function()
			local current = OmniStore.CodecRegistry.new()
			local legacy = LegacyCodecs.new()
			local input = { __omniCodec = 1, typeId = "game.Literal/v1", value = "literal" }
			local wire = current:Encode(input).value
			expect(current:Decode(wire).ok).to.equal(true)
			local oldRead = legacy:Decode(wire)
			expect(oldRead.error.code).to.equal("InvalidData")
			expect(oldRead.error.context.typeId).to.equal("omnistore.PlainTable/v1")
		end)

		it("demonstrates that an old deleter can bypass a new live lease", function()
			local current, legacy, adapter = stores(true)
			local record = current:LoadAsync("record").value
			local before = adapter:Peek("record")
			expect(legacy:DeleteAsync("record").ok).to.equal(true)
			expect(adapter:Peek("record")).to.equal(nil)
			expect(record:SaveAsync().error.code).to.equal("Conflict")
			-- Restore the fixture solely to dispose of its in-memory leased handle cleanly.
			adapter:Update("record", function()
				return before
			end)
			current:CloseAsync()
			legacy:CloseAsync()
		end)
	end)
end
