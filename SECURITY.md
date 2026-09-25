# Security policy

Please report suspected vulnerabilities privately through GitHub's private vulnerability reporting
feature for this repository. Do not open a public issue containing exploit steps, secrets, affected
universe identifiers, or production data.

Include the affected version or commit, impact, reproduction conditions, and the smallest safe proof
of concept available. Maintainers should acknowledge a report, assess affected versions, prepare a
fix and regression test, and coordinate disclosure before publishing technical details.

Only the latest released minor line receives security fixes before `1.0.0`. After `1.0.0`, the latest
major release and any explicitly named supported lines in the compatibility policy are supported.
No response-time or zero-vulnerability guarantee is made.

Never attach production DataStore exports, API keys, cookies, or authentication tokens to a report.
See [the detailed security model](docs/SECURITY.md) for trust boundaries and non-guarantees.
