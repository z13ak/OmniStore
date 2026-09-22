# Changelog

All notable changes follow Keep a Changelog. This project uses semantic versioning.

## [Unreleased]

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
