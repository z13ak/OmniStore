# Reliability and diagnostics

## Lifecycle coordination

Close entity records from the authoritative removal signal, and give the operation a deadline:

```lua
Players.PlayerRemoving:Connect(function(player)
    local result = profiles:CloseRecordAsync(player.UserId, 10)
    if not result.ok then
        warn(result.error.code, result.error.category)
    end
end)
```

`autoBindToClose` remains the final server-shutdown safety net. Neither hook guarantees completion
if the process terminates or Roblox DataStoreService is unavailable. Autosave controls the likely
loss window.

## Structured events

Pass protected callbacks through store config. Logger and metrics failures are ignored so
instrumentation cannot break persistence:

```lua
local store = database:GetStore("Profiles", {
    logger = function(event)
        print(event.level, event.event, event.message, event.context)
    end,
    metrics = function(metric)
        Metrics.increment(metric.name, metric.value, metric.tags)
    end,
})
```

Current events include retry scheduling, exhausted persistence operations, request-budget timeout,
background saturation/errors, autosave failure, lease renewal/loss, successful load/save, and close
timeout. Context intentionally omits raw record keys by default; applications should avoid placing
personal data in custom logs.

## Scheduler behavior

Autosaves and lease renewals share one scheduler per store. The concurrency limit bounds simultaneous
background persistence work, while manual calls remain responsive and use save coalescing per record.
The queue contains the recurring jobs for records currently loaded; it is not durable and disappears
with the server process.
