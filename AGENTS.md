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
it is one library target, `Reserve`: the engine that works out what a finite pot
owes a crowd and records what has been settled. There is no bot here yet, no
gateway, no commands and no chain access. `README.md` says what exists,
`INTENT.md` says why the engine came first.

## The order of work

1. **Intent.** `hi/` is what somebody wants, in plain sentences with ids that
   never move. Read it before a product decision: a threshold, a default, what
   happens when we cannot answer. If what you are about to build is not written
   down there, write it and get it agreed first. See `hi/AGENTS.md`.
2. **Contract.** `specs/reserve/` holds the module spec and its companions. It
   changes in the same pull request as the code it describes, never after.
3. **Code.** `Sources/Reserve/`, with a test in `Tests/ReserveTests/` whose name
   cites the criterion id it protects.

## Where things live

| Path | What it holds |
|------|---------------|
| `hi/` | Criteria, with permanent ids. Read before deciding anything. |
| `specs/reserve/` | The module contract, its requirements, context and testing notes. |
| `Sources/Reserve/` | The payout engine. Foundation only. |
| `Tests/ReserveTests/` | 105 tests, all offline. |
| `.github/workflows/` | The two gates that run on every pull request. |

## Running the gate

```bash
fledge lanes run verify   # swift build, then swift test
specsync check --strict   # the spec and the code still agree
```

## Rules that bite

- Money is integer arithmetic in the asset's smallest unit. No `Double`, no
  locale-sensitive formatting, anywhere near an amount.
- Limits abort a whole run. They never clamp an amount down to fit.
- A claim is written and persisted before a payment is attempted, never after.
- No force unwrap, no `try!`, no `as!`. Explicit access control on every
  declaration. Four-space indentation, opening brace on the same line.
