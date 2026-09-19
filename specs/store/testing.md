---
spec: store.spec.md
---

## Automated Testing

`swift test` runs the whole package offline, with no network, no key and no
database anybody had to create. The store's own share runs the same conformance
suite three times: against the store in memory, against SQLite on a file, and
against SQLite in memory.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `Tests/StoreTests/InMemoryConformanceTests.swift` | Conformance | Every behaviour against the store a contributor needs nothing to run, plus an assertion that the only behaviours it skips are the durable ones. |
| `Tests/StoreTests/StoreRecordTests.swift` | Unit | The key's shape and its refusals, two thousand keys not colliding, rounding on both sides of 1970, a saturated amount surviving a round trip, a refusal that names what to change without printing a whole identifier, and the sentence about the payment record naming the wallet and the holdings it keeps. |
| `Tests/StoreSQLiteTests/SQLiteConformanceTests.swift` | Conformance | The same behaviours against a file and against a database in memory. The file lane asserts nothing was skipped, so a probe going missing is a failure rather than a quieter pass. |
| `Tests/StoreSQLiteTests/SQLiteFileTests.swift` | Integration | The settings in force on the connection that commits, a second store refused, a read-only view taking no lease, every migration having a reverse, the cascade read back off the schema, a schema from the future and an edited migration refused by both the open and the report of what is pending, a file with no schema reported as every migration pending, the copy taken before an upgrade, a store the open invented saying so, a member key the file itself refuses, and amounts sorting by value. |
| `Tests/StoreSQLiteTests/DurableVolumeTests.swift` | Unit | The local volume recognised and allowed, every network filesystem refused, an unidentifiable one allowed rather than refused, and the mount table matched at a path boundary. |
| `Tests/StoreSQLiteTests/TargetShapeTests.swift` | Source | No chat client named anywhere, no route into a statement that is not a literal, no amount in a signed column, and no forced unwrap, try or cast. |
| `Tests/StoreSQLiteTests/SQLiteProbes.swift` | Fixture | A temporary directory removed whether the body passes or throws, a probe that writes rows the store's own writer refuses, and a probe that lets a handle go and opens the storage again. |
| `Tests/StoreSQLiteTests/RawSchema.swift` | Fixture | Reading and editing the file from outside the store, the way an operator with a command line would, which is also the claim about the file being readable by something that is not this project. |

## Requirement Coverage

### REQ-store-001, a save is on storage before it returns

- `SQLiteFileTests.swift`: "Every setting the durability promise rests on is in
  force on the connection that commits".
- `StoreConformance.Behaviour.aClaimIsOnTheStorageBeforeAPaymentIsAttempted`: a
  claim a save returned for, seen by a second view and after the handle is let
  go.

### REQ-store-002, the claim cannot be committed after the payment

- The compiler. `Connection.write` takes a synchronous body and a payment is
  `async`.
- `TargetShapeTests.swift`: "No statement in the SQLite target is built out of
  a string", which also asserts no second route into the connection.

### REQ-store-003, an unreadable row throws

- `anUnreadableEpochThrows`, `anUnreadableBudgetThrows`,
  `anUnreadableAccountThrows`, `anUnreadableStateThrows`,
  `anUnreadableBaselineThrows`.
- `anUnreadableAccountThrows` reads the corrupt row both ways a caller can:
  by address, and through the count the sweep guard takes.
- `SQLiteFileTests.swift`: "A member key that is not a key is refused by the
  file, not skipped by the reader", which is the same corruption done the way
  an operator with a command line would do it.

### REQ-store-004, amounts across the whole range

- `anAccountRoundTrips` at zero, one, the largest signed figure, one past it,
  and the largest unsigned figure.
- `amountsSortByValue`, which reads the order off the database rather than out
  of Swift.

### REQ-store-005, one account one member

- `oneAccountBelongsToOneMember`, including that the refused write leaves the
  stored figure alone and that re-proving your own account keeps it.

### REQ-store-006, nothing derived from a person

- `aKeyComesFromNothing`, including a member who is forgotten and returns.
- `theLedgerNamesNobodyAfterAForgetting`.

### REQ-store-007, a forgetting takes everything

- `forgettingTakesEverything`, `forgettingTwiceIsQuiet`,
  `everyMemberOwnedTableCascades`, `theLedgerDoesNotCascade`.

### REQ-store-008, one process one store

- `aSecondStoreIsRefused`, including that the lease is given back on close.

### REQ-store-009 and REQ-store-010, upgrading

- `aSchemaFromTheFutureIsRefused`, `anEditedMigrationIsRefused`,
  `aPendingMigrationCopiesFirst`, `everyMigrationHasAReverse`.

### REQ-store-011, spend only rises

- `reconciledSpendOnlyRises`, and `ReserveSpendReconciliationTests.swift` for
  the absurd range, the unnamed stream and the epoch still in flight.

### REQ-store-013, a store the open invented

- `SQLiteFileTests.swift`: "A store this open invented rather than found says
  so", over a first open, a second open, and a file deleted between them.

### REQ-store-014, identifiers compared by their bytes

- `identifiersAreComparedByTheirBytes`, over a pair differing after a NUL and a
  pair differing only in how the same characters are spelled.

### REQ-store-015, a value comes back as it was given

- `anEpochRoundTrips`, including a claim list holding the same value twice.
- `reserveStateRoundTrips`, including a state whose three maps name different
  streams and one naming a stream that has done nothing.

### REQ-store-012, the suite runs anywhere

- `InMemoryConformanceTests.swift` asserts the skipped set is exactly the
  durable behaviours, so "this store is not durable" is a statement the suite
  makes.

## Manual Testing

- [ ] Open a store, run a payout, and read the file with a command line
      `sqlite3` to confirm an operator can take it somewhere else (HOST-9).
- [ ] Put a store on a network mount and confirm the refusal names the
      filesystem, on a machine that has one.
- [ ] Start a second copy of a host against the same file and confirm it
      refuses by name rather than starting.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| An amount of the largest unsigned value | Round-trips, because the engine saturates to it on purpose |
| An epoch number of the largest unsigned value | Round-trips, and a reconciliation refuses to walk that far |
| An instant with a fraction of a second | Comes back rounded down, and the suite says so |
| An instant before 1970 | Rounds down, so a recorded instant is never later than the one that happened |
| Two commands admitting the same member at once | One member, one key, because the read that decides to mint is inside the transaction that inserts |
| A hundred accounts proved at once | All land, none overwrites another |
| A claim given back after a refusal | Leaves the stored rows, and the append path falls back to writing the lot |
| A claim list holding the same value twice | Comes back exactly as it was saved, because the rows are keyed by position rather than by value |
| A whole-number column holding text | Throws, rather than the zero the C interface answers with |
| A store file that is not there at open | Made, migrated, and reported as made, so a host can refuse to boot on it |
| A member forgotten mid-epoch, who returns | A new key, and the account and the holding still stop a second payment |
| A store opened twice in one process | Refused, because the lease is per open file description |
| A migration list with a gap | Applied in order; an unknown applied version stops the start |
| A database in memory | Takes no lease, copies nothing, and offers neither probe |
