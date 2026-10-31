# Code review of PR #1 — 2026-10-30

The production diff and relevant tests were reviewed against `main` (`d83a1d4`), starting at PR
head `634371a`. The review was read-only. Runtime verification was performed separately, and no
formal GitHub approval was submitted as part of this review.

The review identified one actionable **P2** issue in unknown-codec preservation:

1. Load an unknown outer codec with `unknownTypePolicy = "Preserve"`, whose opaque payload contains
   a nested codec envelope.
2. Copy the descendant with `record:Get("Item.value.Child")`.
3. Assign it elsewhere with `record:Set("Other", copiedValue)` and save.
4. A newer reader receives a literal tag table at `Other` instead of decoding the nested codec.

Only the outer envelope carried in-memory provenance. Library copying of the descendant therefore
caused it to be escaped as an ordinary literal. This was an introduced regression, not a preexisting
rc.3 behavior.

Commit `7b11766` fixes it by marking the complete opaque wire subtree before defensive copying.
The traversal uses a local seen set to handle cycles/shared references. The encoder continues to
reject cyclic values. A new regression covers Get, Set, save, and decoding with the newer registry.

Follow-up review confirmed that the fix resolves the P2, with no additional concrete issue
identified. No other introduced P1/P2 issue was identified in the production changes inspected.
The expanded Studio suite passed **103 tests**, with zero assertion or planning/runtime errors.

Integration rechecking also exposed a harness flaw: sequential snapshot requests could stay below
the server's configured rate on a slow client, so expecting throttling was timing-dependent.
Commit `78be749` sends 16 concurrent requests, checks every response, and still requires both
accepted and throttled responses for each client. Commit `d414ead` lets explicit per-script test
parameters override launch arguments for repeated memory/live runs in the same Studio session.

These changes do not establish independent-server contention, partition recovery, abrupt-process
termination, or safe production rollout. Those remain separate qualification tasks.
