--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	describe("codec registry", function()
		it("round-trips ordinary tables that resemble registered codecs", function()
			local registry = OmniStore.CodecRegistry.new()
			OmniStore.Codecs.Roblox.registerAll(registry)
			local input = {
				__omniCodec = 1,
				typeId = "roblox.Vector3/v1",
				value = { 1, 2, 3 },
				Extra = "ordinary data",
				Position = Vector3.one,
			}
			local result = registry:Decode(registry:Encode(input).value)
			expect(result.ok).to.equal(true)
			expect(type(result.value)).to.equal("table")
			expect(result.value.Extra).to.equal("ordinary data")
			expect(result.value.typeId).to.equal(input.typeId)
			expect(result.value.value[3]).to.equal(3)
			expect(result.value.Position).to.equal(Vector3.one)
		end)

		it("escapes unknown and escape-marker tables at nested paths", function()
			local registry = OmniStore.CodecRegistry.new()
			for _, typeId in { "game.Future/v1", "omnistore.PlainTable/v1" } do
				local input = { Nested = { __omniCodec = 1, typeId = typeId, value = "literal" } }
				local result = registry:Decode(registry:Encode(input).value)
				expect(result.ok).to.equal(true)
				expect(result.value.Nested.typeId).to.equal(typeId)
				expect(result.value.Nested.value).to.equal("literal")
			end
		end)

		it("can re-encode preserved unknown wire values without changing their data", function()
			local registry = OmniStore.CodecRegistry.new({ unknownTypePolicy = "Preserve" })
			local wire = { __omniCodec = 1, typeId = "game.Future/v1", value = { Name = "future" } }
			local preserved = registry:Decode(wire)
			local result = registry:Decode(registry:Encode(preserved.value).value)
			expect(result.ok).to.equal(true)
			expect(result.value.typeId).to.equal(wire.typeId)
			expect(result.value.value.Name).to.equal("future")
		end)

		it("rejects malformed escape payloads", function()
			local registry = OmniStore.CodecRegistry.new()
			local result =
				registry:Decode({ __omniCodec = 1, typeId = "omnistore.PlainTable/v1", value = 4 })
			expect(result.ok).to.equal(false)
		end)

		it("round-trips registered Roblox datatypes through persistence", function()
			local codecs = OmniStore.CodecRegistry.new()
			OmniStore.Codecs.Roblox.registerAll(codecs)
			local adapter = OmniStore.Adapters.Memory.new()
			local database = OmniStore.new({ autoBindToClose = false })
			local store = database:GetStore("CodecRoundTrip", {
				adapter = adapter,
				codecs = codecs,
				template = { Position = Vector3.zero },
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local record = store:LoadAsync("record").value
			local expected = Vector3.new(1.5, -2, 8)
			expect(record:Set("Position", expected).ok).to.equal(true)
			expect(record:SaveAsync().ok).to.equal(true)
			local wire = adapter:Peek("record").data.Position
			expect(wire.__omniCodec).to.equal(1)
			expect(wire.typeId).to.equal("roblox.Vector3/v1")
			expect(record:CloseAsync().ok).to.equal(true)

			local readerDatabase = OmniStore.new({ autoBindToClose = false })
			local readerStore = readerDatabase:GetStore("CodecRoundTrip", {
				adapter = adapter,
				codecs = codecs,
				autosaveInterval = 0,
				lease = { enabled = false },
			})
			local loaded = readerStore:LoadAsync("record", { mode = "ReadOnly" }).value
			expect(loaded:Get("Position").value).to.equal(expected)
		end)

		it("rejects unknown type IDs by default", function()
			local registry = OmniStore.CodecRegistry.new()
			local decoded = registry:Decode({
				__omniCodec = 1,
				typeId = "game.Unknown/v1",
				value = { 1, 2 },
			})
			expect(decoded.ok).to.equal(false)
			expect(decoded.error.context.typeId).to.equal("game.Unknown/v1")
		end)

		it("preserves unknown encoded values when configured", function()
			local registry = OmniStore.CodecRegistry.new({ unknownTypePolicy = "Preserve" })
			local encoded = {
				__omniCodec = 1,
				typeId = "game.Future/v3",
				value = { Name = "future" },
			}
			local decoded = registry:Decode(encoded)
			expect(decoded.ok).to.equal(true)
			expect(decoded.value.typeId).to.equal("game.Future/v3")
			expect(decoded.value.value.Name).to.equal("future")
		end)

		it("rejects duplicate stable type IDs", function()
			local registry = OmniStore.CodecRegistry.new()
			local codec = {
				typeId = "game.Test/v1",
				isType = function()
					return false
				end,
				encode = function(value)
					return value
				end,
				decode = function(value)
					return value
				end,
			}
			registry:Register(codec)
			local ok = pcall(function()
				registry:Register(codec)
			end)
			expect(ok).to.equal(false)
		end)
	end)
end
