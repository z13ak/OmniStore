# Manual reliability tests

## Reported results — 2026-10-30

The maintainer reported the following checks working in the dedicated OmniStoreTests experience (universe `10767918920`). These are reported manual results; no logs, recordings, exact tested commit, or server identifiers were attached to this record.

| Check | Reported result |
| --- | --- |
| Session locking | A competing server could not own the same record key. |
| Normal handover | Ownership transferred after the owning server closed. |
| Crash recovery | Reported working after abrupt owner termination. |
| Stale-owner protection | Reported working after ownership transferred. |
| Failed load/save | The simulated load and save attempts were rejected. |
| Shutdown persistence | Unsaved changes survived normal shutdown and appeared on the next load. |

The failed-load/save result confirms rejection. A subsequent successful save after restoring access and an independent reload were not separately described, so this record does not claim that additional recovery check. The exact topology and crash method were not recorded; do not treat this report as a captured two-hosted-server qualification run.

## Setup and procedure

Use the [shared record test instructions](../examples/SharedRecordTest.md). Install one server Script and its companion LocalScript in the dedicated test experience. Both servers must use the same namespace, store, and record key. Two clients in one server share one owner and do not test contention between servers.

The controls provide unsaved increments, explicit saves, simulated load/save failures, and a pause of writes and lease renewal. Restore writes before testing successful shutdown persistence. An actual crash check requires terminating the server process; leaving a player session does not establish that the server terminated.

Every successful acquisition adds one claim. For example, starting at 1, adding one unsaved claim, and closing normally should let the next owner display 3: two persisted claims plus its acquisition increment.

## Remaining confirmation

- Record the exact tested commit, server topology, crash method, observed values, and relevant errors on the next repeatable run.
- Confirm recovery after simulated save failure by restoring access, saving successfully, and reloading from another owner.
- Confirm migration compatibility and the deployment drain procedure for any existing stored records before rollout. See [compatibility guidance](COMPATIBILITY.md).
- Remove the shared-record controls from production places. They intentionally allow every player in the dedicated test experience to operate them.

These results do not authorize a merge, release, or production deployment.
