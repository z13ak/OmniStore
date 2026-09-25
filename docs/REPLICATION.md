# Replication

OmniStore replication is an optional server-authoritative, read-only projection of selected record
paths. It is not required for persistence and gives clients no write or save remote.

## Server

```lua
local replicator = OmniStore.Replication.Server.new({
    maxSnapshotBytes = 128_000,
    maxChangeBytes = 32_000,
})

local registered = replicator:Register(player, "Profile", profile, {
    "Coins",
    "Level",
    "PublicLoadout",
})
if not registered.ok then
    warn(registered.error.code, registered.error.message)
end
```

Allowlisted paths are projection roots: allowing `PublicLoadout` also permits changes below that
path. Root paths, malformed paths, duplicate paths, and ancestor/descendant overlaps are rejected.
The server validates the initial snapshot before registration succeeds. It removes registrations
when their player leaves, their record closes or loses its lease, or the replicator is destroyed.

Each channel has a monotonic sequence number. A valid change sends its exact path, defensive-copied
value, and sequence. A change that exceeds the configured event limit sends only an invalidation,
causing the client to request a bounded snapshot instead.

## Client

```lua
local mirror = OmniStore.Replication.Client.new("Profile")

mirror.Changed:Connect(function(path, value)
    print(path, value)
end)

mirror.StatusChanged:Connect(function(status)
    if status == "Stale" then
        warn("Waiting for an authoritative resync")
    end
end)
```

The client subscribes before requesting its initial snapshot so changes around initialization are
queued. It ignores duplicates, applies only contiguous sequences, and requests a new snapshot when
it detects a gap or invalidation. Queued later events are sorted and replayed after the snapshot.
Automatic resyncs have a cooldown; `ResyncAsync()` lets application UI explicitly retry after a
reported stale state. `Resynced` fires after a successful replacement.

`GetStatus()` returns `Synchronizing`, `Synchronized`, `Stale`, or `Destroyed`. Treat mirror values
as presentation state, never as server authorization input.

## Limits and non-guarantees

Snapshot requests are limited per player and time window. Channels per player, paths per channel,
channel length, path depth, payload nesting, queued events, and estimated change/snapshot bytes are
also bounded. Size accounting is conservative and is not an exact Roblox wire-size measurement.

Replication is eventually consistent. It does not promise delivery of every intermediate value,
offline history, cross-channel atomicity, secrecy from the receiving client, or availability during
network loss. A snapshot restores the newest state visible to the server when it is built.
