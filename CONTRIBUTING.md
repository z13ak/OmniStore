# Contributing

Thanks for improving OmniStore. Data-loss prevention and clear failure behavior take priority over
API convenience or throughput.

## Development setup

Install the tools pinned in `rokit.toml` with Rokit, then install development dependencies:

```sh
rokit install
wally install
```

On Windows, contributors with the legacy Aftman setup may use `aftman install`; its versions remain
aligned with `rokit.toml` during the transition.

Run `./scripts/verify.ps1` in PowerShell before opening a pull request. On other platforms, run the
commands listed in the README and package with `wally package --output build/OmniStore.tar.gz`.

## Runtime tests

Connect Roblox Studio to `test.project.json` and run the place. The TestEZ runner must report zero
failures. Persistence smoke tests must use a separate published test universe with Studio API access;
never point test code at production DataStores.

Changes to persistence, leases, migrations, codecs, transactions, replication, or shutdown behavior
need focused regression tests and corresponding documentation. Do not weaken a failing safety test to
make an implementation pass.

## Pull requests

- Keep changes scoped and explain their failure/data-compatibility impact.
- Preserve structured result behavior and strict Luau annotations.
- Update `CHANGELOG.md` under `Unreleased` for user-visible changes.
- Call out stored-envelope, model, codec, or migration compatibility changes explicitly.
- Do not include generated `build/`, `dist/`, package, or place artifacts in commits.

By contributing, you agree that your contribution is licensed under the repository's MIT license.
