<p align="center">
  <img src="assets/github-banner.png" alt="OmniStore — Typed Persistence" width="100%">
</p>

<p align="center">
  <a href="https://github.com/z13ak/OmniStore/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/z13ak/OmniStore/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/z13ak/OmniStore/releases"><img alt="Release" src="https://img.shields.io/github/v/release/z13ak/OmniStore?include_prereleases&sort=semver"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-22c55e.svg"></a>
  <img alt="Language: Luau" src="https://img.shields.io/badge/language-Luau-00A2FF.svg">
  <img alt="Package manager: Wally" src="https://img.shields.io/badge/package-Wally-8B5CF6.svg">
  <img alt="Build: Rojo 7" src="https://img.shields.io/badge/build-Rojo%207-EC4899.svg">
</p>

OmniStore is a typed, game-agnostic Roblox persistence library built around one small model:

`OmniStore -> Store -> Record -> Data`

A record key can represent a player, server, guild, world, plot, season, or any other durable
entity. OmniStore does not hardcode game concepts. It adds schemas, migrations, atomic session
leases, safe mutation helpers, autosave, retry/backoff, request-budget checks, lifecycle signals,
and optional read-only replication on top of Roblox DataStore primitives.

> **Status:** `0.2.0-rc.1` is a public release candidate. Complete Studio API-services testing in a
> separate universe before using it with production data.

## Quick start

```lua
local Players = game:GetService("Players")
local OmniStore = require(game.ReplicatedStorage.Packages.OmniStore)

local database = OmniStore.new({ namespace = "MyGame" })
local profiles = database:GetStore("Profiles", {
    template = {
        Coins = 0,
        Inventory = {},
        Settings = { Music = true },
    },
    schemaVersion = 1,
})

local loaded = profiles:LoadAsync(player.UserId)
if not loaded.ok then
    player:Kick("Your data could not be loaded safely. Please rejoin.")
    return
end

local profile = loaded.value
profile:Increment("Coins", 25)
profile:Insert("Inventory", { Id = "WoodenSword" })

Players.PlayerRemoving:Connect(function(leavingPlayer)
    if leavingPlayer == player then
        local closed = profiles:CloseRecordAsync(player.UserId, 10)
        if not closed.ok then
            warn(closed.error.code, closed.error.message)
        end
    end
end)
```

Every operation that can fail returns `{ ok = true, value = ... }` or
`{ ok = false, error = ... }`. Data reads return defensive copies; mutations must go through the
record API so dirty tracking and validation cannot be bypassed accidentally.

## Design promises

- `UpdateAsync`-oriented writes and atomic per-key lease checks.
- A live lease is never intentionally overwritten; expired leases can be recovered.
- Serialization and optional schema validation run before writes.
- Saves retry retryable adapter failures with exponential backoff and jitter.
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

- [Architecture](docs/ARCHITECTURE.md)
- [Foundation audit and roadmap](docs/AUDIT.md)
- [API reference](docs/API.md)
- [Configuration](docs/CONFIGURATION.md)
- [Failure semantics](docs/FAILURE_SEMANTICS.md)
- [Reliability and diagnostics](docs/RELIABILITY.md)
- [Sessions and read-only access](docs/SESSIONS.md)
- [Schemas, models, and codecs](docs/SCHEMAS_MODELS_CODECS.md)
- [Transactions](docs/TRANSACTIONS.md)
- [Replication](docs/REPLICATION.md)
- [Migrations](docs/MIGRATIONS.md)
- [Error reference](docs/ERRORS.md)
- [Testing](docs/TESTING.md)
- [Performance and capacity](docs/PERFORMANCE.md)
- [Compatibility and upgrades](docs/COMPATIBILITY.md)
- [Incident response](docs/INCIDENT_RESPONSE.md)
- [Release process](docs/RELEASE.md)
- [Security and replication](docs/SECURITY.md)
- [Examples](examples)

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

On Windows, `./scripts/verify.ps1` runs the complete local static, build, and package gate. Aftman
configuration remains available for existing contributors during the toolchain transition.

After `wally install`, connect Studio to `test.project.json`; `tests/init.server.lua` runs the
TestEZ suite. DataStore testing requires a
published test place with **Enable Studio Access to API Services** enabled; use a separate test
universe, never a production universe.

Pull requests run formatting, linting, all Rojo builds, and Wally package inspection in CI. Studio
TestEZ and isolated-universe DataStore smoke tests remain explicit runtime release gates.

## License

MIT. See [LICENSE](LICENSE).
