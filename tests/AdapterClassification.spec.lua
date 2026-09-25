--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local OmniStore = require(ReplicatedStorage.Packages.OmniStore)
	local classifier = OmniStore.Adapters.DataStore.ClassifyError

	describe("DataStore error classification", function()
		it("classifies authorization failures as permanent", function()
			local category, retryable = classifier("HTTP 403: not authorized")
			expect(category).to.equal("Permanent")
			expect(retryable).to.equal(false)
		end)

		it("classifies throttling as retryable", function()
			local category, retryable = classifier("Request was throttled (HTTP 429)")
			expect(category).to.equal("Throttled")
			expect(retryable).to.equal(true)
		end)

		it("bounds unknown failures through the retry policy", function()
			local category, retryable = classifier("unrecognized platform failure")
			expect(category).to.equal("Unknown")
			expect(retryable).to.equal(true)
		end)
	end)
end
