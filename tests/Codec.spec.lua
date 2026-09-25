--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	describe("codec registry", function()
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
