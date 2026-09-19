---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: testing
---

# Testing

Four criteria, four bodies of evidence. Each one is written here as the test
that protects it, what that test asserts, and the build it has to go red
against. The last of those three is the only one that is hard, and it is the
reason this section exists: three of these four criteria are things the code
nearly does already, so a test written to agree with today's behaviour would
pass on the day it was written and keep passing through the change that breaks
it.

Every test named here is offline, needs no key, no funded account and no chat
server, and takes its clock as a parameter. That is not a new rule for this
change: `ReserveRunner.run` already takes `now` and `periodKey` as parameters
(`Sources/Reserve/ReserveRunner.swift:148`), and `RequestGovernor` takes `now`
on every public method. Nothing added here may read a clock of its own, because
every figure in these suites is pinned and a test that reads the wall clock is
a test that fails on one machine in January.

Every new test name ends with the criterion id it protects, in the style the
suites already use: `"A reservation the day cannot cover spends nothing and
pauses nothing (SEE-9)"` at `Tests/ChainTests/RequestGovernorTests.swift:71`.

## What was verified before any of this was written

Each of the four was read in the code first. Two are genuinely absent, one is
true by accident and unprotected, and one is half built. Saying which is which
changes what the evidence has to be.

| Criterion | Verdict after reading the code |
|-----------|--------------------------------|
| SPEND-9.c | **Unmet.** `ReserveEpochRecord` carries `startedAt` and `completedAt` and nothing else (`Sources/Reserve/ReserveEpochRecord.swift:39` and `:42`). The period reaches `ReserveEpochOutcome.periodKey` (`Sources/Reserve/ReserveEpochOutcome.swift:69`), which is a return value nobody stores, and `ReserveState.lastPeriodKeys` (`Sources/Reserve/ReserveState.swift:33`) keeps one key per stream and overwrites it every epoch (`:121`). An operator looking at epoch 14 of 26 has two timestamps. |
| RUN-10.a | **Holds, and is partly protected.** `unpause(now:)` touches `pauseEndsAt`, `pauseCause` and `didAnnouncePause` and never the budget (`Sources/Chain/RequestGovernor.swift:170` to `:189`). `Tests/ChainTests/RequestGovernorTests.swift:208` already catches a full refill. It does not catch the refund a future author is most likely to write. See below. |
| RUN-11 | **Unmet, and nothing is near it.** No per-caller anything exists. `RequestGovernor` has one counter shared by every caller by design (`Sources/Chain/RequestGovernor.swift:3` to `:13`). The closest thing is the per-wallet cooldown in `WalletCheckCache` (`Sources/Chain/WalletCheckCache.swift:24`), whose own comment names this exact problem, "the caller is often a member typing in a channel and there is no upper bound on how fast people type" (`:9` to `:11`), and then keys the brake by wallet address rather than by caller. One member reading fifty different addresses is unbounded, and the cooldown covers nothing but wallet checks. |
| SEE-1.b | **Half built, and unprotected.** `ChainHealthReport` exists and is a pure value with a hand built `jsonBody` (`Sources/Chain/ChainHealth.swift:147` to `:199`), and `ProviderProofProbe` states in its own documentation that it deliberately does not go through the governor (`Sources/Chain/ProviderProofProbe.swift:22` to `:26`). So the pieces are mostly there. What is missing is the assembly point, the budget in the answer, and any test at all that puts a governor next to a health answer and asserts the counter did not move. The change brief says no health surface exists; that is true of the HTTP surface and not of the value. |

## SPEND-9.c: the period an epoch was charged to

### What the tests have to pin

The criterion is about a ceiling, not about a calendar: SPEND-9 is "A job long
enough to cross from one period into the next is still held to one period's
ceiling", and 9.a is that everything one job spends is counted against a single
period. So "which period" has two honest answers and they are different facts:

1. The cadence period the run was given, which is what stops one period paying
   twice (`ReserveRunner.execute`, `Sources/Reserve/ReserveRunner.swift:230`).
2. The period the paying account's ceiling belonged to, which is what the spend
   was actually counted against. That is `ReserveSpendLimits.periodKey`
   (`Sources/Reserve/ReserveSpendLimits.swift:31`), read once into a refusal
   message at `Sources/Reserve/ReservePlanner.swift:282` and then dropped.

They coincide for a host whose spending week is the cadence week, and they do
not have to: a host may cap by calendar month and pay weekly, and a host may
supply no limits at all, because `spendLimits()` is optional and the whole check
is skipped when it returns nil (`Sources/Reserve/ReserveRunner.swift:239`).
A record that keeps one string for both cannot tell an operator which of the two
it is looking at, so the tests below assert both, separately.

There is a third fact the tests have to force into the open. An epoch can be
charged to two periods. Guard 2 refuses a run whose period key equals the
stream's last **claimed** period, and the claim is written only when the loop
reaches the end (`Sources/Reserve/ReserveRunner.swift:299`). An epoch that died
half way through has claimed nothing, so a resumed run in the following week
passes guard 2 and charges the next week's ceiling with the rest of the list.
That is not a hypothetical: the store conformance suite already exercises a run
cut at an arbitrary save and resumed (`StoreConformance.Behaviour.aCutRunPaysNobodyTwice`,
`Sources/StoreTestKit/StoreConformance.swift`). A single field cannot answer
"which period" for that epoch without lying, and the case it lies about is
precisely the boundary crossing SPEND-9 is about.

`design.md` settles this as an **ordered, append-only list of charges**, one per
run that was measured against a ceiling, each naming the limits period key, the
whole units the run was checked for, and when the measurement was taken. The
ordinary epoch has exactly one. The cadence key is not copied onto the charge:
it stays in `ReserveState.lastPeriodKeys` and the runner's parameter is renamed
to say cadence, so the two senses of "period" stop sharing a word. The evidence
below is written to that design.

Two consequences follow that the tests have to state rather than hide, because
each is a place the criterion is answered only partly:

- **A host that states no limits produces no charge**, since nothing was
  measured. SPEND-9.c is then unanswerable for that host, and the honest test
  asserts the absence rather than inventing a period from the cadence key. Worth
  reading twice before approving: `spendLimits()` returning nil is a supported
  host (`Sources/Reserve/ReserveRunner.swift:239`), and for that host this change
  delivers nothing.
- **The charge records what the run was checked for, not what it paid.** Those
  differ whenever a payment fails, and the difference is deliberate: the ceiling
  was measured against the planned figure, so the planned figure is what the
  period was charged. A test asserts they can differ, or somebody will later
  "fix" the record to report the paid amount and quietly change what the number
  means.

### Where the evidence goes

| Test file | Test | What it asserts |
|-----------|------|-----------------|
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "A finished epoch names the period it was charged to (SPEND-9.c)" | After a clean run at cadence `2026-W38` with limits dated the same week, the record reloaded from the store carries exactly one charge, naming that period and the whole-unit figure the planner checked. |
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "An epoch resumed in the next period names both, in order (SPEND-9.c, SPEND-9.a)" | A payer that throws part way through, then a second run of the same epoch whose limits are dated `2026-W39`: two charges, in run order, the first naming W38 and the second W39. |
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "A ceiling from a different calendar is recorded as itself, not as the cadence" | Cadence `2026-W38`, limits `periodKey` `2026-09`: the charge says `2026-09`. The one test that catches an implementation which reaches for the parameter already in scope. |
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "A host that states no ceiling is charged no period (SPEND-9.c)" | A payer whose `spendLimits()` is nil: the run succeeds and the record carries no charge. Nothing is invented from the cadence key. |
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "The charge is what the run was measured for, not what it managed to pay" | An epoch where two payments fail: the charge keeps the planned figure and `paidBaseUnits` is lower. The two numbers are allowed to disagree and the test says which is which. |
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "The charge is on disk before the first payment is attempted (SPEND-9.c)" | A store that records its save order, in the shape of the existing test at `:260`: the charge write lands before the first `pay`. A charge written after the loop is a charge the crash loses, and the crash is when somebody goes looking. |
| `Tests/ReserveTests/ReserveRunnerTests.swift` | "A rehearsal charges no period at all (RESERVE-7.a)" | `rehearse` leaves the store untouched, so the record it would have written has no charge. The existing rehearsal tests at `:523` and `:561` already assert nothing is written; this one asserts the new field did not become the exception. |
| `Tests/ReserveTests/ReserveStoreTests.swift` | "A record written before the period was recorded reads as a period nobody wrote down (SPEND-9.c)" | `InMemoryReserveStore.setRaw` with a JSON row in the shape this build shipped before the change: `loadEpoch` answers a record with no charges, and does not throw. |
| `Sources/StoreTestKit/StoreConformance+Reserve.swift` | `anEpochRoundTrips`, extended | The fixture at `:142` gains charges, so every backend is asserted to return them, in order, by whole-record equality. |
| `Sources/StoreTestKit/StoreConformance+Reserve.swift` | a new behaviour, `anEpochGainsAChargeOnASecondSave` | Save an epoch with one charge, save the same epoch again with two, reload: two. |
| `Tests/StoreSQLiteTests/SQLiteFileTests.swift` | "A file from the build before this one keeps its epochs and gains the period" | Open, take the file back to the previous schema version by hand and hand-write an epoch row, reopen: the pending migration applied, a copy was taken, the old epoch still loads with no charges, and a fresh run records one. |

### What each one must fail against

- **Today's `main`.** Every test above is red at `base_commit`, because
  `ReserveEpochRecord` has no such field. That is the cheapest check that the
  evidence is about the change and not about something already true.
- **A field written only into `ReserveEpochOutcome`.** The outcome already
  carries `periodKey` (`Sources/Reserve/ReserveEpochOutcome.swift:69`) and it is
  a return value. Every assertion above reloads the record **from the store**
  rather than reading the outcome, so an implementation that satisfies the
  criterion in the return value and not on disk stays red.
- **First-writer-wins on a single field.** Passes test 1, fails test 2: the
  resumed half of the epoch is charged to a week the record denies.
- **Last-writer-wins on a single field.** The mirror image, and the more likely
  one, because a plain UPSERT column does this by default.
- **A set rather than a list.** Passes the two-period test's membership check
  and fails its order, which is why test 2 asserts the order rather than the
  membership.
- **The cadence key written where the ceiling's key belongs.** The runner has
  the cadence key in scope at the moment it writes the charge, and for most
  hosts the two strings are identical, so this mistake is invisible in every
  test but the third. It is the test somebody deletes as redundant.
- **A charge written after the payment loop** rather than before the first
  payment. Passes every test that only reloads the record at the end, and loses
  the charge in exactly the crash the record exists for. The save-order test is
  the only one that sees it.
- **A non-optional field on a `Codable` struct.** This is the migration story
  and it is worth being blunt about. `ReserveCoding.decode` throws rather than
  reading an unparseable row as empty, on purpose, and the reason is written at
  `Sources/Reserve/ReserveCoding.swift:33` to `:42`: a ledger row read as blank
  is an epoch nobody was paid for and the next run pays all of it again. A
  required new key turns every epoch row written by the previous build into a
  throw, which by that rule stops the payout of an instance in the middle of a
  twenty six week schedule. The store test above is what makes that a red test
  rather than an outage.
- **A SQLite `save` that writes the new rows on insert and not on update.** The
  epoch UPSERT at `Sources/StoreSQLite/SQLiteStore+Reserve.swift:173` to `:189`
  lists its columns twice, once in `VALUES` and once in `DO UPDATE SET`, and the
  second list is the one people forget. The charge of the ordinary epoch is
  written on the first save and never changes, so the omission is invisible
  until an epoch is resumed. `anEpochGainsAChargeOnASecondSave` is the test that
  sees it.
- **An edit to migration 2 rather than a migration 3.** `SchemaMigration.checksum`
  fingerprints the migration's own text (`Sources/StoreSQLite/SchemaMigration.swift:40`
  to `:49`), so editing the shipped migration makes every existing file refuse to
  open with `schemaDiverged`. The whole SQLite suite goes red at `open`, which is
  the correct outcome and worth knowing is the outcome.

### Cases somebody would forget

- **`StoreDate.recorded(_:)` for the record** (`Sources/Store/StoreDate.swift:79`)
  copies the value and adjusts `startedAt` and `completedAt`. The charge carries
  an instant of its own, and it has to be rounded down there too, or the
  in-memory store and the file disagree by fractions of a second and
  `instantsAreRecordedToTheSecond` goes red for a reason nobody expects. This is
  the most likely single omission in the whole change: the field is one line
  away from the two that are handled and it is in a file nobody is thinking
  about.
- **The write memo.** The SQLite store remembers what it last wrote for an epoch
  so that thousands of saves inside one epoch cost one write between them
  (`Sources/StoreSQLite/SQLiteStore+Reserve.swift:163` and `:245`). A charge memo
  that is never invalidated suppresses the **second** charge of a resumed epoch,
  which is the exact row the criterion is about, and it does so only on the
  resume path, which no ordinary test walks. The memo is keyed per handle, so
  the resumed run in a fresh process writes correctly and the bug appears only
  when the same process runs the epoch twice: a test has to resume in the same
  process to see it.
- **`claimingAll`.** The rehearsal folds the whole epoch in one pass
  (`Sources/Reserve/ReserveEpochRecord.swift:116`). It must not gain a charge,
  because a rehearsal charges nothing, and the finished shape it reports should
  still match what a real run would write in every other respect.
- **An epoch with nobody to pay.** `design.md` says a plan with no entries still
  produces a charge. Reading `planGuardedEpoch` (`Sources/Reserve/ReservePlanner.swift:251`
  to `:255`), an empty plan throws `nothingToPay` before the limits check is ever
  reached, so no such run gets as far as writing one. Either the design means
  something narrower or one of the two is wrong, and a test that asserts the
  refusal is unchanged is how that gets settled rather than discovered.
- **A new `Schema.ClaimKind` case instead of a new table or column.** This is the
  trap. The kind is an integer in an existing column, so adding a case needs no
  DDL, which means no version bump, which means the downgrade refusal never
  fires: an older build opening the file passes `refuseAFileThisBuildCannotRead`
  (`Sources/StoreSQLite/SchemaMigrator.swift:45`) and then throws
  `unreadableRow` from inside `loadEpoch` (`Sources/StoreSQLite/SQLiteStore+Reserve.swift:135`
  to `:140`) at the moment somebody runs a payout. The documented promise is a
  refusal at open, naming the backup (`specs/store/store.spec.md`, "an operator
  takes a newer build, then goes back to the old one"). Whatever shape the
  storage takes, it arrives with a migration so the version moves.
- **Reversibility.** `Tests/StoreSQLiteTests/SQLiteFileTests.swift:76` applies
  every migration and reverses every one, and asserts nothing is left. A
  migration 3 with a `down` that drops nothing turns that test red, which is
  what it is for.
- **The rename.** `design.md` renames the runner's `periodKey` parameter and
  `ReserveEpochOutcome.periodKey` to say cadence. Every one of the forty or so
  call sites in `Tests/ReserveTests/ReserveRunnerTests.swift` moves with it, and
  a mechanical rename across a money path is worth one reviewer reading the diff
  for a site where the wrong string was passed rather than the label changed.

## RUN-10.a: unpausing hands back no budget

### The honest position

This one is a test, and it is a test that already half exists.
`unpauseDoesNotRefillTheBudget` (`Tests/ChainTests/RequestGovernorTests.swift:208`)
sets a limit of one, spends it, pauses, unpauses, and asserts the next request
still throws `requestBudgetSpent`. That already fails against the naive break,
which is an `unpause` that assigns a fresh `DailyRequestBudget`.

What it does not catch is the change a future author would actually make. The
pause it exercises came from spending the budget, so the breaker and the counter
say the same thing and any refund is visible. The refusal RUN-10.a is written
for is the other one: a provider quota error that turned out to be wrong
(`recordRequestFailure`, `Sources/Chain/RequestGovernor.swift:147`). An author
making unpause "more useful" writes the refund for that case, keyed on
`pauseCause == .providerRefusedQuota`, reasoning that requests refused by a
provider that was wrong were never really spent. Every existing test passes:
`unpauseLetsWorkResume` at `:196` uses `limit: 0`, where there is no budget to
give back, and `unpauseDoesNotRefillTheBudget` at `:208` pauses the other way.

### Where the evidence goes

All of it in `Tests/ChainTests/RequestGovernorTests.swift`, under the existing
"Lifting a pause by hand" mark at `:194`.

| Test | What it asserts |
|------|-----------------|
| "Lifting a pause leaves every figure of the day exactly where it was (RUN-10.a)" | Limit 10, four requests spent, breaker tripped by a provider quota refusal at a pinned noon. `snapshot(now:)` is captured before and after the unpause and the two are equal in `usedRequests`, `remainingRequests`, `limit` and `dayStart`, and `remainingRequests(now:)` still answers six. Then six more are taken and the seventh throws. |
| "Lifting the same pause over and over is still one day's budget (RUN-10.a)" | Fifty `unpause` calls in a row, at the same pinned instant, move nothing. The criterion says "anybody who works that out", which is a loop. |
| "Lifting a pause does not rewrite the count on disk (RUN-10.a, RUN-8.b)" | With an in-memory `RequestBudgetStore`, unpause, `flushPersistence()`, and the stored `RequestBudgetUsage` is unchanged. Then a second governor over the same store, `restoreFromStore`, and it starts with four spent. |
| "Lifting nothing is still not a refund (RUN-10.a)" | The early-return branch at `Sources/Chain/RequestGovernor.swift:171` to `:176` also clears state and returns false. Four spent, nothing paused, unpause, four still spent. |
| "Lifting a pause returns no caller's share either (RUN-10.a, RUN-11)" | Added once the share below exists. A caller at their limit is still at their limit after an unpause. The share lives in the same actor, and the natural shape of a generous unpause is one that clears everything it can see. |

### What it must fail against

- An `unpause` that assigns a fresh `DailyRequestBudget`. Already covered; the
  new test keeps covering it.
- An `unpause` that refunds only when `pauseCause == .providerRefusedQuota`.
  **Nothing in the suite catches this today.** The first test above is written
  around that mutation specifically: the pause it trips is the provider one, and
  the counter it checks is partially spent rather than exhausted, so a refund of
  any size is visible.
- An `unpause` that rolls the day forward, whether by touching `dayStart` or by
  calling `restore` with tomorrow. Caught by asserting `dayStart` across the
  unpause rather than only the remaining count.
- An `unpause` that writes a zeroed count to the store, which would survive the
  process and hand the next restart a fresh day. This is the mutation that does
  the most damage and the only one the third test sees.
- An `unpause` that clears the announced thresholds, so the 50, 75 and 90 percent
  notices arrive twice in one day. Not a budget refund and not what the criterion
  is about, so it is an assertion on the notice buffer rather than a test of its
  own, and it may reasonably be left out.

### The case somebody would forget

**An unpause after the UTC day has rolled must show a zero, and that zero is
correct.** Pause at 23:50 with four spent, unpause at 00:05 the next day, and
`usedRequests` is zero because `rollDayIfNeeded` reset it
(`Sources/Chain/DailyRequestBudget.swift:190` to `:196`), not because the
unpause refunded anything. A test written as "used is unchanged across an
unpause" without pinning the instant fails here for the right reason and gets
"fixed" by weakening it. Both halves go in: same-day keeps four, next-day reads
zero, and the test name says which is which.

## RUN-11: one caller's share of the day

### What is being decided, and why it is the riskiest part of this change

Nothing implements this, so the tests below are written against the design, and
if the design moves the tests move with it. What `design.md` settles:

- **The unit is a caller, in two cases**: work on behalf of a member, carrying
  an opaque identifier, and the instance's own work, carrying a job name. Only
  the first is rationed, and the parameter has no default. That is the right
  call and worth restating because the cost is visible and the benefit is not:
  defaulting either way is silent. Default to a member and the sweep is
  throttled the day this lands; default to the instance and the next
  member-facing command written is unlimited.
- **The identifier is opaque to this layer.** `Chain` cannot name a member
  anyway, since `Store` depends on `Chain` and not the other way round, and
  nothing below the chat boundary holds an identifier that came from a person
  (`AGENTS.md`, "Rules that bite"). The guarantee rests on the host passing an id
  its own store minted, because an id a caller can choose is an allowance a
  caller can refresh. That is documentation, not something this layer can check,
  so it is a line in the spec and a case in the docs rather than a test.
- **A share of the day's budget as a percentage, plus a burst**, defaulting to
  5 percent and 10 requests, refilling over the UTC day, held in memory. With no
  day budget set there is no share at all.
- **Reaching the share refuses that caller and nobody else.** The module's stated
  position is that it refuses rather than queues
  (`Sources/Chain/RequestGovernor.swift:11` to `:13`), and `ReserveRunner` says
  the same about its gate at `Sources/Reserve/ReserveRunner.swift:154`.

Two of those deserve an argument on the record before the code exists.

**A percentage plus a burst, rather than a flat count per day.** The burst half
is right for the reason `design.md` gives: "however fast they type" is a rate
problem, and a pure daily quota lets a member empty their share in ten seconds
and then reads to them as the bot being broken for the rest of the day. The
percentage half is the weaker half. Five percent of a day's budget is a
different promise on a free tier and on a paid one, which is the point, and it
is also five percent of a number the operator may have set to something very
large, in which case one member can still cause tens of thousands of reads and
RUN-11 is satisfied on paper. A percentage with an absolute ceiling would close
that, at the cost of a third variable.

**No share when no day budget is set.** Defensible, since the criterion names
the day's budget and an unset budget is no budget. The residual is worth saying
out loud rather than discovering: the default configuration of this package has
no day budget (`dailyRequestBudget` defaults to 0), so out of the box one member
is bounded only by the per-second limiter, which is a process-wide brake and not
a per-caller one. An operator who reads RUN-11 in the catalogue and sets nothing
is not protected by it. That belongs in the documentation as a sentence, and it
is a reasonable thing for a reviewer to reverse.

### Where the evidence goes

A new file, `Tests/ChainTests/CallerShareTests.swift`, suite "One caller's share
of the day", plus two rows in `Tests/ChainTests/ChainConfigurationTests.swift`.

Every one of these cites **RUN-11** and nothing finer. `docs.md` drafts two
sub-criteria, RUN-11.a and RUN-11.b, for the conversation that would add them;
until that conversation happens and `hi check` has run, neither id exists, and
a test naming an id the catalogue does not have is a citation nobody can
follow.

| Test | What it asserts |
|------|-----------------|
| "One caller cannot spend the day on their own (RUN-11)" | A day budget and a share sized so the burst is small: one caller exhausts their burst and the next request throws the share refusal, at a pinned instant so nothing has refilled. The day's counter shows what they took and not one more: a refusal costs nothing. |
| "One caller at their share leaves everybody else working (RUN-11)" | After the caller above is refused, a second caller's request succeeds and the instance's own work succeeds, at the same instant. |
| "Reaching a share is not a pause (RUN-11)" | `pausedUntil(now:)` is nil after the refusal, `snapshot(now:)` reports no pause reason, and no notice was recorded. A share refusal must not look like the instance stopping, because `snapshot` is what an operator reads to find out whether it has. |
| "The instance's own work has no share (RUN-11)" | A sweep sized run of a hundred requests naming a job rather than a member: every one allowed, bounded only by the day's budget. |
| "A share refills, so a member is not locked out for the day (RUN-11)" | Refused at a pinned instant, allowed again after enough of the day has passed for one request to refill. The whole argument for a rate over a quota is this test. |
| "A share refills to its burst and no further (RUN-11)" | An idle caller who has not asked anything for most of the day holds the burst, not the whole day's share, in the same way `TokenBucket` caps capacity at the rate (`Sources/Chain/TokenBucket.swift:18` to `:23`). Otherwise the quiet member is the one who can empty the budget. |
| "A caller refused is not a caller barred (RUN-11)" | Ten refused attempts in a row cost nothing, and the caller is allowed again at the same moment they would have been after none. |
| "Work that cannot be half done is refused whole against a share (RUN-11, SEE-9)" | An all-or-nothing reservation larger than what a caller has left takes nothing from the caller and nothing from the day, and is not a pause. The same shape as `requestBudgetCannotCover` at `Sources/Chain/RequestGovernor.swift:249`. |
| "With no day budget there is no share, and the documentation says so (RUN-11)" | Limit 0: a caller is never refused by a share. Asserting the documented hole is what stops somebody later reading its absence as a bug and closing it by accident in a way that throttles an instance nobody meant to throttle. |
| "A restart hands back at most one burst (RUN-11, RUN-8.b)" | The allowance is in memory, so a fresh governor gives a caller a fresh burst while the day's own count is restored from the store. Bounded, deliberate, and the test names the bound rather than leaving somebody to find it. |
| `ChainConfigurationTests` | "With only the required variables set, the caller share takes its documented defaults" and "A share above a hundred percent refuses at boot, naming the variable" | The defaults are asserted as literals, the way `healthProbe == 30` is asserted at `Tests/ChainTests/ChainConfigurationTests.swift:199`, so changing one is a deliberate edit to a test rather than a silent drift. |

### What it must fail against

- **No share at all**, which is today's `main`. Every test is red at
  `base_commit`.
- **A share that pauses the process.** The easiest wrong implementation is to
  reuse `pause(...)` because it is right there, and it turns one impatient member
  into an outage for the whole server. Two tests see it: the second and the
  third.
- **One counter shared by every caller**, which is the accidental
  implementation when the caller token is dropped somewhere in the middle. Test
  two goes red.
- **A share applied to the instance's own work.** Test four is the only thing
  standing between this change and a role sweep that stops after a handful of
  accounts.
- **A quota rather than a refilling allowance**, which passes the first four
  tests and fails the refill test, and which a member experiences as the bot
  being broken until tomorrow.
- **An allowance that banks the whole day while a caller is idle**, which is the
  default behaviour of a bucket whose capacity is not capped, and which hands
  the quietest member the largest burst. The refill-cap test is the only one
  that sees it, and it is the same mistake `TokenBucket` already documents
  having avoided.
- **A refusal that consumes budget**, which would let a member bar themselves for
  the day by holding down a key, and would also let them spend the shared day's
  budget through refusals alone. Tests one and seven see it.

### Cases somebody would forget

- **The batched path.** `BatchedChainReader` reads through `ChainReader`
  (`Sources/Chain/BatchedChainReader.swift:19`), so whatever carries the caller
  has to survive that hop, and the pool reserve read at `:42` to `:50` spends two
  requests without going through the single wallet path. A caller-attributed read
  that loses its attribution in the batch is a hole shaped exactly like the
  feature.
- **A caller nobody can name.** A member who has not proved a wallet has no
  member key, so a command that reads the chain on their behalf during
  verification has no id to pass. This is unresolved and is named in the open
  questions at the end.
- **The cap on tracked callers.** An allowance per caller is a map bounded by
  the number of distinct callers seen, which is bounded by the membership, which
  is not bounded. Whatever the eviction rule is, the behaviour at the cap is a
  decision and not an accident: refusing a new caller because ten thousand
  others were busy is worse than the problem, and evicting the least recently
  seen is only safe because the id was minted by the instance and cannot be
  churned from outside. A test asserts that an idle caller being forgotten gives
  them a burst and not a day.
- **What the member is told.** The refusal reaches a person, so it has to name
  when the share comes back, in the same way `requestBudgetSpent` names its
  `until`. A test that only asserts "it threw" lets a bare error reach a member
  who then asks the operator whether the bot is broken.

## SEE-1.b: a health answer that costs nothing

### What Chain must expose, and where the boundary falls

This criterion is shared with the runtime change that is being defined at the
same time, and the failure mode is that both assume the other builds it. So the
split is stated as a rule, and each side's tests are named.

**`Chain` owns, and this change builds:**

- The value: `ChainHealthReport` already exists at `Sources/Chain/ChainHealth.swift:147`.
- An assembler that takes the components the host knows about, a
  `RequestBudgetSnapshot` and an optional `ProviderProof`, and answers a report.
  Pure, synchronous, no network, no governor.
- The budget in `jsonBody`, so the string a monitoring check greps for is built
  in one place and pinned by an offline test. Hand building that JSON in the
  runtime would put the shape somewhere no test can see it.
- The guarantee, in the spec and in a test, that nothing on that path reserves a
  request or touches an `AccountDataSource`.

**The runtime change owns, and this change must not build:**

- The listener, the port, the binding order, and the mapping from
  `ChainHealthStatus` to an HTTP status code.
- Which components exist for a running instance and who sets them reached.
- When the proof probe is refreshed, and who holds the one `ProviderProofProbe`.
- A test that its endpoint reaches the assembler and nothing else, and a test
  that the endpoint still answers once the day's budget is spent. That change's
  REQ-runtime-017 and REQ-runtime-032 name both, so the endpoint half of
  SEE-1.b is somebody's rather than nobody's.

**Neither builds:** the probe's own network call. It already exists
(`Sources/Chain/ProviderProofProbe.swift:107` onward) and is deliberately outside
the governor (`:22` to `:26`).

One decision inside that split is worth disagreeing with now. A spent budget or
a live pause is reported as a **field** in the answer and does not make the
status anything other than `ok`. An instance whose day's budget is gone is still
connected, still holding its lease and still answering; turning that into a
failing health check would let a deployment gate replace a working instance over
a quota, which is the failure RUN-3 exists to prevent and which
`ChainHealthReport`'s own documentation already argues about for the bound
socket case (`Sources/Chain/ChainHealth.swift:134` to `:146`). The operator still
learns it, because the number is in the body.

### Where the evidence goes

`Tests/ChainTests/ChainHealthTests.swift`, under a new mark.

| Test | What it asserts |
|------|-----------------|
| "Assembling a health answer spends nothing from the day (SEE-1.b)" | `snapshot(now:)` before and after assembling, equal in every field, against a governor with a real limit and some of it already spent. A stub `AccountDataSource` with a call log asserts zero calls. |
| "A health answer still comes back when the budget is gone (SEE-1.b)" | Budget exhausted, breaker tripped, then assemble: a report, not a throw, whose status is still `ok` when the components are reached, and whose body names the pause and when it ends. |
| "The proof probe is not one of the day's requests (SEE-1.b)" | A `ProviderProofProbe` with a stub probe and a governor beside it: `proof(now:)` runs, the probe's call log shows one call, and the governor's counter has not moved. |
| "An unset budget does not read as nothing left (SEE-1.b, SEE-9)" | With `limit == 0`, the body says there is no budget rather than printing a remaining of zero. `RequestBudgetSnapshot.remainingRequests` is documented as zero when no budget is set (`Sources/Chain/RequestBudgetSnapshot.swift:19` to `:21`), and `hasBudget` is the field that tells them apart. |
| "Monitoring on a timer is one probe, not one per check (SEE-1.b)" | Two assemblies inside the probe lifetime make one probe call. `probeIsCachedForItsLifetime` at `Tests/ChainTests/ChainHealthTests.swift:105` proves it of the probe; this proves it of the thing the runtime will actually call. |
| "A probe that failed still produces an answer (SEE-1.b, SEE-10.a)" | The probe throws, the report is still assembled, there is no provider section, and the failure is readable rather than invented. Builds on `failedProbeInventsNothing` at `:73`. |

### What it must fail against

- **An assembler that reaches `ChainReader`.** The obvious way to answer "is the
  node reachable" is to read something, and every read goes through
  `governor.reserveRequest()` at `Sources/Chain/ChainReader.swift:198`. The
  before-and-after snapshot is the assertion that sees it, and the zero-call data
  source log is the one that says why.
- **A probe wired through the governor.** A tidying pass that routes every
  outbound request through one place would do this, and it is defensible right up
  to the moment the budget runs out and the health check goes dark at exactly the
  moment somebody is looking at it. Test three is the guard, and the comment at
  `Sources/Chain/ProviderProofProbe.swift:22` is the reason.
- **A health answer that throws, or reports `starting`, when the budget is gone.**
  Test two.
- **A body that prints `"remaining":0` for an instance with no budget set.** Test
  four. Somebody's monitoring will alert on that string.

### Cases somebody would forget

- **Escaping.** The body is hand built (`Sources/Chain/ChainHealth.swift:186`)
  and already escapes provider headers. New fields are numbers and fixed keys, so
  there is nothing new to escape, and the test that proves the existing escaping
  still happens with the new fields present is one line and worth having:
  `proofIsEscapedIntoTheBody` at `:62` must keep passing with a budget section in
  the body.
- **Key order.** The body is hand built rather than encoded precisely because an
  encoder may reorder between releases (`:181` to `:185`). The new fields go in a
  fixed position and the test asserts the whole string, not a substring.
- **An instance that has no probe configured.** `proofHeaderNames` empty means
  never probe at all (`Sources/Chain/ProviderProofProbe.swift:44` to `:46`), so
  the assembler has to accept nil proof without inventing a section. Covered by
  `noConfiguredHeadersMeansNoProbe` at `Tests/ChainTests/ChainHealthTests.swift:120`
  for the probe, and needs one assertion at the assembler.

## The shared conformance suite

Two of these criteria change what a store has to do, and the store proves itself
through one suite run against every backend
(`Sources/StoreTestKit/StoreConformance.swift`). That means:

- A new `Behaviour` case is added for each new store behaviour, and every
  backend runs it: the in-memory store
  (`Tests/StoreTests/InMemoryConformanceTests.swift`) and both SQLite
  configurations (`Tests/StoreSQLiteTests/SQLiteConformanceTests.swift`). Three
  runs, not one.
- `anEpochRoundTrips` asserts whole-record equality
  (`Sources/StoreTestKit/StoreConformance+Reserve.swift:142` onward), so adding
  a field to the fixture is what makes a backend that silently drops it go red.
  **The fixture must set the field to something non-nil**, or a store that always
  reads nil passes.
- The README and `AGENTS.md` quote a test count. Adding behaviours changes it by
  three per behaviour, not one, and the README already explains why
  (`README.md`, the State section).

## What this change does not test

- **The HTTP health endpoint.** There is no executable and no listener, and
  building one here would be the runtime change. This change proves the answer
  can be assembled for nothing; the runtime change proves the endpoint serves it.
  Its definition has to name that test, or SEE-1.b ends up proved by neither.
- **The host wiring that decides which caller a command belongs to.** `Chain`
  proves a share is enforced when a caller is named. Naming the caller is the
  host's, and the only thing this change can do about it is refuse to provide a
  default that hides the question.
- **Anything against a real node or a real chat server.** Unchanged, and
  deliberately so: `Tests/ChainTests/ChainFixtures.swift` is the only way into
  the chain from the suite and it cannot reach a network.

## Manual testing

There is nothing to run. No executable target exists (`Package.swift` declares
six libraries and no binary), so the usual checklist of "point it at a node and
watch" cannot be written honestly yet. What can be done by hand:

- [ ] Open a store file written by the previous build with `sqlite3`, run the
      new build against it, and confirm the schema version moved, a copy was
      taken beside the file, and every epoch row is still there.
- [ ] Open the same upgraded file with the previous build and confirm it refuses
      at open, names the migration it does not know, and points at the copy,
      rather than reading an epoch and finding a column missing.
- [ ] Read `hi/spend.md`, `hi/run.md` and `hi/see.md` and confirm each of the
      four criteria is cited by name in a test that exists.

## Running it

```bash
swift test                                   # every target, the only figure worth quoting
swift test --filter ReserveTests             # SPEND-9.c, the engine half
swift test --filter ChainTests               # RUN-10.a, RUN-11, SEE-1.b
swift test --filter StoreSQLiteTests         # SPEND-9.c, the migration half
fledge lanes run verify                      # build, then test
specsync check --strict                      # the contracts and the code still agree
```

## Open questions the evidence cannot settle

1. **Who is the caller for somebody who has not verified yet?** A member key
   exists only for a member on record, so a command that reads the chain during
   verification has no minted id to pass and the only thing to hand is something
   the person supplied. Until that is answered, the tests above exercise callers
   the instance named itself, and the verification path has no test because it
   has no answer.
2. **What happens at the tracked-caller cap**, which `design.md` leaves to the
   implementation. Both plausible rules have a bad day in them.
3. **Whether a host that states no spending limits gets anything from this
   change.** As designed it does not: no limits, no measurement, no charge, and
   SPEND-9.c stays unanswerable for that host. Naming that in the spec is the
   minimum. Recording the cadence period for those runs would close it, at the
   cost of a record whose one field means two different things depending on the
   host, which is the trade `design.md` declined and a reviewer may not.
4. **Whether five percent of a very large budget is a share at all.** RUN-11 can
   be satisfied by the tests above and still leave one member able to cause tens
   of thousands of reads on an instance whose operator set a large budget. An
   absolute ceiling beside the percentage would close it and costs a third
   variable.
