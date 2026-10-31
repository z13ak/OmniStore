# Legacy persistence fixtures

`LegacyStore.lua` and `LegacyCodecRegistry.lua` are copied from commit
`d83a1d49793e0e1f6c3d5bd51ee82c15cf308ce1` (`0.2.0-rc.3`). Their import paths alone are rebound
to the current library's shared helpers so the old persistence and codec algorithms can be tested
without duplicating the entire package. This is a wire-compatibility fixture, not a complete legacy
runtime or a substitute for running old and new packages on separate servers.

The compatibility specs deliberately demonstrate unsafe combinations. A passing test for an old
reader resurrecting a tombstone documents a prohibited rollout combination, not supported behavior.
Keep these fixtures pinned; do not repair the old implementation when changing the current package.
