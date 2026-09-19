---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: design
---

# Design

Four small pieces of work in three library targets. They share nothing except
that each closes a gap between a promise in `hi/` and what the code does, so
the four sections below stand alone and can be built and reviewed in any
order. Where a decision could reasonably have gone the other way it is argued
at the point it arises, and the whole set is gathered again at the end.

Nothing here adds a dependency, a clock, a network call or an environment read
to a module that does not already have one.

## 1. Which period a payout was counted against

### The fact being recorded

A run of an epoch is measured once, against the spending ceiling the host
states, before the first payment goes out. The thing worth recording is that
measurement: which period the ceiling belonged to, and what the run was
measured as costing. An epoch that is cut off and resumed is measured twice,
against two ceilings, so the record is a **list** of measurements and not a
single value.

Two decisions are bound up in that sentence and both could have gone the other
way.

**A list rather than one key.** A single key, written by the first run and
kept, is simpler and reads well in the ordinary case. It is also wrong in
exactly the case SPEND-9.c was written for: an epoch that crashed on Sunday
and resumed on Monday really was charged to two weeks' ceilings, and a record
naming only the first would be a confident lie in the one situation the
operator is looking at it for. A list costs one table and a loop.

**The spending period, not the cadence period.** SPEND-9 is about the
ceiling, so this records what `ReserveSpendLimits.periodKey` said. The cadence
key already has a home in `ReserveState.lastPeriodKeys`, though only the
latest one per stream, which is a separate and smaller gap not closed here.

### Types

| Type | Shape |
|------|-------|
| `ReserveEpochCharge` | A value in `Reserve`: the period key the run was measured against, the whole units the run was checked for, and when the measurement was taken. `Codable`, `Sendable`, `Equatable`, like every other value in the module. |
| `ReserveEpochRecord.charges` | An array of the above, appended to by runs, empty by default. Joins `startedAt` and `completedAt` as the record's account of the epoch's life. |
| `ReserveEpochRecord.chargedPeriodKeys` | Derived, in order, so a reader that only wants the answer does not walk the structs. |
| `ReserveEpochOutcome.charges` | The same list on the value a run hands back, so a host reports without reading the store again. |

The whole-unit figure is the one the planner already computes for the limits
check, so no new arithmetic appears anywhere. The headroom that was left in
the ceiling at the time is deliberately **not** recorded: it is the host's own
figure, it is reconstructible from the host's spend record, and the criterion
asks which period, not how close it came.

### Order of operations inside a run

The runner's private `execute` gains one step, and where it goes is the whole
of the correctness argument.

1. Cadence guard, as today.
2. Prepare the plan, as today.
3. Limits check, as today.
4. **New.** If limits were given, append a charge naming their period key and
   the plan's whole-unit cost, and save the record once.
5. The payment loop, as today: claim, save, save state, pay.
6. Close the epoch, as today.

Step 4 sits after the check and before the first claim, for the same reason
the claim sits before the payment. A charge written afterwards is a charge a
crash loses, and the crash is when the operator goes looking. It costs one
extra store write per run, not per recipient, so the quadratic-write problem
that shaped the claims tables does not arise here.

A host that states no limits produces no charge. A plan with no entries still
produces one, because the epoch really was measured and closed against that
period and a zero is the honest figure. `rehearse` still writes nothing, since
it never saves.

### Storage

`Store` and `StoreSQLite` both persist the record, so both move.

The in-memory store encodes the record as JSON. A record encoded by an older
build has no `charges` key, and synthesised decoding of a non-optional array
throws on a missing key. Here that is not a harmless throw: the store's rule
is that an unreadable epoch row throws rather than reading as unpaid, so an
old row would stop every run of that stream until somebody edited the
database. The record therefore needs decoding that treats a missing `charges`
as an empty list, and only that key. This is the migration story for the
JSON-backed side and it has to be written deliberately, because the default
behaviour of the language is the wrong one.

The SQLite side takes a new migration, version 3, holding one new table. Its
shape mirrors the claims table, which is the shape this store already uses for
an ordered list belonging to an epoch.

| Column | Shape |
|--------|-------|
| stream id | text, part of the key, foreign key to the epoch row with the same cascade the claims rows use |
| epoch | eight-byte big-endian number, part of the key |
| ordinal | whole number from zero, part of the key, so the order is the order the charges happened in |
| period key | text, required |
| checked whole units | eight bytes big-endian, with the same type and length check every other amount column carries, because a whole-unit figure is an amount and store invariant 7 forbids a signed integer column for one |
| recorded at | whole seconds since 1970 UTC, as every instant in this store is |

Three storage shapes were considered.

**A new table**, chosen. The up is a create and the down is a drop, which is
the cheapest and most exactly reversible migration there is, and
`SchemaMigration` requires a real reverse: a test applies every migration and
reverses every one of them.

**A new column on the epoch row**, rejected. It cannot hold the two-period
case without inventing a delimiter and a parser, it needs two columns rather
than one because the amount cannot share the text column, and its reverse
needs either a `DROP COLUMN` that not every SQLite in the wild has or a full
table rebuild of the money table.

**A fourth kind in the existing claims table**, rejected. It would need no new
table, and the claims loader already refuses a kind it does not know, which
would be free forward compatibility. Against it: the kind column carries a
check constraining it to the three values it knows, so adding a fourth means
rebuilding the table that holds the no-double-pay record, which is the last
table in the package worth rebuilding for tidiness. A charge is also not a
claim, and overloading the table that stops double payment with bookkeeping
that does not stop anything makes the next reader work harder.

Writes are memoised the way the claims rows already are: the handle remembers
what it last wrote for an epoch and sends nothing when the charges have not
changed, so the thousands of saves inside one epoch cost one charge write
between them.

### Naming

`ReserveEpochOutcome.periodKey` and the runner's `periodKey` parameter are
renamed to say `cadence`, and the new members all say `charge`. The two senses
will otherwise sit on the same line of the same report, and this repository
has already retired a criterion because two resources shared one word. The
rename is Swift only. No column changes name, no stored value changes, and
`ReserveState` keeps its names because only one sense of the word ever appears
there.

A reviewer could reasonably refuse the rename on the grounds that it touches
the no-double-pay path for a documentation problem. The counter-argument is
that there is no executable and no released consumer, so this is the cheapest
this rename will ever be, and the compiler finds every site.

## 2. Unpausing that cannot hand out a second day

This is a test, and the design is what the tests assert and what they must
fail against. No production code changes. If a reviewer decides `unpause`
should also clear something else one day, these are the assertions that have
to be argued with first.

| Test | Asserts | Must fail against |
|------|---------|-------------------|
| The existing budget-spent test, with the criterion cited by id | The next reservation after an unpause still refuses | Any change that lowers the counter on unpause |
| Unpause after a provider refusal | The whole snapshot is identical either side of the unpause except the pause fields | Zeroing the counter, subtracting from it, or moving the day start forward, on the path where the breaker was tripped by the provider rather than by the budget |
| Unpause writes nothing down | The budget store's write count and stored figure are unchanged after an unpause and a flush | A future unpause that "tidies up" by rewriting the day's count, which would let a repeated unpause walk the persisted figure downward |
| Unpause returns no caller's share, added when section 3 lands | A caller at their limit is still at their limit after an unpause | The most likely way this promise dies: per-caller state in the same actor, and an unpause that generously clears all of it |

Comparing whole snapshots rather than only observing the next throw is the
point of the second row. A change that returned half the day's budget would
pass the existing test whenever the returned half was smaller than what was
already spent, and fail this one.

The provider-refusal path is the one worth adding because it is the one
somebody would try to exploit: the budget-spent pause arrives with the counter
at its ceiling, where there is nothing to gain, while the provider pause
arrives with the counter anywhere at all.

## 3. A share of the day for one caller

### The unit

A reservation names its caller as one of two cases: work done on behalf of a
member, carrying an opaque identifier, or the instance's own work, carrying a
short job name. Only the first is rationed.

Two cases rather than three. A third case for an operator was considered and
dropped: operator-ordered work is the instance doing what the operator asked,
the operator's budget is the one being spent, and every spending surface is
already gated by the admin allowlist, so a separate case would add a decision
for the host to get wrong without adding a rule. If a later change wants
operator work rationed differently, a case is cheap to add and the compiler
will find every site.

The parameter has no default value. A default would mean a host that forgets
gets the unrationed path silently, which is the whole feature bypassed by an
omission. Making the call site say which side of the rule it is on is the same
instinct as `valueEvenIfShort`, which is named so that reaching for the
dangerous one is visible in review.

The identifier is opaque here. The expectation, stated in the documentation
rather than enforceable from this layer, is that a host passes the key its own
store minted: nothing below the chat boundary holds an identifier that came
from a person, the set of possible callers is then bounded by the membership,
and a caller id cannot be forged from outside to get a fresh allowance.

### The share

Two variables, both optional, both defaulted, both refusing an unusable value
at boot in the style the rest of this layer already uses.

| Variable | Meaning | Default |
|----------|---------|---------|
| caller share percent | The share of the day's budget one member may draw, as a percentage. Zero turns shares off. Above one hundred is refused. | 5 |
| caller burst requests | The most one member may take in a burst, before their allowance has to refill. | 10 |

From those two the share derives a sustained rate of that percentage of the
day's budget spread over a UTC day, and a capacity of the burst figure capped
by the daily share. With no daily budget set there is no share at all, because
the criterion is about spending the day's budget and there is no day's budget
to spend a part of.

A percentage rather than an absolute count because a project-neutral bot is
pointed at free tiers and paid tiers whose budgets differ by orders of
magnitude, and one absolute number is wrong at one end or the other. A burst
alongside it because "however fast they type" is a rate problem: a pure daily
quota lets a member empty their share in ten seconds and then locks them out
for the rest of the day, which reads to the member as the bot being broken.

A pure per-day quota was the other serious option and it was rejected on a
second ground as well. To be honest across a crash loop it would have to be
persisted, which means a row per member per day, a new table, a new migration
and a new cascade obligation, and a write in front of every member read. A
refilling allowance held in memory costs a restart at most one burst per
caller, and the day's count itself is persisted and restored, so no restart
trick creates requests out of nothing.

### Where the check lives, and in what order

Inside `RequestGovernor`, not beside it. The governor is already the single
place that says yes or no to a request, and a second gate a caller could
forget to ask is a hole with a nice name. The arithmetic goes in a pure value
beside the actor, the way `TokenBucket` sits beside `RequestRateLimiter`, so
the boundaries are tested by something that finishes instantly.

The order inside a reservation is:

1. Is the process paused? If so, refuse with the pause. An instance refusing
   everybody must tell everybody the same story, or the member goes away with
   the wrong one.
2. Is this a member caller, with a budget set and shares switched on? If so,
   take from their allowance, all of it or none. A refusal here spends nothing
   of the day, trips nothing, and pauses nothing.
3. Take from the day's budget, exactly as today.

An all-or-nothing reservation from a member caller is charged whole against
the allowance, with no special case: a member cannot order an indivisible job
larger than their burst, which is the right answer rather than an awkward one.

Time arrives as the `now` parameter the governor already threads, which is the
wall clock rather than the monotonic one the per-second limiter uses. That is
deliberate: a share is scaled to a day and has to agree with the UTC day the
budget counts. The hazards are stated and handled. A clock moved backwards
grants no refill, because elapsed time is guarded at zero, and a clock moved
forward refills to capacity and no further.

### Where the caller is threaded

Every request is spent in one place, the private reserve-and-run helper inside
`ChainReader` (`Sources/Chain/ChainReader.swift:198`), and that helper can only
charge somebody it has been told about. So the caller has to arrive at
`ChainReader`'s public reads, and through `BatchedChainReader` and
`WalletCheckCache`, which are what a host actually calls.

An explicit parameter on each public read, with no default, rather than a
per-caller view of the reader bound once and reused. The view reads better at
a single call site and it is a lie at the important one: the cache reads a
batch of wallets belonging to many members during a sweep, and a view bound to
one caller would either charge the sweep to a member or charge a member's
command to the sweep. An explicit parameter also keeps the decision in the
diff, where a reviewer sees it.

### Memory, and what the operator sees

Allowances are held in a bounded map. A caller whose allowance is full again
is indistinguishable from a caller nobody has heard of, so full entries are
dropped, which means the map holds roughly the callers who have been active
recently. A hard ceiling on tracked callers sits above that, a constant rather
than a setting. At the ceiling a caller nobody is yet tracking is refused
rather than admitted untracked, because admitting untracked callers is the hole
this exists to close, and a caller who is already tracked is never evicted to
make room, because an evicted caller returns with a full allowance and that is
the exploit. Reaching the ceiling records one notice for the day and means
something is very wrong; the day's budget is the backstop underneath it either
way.

Throttling shows up as a count of refusals today on the budget snapshot, which
is the one value every surface already reports so that the health answer and
the status command cannot disagree. It does **not** show up as a notice per
refusal: a refusal that repeats thousands of times would push the pause
announcement out of the buffer an operator reads exactly when things are
already bad, which is the reasoning the module already records for the
does-not-fit refusal.

A new error case carries the instant the caller's next request would be
allowed. The wording of what a member is told is the host's, because this
layer writes for operators.

### What this does not do

It bounds one caller. Twenty members each staying inside their share can still
finish a small day's budget between them, and nothing in the documentation may
imply otherwise. RUN-11 asks for one member, and that is what is being built.

## 4. A health answer that costs nothing

### What is added

The report gains the day's budget, taken from the same snapshot every other
surface reports. The status keeps its two cases and stays about reachability:
an instance that has reached everything and is nonetheless refusing chain work
answers `ok` with a budget section saying the day is spent or the breaker is
tripped and when it returns. The JSON body gains a section for the budget,
appended after the existing keys, and stays hand built, because the shape of
that string is what a monitoring check greps for.

Assembly comes in two forms. A pure one takes values the caller already holds,
for a host that has them. An asynchronous one asks the governor for its
snapshot, which costs nothing and works while paused, and asks the proof probe
for its proof when one is configured. Neither touches the reader, the batched
reader or any data source, and the test for that is a data source double that
records every call and a call log asserted empty.

A third status for a throttled instance was the alternative and it was
rejected. The argument for it is real and is SEE-1's own: an operator's one
check has to tell them the bot is not doing its job, and a section somebody has
to know to read is weaker than a status. Three things decide it the other way.
The status is what a deploy gate and a container check read, and a version that
has merely spent its provider quota is not a bad deploy, so failing the gate on
it would replace a working version for no reason (RUN-3). It is a published
enum and a grep-able body, so the change lands on everybody who reads either.
And the runtime change being defined alongside this one maps 200 against 503
from reachability today, so a third value would oblige it to change its mapping
mid-flight for a fact its own body already carries. What is written down
instead of the third value is the readiness contract: an unreached component is
not ready, a reached instance with no budget left is ready, and the budget
section is what monitoring alerts on. If somebody still wants the third status,
it is its own change with its own criterion.

### The probe, and what "costs nothing" means

SEE-1.b says the check must not spend the day's budget for reading the chain.
The proof probe is already outside the governor by design and caches its
answer for a configured lifetime, so a monitoring check on a timer does not
become traffic. Two things make the promise honest rather than a technicality.
An operator who names no proof headers gets an answer that opens no socket at
all, and that is the path the zero-request test uses, so the test proves the
assembly rather than the cache. And a probe that fails never fails the answer:
proof simply goes missing, which is the rule the probe already follows.

The assembler does not skip probing when the instance is paused. The endpoint
being probed is the operator's choice and may well be the one that reports the
refusal, and a probe that fails costs a short timeout and nothing else.

### The boundary with the runtime change

Written here because the risk is not that either side builds the wrong thing,
it is that each assumes the other owns it and neither builds anything.

| This change, in `Chain` | The runtime change |
|-------------------------|--------------------|
| The budget and pause facts on the report, and the rule that they are a field and never a status | The listener, its path and its HTTP status codes, mapping an unreached component to a failure and a reached-but-throttled instance to a pass |
| Both assembly forms, touching no reader and no data source | The component list, which only the composition root knows: the chat gateway, the store, whatever proves wallets |
| The JSON body | When the listener binds relative to identifying to the chat gateway |
| The tests that the assembly spends no request and still answers when the budget is gone | The test that the endpoint still answers once the budget is gone, which is the other half of SEE-1.b |
| Nothing about who calls a read | Naming the instance's own work on the boot gate's `verifyAssetDecimals`, once section 3 makes the caller required |

The runtime change adds no health vocabulary of its own, and its
REQ-runtime-032 says so from its side. If it finds it needs one, that is a
signal that this table is wrong and both definitions move together.

## Spec and test impact

| Contract | What moves |
|----------|-----------|
| `specs/reserve/` | The new charge value and the record's and outcome's new members in the public API table. An invariant stating that a run records the ceiling it was measured against before the first payment, and that a resumed run appends rather than overwrites. The two senses of "period" stated once, in one place. A change log row. |
| `specs/store/` | The new table in the schema, the conformance behaviours that cover the round trip and the old row that predates the field, and a note that a missing key in an older encoded record decodes as no charges rather than throwing. A change log row. |
| `specs/chain/` | The caller identity, the two new variables, the new error case, the new snapshot member, the budget on the health report, the rule that a spent budget is a field rather than a status, and the assembly. Invariants for the order of the checks inside a reservation, for a refused caller costing nothing, and for a health answer spending nothing. A change log row. |

Test targets touched: the reserve runner and store suites, the store
conformance kit and both of its backends, and the chain governor and health
suites. Every test stays offline, with no clock read and no network, which is
the condition the whole test suite already meets.

## Decisions a reviewer might reverse

1. Charges are a list, not one key. Simpler is wrong in the boundary case.
2. The charge records the spending period, not the cadence period. The cadence
   gap for old epochs is real and is left open.
3. A new table rather than a column or a fourth claim kind. Reversibility and
   not touching the no-double-pay table decided it.
4. The cadence rename in the runner and the outcome. Cheapest now, and a
   reviewer may still say it is not this change's business.
5. Two caller cases, not three. Operator work rides with the instance.
5a. An explicit caller on every read rather than a reader bound to one caller,
   because the batching cache serves a sweep and a member from the same call.
6. A refilling allowance in memory rather than a persisted daily quota. Costs
   one burst per restart, saves a table and a write per read.
7. A percentage plus a burst, rather than one number. Two knobs to explain,
   and both ends of the budget range work.
8. Refuse rather than queue at the share, which follows the module's existing
   character and keeps a chat interaction from timing out.
9. A budget section rather than a third health status, paid for by an operator
   having to alert on a field, and bought with a readiness contract written
   down for the runtime change rather than assumed.
10. Throttling is a counter on the snapshot, not a notice, to keep the notice
    buffer readable during an incident.

## Unsettled

- The default numbers for the share. Five percent and a burst of ten are
  chosen to be safe on a small budget rather than measured, and the first
  operator to run this at scale will have a better number than this document
  does.
- Whether the new health status should also appear when the per-caller
  refusal count is high. It is a sign of a raid rather than of the instance
  being unwell, and it is left out until somebody has seen one.
- The cadence period of an old epoch remains unanswerable, because the state
  keeps only the latest per stream. Recording it per epoch is a one-line
  addition to the same charge row, and it is deliberately not taken here
  because SPEND-9.c asks about the ceiling.
