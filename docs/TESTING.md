# Testing

## Local static and build gate

On Windows, run:

```powershell
./scripts/verify.ps1
```

This installs locked development dependencies, checks StyLua and Selene, builds package,
development, unit-test, and multiplayer artifacts, creates and inspects the Wally tarball, and checks Git whitespace.
Use `-SkipInstall` only when dependencies are already current. Generated files go under ignored
`build/`.

CI performs the same non-Studio checks on every pull request and main-branch push. CI uploads the
four Rojo builds and Wally candidate archive for inspection. A green CI job does not replace the
Studio runtime gate.

## Studio TestEZ gate

1. Run `wally install`.
2. Serve `test.project.json` with Rojo and connect the Studio plugin.
3. Start the test place.
4. Require zero assertion failures and zero planning/runtime errors, with at least one executed test.
5. Stop the session so background jobs do not obscure later runs.

Most persistence tests use `MemoryAdapter`, injected clocks/waits, and deterministic failure plans.
New tests should prefer those seams over real time or live DataStore calls. Concurrency tests should
state exactly where yielding is expected.

## Studio server with two clients

`multiplayer.project.json` includes the normal unit suite and the opt-in server/client scripts under
`scripts/multiplayer/`. The scripts refuse non-Studio execution. Serve this project into a dedicated
published test universe; the launcher must supply its exact universe ID.

Where StudioTestService multiplayer automation is available, call the following from plugin context:

```lua
local result = game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, {
    kind = "OmniStoreTwoClient",
    expectedUniverseId = 10767918920, -- Replace with your confirmed dedicated test universe.
    liveDataStores = false,
    recordCount = 96,
})
assert(result and result.ok, "multiplayer gate did not pass")
```

For an existing manual Server & Clients session, set a JSON `TestArgs` string attribute on the
server script before starting it. Use the same fields plus `replaceClient = false` and
`autoEnd = false`. Start with two clients. The runner writes its JSON report to
`ServerStorage.OmniStoreMultiplayerResult`. In manual sessions, client departure falls back to a
server kick if StudioTestService cannot disconnect it. Adding a replacement client automatically
is an additional check available only with the automated launcher; it must not be reported as
passed when omitted. Start a fresh two-client session for each run.

The memory run injects 20 ms into measured bulk writes and verifies a maximum of four concurrent
writes. The real-DataStore run uses `liveDataStores = true` and at most 16 bulk records (12 by
default), with a fresh `OmniMP_...` namespace and exact-key tombstone cleanup. Both modes check
profile isolation, defensive mirror reads, snapshot throttling, server authority, 200 replicated
updates, oversized-change resynchronization, channel teardown, player-leave persistence, and a
25-second manager-close gate. Client results are paired with independent server-state and saved
envelope assertions. Client messages are only test reports, never authority for durable mutations.

These are one-server integration checks. They do not establish lease contention or partition
recovery between two separate Roblox servers, nor do they simulate abrupt process termination.

## Published-universe smoke gate

DataStoreService behavior cannot be fully reproduced by a mock. Before a release that changes
persistence, leases, migrations, serialization, codecs, or shutdown:

- use a dedicated published universe with Studio API access enabled;
- use a unique namespace and disposable keys;
- verify create, save, close, reload, read-only load, live-lock rejection, and expired-lease recovery;
- verify at least one model migration and supported Roblox datatype codec round trip;
- never use a production universe or production keys.

`scripts/DataStoreSmoke.lua` supplies a manual runner for this gate. Load it as a ModuleScript in
Studio, start a server session in a confirmed dedicated test universe, and call
`runner.run(OmniStore, expectedUniverseId)`. It refuses other universe IDs and non-Studio contexts.
It generates a fresh `OmniSmoke_...` namespace and uses six exact disposable keys. The returned
summary covers save/reload, foreign locks, lease-aware deletion, codec/model migration, expired
lease recovery, and manager shutdown persistence. Expiry is injected only into its own test key.
Successful cleanup leaves empty tombstones; failed runs can leave their disposable payloads for
investigation. The runner is never executed automatically by TestEZ or the library.

Do not automate destructive cleanup against a broad namespace. Test records can expire naturally or
be deleted only by exact known keys.

## Replication matrix

Protocol unit tests cover malformed inputs, allowlists, size/rate limits, cleanup, and sequence gaps.
Before release, also run a server with at least two clients and exercise initial subscription,
high-frequency changes, simulated client disconnect/reconnect, channel teardown, and UI behavior
while the mirror reports `Stale`. Client data must never be used as server authorization evidence.

## Release evidence

Record the commit, package version, static/build result, TestEZ pass count, smoke-test universe, smoke
scenarios, and reviewer in the release notes or checklist. Never include secrets or record contents.
