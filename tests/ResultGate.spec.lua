--!strict
-- selene: allow(undefined_variable)

return function()
	local Gate = require(script.Parent.ResultGate)
	describe("test release gate", function()
		it("accepts executed passing tests", function()
			expect(Gate.check({ successCount = 2, failureCount = 0, errors = {} })).to.equal(true)
		end)
		it("rejects a planning error even when no assertions failed", function()
			expect(Gate.check({
				successCount = 2,
				failureCount = 0,
				children = {
					{ errors = { "spec failed to load" } },
				},
			})).to.equal(false)
		end)
		it("rejects assertion failures", function()
			expect(Gate.check({ successCount = 1, failureCount = 1 })).to.equal(false)
		end)
		it("rejects a run that executed no tests", function()
			expect(Gate.check({ successCount = 0, failureCount = 0, skippedCount = 3 })).to.equal(
				false
			)
		end)
	end)
end
