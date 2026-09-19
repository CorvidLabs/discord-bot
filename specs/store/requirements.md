---
spec: store.spec.md
---

## User Stories

- As a member, I want to prove a wallet once and be remembered, so that I am
  not asked again every time I run a command (VERIFY-2).
- As a member who links a second wallet, I want everything I hold counted
  together, so that gaining an empty account does not take my rungs away
  (VERIFY-2.a).
- As a member who leaves or asks to be forgotten, I want everything kept about
  me to go, and I want to be able to see what that was before I decide
  (VERIFY-7, VERIFY-7.a).
- As a member, I want whatever the record of a payment has to keep to name me
  no more than it has to (VERIFY-7.b).
- As somebody running this, I want a machine that stops in the middle of a
  payout to under-pay rather than pay somebody twice (RESERVE-6.a).
- As somebody running this, I want a second copy of the bot pointed at the same
  store to refuse to start, rather than pay the same week twice (RESERVE-6.c).
- As somebody running this, I want to take everything out in a form another
  tool can read (HOST-9, HOST-9.a).
- As somebody running this, I want a new build to tell me what it will change
  before I take it, and to refuse rather than guess when the file was written
  by something newer (RUN-9).
- As somebody deciding whether to install this, I want the list of outside code
  to stay short enough to read (TRUST-1).
- As a contributor, I want the tests to need no network, no key and no database
  I had to set up (BUILD-2, BUILD-2.a).
- As a contributor, I want to put made-up members, wallets and holdings in
  front of it without holding anything real (BUILD-1.b).

## Acceptance Criteria

### REQ-store-001

A save SHALL be on storage before it returns. The durability settings SHALL be
applied to the one connection that commits, SHALL be read back, and a mismatch
SHALL stop the process naming the setting, the value asked for and the value in
force.

- Covered by `SQLiteFileTests.swift` and by the `aClaimIsOnTheStorage...`
  behaviour of the conformance suite.

### REQ-store-002

It SHALL NOT be expressible to commit a claim after a payment. The write scope
SHALL take a synchronous body.

- Covered by the compiler: a payment is `async` and cannot be called in one.
  `TargetShapeTests.swift` asserts no other route into a statement exists.

### REQ-store-003

A row that exists and cannot be read SHALL throw, and SHALL NOT read as a fresh
record, as zero, or as nil.

- Covered by the `anUnreadable...Throws` behaviours, with a probe that writes
  rows the store's own writer refuses to write. The probe reaches the epoch,
  the day's count, an account, the reserve's own state and the sweep baseline,
  so the rule is proved on the two rows where breaking it is worst rather than
  only on the ones that were easy to corrupt.
- An unreadable account SHALL refuse on every path that reads it, including the
  count the sweep guard takes, and a member key the reader would not accept
  SHALL be refused by the file rather than skipped by the reader. Covered by
  `anUnreadableAccountThrows` and by `SQLiteFileTests.swift`, "A member key
  that is not a key is refused by the file, not skipped by the reader".

### REQ-store-004

An amount SHALL round-trip across the whole unsigned range, including the
largest value, which the payout engine produces on overflow by design. An
amount SHALL NOT be stored in a signed integer column and SHALL NOT pass
through a floating point value.

- Covered by `anAccountRoundTrips`, `reserveStateRoundTrips`,
  `anEpochRoundTrips`, `theBudgetRoundTrips`, `amountsSortByValue` and
  `TargetShapeTests.swift`.

### REQ-store-005

One account SHALL belong to one member. A second member proving it SHALL be
refused, and the refusal SHALL leave the stored figures untouched.

- Covered by `oneAccountBelongsToOneMember`.

### REQ-store-006

Nothing below the chat boundary SHALL hold an identifier derived from a person.
A member who is forgotten and returns SHALL be given a new key.

- Covered by `aKeyComesFromNothing` and `theLedgerNamesNobodyAfterAForgetting`.

### REQ-store-007

A forgetting SHALL be one transaction, SHALL take every table carrying a member
key, and SHALL leave the payout ledger's guard working.

- Covered by `forgettingTakesEverything`, `forgettingTwiceIsQuiet`,
  `everyMemberOwnedTableCascades` and `theLedgerDoesNotCascade`.

### REQ-store-008

A second process SHALL be refused a store another already holds, before a
handle is opened.

- Covered by `aSecondStoreIsRefused`.

### REQ-store-009

A file holding a migration this build does not know, or a migration whose text
differs from the one shipped, SHALL stop the start and name it. A pending
migration SHALL copy the file first, and SHALL NOT run when the copy fails.

- Covered by `aSchemaFromTheFutureIsRefused`, `anEditedMigrationIsRefused` and
  `aPendingMigrationCopiesFirst`.

### REQ-store-010

Every migration SHALL have a reverse, and reversing them all SHALL leave
nothing but the bookkeeping table.

- Covered by `everyMigrationHasAReverse`.

### REQ-store-011

A recomputed spend SHALL only ever rise.

- Covered by `reconciledSpendOnlyRises` and
  `ReserveSpendReconciliationTests.swift`.

### REQ-store-012

The suite SHALL run against any backend, and a backend that cannot supply a
probe SHALL have the behaviours needing it reported as skipped with a reason
rather than passed.

- Covered by `InMemoryConformanceTests.swift`, which asserts the set of skipped
  behaviours is exactly the durable ones.

### REQ-store-013

An open that found no store at the path and made one SHALL say so. A store that
was invented SHALL NOT be reported the same way as one that was found, because
an invented one reads as a reserve that has never paid anybody.

- Covered by `SQLiteFileTests.swift`, "A store this open invented rather than
  found says so", including the deleted-file case.

### REQ-store-014

Two identifiers whose bytes differ SHALL be two members, in every backend.
Text SHALL cross a storage boundary whole rather than to its first NUL.

- Covered by `identifiersAreComparedByTheirBytes`, over a pair that differs
  after a NUL and a pair that differs only in how the same characters are
  spelled.

### REQ-store-015

A value a store was given SHALL come back as it was given or SHALL be refused.
A list holding the same value twice SHALL NOT come back shorter or reordered.

- Covered by `anEpochRoundTrips` and `reserveStateRoundTrips`, which now name
  different streams in the three maps a state carries.

### REQ-store-016

A store SHALL persist the charges an epoch record carries and SHALL return
them in the order they were written, in every backend, including when the same
epoch is saved again with a further charge appended. An epoch row written by a
build from before the charges existed SHALL read as an epoch with no charges,
and SHALL NOT throw and SHALL NOT have a period invented for it from a
timestamp. That is not an exception to the rule that a row which exists and
cannot be read throws: a field absent from a record an older build encoded is
not an unreadable row, and a backend SHALL NOT treat it as one. Where a
backend keeps the charges under a name of their own, that name SHALL be one of
the shared table names, so a forgetting and an unreadable row report it the
same way whichever backend is running.

Acceptance Criteria
- The shared conformance behaviour covering an epoch round trip, extended with
  charges, proves every backend returns them whole and in the order they were
  written (RESERVE-8.a).
- A new shared conformance behaviour proves an epoch saved a second time with
  a further charge reads back with both charges, in order (SPEND-9.c).
- `InMemoryConformanceTests` and `SQLiteConformanceTests` prove both
  behaviours against each backend rather than proving them once (RESERVE-8.a).
- `SQLiteFileTests` proves a file written by the build before this one keeps
  every epoch row across the pending migration, and that those epochs read as
  charged to no period rather than failing to load (ADOPT-5, RUN-9).

### REQ-store-017

The charges SHALL arrive as a new migration rather than as an edit to a
migration already shipped, because a shipped migration is fingerprinted and
editing one refuses the start for everybody who already ran it. The reverse of
that migration SHALL run on the oldest SQLite version this package admits at
open, and SHALL NOT depend on dropping a column, because that floor is older
than the release which learned to drop one. A reverse SHALL therefore drop
whole objects the migration created, leaving the earlier schema exactly as it
was.

Acceptance Criteria
- The existing reverse-everything test proves that applying every migration
  and reversing every one, including the new one, leaves nothing but the
  bookkeeping table (RUN-9).
- `SQLiteFileTests` proves the new migration takes a copy of the file before
  it runs, and refuses to run when the copy fails (RUN-9).
- `SQLiteFileTests` proves no shipped migration's reverse uses a column drop,
  so every reverse runs on the oldest SQLite the package declares it supports
  (RUN-9).

## Constraints

- The tests run offline with nothing installed. SQLite is the platform's own,
  so no package is fetched and no service is contacted.
- Nothing in these targets reads an environment variable. A path arrives as a
  parameter.
- No chat client in the package graph of any of the three targets.
- Instants are whole seconds. Sub-second precision is not kept, and the suite
  asserts the rounding rather than leaving it to be discovered.
- Money is integer arithmetic in the asset's smallest unit. `SQLValue` has no
  floating point case.

## Out of Scope

- Deciding anything. The ladder, the collections and the pools belong to
  `Gating`; what a pot owes belongs to `Reserve`; reading a chain belongs to
  `Chain`. This module remembers and refuses, and decides nothing.
- Everything listed under **What is missing** in the spec: the holdings cache,
  a payments table, the audit log, claim offers, scheduled tasks, the games'
  rows and a member's saved timezone.
- Refusing to boot on a store the open invented. This reports it; a host
  decides, because a first boot has to be able to happen.
- Enumerating the ledger rows that name a member when they ask what is held
  about them.
