# Transactions

`Record:Transaction` groups related changes into one atomic **local-memory** commit. The callback
receives an isolated `TransactionDraft`, not the live record.

```lua
local changed = profile:Transaction(function(draft)
    local debit = draft:Increment("Coins", -50)
    assert(debit.ok, debit.error and debit.error.message)

    local grant = draft:Insert("Inventory", { Id = "HealthPotion" })
    assert(grant.ok, grant.error and grant.error.message)
end)

if not changed.ok then
    warn(changed.error.code, changed.error.message)
    return
end

local saved = profile:SaveAsync(10)
if not saved.ok then
    warn(saved.error.code, saved.error.message)
end
```

## Local guarantees

- Live reads continue to see the old state while the callback runs.
- Data and metadata become visible together only after a successful callback and final validation.
- `Changed` events are buffered and emitted only after the committed state is visible.
- Callback errors, yield attempts, failed draft mutations, and final serialization/schema failures
  discard the entire draft.
- A failed draft mutation aborts the transaction even when application code ignores its result.
- Temporary intermediate states may violate the record schema; the complete final draft may not.

The draft exposes `GetData`, `Get`, `Set`, `Increment`, `Update`, `Insert`, `Remove`, `GetMetadata`,
`SetMetadata`, and `IsDirty`. Reads return defensive copies. Path methods follow the same rules and
structured-result contract as their `Record` counterparts.

## Callback rules

Transaction callbacks and draft `Update` callbacks must not yield or perform I/O. They should be
short, deterministic local computations. During the callback, mutations, saves, closes, and nested
transactions through the live record are rejected. If a callback captures and reads the live
record, it sees the old committed state; use the draft for transaction-local reads.

Do not retain a draft after the callback. It is detached from the record after commit or abort and
later calls cannot change live state.

## Persistence boundary

A successful transaction marks the record dirty but does not contact DataStoreService. Call
`SaveAsync` or `CloseAsync` afterward when durability is required. A transaction is not a database
transaction: it does not coordinate records or keys, isolate other servers, roll back a successful
save, guarantee shutdown completion, or provide full ACID semantics. The later save uses the normal
single-key lease check and `UpdateAsync` persistence guarantees.
