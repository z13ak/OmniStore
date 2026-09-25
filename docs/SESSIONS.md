# Sessions and read-only access

## Exclusive sessions

Exclusive loads atomically inspect and claim the record lease through `UpdateAsync`. New leases
record owner/session IDs, JobId, PlaceId, universe ID, acquisition time, renewal time, and expiry.
These fields are diagnostic; ownership is still decided by the opaque `owner` token and expiry.

```lua
local loaded = profiles:LoadAsync(player.UserId, {
    timeout = 10,
    mode = "Exclusive",
    staleLeasePolicy = "Recover",
})
```

`Recover` means expired-only recovery. It is not a live-session override. Use `Reject` when an
expired foreign lease should remain untouched for investigation.

## Read-only sessions

Read-only mode supports administrative inspection, leaderboards, support tooling, and diagnostics
that must not compete for ownership:

```lua
local loaded = profiles:LoadAsync(userId, { mode = "ReadOnly", timeout = 10 })
if loaded.ok then
    print(loaded.value:GetData().value)
    loaded.value:CloseAsync()
end
```

A read-only record is a snapshot. It does not renew or release the stored lease and will not receive
later owner changes automatically. Missing keys return `NotFound`; mutations and saves return
`ReadOnly`. Reconciliation and migrations may shape the in-memory snapshot but are not persisted.

## Recovery timeline

1. Server A claims a lease and records its expiry.
2. Server A renews before expiry while healthy.
3. If A disappears, other exclusive loads wait or fail while the lease plus grace remains live.
4. After expiry plus `stealAfter`, `Recover` allows Server B to claim atomically.
5. If A resumes, its next save/renew sees B's owner token and enters `LeaseLost`.

Clock values used for expiry are wall-clock timestamps. Keep a consistent lease configuration across
all servers sharing the store.
