# Performance and capacity

OmniStore trades some request volume for ownership safety. Measure with production-like record counts
and mutation rates before choosing intervals.

## Request model

An exclusive load uses an update request. A save, lease renewal, or close also uses an update request;
a read-only load uses a read request. Retries multiply those costs during throttling or outages.
Autosave checks do not write clean records, but lease renewals run for every active exclusive record.

Approximate steady-state update requests per minute before retries:

```text
dirty autosaves ~= dirty records * 60 / autosaveInterval
lease renewals  ~= exclusive records * 60 / renewInterval
```

Loads, closes, manual saves, and retry attempts are additional. This is a planning estimate, not a
Roblox quota promise; actual budgets vary by platform conditions and universe activity.

## Tuning guidance

- Keep `renewInterval` comfortably below lease duration. The default is 40 seconds for a 120-second
  lease; increasing both lowers request frequency but lengthens stale-session recovery.
- Add autosave jitter and avoid synchronized mass loads/saves after round transitions.
- Set `maxConcurrentBackgroundTasks` from measured latency and request budget, not player count alone.
- Coalesce game mutations locally and avoid calling `SaveAsync` after every small change.
- Split unrelated large entities when their lifecycle and consistency needs differ, but remember
  operations across records are not atomic.
- Keep schemas and migration work linear in payload size and callbacks non-yielding.
- Choose replication allowlists narrowly; a parent path may resend a larger subtree on replacement.

## Payloads and memory

The default persistence safety limit is 4,000,000 JSON bytes and the default traversal depth is 64.
Those are rejection ceilings, not recommended targets. Large records cost more memory, serialization
time, network time, and recovery time. Maintain substantial headroom below both OmniStore and Roblox
limits and load-test the largest expected record.

Record reads and transaction drafts make defensive deep copies. Peak memory can temporarily include
the live value, a draft or save snapshot, encoded data, and observer copies. Avoid retaining full
record snapshots or transaction drafts.

Replication defaults to estimated 128,000-byte snapshots and 32,000-byte changes. Accounting is
conservative rather than exact wire sizing. High-frequency replicated paths should contain compact
presentation data, not full persistent records.

## Capacity test checklist

Measure load/save latency percentiles, adapter attempts, throttled/transient failures, background
queue depth, concurrent task saturation, dirty duration, lease loss, close timeouts, payload size,
Lua memory, and replication resync rate. Test normal traffic, burst joins, intentional throttling,
slow adapter responses, and shutdown. Use the logger/metrics callbacks to feed the game's existing
observability system.
