# Failure semantics

## Guarantees and non-guarantees

OmniStore performs each lease/save operation through one adapter update. With the production
adapter, Roblox makes that transform atomic for one key. OmniStore does not promise atomicity across
keys, durable completion after process termination, or full ACID transactions.

`Transaction` means: create an isolated local draft, run a non-yielding callback, validate the final
draft, then replace the record's local data and metadata in one commit. Reads of the live record see
the pre-transaction state until commit; observer events are emitted only afterward. Callback errors,
yield attempts, failed draft mutations, and final validation failures discard the draft. Durability
happens only when a later save succeeds. See [Transactions](TRANSACTIONS.md).

## Error handling

| Code | Meaning | Typical response |
| --- | --- | --- |
| `Locked` | Another live session owns the key. | Retry/rejoin; never load fallback data. |
| `LeaseLost` | Atomic update proved ownership changed. | Stop gameplay writes and close/kick safely. |
| `PersistenceFailed` | Adapter/platform request failed. | Inspect `retryable`; retry or fail closed. |
| `InvalidData` | Value cannot be serialized or path operation is invalid. | Fix code/data; do not retry blindly. |
| `ValidationFailed` | Custom schema rejected data. | Fix schema/data or migrate. |
| `MigrationFailed` | Migration path/callback failed. | Repair migration before allowing play. |
| `NotFound` | A read-only load found no stored record. | Create through an exclusive load if intended. |
| `ReadOnly` | A write was attempted on a read-only record. | Move the write to its exclusive owner. |
| `Timeout` | Budget or acquisition deadline elapsed. | Back off and try again later. |
| `Conflict` | Local state or stored state changed unexpectedly. | Re-evaluate the operation. |
| `TransactionFailed` | A transaction or draft update callback errored or yielded. | Fix the callback; retry only if application logic permits. |

Never replace a load failure with the template and then save it: that can overwrite real data after
a transient outage. OmniStore returns the failure instead.

A model type mismatch, unknown codec under `Reject`, codec callback failure, or schema rejection also
fails closed. `Preserve` retains unknown codec wire data but does not bypass the configured schema.

By default, OmniStore rejects values nested more than 64 tables deep and uses a conservative
4,000,000-byte JSON safety limit for the complete stored envelope. Both limits are configurable.
They bound local validation work and reserve headroom below Roblox's platform limit; platform
validation remains authoritative.

## Shutdown

`CloseAsync` attempts to save and release every record. Roblox shutdown time is finite and the
process can terminate abruptly, so completion cannot be guaranteed. Autosave limits the loss window;
shorter intervals increase request load. Expired leases allow later servers to recover after an
unclean shutdown.

## Save coalescing

One record runs one persistence save at a time. A concurrent caller requests a follow-up snapshot
and waits for the active save cycle. If the first save fails, the cycle stops and returns the error.
Mutations made after a snapshot never get incorrectly marked clean.

## Deadlines and retry classification

Public load, save, delete, record-close, store-close, and manager-close operations accept optional
deadlines. A timeout before persistence leaves the record active and dirty so the caller can retry;
OmniStore does not mark uncertain data clean. Deadlines cannot preempt an `UpdateAsync` that Roblox
has already started, so elapsed wall time can exceed the requested timeout by one in-flight request.

Permanent failures are not retried. Throttled, transient, and unknown platform failures are retried
only within the configured attempt and deadline bounds. Unknown errors remain retryable because
Roblox does not supply a stable structured category for every DataStore failure.

## Stale lease recovery

An unexpired foreign lease always wins. With `Recover`, OmniStore may claim a foreign lease only
after `expiresAt + stealAfter`; the old owner will receive `LeaseLost` on its next save or renewal.
With `Reject`, even an expired foreign lease produces `Locked` with `context.stale = true`. There is
no public option that force-overwrites a live lease.
