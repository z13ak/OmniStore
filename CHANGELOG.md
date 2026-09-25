# Changelog

All notable changes follow Keep a Changelog. This project uses semantic versioning.

## [Unreleased]

## [0.2.0-rc.1] - 2026-09-25

### Added

- Phase 2 reliability layer: one bounded autosave/lease scheduler per store, operation and shutdown
  deadlines, generic entity close coordination, typed persistence-error categories, and protected
  structured logger/metrics hooks.
- Public timeout options for load, save, delete, record close, store close, and manager close.
- Phase 3 session semantics: diagnostic lease identities, backward-compatible lease enrichment,
  read-only records backed by `GetAsync`, and explicit expired-lease recovery policy.
- Phase 4 typed models: composable path-aware schemas, stable model identities, recursive codecs,
  explicit unknown-codec policy, common Roblox datatype codecs, and per-step migration validation.
- Phase 5 isolated in-memory transactions with draft mutation APIs, non-yield enforcement, buffered
  observer events, final-state validation, and failure-safe local commits.
- Phase 6 replication hardening: monotonic per-channel sequences, client gap resync, event buffering,
  bounded payload/path/channel/request limits, lifecycle cleanup, and synchronization status signals.
- Phase 7 release engineering: pinned Rokit toolchain, pull-request CI, validated Wally/Rojo
  artifacts, draft tag releases, contributor/security policies, and release/upgrade/testing/
  performance/incident-response documentation.

### Fixed

- Bound serialization traversal with a configurable maximum depth and made the JSON payload safety
  limit configurable.
- Preserve manager retry and lease defaults when a store supplies only a partial override.
- Validate templates, stored values, nested mutation inputs, metadata, and complete envelopes before
  copying or persistence.

### Tests

- Added regression coverage for serialization depth and payload limits, configuration merging,
  transient retry success, and dirty-state preservation after an exhausted save.
- Added deterministic coverage for error classification, retry suppression, operation deadlines,
  diagnostic isolation, lifecycle closing, and background concurrency bounds.
- Added multi-session coverage for read-only safety, missing snapshots, stale recovery policy,
  lease loss after takeover, diagnostic identity, and simultaneous exclusive-load races.
- Added schema, model-identity, codec wire/round-trip, unknown-type, and intermediate migration tests.
- Added transaction isolation, observer visibility, callback/yield failure, live-write exclusion,
  final-schema, sticky draft-failure, and metadata durability tests.
- Added adversarial replication coverage for allowlist boundaries, malformed/overlapping paths,
  payload limits, cycles, unsupported values, request throttling, cleanup, and sequence gaps.
- Added package-content verification so development dependencies, tests, and generated builds cannot
  leak into the published Wally archive.

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
