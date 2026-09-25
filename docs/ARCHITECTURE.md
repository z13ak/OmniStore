# Architecture

## Object model

`OmniStore` owns a process/session identity and named `Store` instances. A `Store` owns schema,
lease, retry, adapter, key-prefix configuration, and one bounded background scheduler. A loaded
`Record` owns one key's local data, metadata, state machine, signals, and scheduled job handles.
`Data` is accessed through defensive-copy reads and mutation methods.

Record states are:

`New -> Loading -> Active -> Closing -> Closed`

An active record can enter `LeaseLost` when an atomic save or renewal proves another session owns
the key. It must not continue mutating persistent state after that point.

## Stored envelope

Each adapter value is one table:

```lua
{
    data = { ... },
    metadata = { ... },
    typeId = "game.Profile",
    schemaVersion = 3,
    revision = 42,
    updatedAt = 1789990000,
    lease = {
        owner = "job-guid:session-guid",
        sessionId = "session-guid",
        jobId = "job-guid",
        placeId = 123,
        universeId = 456,
        acquiredAt = 1789990000,
        renewedAt = 1789990040,
        expiresAt = 1789990120,
    },
}
```

The lease and data share the same envelope so ownership checks and data replacement occur in one
`UpdateAsync` transform. A save never does a separate read followed by a blind set.

The optional model `typeId` is stable across schema versions. Codec type IDs describe individual
wire representations and should change only when that representation becomes incompatible.

## Load flow

1. Wait for update-request budget.
2. Atomically inspect the current envelope.
3. Reject an unexpired foreign lease.
4. Create from the template or migrate existing data.
5. Decode registered value types, migrate logical data, reconcile missing template fields, then
   validate serialization and schema.
6. Claim/refresh the lease and return the committed envelope.

Migration callbacks must be deterministic and must not yield because DataStore transforms may be
executed more than once.

Legacy leases containing only `owner` and `expiresAt` remain valid. The next successful exclusive
claim or renewal enriches them with diagnostic identity fields.

## Read-only flow

A read-only load performs a budget-aware, retried `GetAsync`, validates and prepares the returned
envelope in memory, and never calls the adapter update path. It does not create a missing record,
claim or renew a lease, persist reconciliation/migrations, or release another session's lease.

## Save flow

The record snapshots data and its mutation counter, validates the snapshot, then atomically checks
lease ownership and writes a new envelope revision. Dirty state clears only if no local mutation
occurred after the snapshot. Calls arriving during a save request one coalesced follow-up save.

## Transaction flow

`Record:Transaction` copies the current data and metadata into an isolated `TransactionDraft`.
The callback runs once and may use only non-yielding local draft operations. Live-record writes are
locked for the callback's duration. OmniStore rejects callback errors or yields, remembers any
failed draft mutation, and validates the complete final draft before atomically swapping it into the
record. Dirty tracking advances once per draft mutation, and buffered change events fire only after
the committed state is visible. Persistence remains a separate `SaveAsync` operation.

## Background scheduling

Each store runs one scheduler for autosave and lease-renewal jobs. Due work is queued per loaded
record, but no more than `maxConcurrentBackgroundTasks` callbacks execute at once. Saturation,
callback errors, retries, persistence failures, saves, lease failures, and deadline failures can be
observed through protected logger/metrics hooks. User diagnostics cannot throw into persistence.

Explicit timeouts use a monotonic clock. They bound budget waiting, retry delays, coalesced-save
waiting, and multi-record close coordination. They cannot cancel a Roblox request already executing.

## Replication flow

The optional server replicator projects non-overlapping allowlisted record paths into a per-player,
per-channel snapshot. Each accepted record change advances a channel sequence number. Clients apply
only the next contiguous change; duplicates are ignored and gaps trigger a fresh authoritative
snapshot. Events arriving around a snapshot are queued and replayed by sequence. Server request,
channel, path, depth, and estimated-payload limits bound the protocol, while record/player lifecycle
events remove registrations.

## Dependency boundaries

- `adapters/` isolates persistence transports.
- `internal/Serializer` rejects unsupported, cyclic, non-finite, mixed-key, sparse, and oversized
  values before they reach DataStoreService.
- `internal/Migrate` and `internal/Reconcile` prepare loaded data.
- `internal/Scheduler` bounds record background work per store.
- `internal/TransactionDraft` and `internal/NoYield` provide isolated, non-yielding local
  transactions.
- `Schema`, `Model`, and `CodecRegistry` define the optional typed model boundary.
- `Record` owns local consistency and its lifecycle.
- `replication/` is optional and never participates in persistence authority.
