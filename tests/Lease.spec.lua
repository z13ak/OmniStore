--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)

	describe("session leases", function()
		it("rejects a second live owner and permits it after close", function()
			local adapter = OmniStore.Adapters.Memory.new()
			local lease = {
				enabled = true,
				duration = 120,
				renewInterval = 40,
				acquireTimeout = 0,
				stealAfter = 0,
			}
			local firstDatabase = OmniStore.new({ autoBindToClose = false })
			local secondDatabase = OmniStore.new({ autoBindToClose = false })
			local first = firstDatabase:GetStore("Shared", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				lease = lease,
			})
			local second = secondDatabase:GetStore("Shared", {
				adapter = adapter,
				template = {},
				autosaveInterval = 0,
				lease = lease,
			})

			local owned = first:LoadAsync("one")
			expect(owned.ok).to.equal(true)
			local blocked = second:LoadAsync("one")
			expect(blocked.ok).to.equal(false)
			expect(blocked.error.code).to.equal("Locked")
			expect(owned.value:CloseAsync().ok).to.equal(true)
			expect(second:LoadAsync("one").ok).to.equal(true)
		end)
	end)
end
