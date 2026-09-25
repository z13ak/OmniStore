--!strict
-- selene: allow(undefined_variable)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Scheduler = require(ReplicatedStorage.Packages.OmniStore.internal.Scheduler)

	describe("background scheduler", function()
		it("never starts more callbacks than its concurrency limit", function()
			local release = Instance.new("BindableEvent")
			local started = 0
			local scheduler = Scheduler.new(function()
				return 0
			end, 60, 1, nil, nil)
			local function blockingJob()
				started += 1
				release.Event:Wait()
				return nil
			end
			scheduler:Schedule(0, blockingJob)
			scheduler:Schedule(0, blockingJob)
			scheduler:Step()
			task.wait()
			local stats = scheduler:GetStats()
			expect(started).to.equal(1)
			expect(stats.running).to.equal(1)
			expect(stats.queued).to.equal(1)
			scheduler:Close()
			release:Fire()
			release:Destroy()
		end)
	end)
end
