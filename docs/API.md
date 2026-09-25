# API reference

All failure-capable methods return a discriminated result. Check `result.ok` before reading
`result.value`; failures contain `code`, `message`, `retryable`, and optional
`category/cause/context`. Categories are `Transient`, `Throttled`, `Permanent`, or `Unknown`.

## OmniStore

Public construction helpers are exposed as `OmniStore.Schema`, `OmniStore.CodecRegistry`,
`OmniStore.Model`, and `OmniStore.Codecs.Roblox`.

### `OmniStore.new(config?)`

Creates a manager. By default it binds `CloseAsync` to `game:BindToClose` on the server.

### `database:GetStore(name, config?) -> Store`

Configures a named store on first access. Later calls for the same name must omit configuration.
If no adapter is supplied, a DataStore named `<namespace>_<name>` is used.

### `database:GetSessionInfo() -> SessionIdentity`

Returns a copy of this manager's owner, session, job, place, and universe identity.

### `database:CloseAsync(timeout?) -> Result<nil>`

Closes every store within the overall deadline (25 seconds by default). A failed record close keeps
the database open so a caller can retry.

## Store

### `store:LoadAsync(key, timeoutOrOptions?) -> Result<Record>`

Loads and, when enabled, atomically leases a string or numeric key. The key prefix plus converted
key must fit Roblox's 50-byte key limit. A number remains shorthand for a timeout. The options form
is `{ timeout?, mode = "Exclusive" | "ReadOnly", staleLeasePolicy = "Recover" | "Reject" }`.
Exclusive is the default. `Recover` may take over only an expired foreign lease; a live lease is
never overwritten. Read-only loads use `GetAsync`, do not claim leases, and return `NotFound` rather
than creating missing data.

### `store:GetSessionInfo() -> SessionIdentity`

Returns a copy of the identity written into leases owned by this store.

### `store:GetLoadedRecord(key) -> Record?`

Returns only this process's tracked record. It performs no persistence request.

### `store:DeleteAsync(key, timeout?) -> Result<nil>`

Deletes an unloaded key. This is intentionally explicit and is not a soft delete.

### `store:CloseRecordAsync(key, timeout?) -> Result<nil>`

Closes the loaded record for an arbitrary entity key. An unloaded key is a successful no-op. This
is the lifecycle coordination point to call from `Players.PlayerRemoving` or equivalent cleanup.

### `store:CloseAsync(timeout?) -> Result<nil>`

Closes all loaded records and then marks the store closed.

## Record

- `GetData() -> Result<unknown>` returns a defensive copy of the entire data value.
- `Get(path) -> Result<unknown>` accepts `"Inventory.1.Id"` or `{ "Inventory", 1, "Id" }`.
- `Set(path, value) -> Result<unknown>` creates missing table parents.
- `Increment(path, amount?) -> Result<number>` defaults missing values to zero.
- `Update(path, callback) -> Result<unknown>` runs a non-yielding local transform.
- `Insert(path, value, index?) -> Result<number>` inserts into an array.
- `Remove(path, index?) -> Result<unknown>` removes a field or array element.
- `GetMetadata(key?)` and `SetMetadata(key, value)` access developer metadata.
- `Transaction(callback: (TransactionDraft) -> ()) -> Result<nil>` runs the callback against an
  isolated draft, then atomically replaces this record's local data and metadata if the callback
  and final validation succeed. The callback must not yield. Nested transactions and live-record
  writes during the callback are rejected.
- `SaveAsync(timeout?) -> Result<nil>` validates and persists the current snapshot.
- `CloseAsync(timeout?) -> Result<nil>` saves and releases the session lease atomically.
- `IsDirty() -> boolean`; `GetRevision() -> number`.
- `IsReadOnly() -> boolean` reports the load mode.

Read-only records allow reads, revision/state inspection, and close. Every mutation, transaction,
metadata write, and save returns a `ReadOnly` failure.

`record.Changed` fires `(path, newValue, oldValue)` after local mutation.
`record.LifecycleChanged` fires `(newState, oldState)`.

Signal callbacks run in separate tasks. Do not assume ordering between different callbacks.

### TransactionDraft

The draft supports `GetData`, `Get`, `Set`, `Increment`, `Update`, `Insert`, `Remove`,
`GetMetadata`, `SetMetadata`, and `IsDirty` with the same path and result conventions as a record.
Draft changes and observer events remain private until commit. Any failed draft mutation aborts the
transaction even if its result is ignored. A successful transaction is still dirty local state;
call `SaveAsync` separately for durability. See [Transactions](TRANSACTIONS.md).

## Adapters

`OmniStore.Adapters.DataStore.new(name, scope?)` uses Roblox DataStoreService.
`OmniStore.Adapters.DataStore.ClassifyError(cause)` exposes its conservative error classifier.

`OmniStore.Adapters.Memory.new(seed?)` is deterministic, stores no external data, and adds
`Peek(key)` plus `SetFailurePlan(operation, count, message?, retryable?, category?)` for tests.

Custom adapters implement `Read(key)`, `Update(key, transform)`, `Remove(key)`, and
`GetBudget(requestType)`.
An adapter must serialize concurrent updates for a key and may execute `transform` multiple times.

## Schemas

`Schema.any`, `string`, `number`, `boolean`, `literal`, `optional`, `array`, `map`, `object`, `union`,
and `custom` return composable schema objects. `schema:Validate(value)` returns
`(boolean, message?)`; failure messages include the nested path.

Pass a schema directly through store config or bind it into a model. Schema validation runs after
decode/migration/reconciliation and before every accepted mutation or save.

## Codecs

`CodecRegistry.new({ unknownTypePolicy? })` creates a registry. `Register` accepts
`{ typeId, isType, encode, decode }`. `Encode` and `Decode` return structured results.

`unknownTypePolicy` is `Reject` by default or `Preserve` for forward-compatible retention of unknown
tagged values. `OmniStore.Codecs.Roblox.registerAll(registry)` registers Vector2, Vector3, Color3,
CFrame, UDim, and UDim2 codecs.

## Models

`Model.define({ typeId, version, schema, template?, migrations?, codecs?, allowLegacy? })` binds a
stable logical type identity to its persistence contract. Supplying the result as `store.model`
configures those fields together. A mismatched stored `typeId` fails closed. `allowLegacy = false`
also rejects older envelopes with no type ID.

## Replication

On the server, create `OmniStore.Replication.Server.new(config?)` and call
`Register(player, channel, record, allowedPaths) -> Result<nil>`. Paths must be non-empty,
non-overlapping, bounded allowlist roots. Registrations are removed when the player leaves or the
record closes/loses its lease.

On the client, create `OmniStore.Replication.Client.new(channel, config?)`, then use `Get`,
`GetRevision`, `GetStatus`, `IsSynchronized`, and `ResyncAsync`. `Changed`, `Resynced`, and
`StatusChanged` signals report mirror activity. Sequence gaps and oversized invalidation notices
trigger a rate-bounded snapshot resync. There is deliberately no client mutation or save API. See
[Replication](REPLICATION.md).
