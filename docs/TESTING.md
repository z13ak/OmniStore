# Testing

## Local static and build gate

On Windows, run:

```powershell
./scripts/verify.ps1
```

This installs locked development dependencies, checks StyLua and Selene, builds package,
development, and test artifacts, creates and inspects the Wally tarball, and checks Git whitespace.
Use `-SkipInstall` only when dependencies are already current. Generated files go under ignored
`build/`.

CI performs the same non-Studio checks on every pull request and main-branch push. CI uploads the
three Rojo builds and Wally candidate archive for inspection. A green CI job does not replace the
Studio runtime gate.

## Studio TestEZ gate

1. Run `wally install`.
2. Serve `test.project.json` with Rojo and connect the Studio plugin.
3. Start the test place.
4. Require zero TestEZ failures in Output.
5. Stop the session so background jobs do not obscure later runs.

Most persistence tests use `MemoryAdapter`, injected clocks/waits, and deterministic failure plans.
New tests should prefer those seams over real time or live DataStore calls. Concurrency tests should
state exactly where yielding is expected.

## Published-universe smoke gate

DataStoreService behavior cannot be fully reproduced by a mock. Before a release that changes
persistence, leases, migrations, serialization, codecs, or shutdown:

- use a dedicated published universe with Studio API access enabled;
- use a unique namespace and disposable keys;
- verify create, save, close, reload, read-only load, live-lock rejection, and expired-lease recovery;
- verify at least one model migration and supported Roblox datatype codec round trip;
- never use a production universe or production keys.

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
