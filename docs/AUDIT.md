# Foundation audit

Audit date: 2026-09-24; last updated: 2026-09-25

This audit defines the current boundary of OmniStore's initial foundation. It is intentionally
conservative: a feature is not called production-ready merely because an implementation exists.

## Repository and tool state

- Repository: `C:\Users\gayle\Downloads\OmniStore`
- Branch: `main`; remote: `https://github.com/z13ak/OmniStore.git`
- Baseline commit: `7bde679` (`first commit`)
- Release candidate: `0.2.0-rc.1`; this audit accompanies the consolidated implementation candidate
  prepared from the baseline history.
- Available tools: Git 2.53.0, Rojo 7.7.0, StyLua 2.1.0, Selene 0.28.0, and Wally 0.3.2.
- Verification: formatting, lint, and the default, development, and test Rojo builds pass. The Studio
  TestEZ suite passes 59 tests with zero failures. Published-universe smoke checks persist and reload
  normal records; live read-only access and a model/Vector3-codec round trip also pass.
- Release engineering: pinned Rokit/Aftman manifests, pull-request CI, candidate artifact upload,
  package-content checks, and draft tag-release automation are defined. The equivalent local gate
  passes; the GitHub workflows require their first pushed run before they can be considered observed.

## Concise tree

```text
OmniStore/
|-- src/                  typed manager, stores, records, adapters, internals, replication
|-- tests/                TestEZ record, lease, migration, config, and reliability specs
|-- examples/             player, global, server, guild, and replication examples
|-- docs/                 API, architecture, config, failures, migrations, security, this audit
|-- default.project.json  package build
|-- dev.project.json      development place build
|-- test.project.json     TestEZ place build
|-- wally.toml / lock     package and test dependencies
|-- aftman.toml           pinned tool declarations
|-- stylua.toml / selene.toml
|-- README.md / CHANGELOG.md / LICENSE
```

## Completion matrix

| Phase | Status | Evidence and boundary |
| --- | --- | --- |
| 1. Foundation | Complete for the current API | Typed object model, results/errors, memory adapter, serialization checks, paths, templates, validation, reconciliation, migrations, docs, and tests. Depth and payload bounds plus partial-config merging were fixed during this audit. |
| 2. Reliability | Complete for the current contract | Update-oriented persistence, dirty tracking, bounded retries and budget waits, autosave jitter, save coalescing, one concurrency-bounded scheduler per store, explicit operation/shutdown deadlines, generic entity-leave coordination, typed failure categories, and protected logger/metrics hooks are implemented and tested. Roblox requests already in flight remain non-cancellable. |
| 3. Sessions | Complete for the current contract | Exclusive leases carry backward-compatible session/job/place/universe diagnostics. Read-only snapshots, explicit expired-lease `Recover`/`Reject` policy, live-lock protection, lease-loss handling, and simultaneous acquisition tests are implemented. No option overwrites a live lease. |
| 4. Schema/model system | Complete for the current contract | Path-aware composable schemas, stable model IDs, model definitions, recursive codec registry, Reject/Preserve unknown-codec policy, six Roblox datatype codecs, and per-step migration validation are implemented and tested. |
| 5. Transactions | Complete for the current contract | Transactions use isolated drafts, reject yielding callbacks and live-record re-entry, validate the complete final state, commit data and metadata together in memory, and buffer observer events until commit. They are explicitly single-record local operations; persistence remains a separate save. |
| 6. Replication | Complete for the current optional contract | Server-authoritative, non-overlapping allowlists; per-channel sequences; gap/invalidation resync; initialization buffering; synchronization status; request/payload/path/channel bounds; lifecycle cleanup; and adversarial protocol tests are implemented. Replication remains eventually consistent and read-only. |
| 7. Release engineering | Complete for the release-candidate contract | Pinned current/legacy tool manifests, CI, three Rojo artifacts, bounded Wally package contents, draft tag releases, contribution/security policies, compatibility and upgrade rules, complete error reference, testing/performance/incident/release guides, and release evidence requirements are present. Wally publication intentionally remains manual. |

## Architectural risks

1. DataStore errors are string-classified because Roblox does not expose stable structured categories
   for every failure. Unknown failures retry conservatively within attempt/deadline bounds.
2. Background execution is concurrency-bounded, but recurring job count still scales with loaded
   records. Capacity testing should set appropriate autosave intervals and concurrency limits.
3. Read-only records are point-in-time snapshots and do not receive owner updates. They must not be
   treated as authoritative inputs for writes or security decisions.
4. Codec tags use a documented reserved table shape. `Preserve` prevents unknown wire data loss but
   does not make it semantically usable and may still conflict with a strict schema.
5. Replication size accounting is a conservative estimate, not an exact Roblox wire-byte measure.
   Live client/server integration and network-condition testing should supplement protocol tests.
6. Roblox shutdown and DataStore availability remain external limits. A failed load must never be
   replaced with a template and saved as though it were new data.

## Remaining validation gaps

- A live client/server replication test matrix covering latency, disconnects, and high-frequency
  changes.
- Provider-specific logging/metrics integration examples.
- Observed GitHub CI and draft-release runs after these workflows are pushed.
- Capacity measurements from a production-like game workload; generic library defaults cannot supply
  those measurements.

## Prioritized remaining work

1. Review and push the release-candidate branch, then observe the first CI run.
2. Execute and record the manual Studio, isolated-universe, and multi-client replication gates.
3. Choose a release version only after review; update the changelog, tag it, inspect the generated
   draft, and publish Wally manually if approved.

All seven planned implementation phases are complete for the current release-candidate contract.
The remaining work is release validation and game-specific capacity evidence, not another automatic
feature phase.
