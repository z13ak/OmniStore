--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
local ResultGate = require(script.ResultGate)

local results = TestEZ.TestBootstrap:run({ script })
local ok, message = ResultGate.check(results)
script:SetAttribute("Passed", results.successCount)
script:SetAttribute("GatePassed", ok)
script:SetAttribute("Complete", true)
assert(ok, message)
