---
module: store
version: 2
status: active
files:
  - Sources/Store/AccountRecord.swift
  - Sources/Store/BotStore.swift
  - Sources/Store/InMemoryStore.swift
  - Sources/Store/MemberDisclosure.swift
  - Sources/Store/MemberKey.swift
  - Sources/Store/MemberRecord.swift
  - Sources/Store/ReserveSpendReconciliation.swift
  - Sources/Store/RoleBaselineRecord.swift
  - Sources/Store/StoreDate.swift
  - Sources/Store/StoreError.swift
  - Sources/Store/StoreTable.swift
  - Sources/StoreSQLite/BaseUnits.swift
  - Sources/StoreSQLite/Connection.swift
  - Sources/StoreSQLite/DurableVolume.swift
  - Sources/StoreSQLite/InstanceLease.swift
  - Sources/StoreSQLite/Schema.swift
  - Sources/StoreSQLite/SchemaMigration.swift
  - Sources/StoreSQLite/SchemaMigrator.swift
  - Sources/StoreSQLite/SQL.swift
  - Sources/StoreSQLite/SQLiteStore.swift
  - Sources/StoreSQLite/SQLiteStore+Members.swift
  - Sources/StoreSQLite/SQLiteStore+Reserve.swift
  - Sources/StoreSQLite/SQLiteStoreError.swift
  - Sources/StoreSQLite/SQLValue.swift
  - Sources/StoreSQLite/Statement.swift
  - Sources/StoreTestKit/ConformanceDoubles.swift
  - Sources/StoreTestKit/ConformanceFixture.swift
  - Sources/StoreTestKit/InMemoryConformance.swift
  - Sources/StoreTestKit/StoreConformance.swift
  - Sources/StoreTestKit/StoreConformance+Durability.swift
  - Sources/StoreTestKit/StoreConformance+Members.swift
  - Sources/StoreTestKit/StoreConformance+Reserve.swift
  - Sources/StoreTestKit/StoreConformanceFailure.swift
  - Sources/StoreTestKit/StoreUnderTest.swift

db_tables: []
depends_on: ["reserve", "gating", "chain"]
---

# Store

## Purpose

Remember, between restarts, the smallest set of things after which somebody can
run this bot for their own community: who the members are, which accounts they
proved and what those accounts were last read as holding, the baseline that
stops a role sweep stripping a whole server, the payout ledger, and the day's
count of chain requests. Nothing else. What is deliberately absent is listed
under **What is missing** rather than half built.

Three targets, one contract.

- `Store` holds the records, the protocols a host writes against, and
  `InMemoryStore`, which is a real implementation rather than a stub. It
  declares no chat client, so a member is a `String` here and becomes a
  snowflake at an edge that depends on this rather than the other way round.
- `StoreTestKit` holds the conformance suite. Any backend proves itself by
  calling it, and the two that ship both do.
- `StoreSQLite` holds the durable backend, on the SQLite the operating system
  already ships. It adds no entry to `Package.resolved`, so the list of outside
  code somebody has to read before installing this is the same length it was
  (`TRUST-1`).

The promise the payout engine already made is the one this has to keep. A claim
is on storage **before** a payment is attempted, so a machine that stops in the
middle under-pays by one slot and leaves the value in the reserve, rather than
paying somebody the ledger has no record of. What makes that true here is set
out under **Invariants**, and every part of it is checked rather than asserted.

## Public API

Every exported symbol of the three targets, in source order. A name several
types share is described once, at its first declaration.

**Records.**

| Export | Description |
|--------|-------------|
| `MemberKey` | How one instance names a member to itself: a hundred and twenty eight fresh random bits, drawn on first contact, derived from nothing about the person. |
| `characterCount` | Characters in a key: thirty two. |
| `value` | The key itself, lowercase hexadecimal. Also `SQLValue`'s payloads read through their own cases. |
| `mint` | Draws a new key. Takes no argument, so nothing about a person can be fed into it. |
| `description` | The key as text. |
| `encode` | Writes the key as one string rather than an object wrapping one. |
| `MemberRecord` | The directory row: the key, the chat account id, and when the member first proved anything. The only place those two appear together. |
| `key` | The member's key. |
| `externalId` | Who the member is to the chat client, as a plain string. |
| `firstSeenAt` | When they first proved anything, recorded to the second. |
| `id` | The key, so a member can go in a keyed collection by identity. |
| `AccountRecord` | An account a member proved, and what it was last read as holding. |
| `memberKey` | Which member the account belongs to. |
| `address` | The account. Unique across the instance: one account, one member. |
| `provenAt` | When the member proved it. |
| `directBaseUnits` | The gated token held directly, in base units, as last read. |
| `liquidityBaseUnits` | The gated token inside this account's liquidity positions, as last read. |
| `balancesReadAt` | When the two figures were read, or nil when nobody has read them. Nil is not zero. |
| `balance` | The stored figures in the shape the ladder adds up. |
| `init` | Every record's initialiser rounds its instants down to the second, so a record made in code and a record read from a store are the same value. |
| `RoleBaselineRecord` | What the last role sweep that actually ran counted, which is the guard between a mistyped store path and every managed role coming off. |
| `recordedAt` | When that sweep ran. |
| `verifiedMemberCount` | Members with a proved account. Also the directory's own count. |
| `MemberDisclosure` | Everything one instance holds about one member, in the shape a person can be shown before deciding anything. |
| `retainedAfterForgetting` | What survives a forgetting, in sentences a member reads rather than table names. |
| `payoutLedgerSentence` | The one sentence every instance owes a member about the payment record, shared so two backends cannot come to disagree about it. |
| `ForgetOutcome` | What a forgetting did, by table, so it is a forgetting somebody can check. |
| `cleared` | Rows removed, by table. |
| `clearedRowCount` | Rows removed across every table. |
| `clearedTables` | Tables that gave something up, in a stable order. |
| `StoreTable` | The names a store reports rows under, shared so a forgetting reads the same whichever backend is running. |
| `members` | The directory table. |
| `accounts` | The accounts members proved. Also a member's own accounts, oldest first. |
| `roleBaseline` | The sweep guard's baseline. |
| `reserveState` | The reserve's own state. |
| `reserveEpochs` | One row per epoch per stream. |
| `reserveEpochCharges` | The ceilings each epoch was measured against, one row per charge. Named here with the others so a forgetting and an unreadable row report it the same way whichever backend is running. |
| `requestBudget` | The day's request count. |
| `StoreDate` | The precision every instant is written down at: whole seconds since 1970 UTC, as an integer, with no formatter anywhere near it. |
| `whole` | An instant rounded down to its second. Down rather than to nearest, so a recorded instant is never later than the one that happened. |
| `seconds` | Whole seconds since 1970 UTC, as the integer a column holds. |
| `date` | The instant an integer column holds. |
| `recorded` | A reserve state, an epoch record or a day's count as a store records it. |

**Protocols.**

| Export | Description |
|--------|-------------|
| `MemberDirectory` | Members, and the keys this instance drew for them. |
| `member` | The member behind a chat account id, or behind a key. Nil when this instance has never seen them. |
| `admitMember` | The member behind a chat account id, minting a key the first time. Idempotent. |
| `disclosure` | Everything held about a member, or nil when nothing is. |
| `forget` | Removes everything about a member, in one transaction. Forgetting somebody who is not there is quiet rather than an error. |
| `AccountStore` | The accounts members proved, and what they were last read as holding. |
| `account` | The account at an address, whoever proved it. |
| `prove` | Records a proved account. Refuses when a different member already proved it. |
| `recordBalances` | Writes what an account was just read as holding. |
| `unlink` | Removes one account, leaving the member and their others alone. |
| `balances` | A member's stored figures in the shape the ladder adds up, offered so nobody writes the one-line sum that demotes a member for linking an empty wallet. |
| `RoleBaselineStore` | The sweep guard's baseline. |
| `loadRoleBaseline` | What the last sweep that ran recorded, or nil before any has. |
| `save` | Writes the baseline, the reserve's state, or one epoch's record. |
| `BotStore` | Everything one instance keeps, composed from the concerns plus the two seams the engine declared. |
| `close` | Releases the storage, the handle and the lease that keeps a second process out. |

**The store in memory.**

| Export | Description |
|--------|-------------|
| `InMemoryStore` | The whole store in memory, as a real implementation. It keeps rows as encoded text and rounds instants exactly as a column would, so a test that passes here means what it says. |
| `epochKey` | The row key one epoch is kept under. |
| `loadState` | The reserve's state, or a fresh one when nothing was saved. |
| `loadEpoch` | One epoch's record, or a fresh unpaid one. |
| `loadBudgetUsage` | The last request count written, or nil when nothing ever was. |
| `saveBudgetUsage` | Writes the day's count. |
| `corruptEpoch` | Writes an epoch row verbatim, so a test can see what an unreadable one does. |
| `corruptBudget` | Writes the request count row verbatim. |
| `corruptAccount` | Writes an account row verbatim. |
| `corruptState` | Writes the reserve's state row verbatim. |
| `corruptBaseline` | Writes the sweep baseline row verbatim. |

**Putting recorded spend back in step.**

| Export | Description |
|--------|-------------|
| `ReserveSpendReconciliation` | Recomputes what a stream has spent from its epoch rows at boot, and raises the recorded figure to match. Upward only, because an over-count tightens the allocation ceiling and an under-count loosens it. |
| `epochWalkLimit` | The most epochs a stream is walked back over. Beyond it the state is wrong rather than long, and walking a truncated range is refused. |
| `reconciled` | The corrected state, having written nothing. |
| `reconcile` | Corrects and writes back, answering with the streams that moved. |

**Refusals.**

| Export | Description |
|--------|-------------|
| `StoreError` | What a store refuses. Every case names the thing to change, and none of them is a returned optional, because an optional invites a default and the default for "the row would not parse" pays everybody twice. |
| `errorDescription` | The refusal as a sentence a person reads. |
| `accountAlreadyProven` | Another member already proved this account. |
| `memberNotFound` | No member is on record under this key. |
| `unreadableRow` | A row exists and is not the value it should hold. |
| `contended` | Another process held the store and did not let go inside the wait. |
| `backendFailure` | The backend failed at something that should have worked. |
| `epochRangeTooLarge` | A reconciliation was asked to walk more epochs than any schedule has. |

**The conformance suite.**

| Export | Description |
|--------|-------------|
| `StoreConformance` | Every behaviour a store must have, run against a freshly made one. Any backend proves itself by calling it; a third backend is six lines. |
| `Factory` | Makes an empty store plus whatever probes it can offer, once per behaviour, because a store that only works on a clean file fails in week two. |
| `backend` | What to call this backend in a failure. |
| `Behaviour` | One named behaviour, so a failure says which one. |
| `needingCorruption` | Behaviours that need a way to write an unreadable row. |
| `needingDurability` | Behaviours that need a way to look at the storage from elsewhere. |
| `Outcome` | Whether a behaviour ran, or the honest reason it did not. |
| `ran` | The behaviour ran and the store had it. |
| `skipped` | The behaviour did not run, with a reason. A skip is a statement the suite makes rather than a silence. |
| `skipReason` | Why a behaviour did not run, or nil because it did. |
| `run` | Runs one behaviour against a store made for it, and closes that store before returning. |
| `runAll` | Runs every behaviour, answering with what each one did. |
| `aMemberRoundTrips` | A member written is the member read back, by key and by chat id, and admitting the same one twice is the same member. |
| `aKeyComesFromNothing` | Keys differ, carry nothing of the chat id, and a member who is forgotten and returns gets a new one. |
| `identifiersAreComparedByTheirBytes` | Two chat ids whose bytes differ are two members, whether they differ after a NUL or only in how the same characters are spelled. |
| `anAccountRoundTrips` | An account written is the account read back at zero, one, the largest signed figure, one past it, and the largest unsigned figure. |
| `oneAccountBelongsToOneMember` | A second member proving the same account is refused, and the refusal changes nothing. |
| `accountsComeBackOldestFirst` | A member's accounts come back in the order they were proved. |
| `storedBalancesStopADemotion` | Linking an empty second wallet does not drop a member's total, which is the morning the two stored halves exist for. |
| `unlinkingLeavesTheMember` | Unlinking one account leaves the member and their others alone. |
| `theSweepCountCountsMembers` | One member with three accounts is one member, and a member who proved nothing is not counted. |
| `anAbsentBaselineIsNil` | A store nobody has swept has no baseline, which is a first run. |
| `aBaselineRoundTrips` | A baseline written is the baseline read back, twice over. |
| `anAbsentReserveStateIsFresh` | A reserve nobody has run reads as a fresh one. |
| `reserveStateRoundTrips` | The state round-trips, including the saturated figures the engine produces on purpose. |
| `anAbsentEpochIsUnpaid` | An epoch nobody ran reads as unpaid, which is different from missing. |
| `anEpochRoundTrips` | An epoch's record round-trips, including the order its claims were made in. |
| `aReleasedClaimIsGone` | A claim given back really leaves the row. |
| `anEpochGainsACharge` | An epoch saved again with a further ceiling recorded against it reads back naming both, in the order they were charged, which is the case a run cut off under one ceiling and resumed under the next produces. |
| `anAbsentBudgetIsNil` | A day nobody counted reads as nil, and nil means never written. |
| `theBudgetRoundTrips` | The day's count round-trips, including a saturated one. |
| `instantsAreRecordedToTheSecond` | Every instant comes back rounded down to its second, everywhere. |
| `anUnreadableEpochThrows` | A corrupt epoch row throws rather than reading as an epoch nobody was paid for. |
| `anUnreadableBudgetThrows` | A corrupt count throws rather than handing the process a fresh budget. |
| `anUnreadableAccountThrows` | A corrupt account throws rather than reading as absent, both when it is read by address and when the sweep guard counts it. |
| `anUnreadableStateThrows` | A corrupt reserve state throws rather than reading as a reserve that has never paid, which would unclaim the period it paid in. |
| `anUnreadableBaselineThrows` | A corrupt baseline throws rather than reading as a first run, which is the one unreadable row with no second guard behind it. |
| `forgettingTakesEverything` | A forgetting takes the member and everything they owned, and nothing of anybody else's. |
| `forgettingTwiceIsQuiet` | Forgetting somebody already gone clears nothing and says so. |
| `theLedgerNamesNobodyAfterAForgetting` | The payout ledger still stops a resumed run paying a slot twice, and the name it kept leads nowhere. |
| `disclosureShowsEverything` | A member can be shown their row, their accounts, and what survives. |
| `concurrentWritesAllLand` | A hundred writes at once all land, and none overwrites another. |
| `reconciledSpendOnlyRises` | A recomputed spend raises an under-count and never lowers an over-count. |
| `aCutRunPaysNobodyTwice` | A payout cut at three different saves, resumed each time, pays no account and no holding twice. |
| `aCutRunPaysNobodyTwiceAcrossAReopen` | The same, with the handle let go and the storage opened again before the resume. |
| `aClaimIsOnTheStorageBeforeAPaymentIsAttempted` | A claim a save returned for is visible to a second view of the storage, and survives the handle being let go. |
| `StoreConformanceFailure` | A behaviour a store did not have, as a value rather than a call into a testing framework, so the suite builds anywhere with nothing but Foundation in the graph. |
| `behaviour` | Which behaviour failed. |
| `detail` | What was expected, and what was found. |
| `StoreUnderTest` | One freshly made store with whatever it can offer to prove things about itself. |
| `store` | The store the behaviours run against. |
| `corruption` | How to write a row no reader can parse, or nil when a backend cannot. |
| `durability` | How to look at the same storage from elsewhere, or nil. |
| `CorruptionProbe` | Writing a row the store's own reader refuses, so the most important rule in the package is executable rather than a comment. |
| `corruptReserveEpoch` | Leaves one epoch's row present and unparseable. |
| `corruptBudgetUsage` | Leaves the day's count present and unparseable. |
| `corruptReserveState` | Leaves the reserve's own state present and unparseable. |
| `corruptRoleBaseline` | Leaves the sweep baseline present and unparseable. |
| `DurabilityProbe` | Looking at the same storage from somewhere other than the handle that wrote to it. |
| `reopenAfterAbandoning` | Lets the handle go the way a stopped process does, then opens the same storage again. |
| `independentView` | A second view of the same storage while the first is still open, which is what catches a write pushed into a detached task. |
| `InMemoryCorruptionProbe` | How to corrupt a row of the store that keeps them in memory, so that store is held to the same rule the durable one is. |
| `inMemory` | The suite pointed at the store in memory, and the SQLite store that keeps its rows there. |

**SQLite.**

| Export | Description |
|--------|-------------|
| `SQL` | A statement, which can only ever be a literal written in the source. Its literal type is `StaticString` and there is no initialiser from a `String`, so an interpolated statement does not compile. |
| `text` | The literal, as text for the C interface. Also a text column's value. |
| `StringLiteralType` | `StaticString`. |
| `ExtendedGraphemeClusterLiteralType` | `StaticString`. |
| `UnicodeScalarLiteralType` | `StaticString`. |
| `SQLValue` | Everything that can be bound or read. There is no floating point case, so money cannot reach a `Double` through the store. |
| `null` | No value. |
| `integer` | A bounded count. Never an amount. |
| `blob` | Bytes. Amounts live here, eight of them. |
| `BaseUnits` | How an amount is written: eight bytes, most significant first, in a blob with a `CHECK` on the column. |
| `width` | Bytes in a stored amount: eight. |
| `bytes` | An amount as the bytes a column holds. |
| `amount` | The amount a column holds, or a refusal. Never zero on a bad read. |
| `SQLiteStore` | The store on the SQLite the operating system ships. One connection, every durability setting read back, an exclusive lease, and a write scope whose body is synchronous. |
| `open` | Opens a store on a file, migrating it first. The only way to get a writable store, so no caller holds one whose file is out of date. |
| `openInspector` | A second, read-only view taking no lease, for asking the file itself what it holds. |
| `pendingMigrations` | What a new build would change about a file, without changing it. |
| `migrationReport` | What the migration run at open did. |
| `MigrationReport` | Migrations applied, and where the copy taken first went. |
| `applied` | Migrations that were applied, named. |
| `backupPath` | Where the copy went, or nil because none ran. |
| `createdFile` | Whether there was no store at this path and the open made one. A host that expected a store to be there should refuse to boot on it: a volume that did not mount reads as a reserve that has never paid, and the report is otherwise identical to a genuine first boot. |
| `abandon` | Lets the file go without a tidy shutdown, the way a stopped process does. Nothing in a running bot calls it. |
| `revertEverySchemaStep` | Reverses every migration, for the test that proves each one has a reverse. Not a rollback for an operator. |
| `settingsInForce` | The durability settings as they actually are, read from the connection that does the committing. |
| `tableNames` | Every table the file holds. |
| `SQLiteStoreError` | What opening or using a SQLite store refuses. Every case names something an operator can act on. |
| `libraryNotThreadsafe` | The library on this machine was built without thread safety. |
| `libraryTooOld` | The library on this machine is older than this code is written against. |
| `cannotOpen` | The file could not be opened. |
| `settingRefused` | A setting the durability promise rests on is not in force, or the volume cannot keep it. |
| `alreadyHeldByAnotherProcess` | Another process is holding this store. |
| `schemaFromTheFuture` | The file holds migrations this build has never heard of. |
| `schemaDiverged` | A migration already applied is not the migration this build ships. |
| `backupFailed` | The copy taken before a migration failed, so the migration did not run. |
| `statementFailed` | A statement failed. |

## Invariants

1. **A save is on storage before it returns.** One connection, so every
   per-connection setting is in force on the connection that commits; write
   ahead logging with `synchronous = FULL` rather than the usually recommended
   `NORMAL`, which flushes at a checkpoint and can lose a commit that returned;
   `fullfsync`, because a flush on Darwin otherwise returns before the drive
   has the bytes; each of those read back at open with a refusal naming the
   setting, the value asked for and the value in force; and a volume that
   cannot be asked to flush refused outright. What none of it can detect is a
   disk that acknowledges a flush it did not perform. That is the honest limit
   and it belongs to whoever chooses the machine.
2. **A claim cannot be committed after a payment.** The write scope takes a
   **synchronous** body and a payment is `async`, so the wrong order does not
   typecheck. This is the one guard that is structural rather than
   disciplinary, and it is the reason the scope exists in this shape.
3. **A row that cannot be read throws.** Never a fresh record, never zero,
   never nil. A ledger row read as blank looks like an epoch nobody was paid
   for, and the next run pays every one of them again. `nil` means genuinely
   never written and nothing else. It covers the reserve's own state and the
   sweep baseline as well as the epoch, the count and the account, and it
   covers a whole-number column holding something that is not one, which the C
   interface answers zero for and reports nothing about.
4. **One account belongs to one member.** A second member proving it is
   refused, and the refusal leaves the stored figures untouched.
5. **Nothing below the chat boundary holds an identifier that came from a
   person.** The key is minted from a random number generator, and the
   directory row is the only thing that ever connected it to anybody. Deleting
   that row is the forgetting, and every surviving mention refers to nobody.
6. **A forgetting is one transaction, and the cascade is the mechanism.** Every
   table carrying a member key declares `ON DELETE CASCADE` to the directory, so
   a table added in two years is forgotten by the migration that creates it. A
   test reads the schema back and names any table that does not.
7. **An amount is never a signed integer column and never a `Double`.** Eight
   bytes, most significant first, with a `CHECK` on the column, because the
   payout engine saturates to the largest unsigned value on purpose and half of
   that range does not fit in what SQLite actually stores.
8. **Every instant is whole seconds since 1970 UTC, as an integer**, in both
   backends. No formatter, no locale, no platform difference, and two classes
   of future repair migration deleted before they exist.
9. **One process holds one store.** An exclusive lease on a sibling file, taken
   before the handle and long before anything could announce itself to a chat
   gateway. The gate that serialises payout runs is an actor and cannot see
   another process.
10. **A statement is a literal.** `SQL` takes a `StaticString` and has no
    initialiser from a `String`, so a value reaches a statement through a
    placeholder or not at all.
11. **A recomputed spend only ever rises.** An over-count tightens the
    allocation ceiling, which is safe; an under-count lets a later epoch spend
    past it.
12. **Nothing in these targets reads an environment variable.** The path
    arrives as a parameter, so a test cannot accidentally find an operator's
    live file (`BUILD-2.a`).
13. **An identifier is compared by its bytes, in both backends.** Swift
    compares strings by canonical equivalence and a text column compares them
    byte for byte, so two identifiers a chat client calls different have to
    stay two members whichever backend is running: one keyed by `String` would
    hand the second of a normalised pair the first one's member key, and with
    it the first one's wallets and rungs. Text crosses the C boundary with its
    length rather than to its first NUL, for the same reason.
14. **The charges an epoch carries are persisted in order, by every
    backend.** An epoch row written by a build from before they existed reads
    as an epoch charged to no period: that is not an exception to invariant 3,
    because a field absent from a record an older build encoded is not an
    unreadable row, and no period is ever invented for it from a timestamp.
    The JSON-backed store decodes a missing `charges` key as an empty list and
    only that key; the SQLite store keeps them in a table of their own and an
    epoch with no rows there has no charges (ADOPT-5, SPEND-9.c).
15. **The charges arrive as a new migration, and its reverse drops the whole
    table.** A shipped migration is fingerprinted and editing one refuses the
    start for everybody who already ran it, so a new fact is a new version. The
    reverse may not depend on dropping a column: the oldest SQLite this package
    admits at open is older than the release that learned to drop one, and the
    reverse is what an operator runs when an upgrade went wrong. A test reads
    the shipped migrations and fails on any reverse that reaches for one
    (RUN-9).
16. **An open that had to create the store says so.** SQLite makes a missing
    file and the migrations then run on it, so a volume that did not mount, a
    mistyped path and a deleted file all come back as a healthy store in which
    the reserve has never paid anybody and no period is claimed.
    `MigrationReport.createdFile` is the only thing that tells that apart from
    a genuine first boot. The store reports it; refusing to boot on it is the
    host's decision, because a first boot has to be able to happen.

## Behavioral Examples

### Scenario: a member links a second, empty wallet

- **Given** a member whose first account is stored as holding nine thousand
  directly and one thousand in pools
- **When** they prove a second account that holds nothing, and the totals are
  taken with the stored figures of the accounts already on record
- **Then** their combined total is ten thousand and their rungs are unchanged,
  rather than the zero the account that just signed would have given on its own

### Scenario: the machine stops in the middle of a payout

- **Given** an epoch of five recipients, and a store that stops answering at
  the third save
- **When** the run throws from inside the loop, the handle is let go, the
  storage is opened again and the same period is run a second time
- **Then** no account and no holding is paid twice, the epoch closes on the
  second run, and a third run in the same period is refused

### Scenario: a member asks to be forgotten after they were paid

- **Given** a member with two accounts, whose key is recorded in an epoch's
  ledger as already paid
- **When** they are forgotten
- **Then** the directory row and both accounts are gone, neither the key nor the
  chat id finds a member, and the ledger row is untouched, so a resumed run
  still skips the slot it already paid

### Scenario: an operator takes a newer build, then goes back to the old one

- **Given** a file a newer build has migrated
- **When** the older build opens it
- **Then** it refuses, names the migrations it does not know, and points at the
  copy the newer build took before changing anything, rather than reading a
  table that may have lost a column

### Scenario: a second instance is started against the same file

- **Given** a store already held by a running instance
- **When** a second one opens the same path
- **Then** it is refused by name before it opens a handle, and long before
  anything could take the running instance's chat session away from it

## Error Cases

| Condition | Result |
|-----------|--------|
| A different member already proved an account | `StoreError.accountAlreadyProven`, and nothing is written |
| An account is proved for a member who is not on record | `StoreError.memberNotFound` |
| A row exists and will not parse | `StoreError.unreadableRow`, never a fresh record |
| A reconciliation meets an epoch number beyond any schedule | `StoreError.epochRangeTooLarge`, rather than a truncated walk |
| The library is not threadsafe, or is older than this code | `SQLiteStoreError.libraryNotThreadsafe`, `SQLiteStoreError.libraryTooOld` |
| A durability setting did not take, or the volume cannot flush | `SQLiteStoreError.settingRefused`, naming the setting and both values |
| Another process holds the store | `SQLiteStoreError.alreadyHeldByAnotherProcess` |
| The file holds a migration this build does not know | `SQLiteStoreError.schemaFromTheFuture`, naming the versions |
| An applied migration's text does not match the one shipped | `SQLiteStoreError.schemaDiverged`, naming the version |
| An epoch row written before the charges existed | Read as an epoch charged to no period. Not an unreadable row, and no period inferred from `started_at`, which is the timestamp arithmetic the criterion abolishes and is wrong precisely for the boundary-crossing epoch |
| The copy before a migration cannot be taken | `SQLiteStoreError.backupFailed`, and the migration does not run |
| Forgetting somebody who is not on record | Not an error: nothing is cleared and the answer says so |
| A behaviour needs a probe a backend cannot supply | `StoreConformance.Outcome.skipped`, with the reason, rather than a pass |

## What is missing

Named here rather than half built, so nobody builds on something that is not
there (`BUILD-4`).

- **No cache of what an account holds.** No held asset ids, no collection
  membership, no pool positions. Role sweeps read the chain; previews, guest
  lists and the games all want this table and none of them exists yet.
- **No payments table.** The ledger records that an epoch paid a slot; it does
  not record a transaction reference per payment, and there is no typed row a
  weekly cap could be a `SUM` over.
- **No audit log, no claim offers, no scheduled tasks, no game rows, no saved
  timezones, no member display preference.** Each needs the surface that would
  read it, and none of that surface exists.
- **The two-commit window at the reserve seam is compensated, not closed.**
  `save(epoch:)` and `save(state:)` are two commits, and a crash between them
  under-counts spend.
  ``ReserveSpendReconciliation`` puts that right at boot, upward only. The real
  fix is a fifth seam method writing both rows in one transaction, which would
  delete the window rather than compensate for it. That is a protocol change
  with one implementation and no deployed rows, and it is cheaper now than it
  will ever be again.
- **No check anywhere has a network mount.** The volume refusal is written for
  both platforms and both are built and tested, but what is proved is that a
  local volume is recognised and allowed and that the decision refuses every
  filesystem named. The lookup itself is proved against a supplied mount table
  rather than a real one.
- **Durability is proved by letting a handle go, not by killing a process.** A
  second view of the storage cannot see an uncommitted write, so the probe does
  catch a write deferred into a task, which is the regression most likely to be
  introduced. What it does not exercise is a death inside a write call. That
  needs a small executable this package does not have yet.
- **A disclosure does not go and find the ledger rows that name a member.**
  `disclosure(memberKey:)` shows the directory row, the accounts and a sentence
  about what a payment record keeps. It does not enumerate which epochs
  actually name that member's wallets, so "everything held about a member" is a
  shorter list than it sounds. What the ledger keeps after a forgetting is the
  wallet paid and the ids of the things paid for; both are public objects on
  the chain, so both re-identify a forgotten member to anybody holding the
  file, and the sentence a member is shown says so rather than claiming
  otherwise.
- **Nothing in this package acts on `createdFile`.** The store reports that it
  invented the file; there is no host here yet to refuse to boot on it.
- **No read pool and no statement cache.** Both are performance features for a
  workload measured in thousands of rows, and both are where the awkward
  lifetime bugs live. One connection is also what makes the durability settings
  mean anything.

## Dependencies

- `Reserve`, for `ReserveStore`, `ReserveState` and `ReserveEpochRecord`. The
  seam is adopted exactly as written rather than redesigned.
- `Chain`, for `RequestBudgetStore` and `RequestBudgetUsage`, likewise.
- `Gating`, for `AccountBalance`, so the figures a store hands back are the
  ones the ladder already adds up rather than a second type for the same idea.
- `CSQLite`, a system library target wrapping the platform's own `libsqlite3`.
  Nothing is vendored and nothing is pinned.
- No chat client, in any of the three targets. Neither the manifest nor the
  source names one, and the edge that will know about snowflakes depends on
  this rather than the other way round, which SwiftPM enforces by refusing a
  cycle.

## Change Log

| Version | Change |
|---------|--------|
| 1 | The first store: members, the accounts they proved, the sweep baseline, the payout ledger and the day's request count, with a conformance suite two backends pass. Identifiers are compared by their bytes, an open that created the store says so, and the unreadable-row rule reaches the reserve's state and the sweep baseline as well. |
| 2 | An epoch's record carries the ceilings it was measured against, in the order they were charged, in a table of their own with the same cascade the claims rows use and a reverse that drops it whole. A row from the previous version reads as charged to no period rather than failing to load. |
| 2 | satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted: Satisfy four criteria the catalogue states and the code does not: which period a boundary-crossing payout was counted against, unpausing that cannot hand out a second day of budget, a per-caller share of the day, and a health answer that costs nothing |
