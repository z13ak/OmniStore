# Phase 2 reliability verification — 2026-10-30

Audited baseline: `d83a1d49793e0e1f6c3d5bd51ee82c15cf308ce1`.
Branch: `fix/phase-2-reliability`. Functional fixes are committed through `6cca87d`;
the manual smoke runner and its validation hooks are committed as `adc9120`.
These changes have not been published or tagged as a release.

The seven Phase 1 findings are addressed:

| Finding | Resolution | Commit |
| --- | --- | --- |
| Loads escape shutdown | Gate new loads and drain loads already in flight before closing records | `ab53097` |
| Delete bypasses foreign leases | Atomic lease check plus empty tombstone; coordinate local loads/deletes | `19ecc14` |
| Sequential shutdown starves later records | Bounded record/store workers sharing a deadline; coalesced closes | `ab53097` |
| Requests start after retry deadlines | Check before the initial request and after retry waits | `7b774eb` |
| Yielding/reentrant record updates lose changes | Guard callback writes and reject yields | `a7667af` |
| Metadata accepts values it cannot persist | Validate raw metadata for records and transaction drafts | `ce84065` |
| Plain tables collide with codec markers | Escape marker-shaped tables and reserve the escape codec ID | `a50d059` |

Further fault tests established and fixed stale decision flags across retried transforms
(`c9a81bf`), yielding migrations (`c044461`), lost responses after committed saves/closes
(`1340b83`), and persistence attempts while disposing a known lost-lease handle (`6cca87d`).

Verification completed:

- Studio TestEZ: **88 passed, 0 failed**, including 29 added regressions over the 59-test baseline.
- Normalized source checks matched all **46** library and test scripts between the local checkout
  and the Studio server used for the final test run. No missing or mismatched scripts remained.
- Pinned StyLua 2.1.0 formatting check passed.
- Pinned Selene 0.28.0 reported zero errors, warnings, or parse errors.
- Rojo 7.7.0 built the package, development place, and test place successfully.
- Wally 0.3.2 package inspection passed: 39 entries, with development-only files excluded.
- `scripts/verify.ps1 -SkipInstall` and Git whitespace checks passed. TestEZ was already available
  in Studio; its existing sources were exported into ignored `DevPackages` for the test build.
  Dependency installation was not rerun.

The user confirmed that **OmniStoreTests**, universe `10767918920`, place `73812564531596`, is a
dedicated test universe without production data. The Roblox Studio MCP server responded to live
instance/state calls; accessibility was not inferred from the supplied configuration alone.

The final live DataStore run passed all eight scenario groups with no manager-close errors:

1. Create and save.
2. Live foreign-session load and delete rejection.
3. Read-only access and Roblox datatype codec round trip.
4. Close, reload, tombstone deletion, and template-only recreation.
5. Expired lease recovery and rejection of writes from the former owner.
6. Model migration using the real DataStore adapter.
7. Persistence of three dirty records during manager shutdown.
8. Logical cleanup of the exact disposable keys.

Final test namespace: `OmniSmoke_e6319adb47b84ea9b96e`. Two earlier successful runs used
`OmniSmoke_65f4a5f1ec614e249812` and `OmniSmoke_04ccc24ca1ee41848daf`. Each run used only the six
known keys `profile`, `stale`, `migration`, and `shutdown-1` through `shutdown-3`; cleanup left
empty tombstones. No existing application namespaces were accessed. Studio was returned to Edit
mode after testing; its library/spec sources contain the verified changes and the manual smoke
module is available in ServerStorage.

Rollout constraints remain:

- Deploy all readers/writers before using tombstones or escaped plain tables. Older versions do
  not understand those shapes; see `COMPATIBILITY.md`. Existing ambiguous codec-shaped stored
  tables cannot be automatically recovered by this fix.
- Deletion is logical and does not erase historical DataStore versions. Uncoordinated physical
  cleanup can delete a newly recreated record and must not run against live keys.
- Live ownership tests used separate session identities inside one Studio server, not two separate
  running Roblox servers. Expiry was injected into a disposable test key. Actual process termination,
  platform-wide outages, production-scale load, and real cross-server contention were not simulated.
- The shutdown test exercises the close path used by BindToClose; abrupt server termination still
  cannot guarantee a final save. Already-started platform requests cannot be preempted by deadlines.
- If every response to a committed operation is lost, its final result may remain uncertain despite
  retry tokens. The changes do not provide cross-key transactions or exactly-once external effects.

This evidence supports further release qualification; it does not remove the release gates or
authorize publishing the current unreleased changes.
