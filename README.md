<p align="center">
  <img src="assets/github-banner.png" alt="OmniStore — Typed Persistence for Roblox" width="100%">
</p>

<p align="center">
  <a href="https://github.com/z13ak/OmniStore/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/z13ak/OmniStore/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/z13ak/OmniStore/releases"><img alt="Release" src="https://img.shields.io/github/v/release/z13ak/OmniStore?include_prereleases&sort=semver"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-22c55e.svg"></a>
</p>

OmniStore is a typed persistence library for Roblox:

`OmniStore -> Store -> Record -> Data`

A record key can represent any durable entity: a player, server, guild, world, plot, or something
specific to your game. Stores add schemas, migrations, session leases, autosave, and safe mutation
helpers on top of Roblox DataStores. Read-only client replication is optional.

> **Status:** `0.2.0-rc.1` is a public release candidate. Complete Studio API-services testing in a
> separate universe before using it with production data.

## Quick start

```lua
local Players = game:GetService("Players")
local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)

local data = OmniStore.new({ namespace = "MyGame" })
local profiles = data:GetStore("Profiles", {
    template = {
        Coins = 0,
        Inventory = {},
        Settings = { Music = true },
    },
    schemaVersion = 1,
})

Players.PlayerAdded:Connect(function(player)
    local loaded = profiles:LoadAsync(player.UserId)
    if not loaded.ok then
        warn("Profile load failed", player.UserId, loaded.error.code)
        player:Kick("Your data could not be loaded. Please rejoin.")
        return
    end

    local profile = loaded.value
    profile:Increment("Coins", 25)
    profile:Insert("Inventory", { Id = "WoodenSword" })
end)

Players.PlayerRemoving:Connect(function(player)
    local closed = profiles:CloseRecordAsync(player.UserId, 10)
    if not closed.ok then
        warn("Profile close failed", player.UserId, closed.error.code)
    end
end)
```

Every operation that can fail returns `{ ok = true, value = ... }` or
`{ ok = false, error = ... }`. Data reads return defensive copies; mutations must go through the
record API so dirty tracking and validation cannot be bypassed accidentally.

## How writes behave

- `UpdateAsync`-oriented writes and atomic per-key lease checks.
- A live lease is never intentionally overwritten; expired leases can be recovered.
- Serialization and optional schema validation run before writes.
- Retryable adapter failures use bounded exponential backoff with jitter.
- Concurrent save calls coalesce, while mutations made during a save remain dirty.
- `CloseAsync` saves and releases the lease in the same atomic update.
- In-memory transactions use isolated drafts and publish changes only after a successful commit.
- Replication is server-authoritative and exposes only explicitly allowed paths.

## Important limits

OmniStore cannot provide database-wide ACID transactions, guaranteed shutdown saves, protection
from a compromised server, or immunity to Roblox outages and platform limits. A transaction is
atomic only in local memory until a later single-record save. Roblox `UpdateAsync` supplies the
atomic compare/transform behavior for one key; operations across keys are not atomic. See
[failure semantics](docs/FAILURE_SEMANTICS.md) and [security](docs/SECURITY.md).

## Documentation

Start with the [API reference](docs/API.md), [configuration guide](docs/CONFIGURATION.md), and
[examples](examples). The focused guides cover:

- Data integrity: [failure semantics](docs/FAILURE_SEMANTICS.md),
  [sessions](docs/SESSIONS.md), [migrations](docs/MIGRATIONS.md), and
  [transactions](docs/TRANSACTIONS.md).
- Data shape: [schemas, models, and codecs](docs/SCHEMAS_MODELS_CODECS.md).
- Operations: [reliability](docs/RELIABILITY.md), [performance](docs/PERFORMANCE.md),
  [testing](docs/TESTING.md), and [incident response](docs/INCIDENT_RESPONSE.md).
- Project internals: [architecture](docs/ARCHITECTURE.md),
  [replication](docs/REPLICATION.md), [security](docs/SECURITY.md), and
  [compatibility](docs/COMPATIBILITY.md).

## Installation and development

With [Rokit](https://github.com/rojo-rbx/rokit) installed:

```sh
rokit install
wally install
rojo build default.project.json -o OmniStore.rbxm
rojo build dev.project.json -o OmniStoreDevelopment.rbxlx
rojo serve test.project.json
stylua --check src tests examples
selene src tests examples
```

On Windows, `./scripts/verify.ps1` runs the local format, lint, build, and package checks.

After `wally install`, connect Studio to `test.project.json`; `tests/init.server.lua` runs the
TestEZ suite. DataStore testing requires a
published test place with **Enable Studio Access to API Services** enabled; use a separate test
universe, never a production universe.

Pull requests run formatting, linting, all Rojo builds, and Wally package inspection in CI. Studio
TestEZ and isolated-universe DataStore smoke tests remain explicit runtime release gates.

## License

MIT. See [LICENSE](LICENSE).
