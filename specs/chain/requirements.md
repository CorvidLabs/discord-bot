---
spec: chain.spec.md
---

## User Stories

- As a member, I want to keep the role I earned when the bot cannot see my
  balance right now, so that a provider having a bad minute is not the same
  thing as my having sold up (ROLE-1.a).
- As a member who has parked tokens in a liquidity pool, I want that to count
  toward my tier the same as what sits in my wallet, and I want a pool the bot
  could not read to leave me short rather than poor (ROLE-2).
- As an operator, I want which asset is read, at what precision, through which
  node and how hard, to be mine to set, with no default that is somebody
  else's (ADOPT-1.d, ADOPT-12, ADOPT-6.a).
- As an operator, I want to find out I have set it up wrong at boot, from a
  message naming the variable, rather than from a member asking why their role
  disappeared (ADOPT-2, ADOPT-12.a).
- As an operator, I want to see how much of today's budget for reading the
  chain is gone while there is still time to act on it, and I want a problem
  that started overnight to still be readable in the morning (SEE-9, SEE-5).
- As an operator, I want a health check that means the instance is working
  rather than that a process is listening, and one that tells me whose outage
  it is (SEE-1, SEE-1.a, SEE-10.a).
- As an operator, I want checking on the bot never to cost me the thing I am
  checking on, and to still get an answer once the day's budget for reading
  the chain is gone, because that is exactly when I am looking (SEE-1.b).
- As an operator, I want no one member, however fast they type, to be able to
  spend the day's budget for reading the chain on their own, and I want to see
  from the usual place that throttling is happening (RUN-11, SEE-9).
- As an operator, I want to start the bot reading the chain again by hand
  after a wrong refusal, without that handing it a second day's budget for
  anybody who works out how to ask (RUN-10.a).
- As a contributor, I want every failure path exercised without a network, a
  key or an account, so my first contribution does not begin with somebody
  trusting me with a secret (BUILD-2, BUILD-2.a).
- As an operator, I want the pools I wrote down in `POOL_n_` to be the pools
  the bot reads, with no field I have to invent to get from one to the other
  (ADOPT-1.b, ADOPT-2).
- As an operator, I want one set of rules for my environment, so that a number
  I can write in one variable is a number I can write in all of them
  (ADOPT-2).

## Acceptance Criteria

### REQ-chain-001

The module SHALL take the operator's token as a `Gating.TokenProfile` value and
SHALL declare no environment variable of its own naming the asset, its ticker
or its decimal places, so that the asset is read from the environment in
exactly one place in the package.

- Covered by `ChainConfigurationTests.swift` (ADOPT-1.d, ADOPT-8).

### REQ-chain-002

Converting whole tokens to smallest units SHALL be available in two named
forms whose overflow behaviour differs: the ladder's `baseUnits(whole:)` SHALL
saturate, and this module's `amountBaseUnits(whole:)` SHALL throw
`ChainConfigurationError.amountOverflows`. Neither SHALL be reachable by
overload resolution from the other, and both SHALL agree on every value that
fits.

- Covered by `TokenAmountTests.swift` (RAIN-15.b, ADOPT-2).

### REQ-chain-003

A token whose asset id is zero SHALL be refused by `ChainConfiguration.init`
with an error naming `TOKEN_ASSET_ID`, because zero names the chain's own
currency and an unset variable arrives as zero.

- Covered by `ChainConfigurationTests.swift` (ADOPT-2, ADOPT-7.a).

### REQ-chain-004

When `verifiesAssetDecimals` is on, `ChainReader.verifyAssetDecimals()` SHALL
read the asset's precision from the chain at boot and SHALL throw
`ChainError.assetDecimalsDisagree` when it differs from the configured value,
naming both numbers and the variables to correct. An asset the node has never
heard of SHALL throw rather than read as held by nobody.

- Covered by `ChainReaderTests.swift` (ADOPT-12.a, ADOPT-2).

### REQ-chain-005

Every figure that may be short SHALL be a `ChainReading`, and a value a caller
may act on SHALL be obtainable only from `completeValue` or
`requireComplete()`. Completeness SHALL survive `map`. A wallet that could not
be read SHALL be `unavailable` rather than zero, and one unreadable wallet
SHALL make a person's whole combined total short.

- Covered by `IncompleteReadingTests.swift` and `WalletCheckTests.swift`
  (ROLE-1.a).

### REQ-chain-006

A pool whose reserves could not be read SHALL be absent from the reserves map,
and a wallet holding that pool's token SHALL come back `short` with
`poolReservesUnavailable` rather than `complete(0)`. A pool's reserve account
SHALL never be read through the helper that answers a 404 with an empty
account.

- Covered by `BatchedChainReaderTests.swift`, `WalletCheckTests.swift` and
  `ChainReaderTests.swift` (ROLE-2).

### REQ-chain-007

Granting a collection role on a partial positive read SHALL be allowed;
removing one SHALL require a complete negative read, and an unreadable wallet
SHALL leave the role exactly as it is. An incomplete holdings read SHALL never
be written to a store as an empty one.

- Covered by `IncompleteReadingTests.swift` (ROLE-4.b, ROLE-1.a).

### REQ-chain-008

Every request against the node SHALL be reserved from a single
`RequestGovernor` before it leaves the process, and the same governor SHALL
count reads and signing. A spent budget and a provider quota refusal SHALL
both pause reads and signing until UTC midnight, SHALL remain distinguishable
as causes, and SHALL be liftable by hand without granting a budget that is
really spent.

- Covered by `RequestGovernorTests.swift` and `RequestBudgetTests.swift`
  (SEE-9, SEE-11, RUN-10.a).

### REQ-chain-009

The day's request count SHALL be written to `RequestBudgetStore` every
`budgetPersistEvery` requests and on exhaustion, SHALL be restored at boot only
when it belongs to the current UTC day, SHALL never reduce what this process
has already spent, and an unreadable row SHALL throw rather than read as
nothing recorded.

- Covered by `RequestGovernorTests.swift` and `RequestBudgetTests.swift`
  (RUN-8.a).

### REQ-chain-010

The per-second limiter SHALL hold to the configured rate using a monotonic
clock, SHALL never bank more than one second of requests however long it has
idled, SHALL raise a rate below one to one, and SHALL satisfy an ask larger
than its capacity a bucketful at a time rather than waiting forever.

- Covered by `RateLimiterTests.swift` (SEE-9).

### REQ-chain-011

A health report SHALL be `ok` only when every declared component has been
reached, SHALL name what it is waiting on otherwise, and SHALL carry provider
proof only from configured headers that were really present, dropping a stale
answer rather than serving it. Provider values SHALL be escaped in the JSON
body. The report SHALL carry what is left of the day's requests as a field,
taken from the same `RequestBudgetSnapshot` every other surface reports, and a
spent budget or a tripped breaker SHALL NOT change the status.

- Covered by `ChainHealthTests.swift` (SEE-1, SEE-1.a, SEE-10.a, SEE-9,
  HOST-5.a).

### REQ-chain-012

Anything an operator should read about the budget SHALL be a `ChainNotice`
value in a bounded buffer the host drains, announced once per pause rather
than once per refused request, and SHALL survive until it is drained.

- Covered by `RequestGovernorTests.swift` (SEE-5).

### REQ-chain-013

A pool position SHALL be valued by integer arithmetic that cannot overflow on
the way, SHALL round down, SHALL treat a near-maximum minted supply as the
circulating supply minus what the pool itself holds, and SHALL survive a zero
denominator and a holding larger than the supply without trapping.

- Covered by `PoolShareTests.swift` and `ChainReaderTests.swift` (ROLE-2).

### REQ-chain-014

Only a complete reading SHALL be cached, a wallet named twice in one list SHALL
cost one read, and a forced fresh read SHALL not override the cooldown.

- Covered by `WalletCheckCacheTests.swift` (SEE-9).

### REQ-chain-015

Every read of the chain SHALL go through `AccountDataSource`, time SHALL arrive
as a parameter everywhere a lifetime or a day boundary is decided, and the test
suite SHALL run with no network and no credentials.

- Covered by every suite in `Tests/ChainTests` and by `ChainFixtures.swift`
  (BUILD-2, BUILD-2.a).

### REQ-chain-016

There SHALL be exactly one `LiquidityPool` and one `CombinedBalance` in the
package, both in `Gating`, which is where their loaders and the rules that
read them live. This module SHALL extend them rather than declare rivals, and
a catalogue loaded from `POOL_n_` SHALL be usable by `WalletCheck.read` and
`BatchedChainReader.check` with no field a host had to invent.
`LiquidityPool.validate(_:)` SHALL refuse a pool token of zero, a pool whose
own token is the counted token, a pool paired with itself, and two pools
sharing an id.

- Covered by `ChainConfigurationTests.swift` (ADOPT-1.b, ADOPT-2, ROLE-2).

### REQ-chain-017

A `ChainReading` SHALL convert to a `Gating.Reading` by exactly one route, in
which `complete` becomes `known` and **both** `short` and `unavailable` become
`unknown`. `MemberHoldings.fromChain` SHALL build the rules' input from a
`[WalletCheck]`: one wallet short SHALL make the member's balance unknown, no
wallets at all SHALL be unknown rather than zero, the positions SHALL be all
or nothing, and a collection whose registry did not answer SHALL be left out
so its roles are held. Neither route SHALL offer a variant taking a default.

- Covered by `GatingBridgeTests.swift` (ROLE-1.a, ROLE-2).

### REQ-chain-018

This module SHALL read its environment through `Gating.NumberedEnvironment`,
so that digit separators, what counts as blank, trailing whitespace including
newlines, and what makes a URL usable are decided once for the package. A node
URL without a host SHALL be refused at boot rather than failing every read
afterwards.

- Covered by `ChainConfigurationTests.swift` (ADOPT-2).

### REQ-chain-019

A caller whose work cannot be half done SHALL be able to reserve a whole job's
requests in one piece. `RequestGovernor.reserveRequests(_:now:)` SHALL take all
of them or none; a reservation larger than what is left of the day SHALL be
refused with `ChainError.requestBudgetCannotCover` without spending a request,
without pausing, and without recording a notice, so the remainder still reaches
the callers that read one request at a time. A day with nothing left SHALL pause
as a single request would. There SHALL be no way to hand a reservation back, and
`remainingRequests` SHALL answer nil rather than zero when no budget is set.

- Covered by `RequestGovernorTests.swift` and `RequestBudgetTests.swift`
  (SEE-9, RESERVE-7.d, RUN-8.a).

### REQ-chain-020

Every reservation of a request SHALL name the caller it is made for, with no
default value, and that caller SHALL be a closed set of cases separating work
done on behalf of a member from the instance's own work. A member caller
SHALL be held to a share of the day's request budget, configured as a
percentage of that budget together with a maximum burst, and that share
SHALL refill as the day passes rather than being withheld until the next day.
A member caller who has drawn their share SHALL be refused at once with a
typed error carrying the instant at which their next request would be allowed,
and SHALL NOT be queued. A refusal at the share SHALL spend nothing of the
day's budget, SHALL NOT pause the instance, SHALL NOT appear in the notice
buffer an operator drains, and SHALL leave every other caller unaffected. The
instance's own work SHALL carry no share, because a sweep, a scheduled payout
and anything an operator ordered are already bounded by their own batch and
interval and are not one person typing. Where no daily request budget is set
there SHALL be no share at all, since there is no day's budget to take a part
of, and this SHALL be stated where an operator reads the defaults rather than
left to be discovered. A configured share above one hundred percent SHALL be
refused at boot, naming the variable to correct. A pause SHALL be checked
before a share, so an instance that is refusing everybody tells every caller
the same reason. The caller identifier SHALL be opaque to this module,
SHALL NOT be logged, persisted or repeated in an error or a notice, and this
module SHALL bound one caller only, never a crowd.

The tracking itself SHALL be bounded in memory. A caller whose share has
refilled completely carries no information and SHALL be forgotten, so that the
table holds only callers currently drawing on the day and cannot grow with
every member who touched the bot since midnight. Forgetting a caller
SHALL NOT hand them a fresh share beyond what refilling had already restored.
Where the number of tracked callers reaches a bound, a caller not already
tracked SHALL be refused rather than admitted untracked, and a caller already
tracked SHALL NOT be evicted to make room, because evicting the caller who is
drawing hardest is the way an attacker buys themselves a new allowance.

Throttling SHALL be visible to an operator in the same snapshot every other
budget figure comes from, naming how many callers are currently held and how
much of the day their shares have taken. A guard that refuses quietly is one
an operator cannot tell from a provider outage, and the negative rule above,
that a share refusal writes no notice, is about not drowning the notice buffer
rather than about hiding the fact that throttling is happening.

Acceptance Criteria
- `CallerShareTests` proves one member caller exhausts their own share and is
  then refused, while the day's counter shows only what they actually took
  (RUN-11).
- `CallerShareTests` proves a caller refused at their share leaves a second
  caller and the instance's own work succeeding at the same instant (RUN-11).
- `CallerShareTests` proves reaching a share is not a pause: no pause is
  reported by the snapshot and no notice is recorded, however many times the
  caller is refused (RUN-11, SEE-5).
- `CallerShareTests` proves a share refills during the day, refills only to
  its burst however long a caller has been idle, and that an all-or-nothing
  reservation larger than what a caller has left takes nothing from the caller
  and nothing from the day (RUN-11, SEE-9).
- `CallerShareTests` proves the tracking is bounded: a caller whose share has
  refilled is no longer held, a newcomer at the bound is refused rather than
  admitted untracked, and a caller already drawing is never evicted to make
  room for one arriving (RUN-11).
- `CallerShareTests` proves the snapshot an operator reads names the callers
  currently held and what their shares have taken, so throttling cannot be
  happening invisibly (RUN-11, SEE-9).
- `CallerShareTests` proves that with no daily budget configured no caller is
  ever refused by a share, and that a restart hands a caller at most one fresh
  burst while the day's own count is restored from the store (RUN-11,
  RUN-8.b).
- `ChainConfigurationTests` proves the share and the burst take their
  documented defaults as literals, and that a share above one hundred percent
  refuses the boot naming the variable (ADOPT-1, ADOPT-2).

### REQ-chain-021

This module SHALL offer a health answer that can be assembled without
reserving a request from the day's budget and without touching any
`AccountDataSource`, and that answer SHALL still be produced once the day's
budget is spent or the provider has refused. A spent budget or a tripped
breaker SHALL be reported as a field of the answer, naming which of the two it
is and when reading resumes, and SHALL NOT change the health status, which
stays a statement about whether every declared component has been reached. The
budget figures on the answer SHALL come from the same `RequestBudgetSnapshot`
every other surface reports, so a health answer and a status reply cannot
disagree about what is left. An instance for which no provider proof is
configured SHALL produce an answer that opens no socket of any kind, and a
proof that could not be taken SHALL leave the answer without proof rather than
failing it.

Acceptance Criteria
- `ChainHealthTests` proves the governor's snapshot is identical in every
  field before and after an answer is assembled, and that a recording data
  source double is never called (SEE-1.b).
- `ChainHealthTests` proves an answer still comes back with the day's budget
  spent and the breaker tripped by a provider refusal, naming which it is and
  when it ends, with the status still reporting reachability (SEE-1.b,
  SEE-1.a).
- `ChainHealthTests` proves an instance with no budget configured reads as
  having no budget rather than as having none left (SEE-9).
- `ChainHealthTests` proves an answer assembled for an instance with no proof
  configured makes no call at all, and that a proof which failed leaves the
  answer without a provider section and invents nothing (SEE-1.b, SEE-10.a).

### REQ-chain-022

Lifting a pause by hand SHALL return no part of the day's spent request
budget. The day's count, what is left of it, the configured limit and the
start of the day SHALL each be unchanged across an unpause, whichever cause
tripped the pause and however many times the pause is lifted, including when
there was no pause to lift. An unpause SHALL NOT write to
`RequestBudgetStore`, so that a restart cannot read back a count an unpause
lowered, and SHALL return no part of any caller's share. The tests holding
this SHALL name the criterion they protect, so that a later author can see
they are looking at a promise rather than at behaviour that holds by accident.

Acceptance Criteria
- `RequestGovernorTests` proves the whole budget snapshot is equal either side
  of an unpause that follows a provider quota refusal, with the day's counter
  part way through rather than at its ceiling (RUN-10.a).
- `RequestGovernorTests` proves that lifting the same pause many times in a
  row at one pinned instant moves nothing, and that lifting a pause that was
  never set is not a refund either (RUN-10.a).
- `RequestGovernorTests` proves an unpause writes nothing to the budget store,
  and that a second governor restoring from that store starts with the same
  count already spent (RUN-10.a, RUN-8.b).
- `CallerShareTests` proves a caller who has drawn their share is still at
  their share after an unpause (RUN-10.a, RUN-11).

### REQ-chain-023

`ProviderProofProbe` SHALL offer a read that answers from the proof it already
holds, making no request and leaving its cache exactly as it was, and the
assembly that promises to spend nothing SHALL take its proof from that read
rather than from the one that refreshes a stale value. A held proof that has
passed its configured lifetime SHALL be reported as absent by that read rather
than refreshed by it, which is the rule this module already follows for a
stale proof.

Acceptance Criteria
- `ChainHealthTests` proves the held read makes no probe call and leaves the
  cached proof unchanged (SEE-1.b).
- `ChainHealthTests` proves a proof past its lifetime reads as absent through
  that read rather than being refreshed by it (SEE-1.b, SEE-10.a).
- `ChainHealthTests` proves the assembled answer takes its proof from that
  read, so nothing on the path that promises to spend nothing can make a
  request (SEE-1.b).

## Constraints

- Swift 6 with strict concurrency enabled. Every type crossing a concurrency
  boundary is `Sendable`.
- Platforms: macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1 and up. The floor
  is raised above the package's other targets by the rate limiter's use of
  `ContinuousClock`.
- No `Double`, no `NumberFormatter` and no locale-sensitive formatting anywhere
  near an amount. `Double` appears only in the rate limiter, where a rate is a
  rate.
- No force unwrap, no `try!`, no `as!`. Explicit access control on every
  declaration. Four-space indentation, opening brace on the same line.
- No logger, no database, no Discord type and no key material.
- No clock read inside a decision. `now` is a parameter.

## Out of Scope

- Deciding a role. What a balance earns is `Gating`'s. This module shares its
  types and builds its input, and imports no rule: `RoleRules` is never called
  from here.
- Loading a pool, a collection or a tier from the environment. Those loaders
  are `Gating`'s, and this module reads only its own `CHAIN_*` variables,
  through `Gating`'s helpers.
- Sending or signing anything. The governor counts signing requests on a
  host's behalf but nothing here holds a key.
- Storing anything. `RequestBudgetStore` is a protocol; there is no schema and
  no file format.
- Scheduling a sweep, and the rule that a sweep seeing almost nobody should
  refuse (ROLE-5.a). This module reports completeness; acting on it is the
  host's.
- Discovering pools, collections or tiers. They arrive as configuration.
