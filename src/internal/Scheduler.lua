--!strict

export type Job = {
	Cancelled: boolean,
	Cancel: (self: Job) -> (),
}

type InternalJob = Job & {
	dueAt: number,
	callback: () -> number?,
	running: boolean,
	saturationReported: boolean,
}

export type Scheduler = typeof(setmetatable(
	{} :: {
		_clock: () -> number,
		_tick: number,
		_maxConcurrent: number,
		_jobs: { InternalJob },
		_running: number,
		_closed: boolean,
		_started: boolean,
		_onSaturated: (() -> ())?,
		_onError: ((unknown) -> ())?,
	},
	{} :: any
))

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(
	clock: () -> number,
	tickInterval: number,
	maxConcurrent: number,
	onSaturated: (() -> ())?,
	onError: ((unknown) -> ())?
): Scheduler
	return setmetatable({
		_clock = clock,
		_tick = tickInterval,
		_maxConcurrent = maxConcurrent,
		_jobs = {},
		_running = 0,
		_closed = false,
		_started = false,
		_onSaturated = onSaturated,
		_onError = onError,
	}, Scheduler) :: any
end

function Scheduler:_start()
	if self._started then
		return
	end
	self._started = true
	task.spawn(function()
		while not self._closed do
			self:Step()
			task.wait(self._tick)
		end
	end)
end

function Scheduler:Schedule(delay: number, callback: () -> number?): Job
	assert(not self._closed, "scheduler is closed")
	local job: InternalJob
	job = {
		Cancelled = false,
		dueAt = self._clock() + math.max(0, delay),
		callback = callback,
		running = false,
		saturationReported = false,
		Cancel = function(selfJob: InternalJob)
			selfJob.Cancelled = true
		end,
	}
	table.insert(self._jobs, job)
	self:_start()
	return job
end

function Scheduler:Step()
	if self._closed then
		return
	end
	local now = self._clock()
	for index = #self._jobs, 1, -1 do
		local job = self._jobs[index]
		if job.Cancelled and not job.running then
			table.remove(self._jobs, index)
		elseif not job.running and job.dueAt <= now then
			if self._running >= self._maxConcurrent then
				if self._onSaturated and not job.saturationReported then
					job.saturationReported = true
					self._onSaturated()
				end
			else
				job.running = true
				job.saturationReported = false
				self._running += 1
				task.spawn(function()
					local ok, nextDelay = pcall(job.callback)
					self._running -= 1
					job.running = false
					if not ok and self._onError then
						self._onError(nextDelay)
					end
					if not ok or nextDelay == nil or job.Cancelled or self._closed then
						job.Cancelled = true
					else
						job.dueAt = self._clock() + math.max(0, nextDelay)
					end
				end)
			end
		end
	end
end

function Scheduler:Close()
	self._closed = true
	for _, job in self._jobs do
		job.Cancelled = true
	end
	table.clear(self._jobs)
end

function Scheduler:GetStats(): { queued: number, running: number, limit: number }
	local queued = 0
	for _, job in self._jobs do
		if not job.Cancelled and not job.running then
			queued += 1
		end
	end
	return { queued = queued, running = self._running, limit = self._maxConcurrent }
end

return Scheduler
