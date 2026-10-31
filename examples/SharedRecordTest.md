# Shared record reliability test

Use only the dedicated OmniStoreTests universe (10767918920). Everyone joining this test universe can operate the controls. Remove both scripts before using an experience for production.

Install `SharedRecordTest.server.lua` as one Script in ServerScriptService, replacing the previous shared record script. Install `SharedRecordTest.client.lua` as a LocalScript in StarterPlayer/StarterPlayerScripts. The package must be at ReplicatedStorage/Packages/OmniStore. Publish both scripts to use them in hosted servers.

All servers use `OmniStoreSharedKeyTest/Records/shared-record`. Players in one server share its handle. Use two independent servers for contention and takeover; two clients connected to one server do not provide that test.

| Check | Steps | Expected result |
| --- | --- | --- |
| Locking | Start A, then B. | A owns; B reports LOCKED. |
| Handover | Close A normally. | B owns and its saved claim number increases. |
| Shutdown persistence | In A, click +1 (unsaved), note Claims, then close A normally without clicking Save. | B loads that increment and adds its own acquisition increment: its claim number is one higher than the noted value. |
| Failed save and recovery | While owning, click +1, then Simulate failed save. After it finishes, click Save. | Failure reports dirty = true; the later Save succeeds. Reopen on another server and check the saved increment, allowing for the acquisition increment. |
| Failed load | Click Simulate failed load. | The fresh manager returns an error and no record. Its isolated adapter forwards no requests to storage; existing data is untouched. The owning manager is unaffected. |
| Expiry and stale owner | In A, click +1 without saving, then Pause writes + renewal. Keep A running. Wait for B to own. In A, click Restore writes, then Save. | B takes over after expiry. A reports LeaseLost and cannot overwrite B. Renewal may detect lease loss before Save. B must not contain A's unsaved increment. |
| Abrupt process loss | With A owning in local Studio, terminate that Studio/server process through Task Manager. Keep B running. | B acquires after expiry and loads previously saved data. Unsaved changes are not expected to survive a crash. |

The test lease lasts 30 seconds, renews every 10 seconds, and waiting servers retry every 5 seconds. Allow additional time for DataStore latency. Pause writes blocks all persistence through that server's adapter, including renewal. It simulates an outage, not an actual process crash. Failed save blocks adapter requests for the operation's three-second deadline and restores the prior pause setting. First make a change: a clean record may not need a save request.

The load-failure probe checks failure handling with an isolated adapter. It does not measure Roblox's actual outage behavior, request budgets, or service recovery. Simulated errors are transient and exercise bounded retries. No test rewrites stored leases or calls private library methods.

On normal shutdown the current pause setting remains in effect. Restore writes first when testing successful shutdown persistence. After lease loss, restart A for another ownership test. The display is a command-result snapshot, not continuous telemetry.
