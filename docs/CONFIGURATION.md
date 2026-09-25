# Configuration

## Manager configuration

| Field | Default | Meaning |
| --- | --- | --- |
| `namespace` | `"OmniStore"` | Prefix for automatically created DataStore names. |
| `keyPrefix` | `""` | Prefix applied to every key. Counts toward the 50-byte limit. |
| `autoBindToClose` | `true` | Register graceful shutdown on the server. |
| `closeTimeout` | `25` | Overall default deadline used by manager shutdown. |
| `defaultStoreConfig` | `{}` | Defaults merged into every store configuration. |

## Store configuration

| Field | Default | Meaning |
| --- | --- | --- |
| `adapter` | DataStore adapter | Persistence backend. |
| `model` | none | Model definition binding type ID, version, schema, template, migrations, and codecs. |
| `schema` | none | Composable `OmniStore.Schema` validator. |
| `codecs` | none | Codec registry used before persistence and after load. |
| `template` | `{}` | Initial data and reconciliation source. |
| `validate` | none | `(data) -> (boolean, message?)` schema validator. |
| `reconcile` | `true` | Add missing template fields without deleting unknown fields. |
| `schemaVersion` | `1` | Current positive schema version. |
| `migrations` | `{}` | Ordered migration graph, selected by `from`. |
| `maxSerializationDepth` | `64` | Maximum nested table depth accepted before mutation, load, or save. |
| `maxPayloadBytes` | `4,000,000` | Maximum JSON-encoded bytes accepted for a value or stored envelope. |
| `autosaveInterval` | `60` | Seconds between dirty checks; `0` disables autosave. |
| `autosaveJitter` | `10` | Symmetric random spread to avoid request spikes. |
| `maxConcurrentBackgroundTasks` | `4` | Maximum autosave/renew callbacks running per store. |
| `backgroundTick` | `0.25` | Seconds between scheduler due-job scans. |
| `requestBudgetTimeout` | `10` | Maximum seconds spent waiting for request budget. |
| `closeTimeout` | `25` | Default record/store close deadline. |
| `metadata` | `{}` | Initial metadata for new records. |
| `logger` | none | Protected callback receiving structured diagnostic events. |
| `metrics` | none | Protected callback receiving counters and string tags. |
| `clock`, `monotonicClock`, `wait`, `random` | platform defaults | Dependency injection points for tests. |

Retry defaults are five attempts, 0.5-second base delay, 8-second maximum delay, and 25% jitter.
Only failures marked retryable are retried.

The production adapter classifies recognized authorization/configuration failures as permanent,
throttling as retryable `Throttled`, common service/timeout failures as `Transient`, and unrecognized
platform messages as retryable `Unknown`. Every retry remains bounded by attempts and deadlines.

Lease defaults are enabled, 120-second duration, 40-second renewal, 30-second acquisition timeout,
zero additional `stealAfter` grace, and `staleLeasePolicy = "Recover"`. Renewal must be shorter than
duration. Larger grace reduces false takeover risk after pauses but increases reconnect delay.

`staleLeasePolicy = "Reject"` refuses an expired foreign lease instead of recovering it. This is
useful for manual investigation but can strand records until policy changes. Neither policy permits
overwriting an unexpired foreign lease.

Use one consistent lease policy across servers sharing a store. Disabling leases is appropriate for
tests or workloads whose keys are intentionally written concurrently, but it removes session
ownership protection.

Store-level `retry` and `lease` tables are partial overrides. Omitted fields inherit the manager's
`defaultStoreConfig` values rather than resetting to library defaults.

When `model` is supplied, its schema, version, migrations, template, and codecs become store
defaults. Explicit conflicting `schemaVersion` configuration is rejected. Prefer defining the full
contract in the model rather than overriding individual model fields.

The depth and payload limits are defensive application limits, not a replacement for Roblox's own
DataStore validation and limits. Lower them when a schema has tighter bounds. Raising the payload
limit reduces safety headroom and does not make Roblox accept larger values.

## Replication configuration

Server defaults are 128,000 snapshot bytes, 32,000 change bytes, 32 payload levels, 8 snapshot
requests per 10 seconds, 8 channels per player, 32 allowlisted paths per channel, 64 channel bytes,
and 32 path segments. The optional `logger(event, message)` callback is protected from propagating
errors. Limits are conservative estimates rather than Roblox wire-byte measurements.

Client defaults mirror the server payload/depth/path limits, wait up to 10 seconds for remotes, keep
at most 128 changes queued during synchronization, and wait at least one second between automatic
resync requests. Server and client payload limits should match; the server remains authoritative.
