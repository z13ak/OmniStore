--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestEZ = require(ReplicatedStorage.Packages.TestEZ)

local results = TestEZ.TestBootstrap:run({ script })
if results.failureCount > 0 then
	error(`OmniStore tests failed: {results.failureCount} failure(s)`)
end
