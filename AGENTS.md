<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge trust verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->

## What this is

A Discord bot for Algorand projects, built in the open a piece at a time. Today
it is six library targets and no bot: `Reserve` works out what a finite pot
owes a crowd and records what has been settled, `Gating` decides what holding
something earns somebody in a server, `Games` is three games of cards and
chance as replayable reducers, `Chain` reads an Algorand node behind two
brakes, and `Store` with `StoreSQLite` is what one instance remembers between
restarts.

**There is no gateway, no slash command and no executable**, so
nothing here can be run or deployed. `README.md` says what exists and what is
missing; `INTENT.md` says why the engine came first.

## The order of work

1. **Intent.** `hi/` is what somebody wants, in plain sentences with ids that
   never move. Read it before a product decision: a threshold, a default, what
   happens when we cannot answer. If what you are about to build is not written
   down there, write it and get it agreed first. See `hi/AGENTS.md`.
2. **Contract.** A module's spec lives in `specs/<module>/` and changes in the
   same pull request as the code it describes, never after. Every target has
   one, and `.specsync/config.toml` lists every source directory, so a new
   export without a contract fails the gate rather than passing unread.
3. **Code.** `Sources/<Module>/`, with a test in `Tests/<Module>Tests/` whose
   name cites the criterion id it protects.

## Where things live

| Path | What it holds |
|------|---------------|
| `hi/` | Criteria, with permanent ids. Read before deciding anything. |
| `specs/reserve/`, `specs/chain/` | Module contracts, with their requirements, context and testing notes. |
| `Sources/Reserve/` | The payout engine. Foundation only. |
| `Sources/Gating/` | The role rules and the operator's configuration. Foundation only. |
| `Sources/Games/` | The game engine. Foundation only. |
| `Sources/Chain/` | Reading the chain, and the two brakes. Depends on `Gating` and on `swift-algorand`. |
| `Sources/Store/` | The records, the protocols and the store in memory. Depends on `Reserve`, `Gating` and `Chain`, and on no chat client. |
| `Sources/StoreTestKit/` | The conformance suite. A plain target no product reaches, so it never ships. |
| `Sources/StoreSQLite/` | The durable store, over `Sources/CSQLite`, which wraps the platform's own `libsqlite3`. No new pin. |
| `Tests/` | 635 tests in 47 suites, all offline. Six targets; `swift test` is the only figure worth quoting, because a per-target filter matches suite names across targets and double counts. |
| `docs/README.md` | Which document owns which fact, and the rules that keep the set from contradicting itself. Read it before putting a fact in a new place. |
| `docs/CONFIGURATION.md` | Every environment variable an operator sets: what it means, its default, and what goes wrong when it is wrong. A pull request that adds, renames or redefaults a variable edits it in the same pull request. Its worked example is loaded by a test, so it cannot quietly stop being true. |
| `docs/WHAT-IT-TALKS-TO.md` | Every outside service and every secret, derived from the source. A pull request that adds an outbound call, a host, a dependency or a secret edits it in the same pull request. |
| `CHANGELOG.md` | What changed between two versions. New work goes under `Unreleased`. |
| `.github/workflows/` | The two gates that run on every pull request, on macOS and on Linux. |

## Running the gate

```bash
fledge lanes run verify   # swift build, then swift test
specsync check --strict   # the spec and the code still agree
```

`.specsync/config.toml` lists every source directory with a contract. Adding a
module's sources to `source_dirs` without writing its spec first turns the gate
red, which is the point.

## Rules that bite

- Money is integer arithmetic in the asset's smallest unit. No `Double`, no
  locale-sensitive formatting, anywhere near an amount.
- Limits abort a whole run. They never clamp an amount down to fit.
- A claim is written and persisted before a payment is attempted, never after.
  In `StoreSQLite` that is structural rather than remembered: the write scope
  takes a synchronous body and a payment is `async`, so the wrong order does
  not compile.
- An amount is never a signed integer column and never a `Double`. Eight bytes,
  most significant first, because the payout engine saturates to the largest
  unsigned value on purpose and half that range does not fit in what SQLite
  stores.
- Nothing below the chat boundary holds an identifier that came from a person.
  A member is named by a key the instance drew at random, and deleting the one
  row that links it to them is the forgetting.
- A fact nobody could read is **unknown**, not zero and not empty. A short
  answer is not a smaller true answer. Nothing is granted or taken away on an
  unknown.
- One idea, one type. Two modules declaring a type of the same name for the
  same job is a defect, not an untidiness: the pool and the combined balance
  were each declared twice and each cost something real.
- Nothing falls back to a value somebody else chose. A missing required
  variable is a refusal naming it.
- No force unwrap, no `try!`, no `as!`. Explicit access control on every
  declaration. Four-space indentation, opening brace on the same line.
- This repository is public. No real address, asset id, Discord snowflake or
  personal path in code, tests, specs or commit messages, and no naming of the
  private project any of it was ported from.
