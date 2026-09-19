---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: plan
---

# Plan

## What the code says today

Four criteria, four different shapes of work. Each was read against the code at
the base commit before it was planned, and two of the four are not quite what
the change description assumed.

**SPEND-9.c is unmet.** `ReserveEpochRecord` carries `startedAt`
(`Sources/Reserve/ReserveEpochRecord.swift:39`) and `completedAt` (`:42`) and
nothing that names a period. The period an epoch was measured against is
`ReserveSpendLimits.periodKey` (`Sources/Reserve/ReserveSpendLimits.swift:31`),
and it has exactly one reader in the package: the refusal raised when the
limits describe a period that has already ended
(`Sources/Reserve/ReservePlanner.swift:282`). An epoch that was admitted, paid
and closed leaves no record of which ceiling it was charged to. The cadence key
the run was given survives only for the newest epoch of each stream, in
`ReserveState.lastPeriodKeys` (`Sources/Reserve/ReserveState.swift:33`), and it
is a different fact from the ceiling in any case.

**RUN-10.a holds by accident and is half covered.** `unpause` clears
`pauseEndsAt`, `pauseCause` and `didAnnouncePause`, and touches the day's
counter nowhere (`Sources/Chain/RequestGovernor.swift:170`). A test exists:
"Lifting a pause does not hand back a budget that really is spent"
(`Tests/ChainTests/RequestGovernorTests.swift:208`). That is not nothing, and it
is not enough. It uses a budget of one that was already exhausted, so it catches
a wholesale refill and would pass a partial one. It pauses through an exhausted
budget and never through a provider refusal, which is the case the criterion is
actually about, a refusal that turns out to be wrong. It asserts a throw rather
than the counter, so it says nothing about what the snapshot or the persisted
row reads afterwards. And it cites no criterion id, so nobody editing `unpause`
is told what the test is defending.

**RUN-11 is unimplemented, and the two brakes that exist are not it.** Nothing in
the package knows who a request is for: `RequestGovernor` counts requests and
has no notion of a caller, and the single call site that spends from it
(`Sources/Chain/ChainReader.swift:198`) passes nothing but the clock. The
per-second limiter (`Sources/Chain/RequestRateLimiter.swift:12`) is
process-wide and, as its own documentation says, will hold a published rate
perfectly while the day disappears. The wallet cooldown
(`Sources/Chain/WalletCheckCache.swift:24`) bounds how often the *same* wallet
is re-read, so a member asking about a thousand different addresses pays a
thousand requests and nothing objects.

**SEE-1.b has its parts and no whole, and the setting is not orphaned.**
`ChainConfiguration.healthProbe` (`Sources/Chain/ChainConfiguration.swift:390`)
does have a consumer: `ProviderProofProbe`
(`Sources/Chain/ProviderProofProbe.swift:61`), which caches a provider's
headers and deliberately stays outside the governor (`:23`). What does not
exist is anything that assembles a health answer. `ChainHealthReport`
(`Sources/Chain/ChainHealth.swift:147`) is constructed nowhere outside its own
test file; it carries no budget state, so it cannot say that reads are paused;
and the only way to ask the probe for proof is `proof(now:)` (`:73`), which
makes a request whenever the cache is stale. A health surface built on what is
here today would either call the network inside the request path or drop
provider proof altogether.

## The order of work

1. **RUN-10.a, the test, first.** It is the smallest item and it has to come
   before RUN-11, not after. The criterion's whole risk is that the next person
   to make unpausing more useful breaks it without noticing, and RUN-11 *is*
   that next person: it adds per-caller state to the same actor, and "give the
   member their share back when the operator unpauses" is a plausible and wrong
   thing for somebody to write. The test must exist, and be extended in step 3
   to cover the new state, or the guard arrives a week late.
2. **SEE-1.b, the Chain side, second.** It is additive, it is small, and it is
   on another change's critical path. The runtime change being defined
   alongside this one cannot build a health answer until these values exist,
   and if it waits for the end of this change it will invent its own.
3. **RUN-11 third.** It is the largest diff and the largest design risk, and it
   changes the signature of the type the previous two steps just settled.
   Doing it after them keeps the governor's diff coherent and lets step 1's
   test grow by two assertions rather than being rewritten.
4. **SPEND-9.c last, as one block across `Reserve`, `Store` and
   `StoreSQLite`.** It depends on none of the above and touches none of the
   same files, so it can be reviewed on its own. It is last rather than first
   because its risk is schedule risk, not correctness risk: the migration is
   guarded by the migrator's existing backup and version refusal
   (`Sources/StoreSQLite/SchemaMigrator.swift:32`), and nothing else in the
   change is blocked on it.

Specs move with each step rather than at the end. `specs/` is in
`ignored_paths` in `.specsync/sdd.json`, so a contract edit needs no workspace
of its own, but a step is not done until its contract says what the code does.

## The decisions somebody may disagree with

### SPEND-9.c: what gets recorded, and what an absent record means

The field records **the spending period the epoch was admitted against**, taken
from `ReserveSpendLimits.periodKey`, because that is the ceiling SPEND-9.a says
a long job is held to and the thing SPEND-9.c asks an operator to be able to
read. It is not the cadence key: the cadence key stops fifty-two epochs paying
in one afternoon, which is a different guarantee, and the two can differ
honestly when a host's wallet limit runs monthly and its schedule runs weekly.

The record is **an ordered, append-only list of charges, one per run of the
epoch**, and not a single field. Each charge names the period key of the limits
that run was measured against and the whole-unit figure it was checked for. An
ordinary epoch has exactly one; an epoch cut off on a Sunday and resumed on the
Monday has two, in the order they were charged, which is the case SPEND-9.c was
written for and the case a single field can only describe by naming one of the
two ceilings and hiding the other. `design.md` and `testing.md` carry the same
shape, and this plan was written against a single-field draft and has been
brought into line with them.

A charge is appended **after the limits check and before the first claim of
that run**, from the limits already fetched at
`Sources/Reserve/ReserveRunner.swift:239`, and saved once per run rather than
once per recipient. Written at the end instead, an epoch that died half way
through would be the one case with no record, and that is exactly the epoch
somebody is trying to understand.

The alternative, a single nullable field on the epoch row that is never
overwritten, is cheaper and reads well in the ordinary case. It was rejected on
two grounds. It is a confident lie in the boundary case, and its reverse
migration is a `DROP COLUMN` the SQLite floor this package declares does not
have, which `context.md` has already ruled out; a new table's reverse is a
plain drop of something whole. A fourth kind in `reserve_epoch_claims` was
rejected as well, because the `kind` CHECK at
`Sources/StoreSQLite/Schema.swift:149` cannot be altered in place and the table
it would rebuild is the no-double-pay record.

An absent record must not mean two things, and with a list it does not. A host
that states no limits produces **no charge**, and nothing invents one; a record
written before this build also carries none. The two are told apart by what the
reader is shown: a run against no stated ceiling is reported as no ceiling
having been in force, and an epoch from an older build is reported as a period
nobody wrote down. Neither is ever derived.

**Nothing is back-filled.** An older row reads back with no charges. The engine
cannot know which period function the host used, since `ReservePeriod` offers a
week, a month and a day and the limits' period is the host's own and need not
be any of them, and deriving it from `startedAt` is precisely the inference the
criterion exists to remove.

### RUN-10.a: what the test asserts, and what it must fail against

One test, citing RUN-10.a, over the case the criterion describes, a pause that
turned out to be wrong:

- A governor with a budget of 100 and a store double, day pinned. Spend 40.
- Trip the breaker with a provider quota refusal, not an exhausted budget.
- Take a snapshot, unpause, take another. `usedRequests`, `remainingRequests`
  and `dayStart` are identical across the two, and `remainingRequests(now:)`
  still answers 60.
- Spend 60 more one at a time. The sixtieth is allowed and the sixty-first
  throws `ChainError.requestBudgetSpent`, so the day still ends where it would
  have ended had nobody unpaused anything.
- The counts written to the store are non-decreasing and never drop below what
  was spent before the unpause.

It must fail against each of these mutations, and each should be tried by hand
before the test is called done:

| Mutation to `unpause` | Caught by the existing test? |
|---|---|
| Replace the budget with a fresh `DailyRequestBudget` | yes |
| Zero the day's counter | yes |
| Refund only what was spent since the pause began | **no**, because the existing test's budget was already spent |
| Advance `dayStart` so the next reservation rolls the day | yes |
| Clear the per-caller ledger added in step 3 | not applicable yet, added in step 3 |

The existing test at `Tests/ChainTests/RequestGovernorTests.swift:208` stays. It
is the exhausted-budget half of the same guarantee and deleting it to avoid
overlap would trade a cheap test for a gap.

### RUN-11: the unit, the share, and what happens at the ceiling

This is the decision in the change most likely to be wrong, so the reasoning is
set out rather than the conclusion.

**The unit is a caller, and a caller is either a member or the system.** A
request is reserved on behalf of `.member(key)` or `.system`. Sweeps, payouts,
boot checks and scheduled work are `.system` and draw on the day's budget alone.
Metering every caller alike was considered and rejected: a sweep's size is the
community's size, so a sweep starved by its own share would stop part way, and
because an unreadable balance holds a member's role rather than removing it, a
starved sweep looks like nothing happening at all. That is a worse failure than
the one being prevented, and the criterion names a member, not a caller. The
cost of this choice is that a host which classifies an admin command as system
work leaves it unmetered; that is accepted, because an operator who can spend
money can certainly spend requests, and operator surfaces are gated elsewhere.

The key passed for a member is the key this instance drew for them, never a chat
account id, so the governor never holds anything that reads back as a person.
Hosts mint that key on first sight, so an unverified member typing a command
still has one.

**The share is a percentage of the day's budget plus a burst, and an operator
can set both.** The percentage defaults to 5 and the burst to 10 requests, as
`design.md` fixes them: the percentage spread over the UTC day is the sustained
rate, and the burst is the capacity a caller can draw at once, capped by the
day's share. A percentage rather than an absolute count because budgets differ
by orders of magnitude between a free tier and a paid one. A burst alongside it
because "however fast they type" is a rate problem, and a pure daily quota lets
a member empty their share in ten seconds and then reads to them as the bot
being broken for the rest of the day. The day is the same UTC day the budget
uses, rolling with `DailyRequestBudget.rollDayIfNeeded`
(`Sources/Chain/DailyRequestBudget.swift:190`), because two day boundaries in
one process is a bug that only shows up at midnight.

*An earlier draft of this plan proposed a percentage with an absolute floor and
a flat per-day counter.* The floor's argument survives as an open question
below, because a percentage of a small budget really can be fewer requests than
one command costs; the per-day counter does not survive, because it is the
quota shape the burst exists to avoid and because a restart would hand a caller
a whole fresh day rather than one burst.

**With no daily budget set there is no share.** The budget defaults to zero,
meaning no ceiling, and inventing a per-member ceiling where the operator set
none would refuse work in a healthy deployment, which is the reasoning already
written into `ChainLimits.dailyRequestBudget`. The honest consequence is that
RUN-11 is vacuous in a default deployment, and the boot report should say so
rather than imply a protection that is not there. A reviewer may reasonably
want a share even with no budget, backed by the per-second limiter alone; that
is a real disagreement and is recorded as an open question rather than settled
here.

**Reaching the share refuses, and never queues.** The governor's stated posture
is that work which waits for the budget is work that lands hours later when
whoever asked has gone (`Sources/Chain/RequestGovernor.swift:11`), and queueing
hands one fast caller the power to make everybody else wait, which is the same
denial of service by a politer route. The refusal is its own `ChainError` case,
not `requestBudgetSpent`, because the day is fine and the advice differs: it
names when the share comes back, at the next UTC midnight, and how much of it
was used. It must not trip the breaker, or one member typing fast stops the
whole process, which is the criterion inverted. It records no notice per
refusal, for the reason already written at
`Sources/Chain/RequestGovernor.swift:249`: a refusal answered to its caller
there and then, repeated, would push the pause announcement out of the buffer an
operator reads exactly when things are bad.

**It is enforced inside the one reservation path**, `RequestGovernor.spend`
(`:235`), rather than in a wrapper. Two gatekeepers is how this budget came to
have two counters before, which is the failure the type's own documentation
opens with. Order inside that path: the pause check first, unchanged, then the
caller's share, then the day. The share is checked without mutating anything, so
a refused member costs the day nothing; there is no way to hand a reservation
back and there must not be one.

**The caller is a required parameter, not a defaulted one.** `RequestGovernor`,
`ChainReader`, `BatchedChainReader` and `WalletCheckCache` all take it with no
default. This is the largest diff in the change, roughly thirty call sites
across `Sources/` and `Tests/`, and it is deliberate: a default of `.system`
makes the guarantee opt-in, and the place it will be forgotten is a new command
written in a hurry, which is the member-initiated path the criterion is about. A
task-local value was considered, which threads nothing and reads cleanly, and
rejected because attribution then becomes invisible at the call site and
silently wrong across a detached task.

**The ledger is one refilling allowance per member, in memory, bounded.** It
refills at the sustained rate towards the burst and no further, and a caller
whose allowance is full again carries no information, so the entry is dropped.
The number of tracked callers is capped by a constant rather than a setting, in
the manner of `RequestGovernor.maxRetainedNotices` (`:21`), and at the cap a
caller nobody is tracking yet is refused rather than admitted untracked,
because admitting untracked callers is the hole the whole thing exists to
close. A caller already tracked is never evicted to make room: eviction hands
the evicted caller a full allowance, which is the exploit, and recency is
exactly what a fast caller produces. Reaching the cap records one notice for
the day.

**The ledger does not survive a restart, and that is a known gap**, recorded
rather than hidden. Persisting it needs a new `Store` seam and a row per member
per day, which would double this change's migration surface for a second-order
benefit. What still holds across a restart is the day's total, which is
persisted already, so a crash loop hands a member at most one fresh burst and
cannot lift the ceiling that share is carved out of.

### SEE-1.b: exactly what `Chain` exposes, and where the line falls

`Chain` gains three things and no more:

1. A non-probing read on `ProviderProofProbe` that answers with the cached proof
   while it is still fresh, and nil otherwise, without making a request and
   without mutating the cache. `proof(now:)` keeps its current behaviour for the
   caller that wants to refresh out of band.
2. A budget section on `ChainHealthReport`, carrying the
   `RequestBudgetSnapshot` the governor already produces, plus its key in the
   hand-built JSON body, appended after the existing keys so a monitoring check
   grepping the current shape is undisturbed.
3. A stated and tested guarantee that assembling a report reserves nothing.
   The guarantee is structural rather than a promise: the report is built from
   values, so there is no seam through which it could make a request.

`status` deliberately does **not** become `starting` when reads are paused. A
paused chain reports `ok` with a budget section saying so. `starting` is what a
deployment gate reads to decide whether a new version came up, and a provider
quota outage must not roll back a release that is working perfectly, nor tell
an operator their new version is broken when the truth is their provider is. A
check that wants to alert on a pause reads the budget section, which is why the
budget section exists.

The line between this change and the runtime change:

| Owned here, in `Chain` | Owned by the runtime change |
|---|---|
| The report value, its status rule and its JSON body | The listener, the route, and the HTTP status mapping |
| The budget and pause facts, from the governor's snapshot | Which components exist and when each is marked reached |
| A non-probing read of the last provider proof | When the probe is refreshed, always outside the request path |
| A test proving the count did not move, and that a report still answers once the budget is gone | A test that the endpoint answers once the budget is gone, and the process facts: version, store opened, gateway connected |
| Nothing about who a read is for | Naming the instance's own work on the boot gate's one chain read, once step 3 makes the caller required |

If both changes assume the other owns it, the specific thing nobody writes is
the non-probing proof read, and the runtime then either probes inside the
request path, which is the traffic `ProviderProofProbe` was built to avoid, or
drops provider proof and leaves SEE-10.a unmet as well. So the ordering is
declared rather than assumed: this change lands the `Chain` side, the runtime
change depends on it, and the dependency is recorded with
`specsync change depend` rather than in somebody's head.

## Not in this change

- **The health surface itself.** No HTTP type, route, port or status code is
  added here. `Chain` does not learn that a socket exists.
- **Any command or card.** There is no executable and no command layer, so
  nothing displays the new epoch stamp, the share, or the budget section. The
  values are shaped so a card can print them; printing them is the runtime's.
- **Back-filling a period onto epoch rows written by an older build.** Argued
  above: a derived period is the inference the criterion removes.
- **Recording the cadence period per epoch.** `ReserveState.lastPeriodKeys`
  keeps only the newest per stream, and an operator asking "which week did
  epoch seven pay in" still cannot be answered. It is a real gap and a
  different criterion from SPEND-9.c. Named in the open questions.
- **A general per-caller quota covering sweeps, payouts and scheduled work.**
  Only member-initiated work is metered, for the reasons above.
- **Persisting the per-member ledger.** Named as a known gap.
- **Queueing, backpressure or fair scheduling of any kind.** Refusal only.
- **Any change to the day boundary, the weekly ceiling, the cadence key, the
  four no-double-pay guards, or `ReserveState`'s shape.**
- **Editing `hi/`.** This change satisfies criteria; it does not rewrite them.
  Editing the catalogue so it matches the code is how a gate stops meaning
  anything. If the refuse-not-queue decision deserves a sub-criterion, that is a
  catalogue change with its own workspace.

## What could not be settled here

1. Whether a member's share should exist when no daily budget is set. Read
   strictly, RUN-11 is about the day's budget and there is none; read
   generously, one member should never be able to hammer a provider whatever the
   operator configured. Settled here as the strict reading, and flagged.
2. Whether a resumed epoch should record every period it was admitted against
   rather than the first. Settled as every one, in order, because a single
   value is a lie in the only case the criterion is about. The cost is a table,
   a conformance behaviour and a read.
3. Whether the per-member ledger should survive a restart. Settled as no, for
   this change.
4. Whether the cadence period should be recorded per epoch alongside the
   spending period, in the same migration. Recommended no, and cheap to change
   the mind about only while the migration is unwritten.
5. Moot now that the charges are their own table: no column is added to
   `reserve_epochs`, so the bundled SQLite's handling of `ALTER TABLE ADD
   COLUMN` with a CHECK does not arise, and the reverse is a plain drop.
6. The default share numbers, 5 percent and a burst of 10, are a judgement with
   no deployment behind them. Nobody is running this yet, so there is no data to
   appeal to; they should be revisited by the first operator who has members.
8. Whether the share needs an absolute floor as well as a percentage and a
   burst. On a small budget five percent can be fewer requests than one
   command costs, and every member would be refused on their first command of
   the day. A third knob is the cost. Recorded rather than settled.
7. Whether adding a `budget` key to the health body counts as breaking anybody's
   monitoring. Nobody is running this, so now is the moment to do it.
