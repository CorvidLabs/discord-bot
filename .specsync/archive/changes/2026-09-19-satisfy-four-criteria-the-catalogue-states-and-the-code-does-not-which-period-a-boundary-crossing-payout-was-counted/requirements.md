---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: requirements
---

# Requirements

Four criteria in `hi/` promise something the library targets do not do. This
document says what has to become true for each, in a form somebody can test.
Every claim below about the current code was checked by reading it at the
change's base commit, and the file and line are cited so a reviewer can
disagree with the reading rather than with the conclusion.

One of the four turned out to be in a different state from the one the change
brief describes, and that is written up honestly under **RUN-10.a** rather
than being padded out into work.

Requirement ids are stable. They are not `hi` ids: each requirement cites the
catalogue criterion it serves, and several requirements can serve one
criterion.

## What is already true, and what is not

| Criterion | State at the base commit |
|-----------|--------------------------|
| SPEND-9.c | Not met. The epoch record carries two timestamps and no period, and the spending period is thrown away once it has been checked. |
| RUN-10.a | Behaviour already correct, and already guarded by a test that would fail if it broke. What is missing is the citation and two uncovered paths. |
| RUN-11 | Not met. There is one counter for the whole process and no notion of who a request is for. |
| SEE-1.b | Half built. The pieces exist and are deliberately outside the budget; nothing assembles them into an answer, and no test pins the promise. |

---

## 1. Which period a payout was counted against (SPEND-9.c)

### What the code does today

`ReserveEpochRecord` carries `startedAt` and `completedAt`
(`Sources/Reserve/ReserveEpochRecord.swift:39` and `:42`) and nothing else
about time. `ReserveSpendLimits.periodKey`
(`Sources/Reserve/ReserveSpendLimits.swift:31`) is read in exactly one place,
into the refusal `ReserveError.spendLimitsExpired`
(`Sources/Reserve/ReservePlanner.swift:282`), and is dropped on the floor when
the check passes, which is the case that matters. So an operator whose payout
ran from Sunday evening into Monday has two timestamps and no answer, which is
the arithmetic SPEND-9.c exists to abolish.

There is a second, unrelated period in the same module and it must not be
confused with this one. `ReserveRunner.run(streamId:recipients:periodKey:now:)`
(`Sources/Reserve/ReserveRunner.swift:148`) takes a **cadence** period, the
ISO week or month that stops one schedule being paid twice, and stores it in
`ReserveState.lastPeriodKeys`. The **spending** period is the host's ceiling,
and it is the one SPEND-9 is about. Nothing today records either of them
against a particular epoch: the state keeps only the latest cadence key per
stream, so even that is unanswerable for an epoch from two months ago.

### Requirements

- **R-PERIOD-1** (SPEND-9.c) An epoch's stored record names the spending
  period that each run of that epoch was measured against. Test: run an epoch
  with limits whose `periodKey` is a known value, load the record back through
  `ReserveStore`, and read that value off it without consulting any timestamp.

- **R-PERIOD-2** (SPEND-9.c, SPEND-5.b, RESERVE-6.a) The period is written to
  the store **before the first payment is attempted**, on the same claim
  before pay discipline the epoch row already follows. Test: a payer double
  that throws on its first call leaves a stored record that already names the
  period.

- **R-PERIOD-3** (SPEND-9.c, SPEND-9.a) An epoch that was cut off and resumed
  in a later spending period names both periods, in the order they were
  charged, with the whole-unit figure each run was checked for. A single value
  would be a lie in exactly the case the criterion was written for. Test: run
  an epoch to a payer that dies part way, re-run it with limits naming a
  second period, and read two charges back in order.

- **R-PERIOD-4** (SPEND-9.c) A host that states no spending limits produces no
  charge, and nothing anywhere invents one. Test: run with
  `ReservePayer.spendLimits()` answering nil and assert the record's charges
  are empty and the report says no ceiling was in force.

- **R-PERIOD-5** (SPEND-9.c) The spending period and the cadence period never
  share a word in the public API, in a spec table or on anything an operator
  reads. This repository has already retired one criterion because two
  resources shared the word "allowance" (see the Retired section of
  `hi/see.md`), and the two senses of "period" are now close enough to appear
  on the same line of the same report.

- **R-PERIOD-6** (SPEND-9.c, ADOPT-5) An epoch row written by a build from
  before this change reads back cleanly, with no charge recorded, and is
  reported as not recorded. It is never inferred from `startedAt`, because
  inferring it is the timestamp arithmetic the criterion forbids and it is
  wrong precisely for the boundary-crossing epoch. Test: two of them, one per
  backend. For the JSON-backed store, decode a record encoded without the new
  key. For the SQLite store, open a file migrated to the previous schema
  version, apply the migrations, and read the epoch back.

- **R-PERIOD-7** (SPEND-9.c, RESERVE-8.a) The new fact round-trips through
  every `ReserveStore` implementation, proved by the shared conformance suite
  rather than by a test per backend, and the migration that carries it has a
  real reverse. Test: new `StoreConformance.Behaviour` cases, run by both the
  in-memory and the SQLite conformance targets; the existing revert-everything
  migration test covers the reverse.

- **R-PERIOD-8** (SPEND-9.c, RESERVE-7.a) `ReserveEpochOutcome` carries the
  charges, so a host can report which ceiling the run was counted against
  without a second read of the store. This repository has no operator surface
  yet, so this value is where the answer has to arrive; drawing it on a card
  belongs to whichever change builds the surface.

---

## 2. Unpausing that cannot hand out a second day of budget (RUN-10.a)

### What the code does today, and the honest finding

**RUN-10.a already holds, and a test already fails if it stops holding.** The
change brief says nothing says so; that is not quite right, and saying so
plainly is cheaper than building something twice.

`RequestGovernor.unpause(now:)`
(`Sources/Chain/RequestGovernor.swift:170`) assigns `pauseEndsAt`,
`pauseCause` and `didAnnouncePause`, and appends one notice. It never touches
`budget`, and `DailyRequestBudget` exposes no way to lower its own counter:
`restore` takes the larger of what it holds and what it is handed
(`Sources/Chain/DailyRequestBudget.swift:178`) and `rollDayIfNeeded` zeroes it
only when the UTC day really changed (`:190`). The test
`unpauseDoesNotRefillTheBudget`
(`Tests/ChainTests/RequestGovernorTests.swift:209`) spends a budget of one,
lifts the pause, and asserts the next reservation still throws
`requestBudgetSpent`. Make `unpause` reset the counter and that test goes red.

So the work here is not a feature. It is closing the three gaps that would let
somebody make unpause more useful and lose the promise without noticing.

### Requirements

- **R-UNPAUSE-1** (RUN-10.a) The test that protects the criterion cites it by
  id in its name or its comment, so that somebody reading the test knows they
  are looking at a promise rather than at a convenience. Applies to the
  existing test as well as the new ones below.

- **R-UNPAUSE-2** (RUN-10.a) Lifting a pause caused by the **provider's own
  refusal** leaves the day's count exactly where it was. The existing test
  covers only the pause the process gives itself by spending the budget; the
  other way in is `recordRequestFailure` with a quota refusal
  (`Sources/Chain/RequestGovernor.swift:147`), and that path pauses with the
  counter mid day, which is the interesting one for anybody working out how to
  farm requests. Test: reserve some requests, trip the breaker with a quota
  refusal, unpause, and assert `snapshot.usedRequests` and
  `remainingRequests` are unchanged across the unpause.

- **R-UNPAUSE-3** (RUN-10.a) Unpausing changes nothing in the snapshot except
  the pause. Asserting the whole `RequestBudgetSnapshot` before and after,
  rather than only that the next reservation throws, is what makes the test
  fail against a change that returns *some* of the day rather than all of it.
  It must fail against three mutations: zeroing the counter, subtracting any
  amount from it, and moving `dayStart` forward.

- **R-UNPAUSE-4** (RUN-10.a, RUN-8.b) Unpausing writes nothing to the
  `RequestBudgetStore`, so an unpause cannot lower the count a restart reads
  back. Test: unpause with an in-memory budget store attached, flush, and
  assert `writeCount` did not move and the stored count is unchanged.

- **R-UNPAUSE-5** (RUN-10.a, RUN-11) Once per-caller shares exist, unpausing
  hands a caller back none of their share either. This is the concrete way the
  promise is most likely to be lost: the share lives in the same actor, and
  "give everybody their allowance back when the operator lifts a pause" is a
  plausible and wrong thing for the next person to write. The assertion is
  added to the same tests when the share lands, which is why the unpause tests
  are built before the share and not after it.

---

## 3. A share of the day for one caller (RUN-11)

### What the code does today

`RequestGovernor` holds one counter for the whole process and its reservation
methods take a clock and nothing else
(`Sources/Chain/RequestGovernor.swift:86` and `:125`). Nothing in the module
knows who a request is for, so nothing can bound one caller.

The nearest thing that exists is the per-wallet cooldown in
`WalletCheckCache` (`Sources/Chain/WalletCheckCache.swift:24` and `:36`),
whose own comment says the caller "is often a member typing in a channel and
there is no upper bound on how fast people type". That bounds **one wallet**,
not one member. At the shipped default of sixty seconds a member with ten
proved accounts can draw ten reads a minute all day, which is fourteen
thousand four hundred requests, more than the whole daily budget most
operators will set. RUN-11 is genuinely unmet.

### Requirements

- **R-SHARE-1** (RUN-11) Every reservation names who it is for, and there is
  no default. A host that forgets does not compile. The identity is a small
  closed set of cases rather than a free string, so which side of the rule a
  call sits on is visible in review.

- **R-SHARE-2** (RUN-11) Only work done on behalf of a member is rationed. The
  instance's own work, which includes the role sweep, a scheduled payout and
  anything an operator ordered, is not. A sweep is not a member, cannot type
  fast, is already bounded by its batch size and its interval, and rationing
  it to one member's share would break the product's main job in order to
  protect it. The reason is written into the type's documentation, not only
  here.

- **R-SHARE-3** (RUN-11, ADOPT-1) The share is configuration with a default
  that needs no thought: a percentage of the day's budget, plus a maximum
  burst in requests. A percentage rather than a fixed count because operators'
  budgets differ by orders of magnitude between a free tier and a paid one,
  and a count that is sensible for one locks members out of the other. A burst
  as well as a rate because "however fast they type" is a rate problem, and a
  daily quota alone locks a member out for fifteen hours after a busy morning.
  Both variables refuse an unusable value at boot and name themselves in the
  refusal, as every other variable in this layer does.

- **R-SHARE-4** (RUN-11) With no daily budget set there is no share, because
  there is no day's budget to spend a part of. Setting the percentage to zero
  turns shares off, consistent with every other zero in this layer meaning
  off. A percentage above one hundred is refused at boot rather than clamped.

- **R-SHARE-5** (RUN-11) A caller who has reached their share is **refused**,
  at once, with a typed error carrying the instant at which their next request
  would be allowed. It is never queued. The governor already refuses rather
  than queues and says why (`Sources/Chain/RequestGovernor.swift:12`), and a
  queued read holds a chat interaction open until it times out, which turns a
  throttle into a visible failure.

- **R-SHARE-6** (RUN-11, SEE-9) A refused caller spends nothing of the day's
  budget, trips no breaker and pauses nothing. The rest of the day belongs to
  everybody else. This is the same rule `notEnoughBudget` already follows
  (`Sources/Chain/DailyRequestBudget.swift:97`).

- **R-SHARE-7** (RUN-11, HOST-2) The caller identifier is opaque to this
  layer. Nothing that came from a chat account reaches it, it is never logged,
  never persisted by this layer and never appears in an error message or a
  notice. The expectation that a host passes the key its own store minted is
  stated in the type's documentation.

- **R-SHARE-8** (RUN-11, RUN-8.b) The tracking is bounded in memory and a
  restart cannot be farmed. A restart may hand a caller at most one fresh
  burst, never a fresh day, because the day's count itself is persisted and
  restored. A caller whose allowance is full again carries no information and
  is forgotten. Test: fill a caller's share, advance a day, and assert the
  tracking no longer holds them.

- **R-SHARE-9** (RUN-11, SEE-9, SEE-5) An operator can see that throttling is
  happening, from the same snapshot every other budget figure comes from, and
  a throttled caller does not produce one notice per refused request. A
  refusal that repeats thousands of times must not push a pause announcement
  out of the buffer an operator reads when things are already bad, which is
  the reasoning already recorded at
  `Sources/Chain/RequestGovernor.swift:250`.

- **R-SHARE-10** (RUN-11, SEE-11) The pause is checked before the share, so an
  instance that is refusing everybody tells everybody the same story rather
  than telling one member their share is spent.

- **R-SHARE-12** (RUN-11) The caller reaches the governor from the call that
  started the work. Every public read on `ChainReader`, `BatchedChainReader`
  and `WalletCheckCache` names its caller, with no default, because the single
  choke point that spends a request
  (`ChainReader`'s private reserve-and-run helper at
  `Sources/Chain/ChainReader.swift:198`) can only charge somebody it was told
  about.

- **R-SHARE-11** (RUN-11) The honest limit is written down: this bounds one
  caller, which is what the criterion asks for. It does not bound a crowd, and
  nothing in the documentation or the report may suggest that it does. Twenty
  members each inside their share can still finish a small day's budget, and
  the day's budget is the backstop for that.

---

## 4. A health answer that costs nothing (SEE-1.b)

### What the code does today

More exists here than the change brief suggests, and the gap is narrower and
sharper than "no health surface".

- `ChainHealthReport` (`Sources/Chain/ChainHealth.swift:147`) already answers
  what the instance has reached, with `status`, `waitingOn` and a hand-built
  `jsonBody`. It carries no budget and no pause.
- `ProviderProofProbe` (`Sources/Chain/ProviderProofProbe.swift:27`) is
  deliberately outside the request governor and says so in its own
  documentation at `:23`, and caches its answer for
  `ChainCacheLifetimes.healthProbe`, which defaults to thirty seconds
  (`Sources/Chain/ChainConfiguration.swift:403`).
- `RequestGovernor.snapshot(now:)` (`Sources/Chain/RequestGovernor.swift:198`)
  costs nothing and works while paused.

So the parts are there and they are the right parts. What is missing is that
nothing puts them together, the answer cannot state the budget, no test
asserts that assembling an answer moved no counter, and no test assembles one
after the budget is gone. `ChainConfiguration.cacheLifetimes.healthProbe` is
configured and read by the probe, and no health answer exists for it to serve.

### Requirements

- **R-HEALTH-1** (SEE-1.b) A health answer can be assembled without spending a
  request from the day's budget. Test: assemble one against a governor with a
  budget and a data source double that records every call
  (`Tests/ChainTests/ChainFixtures.swift:196` and the `CallLog` at `:172`);
  assert the call log is empty and `snapshot.usedRequests` is the same before
  and after.

- **R-HEALTH-2** (SEE-1.b) The answer still comes back once the budget is
  gone, and once the provider has refused, and says which of the two it is.
  Test: spend the budget, assemble, and assert a report comes back naming the
  spent budget; separately trip the breaker with a quota refusal, assemble,
  and assert the report names the provider.

- **R-HEALTH-3** (SEE-1.b, SEE-9) The answer states the day's budget from the
  same `RequestBudgetSnapshot` every other surface reports, so a health page
  and a status command cannot disagree about how much is left.

- **R-HEALTH-4** (SEE-1.b, SEE-1.a, RUN-3) The status keeps the two cases
  `ChainHealthStatus` has today and stays about reachability. An instance that
  has reached everything and is refusing chain work, because the day's budget
  is spent or the breaker is tripped, answers `ok` and says so in the body as a
  field; it is not a third status and it is not `starting`. The readiness
  mapping is stated as part of the contract, because the deploy gate and the
  runtime change both read it: an unreached component is not ready, and a
  reached instance whose budget is gone is ready. Otherwise a gate would roll
  back a perfectly good version because its provider quota ran out at four in
  the afternoon, which is RUN-3's failure by the other door. SEE-1.a is served
  by the body rather than the status: an operator's check tells them the budget
  is gone and when it comes back, in the same answer, and monitoring alerts on
  that field. A third status was considered and dropped: it is a published enum
  and a grep-able JSON shape, it would oblige the runtime change to change its
  HTTP mapping mid-flight, and no acceptance criterion of this change asks for
  it. If somebody wants one, it is its own change with its own criterion.

- **R-HEALTH-5** (SEE-1.b, SEE-10.a) An answer can be produced with no probe
  at all, and a probe that fails never fails the answer. An operator who names
  no proof headers gets a health answer that touches no socket of any kind.
  This is what makes R-HEALTH-1's test honest rather than a test of a cache.

- **R-HEALTH-7** (SEE-1.b) `ProviderProofProbe` offers a read that answers
  from what it already holds, **without making a request and without mutating
  the cache**, and it is that read the health path uses. This is a separate
  requirement because the existing `proof(now:)` refreshes when its value is
  stale, so a health answer routed through it would put a network call on the
  one path that must never make one, and would do it only sometimes: fine in
  every test, a surprise in production at the moment the cache expires. A
  reviewer should be able to name the method and see that the health path
  calls that one. The runtime change's REQ-runtime-017 depends on this
  existing; if this requirement is dropped, that one becomes unsatisfiable.

- **R-HEALTH-6** (SEE-1.b) The boundary with the runtime change is written
  down in both definitions, naming what each side ships, so that neither side
  can assume the other owns it. The list is in this change's design and is
  reproduced under **Boundary** below. A health answer that is assembled but
  never served satisfies nothing, and a listener with nothing to serve
  satisfies nothing either.

### Boundary

This change ships, inside `Chain`:

1. The budget and pause facts on the health report, and the rule in R-HEALTH-4
   that they are a field and never a change of status.
2. A pure assembly that takes values already held, and an asynchronous
   assembly that asks only the governor and, when one is configured, the proof
   probe. Neither touches `ChainReader`, `BatchedChainReader` or any
   `AccountDataSource`.
3. The JSON body, which stays hand built for the reason already recorded at
   `Sources/Chain/ChainHealth.swift:183`.
4. The tests for R-HEALTH-1, R-HEALTH-2 and R-HEALTH-5.

The runtime change,
`make-the-package-a-program-an-executable-a-composition-root-boot-gates-that-name-the-variable-to-fix-and-a-health`,
ships the listener, the path, the HTTP status codes, the order of binding
against connecting to the chat gateway, the component list (which only the
composition root knows), the probe's URL and its wiring, the deploy gate that
reads the answer, and the test that the endpoint answers once the day's budget
is spent. It consumes the types above and adds no health vocabulary of its own.
Its REQ-runtime-032 says the same thing from the other side, so the split is
written down in both definitions rather than in one.

There is a second edge between the two changes and it is not about health.
R-SHARE-12 makes every public read on `ChainReader` name its caller with no
default, and the runtime's boot gate calls `verifyAssetDecimals` before it
serves anybody. That call is the instance's own work under R-SHARE-2, so it
names a job and not a member. Whichever change lands second carries that
one-line edit; it is named here and in REQ-runtime-032 so neither side
discovers it in a failing build.

---

## Out of scope

- No operator-facing card, command or endpoint. There is no executable in this
  repository and this change does not add one.
- No rename of the cadence period key in `ReserveState`, where only one sense
  of the word exists and nothing else appears beside it.
- No per-member persistence of the share across restarts, and no per-member
  row in any store. R-SHARE-8 states what that costs and why the bound is
  accepted.
- Nothing about SEE-10, SEE-13 or naming which dependency is down. The probe's
  recorded failure is left where it is.
