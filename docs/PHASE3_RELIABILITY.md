# Phase 3 Studio qualification — 2026-10-30

Branch: `development` (formerly `fix/phase-2-reliability`).
This phase used one Studio server with two clients in the confirmed dedicated
test universe `10767918920`, place `73812564531596`.

Completed changes:

- `d99e743`: pinned rc.3 persistence fixtures, five compatibility tests, and concrete rollout constraints.
- `9947584`: test runner rejects planning/runtime errors and empty runs, with four regression tests.
- `eb5f10f`: opt-in multiplayer server/client harness, separate Rojo project, and static/build hooks.

The library's production source has not changed during this phase. Qualification adds tests,
test infrastructure, and release evidence to the Phase 2 fixes.

## Results

| Gate | Result |
| --- | --- |
| TestEZ | 97 executed and passed; zero assertion failures and zero planning/runtime errors |
| Memory integration | Passed with two separate Studio client processes and 96 dirty bulk records |
| Live DataStore integration | Passed with two Studio client processes and 12 dirty bulk records |
| Memory close sample | 0.812728 seconds; peak concurrent bulk writes: 4 |
| Live close sample | 1.617466 seconds; peak concurrent bulk writes: 4 |
| Static checks | StyLua passed; Selene reported zero errors, warnings, and parse errors |
| Builds | Package, development place, unit-test place, and multiplayer place passed |
| Package boundary | Wally archive validated with 39 entries; test code and multiplayer project excluded |

Both integration runs verified:

- Initial per-player profiles and a shared read-only mirror synchronized on both clients.
- Private fields and another player's channel remained unavailable.
- Mutating a returned mirror copy did not change mirror state; mirrors exposed no save/write API.
- Sending a forged client change did not mutate authoritative server data.
- Snapshot request limits applied per player; both clients saw accepted and rate-limited responses.
- Both clients converged on all 200 shared-record updates, at sequence 200.
- An oversized change caused snapshot resynchronization instead of silent divergence.
- Closing one profile made its mirror stale/unavailable while its peer and shared channel stayed usable.
- Disconnecting a client triggered profile close and persisted its final server value.
- Manager close persisted every bulk record within 25 seconds and released every checked lease.

The memory adapter injected 20 ms into measured bulk writes to exercise concurrency. These timings
are individual test samples, not production capacity estimates. The concurrency metric measures
the bulk store; another store may close concurrently under the manager's separate bounded workers.

Raw reports:

- `verification/phase3-memory.json`: namespace `OmniMP_c7f5942e2eca4cebb07c`, synthetic clients -1 and -2.
- `verification/phase3-live-datastore.json`: namespace `OmniMP_cb2d2d81e6ba49529f7d`, synthetic clients -2 and -3.

Only fresh disposable keys in that live namespace were used. The successful live run left 15 empty
tombstones after exact-key logical cleanup. Existing application namespaces were not accessed.

## Compatibility decision

Ordinary rc.3 records are readable by development, and rc.3 can read ordinary development records
containing the new write token. Three combinations are explicitly unsafe:

1. rc.3 readers treat new tombstones as ordinary template-shaped records.
2. rc.3 codecs reject escaped plain tables as an unknown codec type.
3. rc.3 deletion can erase a record despite a development server's live lease.

Drain old writers before enabling deletion or new-format writes. A normal rolling deployment does
not remove existing old servers, and reverting the binary after new-format writes is not a safe
rollback. The fixture imports use current shared helpers, so this matrix tests the pinned old
persistence/codec algorithms rather than claiming a complete legacy runtime test. See
`COMPATIBILITY.md` for the drain and rollback procedure.

## Limits and remaining release gates

The tested topology is one server with two clients. It does not test competing leases,
network partitions, or takeover between two independent Roblox servers. The timed close invokes
the manager close path; it does not simulate abrupt process death or prove completion during a
real server shutdown under platform pressure.

StudioTestService's automated launch returned no result in this environment, and adding players
through that service was unavailable in the existing manual session. The tests therefore ran
directly in an existing Server & Clients session. Client departure used a server kick after the
client reported `CanLeaveTest = false`. An additional local Studio client was launched between the
successful runs and participated in the live run. Automatic replacement-join **within** either run
was skipped and is explicitly recorded as not run in both reports.

Unavailable automation left the skipped scenarios unverified. CI builds the
multiplayer artifact but does not launch Studio itself. No release, tag, push, or production rollout
was performed.
