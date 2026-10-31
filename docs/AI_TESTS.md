# AI-assisted test records

This document records checks executed or coordinated by the coding assistant. It is separate from the maintainer's [manual test record](MANUAL_TESTS.md). Running a scripted test through a tool does not turn it into a maintainer-performed manual check, and a manual report is not independently captured execution evidence.

## Tool access

The Roblox Studio MCP connection was verified through live instance/state calls. Accessibility was not inferred from the supplied server configuration alone. Tests ran in the confirmed dedicated OmniStoreTests universe `10767918920`, place `73812564531596`.

## Existing evidence

| Record | Scope |
| --- | --- |
| [Phase 2](PHASE2_RELIABILITY.md) | Reliability fixes, 88-test suite, static/build checks, and dedicated-universe persistence smoke checks. |
| [Phase 3](PHASE3_RELIABILITY.md) | Historical 97-test suite and one-server/two-client integration samples. |
| [Final diff review](FINAL_REVIEW.md) | Findings, corrections, and the historical 102-test verification. |
| [Separate code review](INDEPENDENT_REVIEW.md) | Read-only review and the nested-codec correction; no formal pull-request approval. |
| [Final-source integration recheck](PR1_INTEGRATION_RECHECK.md) | 103 passing tests, static/build/package checks, and memory/live DataStore integration on the specified source commit. |

These records retain their original source commits, metrics, raw reports, and limitations. Earlier statements that a scenario was not tested describe those runs; later manual reports do not retroactively expand their scope.

## Shared record controls — 2026-10-30

Example commit: `ce24a97` (`Add shared record test controls`). The server and client examples were checked with StyLua and Selene, which reported zero errors, warnings, or parse errors. Git whitespace checks passed.

Tool-driven Studio checks verified:

- Six client buttons were created and an unsaved increment changed the displayed value.
- A simulated save failure returned Timeout with `dirty = true`; a subsequent save succeeded.
- The isolated failed-load probe returned Timeout without returning a record or forwarding storage requests.
- Pausing persistence allowed a second session in the same Studio server to acquire the expired lease and load the saved value.
- Restoring persistence and attempting to save from the previous session returned LeaseLost.

The final stale-owner check observed `SAVE REJECTED — LeaseLost; dirty = true`. An earlier attempt remained paused and returned Timeout; it is not counted as evidence of stale-owner rejection. The check was repeated after explicitly confirming writes were restored.

These checks used two session identities inside one Studio server, not two independent hosted servers. They did not terminate a process or establish crash recovery. Temporary runtime probes were removed when Play stopped; the updated server Script and companion LocalScript remained in the editable test place. No publication was performed as part of these checks.

## Evidence boundaries

Simulated adapter errors test failure handling, not Roblox service outage behavior. Timing samples are not production capacity estimates. Maintainer reports of crash recovery, handover, and shutdown persistence are recorded only in the manual record. Migration/deployment compatibility and maintainer approval remain separate release requirements.

## rc.4 candidate verification — 2026-10-30

The candidate updates the version, lockfile, changelog, and documentation on top of merged commit `511f88a`; library, unit-test, and integration-harness source is unchanged. Wally dependency installation completed, followed by `scripts/verify.ps1 -SkipInstall`. Formatting, linting, all four Rojo builds, package inspection (40 entries), and whitespace checks passed.

All 52 library/test sources matched the dedicated Studio test place after newline normalization. A fresh Play run reported `Passed = 103`, `GatePassed = true`, and `Complete = true`. Play was then stopped. No new multiplayer or hosted-server run is claimed for this candidate; the existing evidence retains its original scope.

The candidate was committed as `a792e74` and tagged `v0.2.0-rc.4`. Main-branch CI and the tag's release workflow both completed successfully. The GitHub release is marked as a prerelease. All five uploaded package/model/place assets were downloaded and matched the release SHA-256 manifest; the manifest also matched GitHub's asset digest. The downloaded Wally ZIP passed package inspection with 40 entries.

Wally registry publication was attempted after artifact verification but returned `Authentication is required to publish, use wally login`. The registry publication is incomplete; the GitHub prerelease and its assets are available. No game deployment was performed.
