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
  (SEE-9, SEE-11).

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
body.

- Covered by `ChainHealthTests.swift` (SEE-1, SEE-1.a, SEE-10.a, HOST-5.a).

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
