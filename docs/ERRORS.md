# Error reference

Every failure-capable operation returns `{ ok = false, error = ... }`. `retryable` and `category`
describe the specific failure instance; do not decide retry behavior from the code alone.

| Code | Meaning |
| --- | --- |
| `AlreadyLoaded` | Loading was attempted again for the same record object/key lifecycle. |
| `Cancelled` | Work ended without a completed result, commonly after coordinated save state changed. |
| `Closed` | The manager, store, record, replicator, or mirror is closed/destroyed. |
| `Conflict` | Local state conflicts with the requested operation, including nested transactions or duplicate registrations. |
| `InvalidConfig` | Configuration, model definition, path allowlist, or required adapter capability is invalid. |
| `InvalidData` | A value/path/payload is unsupported, malformed, cyclic, too deep, or too large. |
| `InvalidKey` | A persistence key is empty, unsupported, or exceeds Roblox's byte limit after prefixing. |
| `LeaseLost` | An atomic update proved that this session no longer owns the key. |
| `Locked` | Another unexpired session owns the key, or stale policy rejects takeover. |
| `MigrationFailed` | No valid migration path exists or a migration callback/output failed. |
| `NotLoaded` | An operation requires an active loaded record. |
| `NotFound` | A read-only load found no stored envelope. |
| `PersistenceFailed` | The adapter or platform request failed. Inspect category and cause. |
| `ReadOnly` | A mutation/save was attempted through a read-only record. |
| `Timeout` | A configured deadline elapsed while waiting for budget, retry, save, or close coordination. |
| `TransactionFailed` | A transaction or draft-update callback errored or attempted to yield. |
| `ValidationFailed` | The configured schema/custom validator rejected a value. |

Categories are `Transient`, `Throttled`, `Permanent`, and `Unknown`. Causes and context are diagnostic
and may contain platform-dependent text; do not parse them as a stable API. Log codes/categories and
bounded context, but avoid recording full persistent payloads.
