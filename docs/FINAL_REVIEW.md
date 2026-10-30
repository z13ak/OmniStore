# Development draft PR review — 2026-10-30

Reviewed the complete development diff against `main` at `d83a1d4`, including lifecycle changes,
codec handling, retry semantics, regression tests, integration harnesses, packaging, and CI hooks.
The review found and corrected three additional issues before publishing the draft PR:

| Severity | Finding | Correction and regression coverage |
| --- | --- | --- |
| P2 | An invalid inherited manager concurrency setting could bypass store overrides and report successful close without draining records, or yield a fractional worker target. | Validate the manager limit before changing lifecycle gates. Invalid settings return InvalidConfig while records remain usable. |
| P2 | A scalar value returned by a read-only adapter was indexed before envelope validation, throwing and leaving the pending-load count elevated. | Reject non-table envelopes as InvalidData before inspecting deletion flags. A subsequent healthy load and store close succeed. |
| P1 | Escaping codec-shaped plain tables also escaped preserved unknown wire tags after a save, preventing a newer registry from decoding them later. | Track preserved-wire provenance in memory with weak keys and propagate it through defensive copies. Preserved tags remain wire tags; new literal tables still escape. Future-reader, transaction, and cycle regressions cover both contracts. |

Final local verification after these corrections:

- **102 TestEZ tests passed**, zero assertion failures and zero planning/runtime errors.
- StyLua formatting and Selene lint passed with zero warnings or parse errors.
- All four Rojo builds passed.
- Wally package inspection passed with 40 entries, including the new internal CodecWire module
  and excluding tests, development dependencies, scripts, and the multiplayer project.
- `scripts/verify.ps1 -SkipInstall` and Git whitespace checks passed. Existing TestEZ development
  dependencies were used; dependency installation was not repeated.

The earlier two-client integration evidence remains in `PHASE3_RELIABILITY.md` and its raw reports.
Those runs used the pre-review source at `4f40b7e` and passed with 96 memory records and 12 live
DataStore records. Their timings are historical samples, not new performance measurements for the
review fixes. The final corrections were verified by the expanded unit suite and static/build
checks; the full two-client matrix was not rerun after them.

No remaining P1/P2 issue was identified in this diff review. This is not a production-release
approval: two-independent-server contention/partition recovery and abrupt termination remain
untested. Existing rc.3 writers must be drained before new tombstones or escaped literal tables
are written; a mixed-version rollback remains unsafe. See `COMPATIBILITY.md`.

The pull request should remain a draft until those release gates and human review are complete.
Opening it does not authorize a merge, tag, package publication, or production deployment.

Follow-up: the separate AI review and its corrected nested-codec finding are recorded in
`INDEPENDENT_REVIEW.md`. The expanded 103-test suite and final-source integration recheck are
recorded in `PR1_INTEGRATION_RECHECK.md`; the historical "not rerun" limitation above no longer
describes the latest source.
