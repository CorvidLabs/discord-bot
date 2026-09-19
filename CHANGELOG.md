# Changelog

Everything worth knowing about between one version of this package and the
next, so that somebody running it can tell what changed without reading a
diff, and can tell whether a hole somebody found is still in the version they
have (TRUST-3.a).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
How a release is cut and how its number is chosen is in
[CONTRIBUTING.md](CONTRIBUTING.md#releases).

**Nothing has been released.** There are no tags, so there is no version you
can depend on yet and nothing below has shipped. Everything here is in `main`.
Comparison links appear beside each version once there is a first tag to
compare against.

## [Unreleased]

### Added

- **`Reserve`**: a finite pot, split into named streams, paid to recipients
  over epochs at a fixed share per slot, with four independent guards against
  paying one period twice. It plans and it records. It never sends anything,
  and it has no idea what a database is: the ledger lives behind the
  `ReserveStore` protocol, which ships with an in-memory implementation for
  tests.
- **`Gating`**: what holding something on chain earns somebody in a server. A
  tier ladder, a collection catalogue with a match rule per collection, a pool
  catalogue, and the pure decision that turns what a member holds and the roles
  they have now into the roles they should have. A role the operator did not
  configure is never touched, and a fact nobody could read manages nothing
  rather than being read as zero.
- **`Games`**: three games of cards and chance as reducers over a context that
  carries the clock and the randomness, so a table replays exactly from a seed.
  Chips are a score: there is no path from a game to anything that moves value.
- **`Chain`**: reading an account, an asset and a pool from an Algorand node,
  behind a per-second rate limiter on a monotonic clock and a per-UTC-day
  request budget that survives a restart through the `RequestBudgetStore`
  protocol. Every figure it hands out says whether it is the whole answer, and
  a short answer becomes unknown rather than a smaller number.
- Every target's configuration is read from numbered environment variables,
  with no default that somebody else chose: a missing required variable is a
  refusal that names it.
- `hi/`, the intent catalogue: nineteen families of criteria with permanent
  ids, written before the code and cited by the tests.
- `specs/`, a contract per module, checked against the exported API by
  `specsync check --strict` in CI.
- 571 tests in 39 suites, all offline. No test reaches a network, and none
  needs a key, a funded wallet or a Discord server.
- `docs/WHAT-IT-TALKS-TO.md`: every outside service the package contacts and
  every secret it asks for, derived from the source, with the commands that
  check each claim and a plain statement of what a reader cannot check by
  grepping this repository (TRUST-1).
- A Linux job in the test workflow, on a GitHub-hosted runner in an official
  Swift container image. The deployment target is a Linux container, and until
  now nothing had ever been built for one.
- This file, and a section in `CONTRIBUTING.md` on how a release is cut.

### Changed

- `Package.resolved` is committed instead of ignored, so two clones of one
  commit build the same code (TRUST-4).
- The `swift-algorand` dependency is `.upToNextMinor(from: "0.4.0")` instead of
  `from: "0.1.0"`. A 0.x release makes no compatibility promise across a minor
  bump, so the old range allowed a dependency to break this package without
  breaking its own rules.

### Fixed

- `swift-tools-version` was `6.0`, and the package could not be built with
  Swift 6.0. The resolved graph reaches `swift-asn1` 1.7.3, whose own manifest
  requires 6.1.0, so `swift build` on a fresh clone stopped with an error
  naming a package the reader had never heard of rather than saying that this
  manifest asked for the wrong toolchain. The declared floor is now `6.1`:
  6.0.3 fails, 6.1.3 builds and passes every test on Linux, and the new Linux
  job builds on 6.1 rather than on whatever is newest that week.

### Known gaps

Not a Keep a Changelog section, and here on purpose: an operator reading this
before installing should not have to infer it from what is missing above.

- There is no Discord surface, no wallet verification, no persistence, no host
  and no executable target. Nothing here can be run or deployed.
- There is no way to ask a running instance what it has been reaching, because
  there is nothing running (TRUST-1.a is half answered, by grep).
