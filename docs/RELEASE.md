# Release process

Releases are deliberate and never performed merely because a development phase completed.

## Candidate checklist

1. Choose the version using the compatibility policy.
2. Update `wally.toml` and move `CHANGELOG.md` entries from `Unreleased` into a dated version heading.
3. Run `./scripts/verify.ps1` and inspect the Wally package file list.
4. Run the Studio TestEZ suite with zero failures.
5. Complete the published-universe and replication smoke gates in `TESTING.md` when relevant.
6. Review docs, migration/codec compatibility, failure semantics, package contents, and generated
   artifacts. Confirm no secrets or production data are present.
7. Commit the reviewed candidate, create the exact tag `v<manifest-version>`, and push it.

## Automation

Pull requests and main-branch pushes run static checks, all Rojo builds, and Wally package inspection.
An approved `v*` tag runs the same toolchain, requires the tag to equal the manifest version and a
dated changelog heading, then publishes a GitHub release with the Wally and Rojo artifacts. Versions
containing a SemVer prerelease suffix are marked as GitHub prereleases. Review the SHA-256 manifest
and recorded Studio/smoke evidence before creating the tag.

Wally registry publication remains manual so a GitHub tag cannot publish an unreviewed package.
Authenticate locally, inspect the exact candidate archive and repository state, then run
`wally publish` only after the GitHub release and its artifacts are approved. Registry publication is generally
irreversible for a version; never reuse a released version number.

## Rollback

Keep the previous artifact available. Code rollback is safe only when the previous version can read
every data shape written by the candidate. If not, pause rollout/writes and ship a forward fix or an
explicitly tested reverse migration strategy. Never rewrite broad DataStore namespaces as an
emergency shortcut.
