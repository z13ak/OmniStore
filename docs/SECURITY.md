# Security and replication

Persistence code belongs on the server. Never construct a DataStore adapter or trust client-provided
record keys, values, paths, currency amounts, inventory items, or migration input without
server-side authorization and validation.

The optional replication layer is server-authoritative:

- The server associates a specific player and channel with a loaded record.
- Only explicitly allowed paths are included in snapshots and change events.
- Clients have `Get` and `Changed`, with no remote write/save operation.
- A client cannot request another player's channel unless the server registered that exact pair.
- Snapshot requests are rate-limited, and channel/path counts plus estimated payload size/depth are
  bounded with conservative defaults.

Allowed data is still sent to the client and must be considered visible and inspectable. Never
replicate secrets, moderation evidence, purchase validation state, private identifiers, or server
authorization flags. Validate `allowedPaths` as carefully as an API response schema.

Replication does not stop an exploiter from modifying their local mirror or firing unrelated game
remotes. Game systems must calculate and authorize all persistent mutations on the server.

Channel names are routing identifiers, not secrets. An unavailable and an unregistered channel use
the same response, but clients can always inspect data legitimately replicated to them. Payload
limits reduce accidental or abusive load; they are not a substitute for Roblox network limits or
game-specific rate limits on other remotes.

Session leases reduce accidental concurrent-server writes; they are not a security boundary against
a compromised server or malicious code with access to the same DataStore.

Read-only mode is enforced by the `Record` API and avoids DataStore writes. It is an operational
safety mechanism, not a sandbox against other server scripts: trusted server code can still create
an exclusive store or call DataStoreService directly.

Schema, migration, and codec callbacks are trusted server code. Do not call remotes, perform I/O,
yield, or execute data-provided code from these callbacks. Codec tags are data, not executable type
names; only explicitly registered codec functions are invoked.

Transaction and draft-update callbacks are also trusted, synchronous server code. They must not
yield, perform I/O, invoke remotes, or re-enter live-record mutations. Authorize and validate any
client-derived intent before placing it into a transaction; the draft is a consistency boundary,
not an authorization boundary.

Report vulnerabilities through GitHub's private vulnerability reporting for this repository. See
the root [security policy](../SECURITY.md) for what to include.
