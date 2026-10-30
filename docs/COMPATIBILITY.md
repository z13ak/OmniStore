# Compatibility and upgrades

`DeleteAsync` now writes an empty envelope with `deleted = true` instead of unconditionally removing
the key. Upgrade all readers/writers before using deletion: old versions do not recognize tombstones.
Do not run uncoordinated `RemoveAsync` cleanup against live keys; it can erase a recreated record.
Historical DataStore versions require a separate administrative retention/erasure procedure.

Codec registries reserve `omnistore.PlainTable/v1` to escape ordinary tables that resemble codec
markers. Deploy readers supporting this escape before writing marker-shaped tables; older readers
cannot decode the new escape. Existing unescaped marker-shaped values are inherently ambiguous and
retain their legacy decoding behavior. Escaping cannot recover data already misinterpreted by an
older reader.

## Supported environment

| Surface | Policy |
| --- | --- |
| Roblox engine | Current production Roblox server/client runtime with strict Luau enabled. |
| Rojo | `7.7.0`, pinned for reproducible package/place builds. |
| Wally | `0.3.2`, with the committed lockfile used for development dependencies. |
| StyLua | `2.1.0`. |
| Selene | `0.28.0` with the Roblox standard library. |
| Test framework | TestEZ `0.4.1`. |
| Persistence adapter | Roblox DataStoreService through `UpdateAsync`/`GetAsync`, or the bundled memory adapter. |

OmniStore does not depend on undocumented Roblox APIs. Because Roblox updates continuously, the
runtime suite and a separate-universe persistence smoke test are release gates instead of promising
compatibility with a permanently fixed Studio build.

## Semantic versioning

- Patch releases fix defects without intentionally changing the public API or stored format.
- Minor releases may add backward-compatible APIs, fields, codecs, and behavior. Before `1.0.0`, a
  necessary breaking change may occur in a minor release and must be highlighted in the changelog.
- Major releases may change public APIs or persistence contracts and require a documented upgrade.

The stable public surface is the value returned by `src/init.lua` and the documented methods/types.
Modules under `internal/`, wire remotes, stored lease diagnostics, and undocumented table fields are
implementation details.

## Persistence compatibility

The stored envelope, model `typeId`, `schemaVersion`, codec IDs, and migration chain are more durable
than ordinary code APIs:

- Never reuse a model or codec ID for incompatible data.
- Add a migration for every persisted schema-version step and validate its output.
- Keep migrations deterministic, non-yielding, and deployable before code that writes the new shape.
- Retain old decoders/migrations while stored records may still contain their formats.
- Test upgrades against copied production-like data in a separate universe.

An application schema version is independent from the OmniStore package version.

## Upgrade procedure

The rc.3-to-development matrix is covered by `tests/Compatibility.spec.lua` using pinned persistence
fixtures from `d83a1d4`:

| Writer/operation | Reader/owner | Result |
| --- | --- | --- |
| rc.3 ordinary data | development reader | Supported |
| development ordinary data, including `writeId` | rc.3 reader | Supported |
| development tombstone | rc.3 reader | Unsafe: old reader returns a template-shaped record instead of NotFound |
| development escaped marker table | rc.3 codec reader | Rejected as an unknown codec |
| rc.3 DeleteAsync | development live lease | Unsafe: old deletion bypasses the lease |

For this upgrade, pause writes and drain every rc.3 server before allowing new servers to write
tombstones or escaped marker tables. A rolling deployment alone does not retire existing servers.
Keep writes paused if old servers cannot be drained. Restoring the old binary after new-format
writes is not a safe rollback; retain updated readers and ship a forward fix instead. A small
new-server cohort may validate ordinary records before the drain, but must not use deletion or
marker-shaped plain-table writes, and old deletion paths must remain disabled.

1. Read every changelog entry between the deployed and target versions.
2. Update the dependency in a branch and regenerate the lockfile intentionally.
3. Run static verification and all Studio TestEZ tests.
4. Exercise migrations and codecs with representative copied data using the memory adapter first.
5. Run exclusive-load, save, close/rejoin, stale-lease, shutdown, and replication smoke cases in a
   separate published universe.
6. Deploy to a small server cohort when the game platform supports it, monitor diagnostics, then
   expand. Keep the previous package and application code available for rollback.

Rolling back code does not reverse already-written schema migrations. A rollback must understand any
data the newer deployment wrote, or writes must be paused until a forward fix is ready.
