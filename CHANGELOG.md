# Changelog

All notable changes follow Keep a Changelog. This project uses semantic versioning.

## [Unreleased]

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
