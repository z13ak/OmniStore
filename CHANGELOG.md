# Changelog

All notable changes follow Keep a Changelog. This project uses semantic versioning.

## [Unreleased]

### Fixed

- Gate shutdown before accepting more work, drain in-flight loads/deletes, and close records with
  bounded concurrency and coalesced close results.
- Reject yielding/reentrant updates and yielding migrations; isolate retry transform decisions.
- Enforce retry deadlines before requests and recognize committed saves/closes after response loss.
- Validate metadata in its persisted form and preserve marker-shaped plain tables through codecs.
- Fence deletion against live leases using atomic empty tombstones; never reactivate lost-lease handles.

### Added

- Opt-in Studio server/two-client integration harness covering replication, client isolation,
  rate limits, join/leave persistence, and bounded shutdown with memory and live DataStore adapters.
- Pinned rc.3 persistence compatibility fixtures and a test gate that detects planning errors and
  empty runs as well as failed assertions.

- Deterministic regression coverage for concurrency, response loss, migration replay, and shutdown.
- Manual dedicated-universe DataStore smoke runner, excluded from automatic tests and package code.

### Changed

- `DeleteAsync` performs logical deletion; empty tombstones remain stored. Upgrade all writers/readers
  before using this behavior. Codec plain-table escaping also requires updated readers; see
  `docs/COMPATIBILITY.md` before rollout or rollback.

## [0.2.0-rc.3] - 2026-10-03

### Changed

- Changed the Wally package scope to `z13ak/omnistore`, matching the publishing account.
- Documented installation through the Wally registry.

### Fixed

- Package release archives before creating generated artifact directories.

## [0.2.0-rc.2] - 2026-09-26

### Changed

- Tightened the README, security policy, and contributor guidance.
- Improved failure handling in the guild, server, and typed-model examples.
- Removed the internal development audit from the published documentation.

## [0.2.0-rc.1] - 2026-09-25

### Added

- Bounded operation and shutdown timeouts, background-work concurrency, and structured diagnostic
  callbacks.
- Read-only loads, diagnostic lease identities, and configurable expired-lease recovery.
- Composable schemas, typed models, recursive codecs, and codecs for common Roblox datatypes.
- Isolated in-memory transactions with validation and buffered change events.
- Sequence-aware, server-authoritative replication with resynchronization and payload limits.
- Pinned development tools, CI checks, and release artifact validation.

### Fixed

- Label Wally output as ZIP and validate its actual archive format consistently across Windows and
  Linux release gates.
- Bound serialization traversal with a configurable maximum depth and made the JSON payload safety
  limit configurable.
- Preserve manager retry and lease defaults when a store supplies only a partial override.
- Validate templates, stored values, nested mutation inputs, metadata, and complete envelopes before
  copying or persistence.

### Tests

- Added coverage for timeouts, retries, lease races, schemas, codecs, migrations, transactions, and
  replication boundaries.
- Added package-content checks to keep tests, development dependencies, and generated builds out of
  published archives.

## [0.1.0] - 2026-09-22

### Added

- Typed `OmniStore -> Store -> Record -> Data` API.
- DataStore and deterministic in-memory adapters.
- Serialization and optional schema validation, template reconciliation, and migrations.
- Atomic session leases, stale-session recovery, autosave jitter, retries, save coalescing,
  request-budget awareness, lifecycle signals, metadata, and graceful shutdown.
- Path mutation helpers and rollback-capable in-memory transactions.
- Optional server-authoritative replication with read-only client mirrors.
- Documentation, examples, Rojo/Wally configuration, and tests.
