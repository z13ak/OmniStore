# PR #1 final-source integration recheck — 2026-10-30

Source and harness commit: `d414ead66f7307f9a4630ff7b6ad5c50b1044cba` on `development`.
The subsequent evidence commit changes only documentation/reports. The separate AI review is
recorded in `INDEPENDENT_REVIEW.md`; its one P2 finding was fixed and reviewed again.

The final source passed **103 unit tests**, zero assertion failures, and zero planning/runtime
errors. StyLua, Selene, all four Rojo builds, package inspection (40 entries), and whitespace checks
passed. Existing development dependencies were used with `scripts/verify.ps1 -SkipInstall`.

Normalized source checks matched all 52 library/test scripts between the checkout and the Studio
server, with no missing scripts. Both multiplayer harness sources also matched after normalizing
line endings and trailing whitespace.

| Recheck | Result |
| --- | --- |
| Two-client memory integration | Passed; 96 dirty bulk records closed in 0.808042 seconds |
| Two-client live DataStore integration | Passed; 12 dirty bulk records closed in 1.449556 seconds |
| Peak concurrent bulk writes | Four in each run |
| Replication | Both initial clients converged on sequence 200 and value 200 |
| Isolation/security | Private fields and peer channels unavailable; forged changes did not alter server data |
| Snapshot burst | Each client received five accepted and eleven rate-limited responses |
| Resynchronization | Oversized-change invalidation converged through a fresh snapshot |
| Lifecycle | Profile teardown and player-leave persistence passed |
| Replacement join | Passed in the live run using StudioTestService AddPlayers; replacement synchronized successfully |

Raw results are stored in `verification/pr1-recheck-memory.json` and
`verification/pr1-recheck-live-datastore.json`, each naming the tested source commit.

The confirmed dedicated test universe was `10767918920`, place `73812564531596`. The memory run
used `OmniMP_da00664504df4942a4c1`. The live run used the fresh namespace
`OmniMP_c75cab1e7d4d44839206` and left 16 empty tombstones after exact-key cleanup. No existing
application namespace or production data was accessed. These are individual timing samples,
not production-scale performance estimates; the concurrency metric is scoped to the bulk store.

Two unsuccessful setup/development attempts are not counted as passing evidence: one initial
automated run timed out before both clients completed startup; another exposed a timing-dependent
throttling assertion because sequential requests stayed below the configured rate. The successful
rechecks used the corrected concurrent-burst test. The memory run explicitly disabled replacement
join; its raw skip field retains the earlier harness wording about an existing manual session.
The live run subsequently exercised native LeaveTest and automatic replacement join successfully.

This closes the earlier gap between the pre-review integration sample and the reviewed source.
It does not qualify competing leases or partition recovery across two independent Roblox servers,
simulate abrupt process termination, or execute the production old-server drain. Those remain
separate release gates. The PR remains a draft; no merge or release is implied.
