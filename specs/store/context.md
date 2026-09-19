---
spec: store.spec.md
---

## Key Decisions

- **A new table for the charges, rather than a column or a fourth claim kind.**
  A column cannot hold the two-period case without inventing a delimiter and a
  parser, needs two columns because a whole-unit figure is an amount and cannot
  share a text column, and its reverse needs either a column drop the oldest
  SQLite this package admits at open does not have or a rebuild of the money
  table. A fourth kind in the claims table would mean rebuilding the table that
  holds the no-double-pay record, for bookkeeping that stops nothing. A create
  and a drop is the cheapest exactly reversible migration there is.
- **The platform's SQLite over the C interface, rather than an ORM.** The list
  of outside code somebody reads before installing this stays at three entries
  (TRUST-1), and the part that must not lose a payment record is a
  write-ahead log this project did not write and does not maintain. What is
  hand written is the thin layer above it. The trade is roughly a thousand
  lines of C interop, which is where a bug can hide with no test looking at it,
  and it is bounded by keeping the pointers inside single methods of one actor
  and by asking SQLite to copy everything bound to a statement.
- **One connection, and no read pool.** Every durability setting is per
  connection, so a pool is a pool in which one handle has them. A pool also
  hands out a connection that reads `synchronous` back as zero after it was set
  once, which is the silent version of this failure. The actor above serialises
  everything anyway, so a second connection buys nothing in one process.
- **The write scope takes a synchronous body.** This is the one guard here that
  is structural rather than disciplinary. A payment is `async`, so no later
  refactor can batch a claim, defer it into a task, or commit it after the value
  has moved. Every other design considered kept that rule alive with a comment.
- **`SQL` is a `StaticString` literal and nothing else.** No initialiser from a
  `String`, no interpolation, no escape hatch. A value reaches a statement
  through a placeholder or it does not reach one.
- **`SQLValue` has no floating point case.** Money cannot meet a `Double`
  through the store, and that is a property somebody can check by reading a
  twelve-line type.
- **An amount is eight bytes, most significant first.** Measured rather than
  assumed: SQLite's `INTEGER` is signed, the payout engine saturates to the
  largest unsigned value on purpose, and the obvious mapping fails while
  somebody is being paid. Big-endian bytes also compare the way the numbers do,
  which decimal text does not, and an operator reading the file elsewhere sees
  a blob rather than a negative number that is secretly a large positive one.
- **A member key is minted, not derived.** A hundred and twenty eight random
  bits with nothing of the person in them. This is what lets the payout ledger
  keep who was already paid and a member still be forgotten: the directory row
  was the only link, deleting it is the forgetting, and every surviving mention
  refers to nobody. The alternatives all cost something real. A keyed hash
  needs a key destroyed on a timer and a discipline that nothing anywhere logs
  the two together, and its failure is silent. Redacting the ledger row breaks
  the guard it was protecting. Neither is needed once the identifier never came
  from a person in the first place.
- **The ledger keeps the account in plain text, deliberately.** The planner
  compares it and the payer sends to it, so a transformed account either stops
  matching, which pays everybody again on a resumed run, or sends money to a
  token. The recipient id is the only field that may be an opaque name, and it
  is the only one that is.
- **Claims are their own rows rather than three lists inside the epoch row.**
  A runner saves the whole record once per recipient, so lists in the row mean
  rewriting a growing value several thousand times and flushing each version:
  hundreds of megabytes for one epoch and quadratic beyond. A payout that is
  correct and takes two minutes gets killed by an operator's timeout half way
  through, which is the half-finished payout the design exists to prevent,
  arriving by the back door. The write is an append wherever the stored rows
  really are a prefix of what is being saved, and falls back to writing the lot
  when a claim was given back.
- **Instants are whole seconds since 1970 UTC, in both backends.** The
  alternative is a formatter, which brings a locale, a calendar, a platform
  difference and the repair migrations that follow them. Sub-second precision
  is lost and the suite asserts the rounding rather than hiding it.
- **The in-memory store keeps rows as encoded text.** It costs a little and it
  means the rule that an unreadable row throws is exercised rather than
  asserted, and that a record which round-trips in a contributor's fast lane
  round-trips on disk too.
- **The conformance suite does not import a testing framework.** It throws a
  named failure instead, so it builds on any toolchain and any platform with
  nothing but Foundation and this package in the graph, and a test target turns
  one into a failure at its own call site.
- **The under-counted spend at the reserve seam is compensated at boot, not
  hidden.** `save(epoch:)` and `save(state:)` are two commits and a crash
  between them under-counts, which is the direction the engine itself calls
  unsafe. The compensation is upward only and goes through the four methods the
  seam already has. The real fix is a fifth method writing both rows in one
  transaction, and the spec says so rather than letting the workaround stand in
  for it.
- **`revertEverySchemaStep` is not a rollback for an operator**, and is
  documented as not being one. It exists so a test can prove every migration
  has a reverse. What an operator rolls back to is the copy the migrator takes
  before it changes anything.

## Files to Read First

- `Sources/Store/BotStore.swift`: the whole surface a host writes against, in
  four small protocols plus the two the engine already declared.
- `Sources/Store/MemberKey.swift`: the identity decision, in one type, with the
  reason it dissolves the forgetting problem rather than managing it.
- `Sources/StoreSQLite/Connection.swift`: the one connection, the settings that
  are read back, and the write scope whose body is synchronous.
- `Sources/StoreSQLite/BaseUnits.swift`: why an amount is eight bytes and not
  an integer column.
- `Sources/StoreSQLite/Schema.swift`: every table, with the cascade that is the
  forgetting and the claim table that deliberately has none.
- `Sources/StoreTestKit/StoreConformance.swift`: the list of behaviours a store
  has to have, which is the readable version of this contract.
- `hi/verify.md` and `hi/host.md`: what a member and an operator are owed.

## Current Status

Implemented, and both backends pass the same suite. The store in memory needs
nothing installed and skips the two behaviours it cannot honestly prove, saying
so. The SQLite store runs the whole suite on a file and again in memory.

There is still no bot: no gateway, no command, no executable. This module is
what the bot will write through when there is one. What is deliberately not
built is listed under **What is missing** in the spec.

## Notes

- Three durability facts here were measured rather than recalled, on this
  machine, against this library: a pooled connection reads a durability setting
  back as unset after it was set once, which is why there is one connection; an
  unsigned amount does not survive a signed integer column across half its
  range, which is why an amount is bytes; and a write-ahead log with the
  usually recommended `synchronous = NORMAL` flushes at a checkpoint rather
  than at a commit, which is why it is `FULL`.
- The evidence for durability here is a second view of the storage that cannot
  see an uncommitted write, plus a handle let go without a tidy shutdown. That
  catches a write deferred into a task, which is the regression most likely to
  be introduced by somebody making an epoch loop faster. It does not exercise a
  death inside a write call, which needs a small executable this package does
  not have.
- The volume is identified two different ways because the platforms report it
  two different ways: a name from `statfs` on Darwin, and the kernel's own
  mount table on Linux, which Swift can read as text and which needs no C
  interop and no architecture-dependent integer width. Both are built and
  tested. What no check has is a real network mount, so the decision is proved
  against a supplied table.
