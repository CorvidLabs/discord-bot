---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: research
---

# Research

Everything below was read in the tree at the change's base commit. Each of the
four items was checked against the code before anything was written about it,
and one of them turned out to be mostly satisfied already. Line numbers are
from the files as they stand; treat them as a pointer to the right paragraph
rather than a guarantee after the next edit.

## 1. SPEND-9.c, naming the period a payout was counted against

### What is there now

`ReserveEpochRecord` is the per-epoch row and the no-double-pay guard. It holds
the stream, the epoch number, three claim lists, the smallest units committed,
and two instants: `startedAt` at `Sources/Reserve/ReserveEpochRecord.swift:39`
and `completedAt` at `:42`. There is nothing on it that names a period.

The ceiling an epoch is measured against arrives separately, as
`ReserveSpendLimits`. Its `periodKey` is declared at
`Sources/Reserve/ReserveSpendLimits.swift:31` and documented as "The period
these figures describe". It is read in exactly one place,
`ReservePlanner.requireWithinLimits(plan:limits:now:)` at
`Sources/Reserve/ReservePlanner.swift:275`, where the guard at `:280` refuses
limits describing a period that has already ended and puts `limits.periodKey`
into the refusal at `:281`. On the path where the limits are fine, which is
every path that pays anybody, the key is never looked at again.

`ReserveRunner.execute` calls that check once, before the first payment, at
`Sources/Reserve/ReserveRunner.swift:239` to `:241`. From there it claims each
line and persists the claim before handing value over, at `:255` to `:258`, and
sets `completedAt` and saves once the loop reaches the end, at `:295` to `:296`.
So the one moment the process knows which ceiling this epoch is being charged
to is a few lines above the loop, and that knowledge is discarded there.

### Two different periods, and which one the criterion means

This is the thing most likely to be got wrong, because both are called a period
key and both are strings of the same shape.

The first is the **cadence** period: the argument to
`ReserveRunner.run(streamId:recipients:periodKey:now:)` at
`Sources/Reserve/ReserveRunner.swift:151`. It identifies a firing, so that a
stream pays at most one epoch per week whatever an operator types. It is checked
at `:230`, claimed at `:299` through
`ReserveState.claimingPeriod(streamId:periodKey:)`
(`Sources/Reserve/ReserveState.swift:119`), and reported on the outcome at
`Sources/Reserve/ReserveEpochOutcome.swift:69`.

The second is the **spend** period: `ReserveSpendLimits.periodKey`, which names
the window the paying account's ceiling is counted over. It belongs to the host,
not to the schedule. `ReserveSpendLimits` says as much in its own doc comment:
the limits "are the host's, not the reserve's", and "they usually apply to
everything it does, not only to this schedule".

They coincide in the obvious deployment, where both are an ISO week, and they
are not the same thing. A host whose account ceiling runs on a calendar month
while the schedule fires weekly has four epochs charged to one spend period, and
recording the cadence key would answer a question nobody asked.

SPEND-9 is headed "A job long enough to cross from one period into the next is
still held to one period's ceiling", and SPEND-9.c asks which period the job was
"counted against". Counted against a ceiling. So the field to record is the
spend period, and the cadence period is deliberately out of scope for this
change. That said, the cadence period has the same hole: `lastPeriodKeys` keeps
only the most recent key per stream, so for epoch seven of twenty six there is
no record of which firing claimed it either. No criterion asks for that today.
It is named here so that a later reader does not assume this change covered it.

### The resumed epoch, where a single field becomes a lie

A run that dies part way is resumed, and resuming is designed for: the planner
skips accounts, people and holdings the record already claims
(`Sources/Reserve/ReservePlanner.swift:96` onward), and the runner re-prepares
from the stored record at `Sources/Reserve/ReserveRunner.swift:234`.

Crucially, the resumed run checks the limits again, at `:239`, against whatever
the host reports now. If the first run paid two hundred lines in one week and
the second run finishes the remaining three hundred in the next week, then two
hundred lines were charged to the first week's ceiling and three hundred to the
second. Both figures are true and a single field can hold only one of them.

This is not an exotic case. It is the case SPEND-9 exists for, arriving through
the crash door rather than the slow-payout door.

Three shapes were considered.

- **One nullable field, first writer wins.** Simplest. Lies about the resumed
  epoch by naming only the first ceiling, which is precisely the epoch an
  operator is most likely to be asking about.
- **One nullable field, last writer wins.** Same objection, other end.
- **An ordered list, one entry per run that paid something in this epoch.**
  Honest in every case, one entry long in the ordinary case, and it costs a
  little storage and one more read.

The recommendation is the list, and the argument is that the only reason to
prefer a single field is that it is less work, while the only case where they
differ is the case the criterion was written for.

There is a fourth shape, a period recorded against each individual claim row,
which would answer "this recipient's payment was charged to that week". It is
rejected as out of proportion: it triples the size of the claim rows and answers
a question nobody in the catalogue asks.

### Where the list lives, and why not a column

The obvious storage is a column on `reserve_epochs`
(`Sources/StoreSQLite/Schema.swift:108` to `:122`), added by a new migration.
Two facts make that harder than it looks.

First, **an existing migration cannot be edited.** `SchemaMigration.checksum`
(`Sources/StoreSQLite/SchemaMigration.swift:40`) fingerprints the migration's
own name and statements, and
`SchemaMigrator.refuseAFileThisBuildCannotRead(applied:)`
(`Sources/StoreSQLite/SchemaMigrator.swift:150` to `:174`) refuses to open a
file whose applied row disagrees with the shipped text, throwing
`schemaDiverged`. Adding a column to migration two would refuse to start for
every operator who has already run it. Whatever is added is migration three.

Second, **every migration must have a real reverse.** `SchemaMigration`'s doc
comment says a reverse that is a comment is a migration nobody can step back
over, and the test at `Tests/StoreSQLiteTests/SQLiteFileTests.swift:76`,
"Every migration has a reverse, and reversing them all leaves nothing behind",
applies every migration, reverses every migration, and asserts the database is
empty. A column added with `ALTER TABLE ... ADD COLUMN` reverses with
`ALTER TABLE ... DROP COLUMN`, which SQLite learned in 3.35. The floor this code
declares is `Connection.oldestSupportedVersion = 3_024_000`
(`Sources/StoreSQLite/Connection.swift:33`), that is 3.24, and it is enforced at
open (`:52`). So a reverse written with a column drop would fail on a machine
the package says it supports. The alternatives are a twelve step table rebuild
in the reverse, or raising the declared floor, and raising the floor is a
separate decision with its own reasons.

A **new table** sidesteps both. Its forward step is a `CREATE TABLE` and its
reverse is a `DROP TABLE`, which every SQLite in range can do, and a table
naturally holds an ordered list. There is a pattern to copy: `reserve_epoch_claims`
(`Sources/StoreSQLite/Schema.swift:144` to `:157`) is exactly an ordered list of
strings hanging off an epoch with a cascade, keyed by position rather than by
value, and the reasoning for that shape is written into the migration itself.

The one thing not to do is reuse `reserve_epoch_claims` with a fourth claim
kind. Its `ClaimKind` doc (`Sources/StoreSQLite/Schema.swift:184`) says adding a
kind means adding a number and never renumbering, which sounds like an
invitation, but the column carries `CHECK (kind IN (0, 1, 2))` at `:149`, and
SQLite cannot alter a check constraint without rebuilding the table. That
rebuild is the same work as the column drop, plus it mixes a fact about a run
into a table whose rows are facts about recipients, and the epoch's claim rows
are the ones `hi/reserve.md` RESERVE-10.b says a store may be asked to erase.
A period key is not an identifier for anybody and should not sit where the
things that are do.

### The migration story for a record written before the field existed

Two storage paths, and both need an answer.

**The durable store.** A new table means the rows simply are not there for an
epoch paid by an older build. `SQLiteStore.loadEpoch` at
`Sources/StoreSQLite/SQLiteStore+Reserve.swift:104` reads the epoch row and then
its claim rows, and the same pattern gives an empty list here. The migrator takes
a backup before running anything pending when a file already has migrations
applied (`Sources/StoreSQLite/SchemaMigrator.swift:57` to `:65`), so the upgrade
is recoverable if it goes wrong.

**The encoded path.** `InMemoryReserveStore` deliberately stores rows as encoded
text so the encode and decode path is genuinely exercised
(`Sources/Reserve/ReserveStore.swift:36` onward), and `ReserveCoding.decode`
throws rather than reading an unparseable row as empty
(`Sources/Reserve/ReserveCoding.swift:40`), because a ledger row read as blank
looks like an epoch nobody was paid for. That rule turns a careless Codable
change into a payout that refuses to run: Swift's synthesised decoding requires
a key for a non-optional property, so a plain array added to
`ReserveEpochRecord` would make every previously encoded record fail to decode,
and the runner would then refuse rather than pay. The new member has to decode
absent as empty, by being optional or by a hand-written decode with a default,
and there has to be a test that decodes a record encoded in the previous shape.
This is the single most likely way to break a live ledger with this change.

**What an absent value means to a reader.** Three states have to stay apart, and
two of them look the same if this is done carelessly: an epoch written before the
field existed, an epoch paid by a host that supplies no spending limits at all
(`payer.spendLimits()` returning nil is a supported case, guarded at
`Sources/Reserve/ReserveRunner.swift:239`), and an epoch paid under a named
ceiling. The suggestion is that a run which pays under no limits still records
an entry, with the period left empty, so that no entries at all means written by
an older build and an empty entry means no limits were in force. A surface must
print the first as not recorded and never as a guess, which is the same
unknown-is-not-zero rule the repository states elsewhere.

### When the value is written

Once per run that pays anything, not once per line, and before the first claim
is persisted. The moment is after `requireWithinLimits` returns at
`Sources/Reserve/ReserveRunner.swift:241` and before the loop at `:249`, so the
first `save(epoch:)` inside the loop carries it. A crash after the first payment
then leaves a record that names the ceiling that payment was charged to, which
is the whole point. `claim(entry:at:)` and `release(entry:)` must leave it alone:
a released claim is a payment that provably moved nothing, but the run was still
measured against that ceiling.

### What moves with it

`Reserve` for the field and the runner, `Store` for the record travelling
through the protocol, `StoreSQLite` for the migration and the two halves of the
epoch read and write, `StoreTestKit` for the conformance behaviour that proves a
backend round-trips it, and the contracts in `specs/reserve/` and `specs/store/`.
`Tests/StoreSQLiteTests/SQLiteFileTests.swift:330` asserts a fresh file has two
migrations pending and becomes three. `StoreTable`
(`Sources/Store/StoreTable.swift`) names the tables a store reports rows under
and gains one.

### What the reference implementation does

Nothing, and that is worth stating. The private bot this engine was ported from
has the same record with the same two instants and no period on it, and its
weekly ceiling is held in memory on the signing service, rolled over by
comparing a week key string and resetting a counter when it changes. Its status
card prints when the current week started, so an operator can work out the
current week and nothing else. There is no record anywhere of which week a past
payout was charged to. So this is new work rather than a port, and there is no
prior art to copy or to be constrained by.

## 2. RUN-10.a, unpausing that cannot hand out a second day of budget

### This one is already satisfied, and it has a test

`RequestGovernor.unpause(now:)` is at
`Sources/Chain/RequestGovernor.swift:170` to `:189`. It clears `pauseEndsAt`,
`pauseCause` and `didAnnouncePause`, records a notice, and returns whether
anything was paused. It does not touch `budget`. Its own doc comment at `:161`
to `:168` states the reason: without it the only way back from a wrong refusal
was a restart, which also zeroed the counter and so quietly granted a second
day's budget.

There is also a test: `unpauseDoesNotRefillTheBudget`, at
`Tests/ChainTests/RequestGovernorTests.swift:208`, named "Lifting a pause does
not hand back a budget that really is spent". With a limit of one it spends the
request, watches the second throw, lifts the pause, and asserts the next request
throws `requestBudgetSpent` again.

So the original framing of this item, that the criterion happens to hold and
nothing says so, is half right. The behaviour holds and something does say so.
What is genuinely missing is narrower.

### What is actually missing

**The criterion id is not cited.** The repository's convention, stated in
`AGENTS.md`, is that a test's name cites the criterion id it protects, so a
failing test names the promise it broke. The suite cites ids elsewhere, for
instance "A reservation the day cannot cover spends nothing and pauses nothing
(SEE-9)" at `Tests/ChainTests/RequestGovernorTests.swift:71`. RUN-10.a is not
cited anywhere in the repository. Searching the tree for the id finds it only in
`hi/run.md:37`.

**The existing test asserts a consequence at one boundary.** It works with a
limit of exactly one, fully spent, and checks that the next request throws. That
catches the blunt regression, an unpause that resets the counter, because a reset
would let the next request through. It does not catch a subtler one. A future
change that gave back only the requests spent since the pause began, or granted
a small grace allowance computed as a percentage and floored to zero at a limit
of one, would leave this test green.

### What the new test must assert, and what it must fail against

Assert the counter itself, either side of the call, at a point where the budget
is not spent. Concretely: a governor with a limit comfortably above the number of
requests taken; take some requests; trip a pause the way a provider quota refusal
does, through `recordRequestFailure(_:now:)` at
`Sources/Chain/RequestGovernor.swift:147`, which pauses without the budget being
exhausted; lift it with `unpause(now:)`; then read `snapshot(now:)` at `:198` and
assert `usedRequests` and `remainingRequests` are exactly what they were before
the unpause, and that `dayStart` has not moved. Keep the existing spent-budget
test as well, since it protects the other end.

It must fail against any mutation of `budget` inside `unpause`: replacing it with
a fresh `DailyRequestBudget`, subtracting anything from the count, or adding a
grace allowance of any size. Note one near miss that would not be caught and does
not need to be:
`DailyRequestBudget.restore(used:dayStart:now:)`
(`Sources/Chain/DailyRequestBudget.swift:175`) takes the larger of what it is
given and what is already spent, so restoring zero is a no-op and cannot lose a
request.

Choosing a provider-quota pause rather than a spent-budget pause matters. On a
spent day the remaining count is zero and stays zero whatever an unpause does to
it, so the assertion proves nothing there. The wrong-refusal case, which is the
case RUN-10.a is written about, is exactly the case with budget left.

The reference implementation's equivalent behaves the same way, clearing its
pause flag and leaving its counter alone, and has no test over it at all.

## 3. RUN-11, a per-caller share of the day

### Nothing implements it, and what is nearby

There is no notion of a caller anywhere in `Chain`. The budget is one counter for
the whole process, and that is deliberate: `RequestGovernor`'s doc comment at
`Sources/Chain/RequestGovernor.swift:3` to `:13` explains that reads and signing
used to count separately, so the configured number was not the number of requests
the process could make, and that one counter and one breaker for both paths is
the only version an operator can reason about. Nothing in that reasoning argues
against a second, per-caller ceiling underneath it, but it does argue that the
second ceiling must live in the same place, or a caller reaching straight for
`reserveRequest` would step around it.

The nearest existing thing is the cooldown in `WalletCheckCache`. The type holds
a cache and a cooldown as two separate maps
(`Sources/Chain/WalletCheckCache.swift:23` and `:24`) and says why in its own doc
comment at `:6` to `:11`: the cache holds a reusable answer, while the cooldown
refuses to ask the chain about the same wallet again too soon "because the caller
is often a member typing in a channel and there is no upper bound on how fast
people type". `isOnCooldown(_:now:)` is at `:88`, the cooldown is honoured even
when a caller asks for a fresh read (`:45` to `:47`, and the condition at `:63`),
and its length is configuration, `walletCheckCooldown`, defaulting to sixty
seconds at `Sources/Chain/ChainConfiguration.swift:386`.

**Why that is not RUN-11.** It is keyed by address. It bounds how often any
caller can make the process read one wallet, which covers the commonest shape of
the abuse, somebody re-running a command about their own wallet. It does nothing
about a caller who varies the address: a command that looks up somebody else's
wallet, an autocomplete over addresses, or a member who has proved several
wallets and cycles through them. Each new address is a fresh cooldown key and a
fresh request. One caller, unbounded in total.

### What the reference implementation did, and why

The private bot hit this and answered it with a per-member spacing window rather
than a share. Its cooldown type keeps the last attempt per chat account id and
returns the whole seconds still to wait, with a default window of thirty seconds,
and its doc comment names the failure exactly: every claim attempt by a member
with a pending offer cost one chain read per verified wallet, there was no
spacing, and one member tapping in a loop could spend the day's request budget
and trip the global pause for roles, payouts and everybody else's claims. It also
records the design choice that the pending work keeps waiting and nothing is
skipped.

Two things to take from it and one not to. Take the shape of the harm, which is
one member with a repeating action costing a request per wallet each time. Take
the refusal that does not cancel the underlying work. Do not take the key, which
is a chat account id, because in this repository nothing below the chat boundary
may hold an identifier that came from a person.

### The unit

Not "a member". Three kinds of caller reach the chain, and only one of them has
an unbounded arrival rate.

- **On-demand work started by a person**: a command, a button, an autocomplete.
  Arrival rate is whatever a person can produce, which is the whole problem.
- **Background work the operator scheduled**: a role sweep, a payout run, a boot
  check. A sweep is not a member and must not be given a member's share. Its cost
  is proportional to the community and the operator already chose how often it
  runs by setting the sweep interval. A per-caller share applied here would break
  the sweep the budget was sized for.
- **Operator work**: an admin command. Rare, and in the same breath as on-demand
  work, so it can share the same treatment; an operator who hits the share can
  raise it, which a member cannot.

So the unit is a **caller key carried on the reservation**, with background work
either exempt or given its own identity that is not shared out. Concretely, a
request either names a caller or declares itself background, and only the named
ones are counted per caller. Making background work declare itself explicitly is
better than letting it default to unnamed, because a new background job that
forgot to say so would then be silently throttled at a member's rate, which is a
sweep that mysteriously stops half way.

**What the key is.** An opaque string that `Chain` never interprets, never
parses and never prints in full. The host passes the member key it already
minted. `Chain` cannot use the existing minted key type directly: `MemberKey`
lives in `Store` (`Sources/Store/MemberKey.swift:32`) and `Store` depends on
`Chain`, per the target graph in `Package.swift`, so taking that type would
invert the dependency. Declaring a small opaque key type in `Chain` and letting
the host hand over the string is the option that keeps the layering and the
promise that nothing down here holds an identifier that came from a person.

### The share

Four candidate shapes were weighed.

1. **A fraction of the day's budget.** Reads well, scales with the budget, and
   breaks in the case the code already supports: a limit of zero means no budget
   at all, and a fraction of nothing is nothing, so every on-demand read would be
   refused on a deployment that deliberately set no ceiling. It also makes a
   refusal message hard to write, because an operator reading "you have used your
   share" has to do arithmetic to find out what their share was.
2. **An absolute number of requests per caller per UTC day.** Denominated in the
   same currency as the thing it protects, rolls over on the same boundary the
   day's budget rolls over on (`DailyRequestBudget.rollDayIfNeeded`,
   `Sources/Chain/DailyRequestBudget.swift:190`), works whether or not a budget is
   set, and is a number an operator can read back and reason about.
3. **A short rolling window, the reference's answer.** Stops the loop immediately
   and costs almost nothing to keep, but does not bound a day: at one action every
   thirty seconds a determined caller still makes thousands of requests, which is
   not what RUN-11 says.
4. **Both a window and a daily total.** Strictly better protection and two
   concepts for an operator to hold.

The recommendation here was the second, an absolute per-caller daily ceiling
with a derived default. **The change settled on the fourth**, a share of the
day's budget as a percentage with a burst alongside it, defaulting to five
percent and ten requests (`design.md`, `requirements.md` R-SHARE-3). Two
arguments moved it. RUN-11 says "however fast they type", which is a rate
problem that a daily total does not answer: a quota lets a member empty their
share in seconds and then locks them out until midnight, which reads to them as
the bot being broken. And a flat daily total has to be persisted to be honest
across a crash loop, which is a table, a migration and a write in front of
every member read, where a refilling allowance costs a restart one burst and
nothing else. The cost of the settled shape is the second knob, and the
unanswered half of shape 1 is recorded as open question 8 in `plan.md`: a
percentage of a small budget can still be fewer requests than one command
costs.

It is worth being explicit that this is a ceiling on one caller's damage and not
a fair share. It does not divide the day between members and must not be
described as though it did, or the first operator with more members than the
budget divides into will read it as a promise it is not making.

**On the third shape.** The per-wallet cooldown already covers the immediate loop
for the commonest case, so the window is less needed here than it was in the
reference. If review disagrees and wants a window as well, it should be a second
change with its own criterion, because RUN-11 as written is about the day.

### Refused or queued

Refused, and the reasons are already written down twice in this repository.
`RequestGovernor`'s doc comment at `Sources/Chain/RequestGovernor.swift:12` says
it "refuses rather than queues. Work that waits for the budget to come back is
work that lands hours later, when the thing that asked for it has gone." The
payout gate says the same for its own case at
`Sources/Reserve/ReserveRunner.swift:154`.

Three further reasons specific to this case. A command from a person has a reply
deadline measured in seconds, so a queued reply arrives after the interaction it
answers has expired, which reads to the member as the bot being broken. A queue
does not satisfy the criterion at all, because the requests are still made, only
later, and the day's budget still goes. And a queue is unbounded memory keyed by
whoever is typing fastest, which is the same exposure in a new place.

**What the refusal must not do is pause the process.** One caller reaching their
share is not a reason to stop reading the chain for everybody. There is a
precedent for exactly this distinction in `DailyRequestBudget.Decision`:
`notEnoughBudget` at `Sources/Chain/DailyRequestBudget.swift:97` is deliberately
not `exhausted`, with the comment that the budget is not spent and what is left
belongs to every caller that can use it. A caller over their share should be the
same kind of answer: a refusal to that caller, no notice recorded, no breaker
tripped, and a message naming when the share resets, which is the next UTC
midnight.

There is also an ordering requirement. The per-caller check happens before the
day's budget is touched, and a refusal takes nothing from either counter, or a
caller could drain the day by being refused.

### Loose ends on this item

- **Where the arithmetic lives.** Inside the governor for enforcement, so nothing
  can go round it, but as a pure value type beside `DailyRequestBudget` for the
  counting, for the same reason `TokenBucket` was split out of
  `RequestRateLimiter`: every boundary then has a test that finishes instantly.
- **Memory.** One refilling allowance per caller, and an entry dropped once it
  is full again, because a full allowance is indistinguishable from a caller
  nobody has heard of. The warning here stands and shaped the settled answer: a
  cap that **evicts** is worse than none, because an evicted caller returns with
  a full allowance, which is the exploit. So the cap that was settled on never
  evicts a tracked caller; at the ceiling a caller nobody is tracking yet is
  refused rather than admitted untracked, and one notice is recorded for the
  day.
- **Reporting.** `RequestBudgetSnapshot` is the one value every status surface
  reads (`Sources/Chain/RequestBudgetSnapshot.swift:9`), and it describes the
  process. A per-caller figure means nothing globally, so it should not be bolted
  onto that value; a separate small answer for "what is left of this caller's
  share" is the better shape.

## 4. SEE-1.b, a health answer that costs nothing

### What exists

`ChainConfiguration.cacheLifetimes.healthProbe` is at
`Sources/Chain/ChainConfiguration.swift:390`, defaulting to thirty seconds, read
from `CHAIN_HEALTH_PROBE_CACHE_SECONDS`, and consumed in exactly one place,
`ProviderProofProbe`'s convenience initialiser at
`Sources/Chain/ProviderProofProbe.swift:61`.

The pieces around it are real and are tested.

- `ChainHealthReport` (`Sources/Chain/ChainHealth.swift:147`) is a pure value:
  components a host declares, optional provider proof, a status that is `ok` only
  when everything declared has been reached, and a hand-built `jsonBody` at
  `:186`. `ChainHealthTests` covers the meaning of the status, the proof parsing
  and the escaping.
- `ProviderProofProbe` (`Sources/Chain/ProviderProofProbe.swift:27`) caches the
  last thing the provider said about itself, and its doc comment at `:22` to `:26`
  states the SEE-1.b rule outright: it deliberately does not go through the
  request governor, because a health check must keep working when the day's budget
  is spent and must not be the thing that spends the last of it.
- `RequestGovernor.snapshot(now:)` at `Sources/Chain/RequestGovernor.swift:198` is
  a pure read that reserves nothing.

### What does not exist

**No assembly.** Nothing puts a snapshot, a set of components and a proof
together into an answer. Every host would do it by hand and each would do it
differently, which is the exact failure `RequestBudgetSnapshot`'s doc comment
warns about when it says one value stops the health page, the status command and
the logs disagreeing.

**No budget in the answer.** `ChainHealthReport` has no place for the budget at
all, so today a health answer can say `ok` while every read is refused until
midnight. That is a smaller version of the incident the whole SEE family is
written about: true, and useless.

**No proof that building an answer costs nothing.** No test anywhere asserts that
the governor's request count did not move across the construction of a health
answer, and no test asserts an answer is still produced once the budget is gone.
The acceptance criterion asks for both.

**No way to read the last proof without possibly making a request.**
`ProviderProofProbe.proof(now:)` at `:73` is `async`, and on a cold or stale
cache it awaits a network call inside the call that is meant to produce the
health answer. This is the one place where the current code can make checking
cost something. It does not spend the day's *budget*, which is what SEE-1.b says
literally, but it does spend a request at the provider, on the request path, with
no ceiling other than the probe lifetime, and a provider quota is a real resource
that the same criterion is trying to protect.

The reference implementation hit this and fixed it in the obvious way. Its health
route serves the last known proof immediately and kicks a background refresh, and
the comment in its source records why: a synchronous probe on the route stalled
webhook accepts for up to four seconds on a cold miss. It also rate limits the
verification route and deliberately does not rate limit the health route, because
behind a reverse proxy every request shares one client address and counting health
checks would starve the verification callbacks.

### What `Chain` must expose, precisely

This is the list the runtime change can build against, and the boundary is drawn
so that neither change has to wait for the other.

1. **A way to assemble an answer from values alone.** A synchronous, pure
   construction that takes the components the host declares, a
   `RequestBudgetSnapshot`, and an optional `ProviderProof`, and returns a
   `ChainHealthReport`. Synchronous is the load-bearing word: if it cannot await,
   it cannot reserve a request, and the criterion is kept by the shape of the API
   rather than by everybody remembering.
2. **A non-awaiting read of the last proof.** Something on `ProviderProofProbe`
   that answers what is currently held, and nothing else: no probe, no refresh, no
   network. The existing `proof(now:)` stays as the refreshing call, for a host to
   run on its own schedule away from the request path. `lastFailure` at
   `Sources/Chain/ProviderProofProbe.swift:39` is already such a read and is
   already named in the chain contract as being there so a health surface can say
   what is wrong rather than only that proof is missing.
3. **The budget in the answer.** `ChainHealthReport` gains an optional budget
   section carrying what `RequestBudgetSnapshot` already holds: used, limit,
   remaining, whether work is paused, why, and until when. The figures come from
   one value, so the health answer and the operator's status command cannot
   disagree, which is the reason that value exists.
4. **A stated rule about what the budget does to the status.** See below.
5. **Nothing else.** No listener, no route, no status codes, no timers.

### The decision most likely to be disputed here

Does a spent budget make the check say `ok` or not?

`ChainHealthStatus` has two cases today, `ok` and `starting`
(`Sources/Chain/ChainHealth.swift:105`), and `status` is `ok` only when every
declared component has been reached (`:172`). A paused governor is not a component
that has not been reached: the node is reachable, the gateway is connected, the
process is doing its job as configured and will read the chain again after
midnight.

The recommendation is that **the status stays about reachability and the budget
appears as its own section in the body**, for a practical reason. The status is
what a deploy gate and a container health check read, and those must roll a
version back when it comes up broken, not when it is merely throttled. A bot that
has spent its day's budget is not a bad deploy, and failing the gate on it would
replace a working version with an older one for no reason. An operator, by
contrast, wants to be told, and the body is where they are told; monitoring can
alert on the budget section without the deploy gate treating it as a failure.

The counter-argument deserves stating, because it is not weak: SEE-1 says an
operator should be able to tell whether the bot is really working from one check,
and a bot that will not change anybody's roles until midnight is not working in
the sense a member would mean. Somebody may reasonably prefer a third status for
throttled. That would be a change to a published enum and to the hand-built JSON
that a monitoring check greps for, so if it is wanted it should be decided now
rather than added later.

### Where the boundary falls with the runtime change

`Chain` owns: the report value and its JSON, the budget section, the proof and
its cache, the non-awaiting read, the rule that assembly spends nothing, and the
tests that prove it.

The runtime owns: the listener and the route, the mapping from status to an HTTP
code, declaring which components exist for this deployment and marking them
reached, owning the probe instance and deciding when it refreshes, and keeping
the refresh off the request path.

The sentence that keeps them from colliding: **everything the runtime needs to
answer a health check must be obtainable from `Chain` without awaiting anything
that could reach the network.** If the runtime finds itself awaiting on the
request path, the boundary has been crossed and the missing piece belongs on this
side.

## Questions this research could not settle

1. **The shape of the recorded spend period, list or single field.** Settled as
   the list, for the resumed epoch, and because the single field's reverse
   migration is a `DROP COLUMN` this package's SQLite floor does not have while
   a new table's reverse is a plain drop. It costs a table, a conformance
   behaviour and a read. Somebody who thinks a resumed epoch crossing a
   spend-period boundary is rare enough to document rather than record may
   still reverse it at approval.
2. **Whether the cadence period should be recorded per epoch too.** Out of scope
   as argued, but it is the same hole in the same row and leaving it means the row
   answers one period question and not the other. Cheap to add while the table is
   being created; impossible to add cheaply afterwards.
3. **The default per-caller share.** No number is proposed here on purpose. It
   depends on what one member's heaviest ordinary action costs, which is a
   function of how many wallets a member has proved and how many pools are
   configured, and nothing in the package establishes a typical figure. Somebody
   has to pick one and defend it.
4. **Whether an operator is exempt from the per-caller share.** An admin command
   that sweeps or previews can legitimately cost a lot, and an operator locked out
   of their own bot by a limit they set is a bad afternoon. Exempting them is a
   hole if an operator account is compromised. Not settled.
5. **Whether a spent budget belongs in the health status or only in the body.**
   Settled as body only, as recommended, with the readiness rule written into
   the contract (R-HEALTH-4) because the runtime change's HTTP mapping reads
   it. The counter-argument stands and a third status remains somebody else's
   change with its own criterion.
6. **Whether the probe lifetime should have a floor.** Zero currently means probe
   every time (`Sources/Chain/ChainConfiguration.swift:398`), which turns a
   monitoring check on a short timer into steady traffic at the provider. That is
   within the letter of SEE-1.b and against its spirit. Whether to refuse a zero,
   floor it, or leave it as the operator's rope is not settled.
