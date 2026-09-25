# Incident response

## Immediate priorities

1. Stop expanding the blast radius. Disable the affected deployment or persistence feature through
   the game's normal controlled rollout mechanism.
2. Do not load a failed record as a template and save it. Preserve failure evidence and fail closed.
3. Record the deployed commit/package, universe and place, timestamps, affected key categories,
   structured error codes/categories, lease identities, and relevant platform status.
4. Protect user privacy. Do not paste full records, secrets, receipts, or identifiers into public
   tickets or logs.

## Triage

Distinguish platform/transient failures from permanent configuration errors, schema/migration
failures, lease conflicts, payload rejection, and application misuse. Check request budgets, retry
counts, save/close failures, lease loss, dirty duration, and whether failures began after a rollout.
Use exact-key read-only inspection tooling where authorized; never bulk rewrite while the cause is
unknown.

## Recovery

- Prefer a forward-compatible fix. Rolling back code may be unsafe after newer code writes migrated
  data.
- Never force a live lease takeover. Wait for expiry plus configured grace or close the confirmed
  owner normally.
- Repair data only with reviewed, idempotent, exact-key tooling and a recoverable backup/export
  process appropriate to the game.
- Roll out gradually and monitor both successful operations and failures. Absence of errors alone is
  not proof that saves are occurring.

## Afterward

Document impact and timeline, root cause, why existing controls did or did not catch it, recovery
actions, and follow-ups. Add a deterministic regression test, update migration/compatibility notes,
and rotate any exposed credentials. Security issues follow the private process in root `SECURITY.md`.
