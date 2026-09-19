---
spec: chain.spec.md
---

## Automated Testing

`swift test --filter ChainTests` runs this target's suite: 230 tests in 14
suites, all offline. The whole package runs 694 tests in 48 suites, across
`Chain` (230), `Games` (167), `Gating` (133), `Reserve` (122),
`StoreSQLite` (29) and `Store` (26).

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `TokenAmountTests.swift` | Unit | The one token at the operator's precision, and the two whole-to-base conversions: saturating for a threshold, throwing for an amount, agreeing everywhere that fits. |
| `ChainConfigurationTests.swift` | Unit | The token arriving as a value rather than being read again, the refusal of asset id zero, every variable that has no default, every variable that has one, one set of rules for reading them, and the pool refusals. |
| `GatingBridgeTests.swift` | Unit | The join: a short reading becoming unknown rather than smaller, a member built from the wallets read for them, and the decision that holds a rung when a pool could not be read. |
| `ChainReaderTests.swift` | Unit | One account read: a 404 as a complete answer, a failed request as a refusal, the boot-time precision check, the pool reserve reads, and what each one costs from the budget. |
| `BatchedChainReaderTests.swift` | Unit | A whole community read at once: order preserved, one bad wallet not spoiling the others, a pool read once for the sweep, and the run stopping when the provider refuses. |
| `WalletCheckTests.swift` | Unit | Interpreting one wallet's holdings, pool positions counted, a missing pool leaving the total short, and adding a person's wallets up across every address they have linked. |
| `IncompleteReadingTests.swift` | Unit | The rule that a short reading is not an empty one, in all three places it is applied: tiers, collection badges and what may be written to a store. |
| `WalletCheckCacheTests.swift` | Unit | The cache and the cooldown: only complete readings remembered, a duplicate address costing one read, and a forced read still respecting the cooldown. |
| `PoolShareTests.swift` | Unit | Valuing a pool position in integers: rounding down, surviving a zero denominator and a holding larger than the supply, and two sides with different precision. |
| `RequestBudgetTests.swift` | Unit | The per-day brake on its own: counting, refusing, the warning thresholds, the UTC day boundary and restoring a count written earlier in the same day. |
| `RequestGovernorTests.swift` | Unit | The one counter and one breaker shared by reading and signing, the two pause causes, lifting a pause by hand, persistence, and the notice buffer. |
| `RateLimiterTests.swift` | Unit | The per-second brake: a full bucket, an idle hour buying nothing, a clock stepped backwards, and an ask larger than the bucket finishing rather than hanging. |
| `ChainHealthTests.swift` | Unit | A health answer that is not "the process is alive", provider proof that is configured, escaped, cached briefly and never invented, the read that answers from what is held without probing, the refresh that fills it beside an answer rather than in front of one, and an answer assembled without spending a request that still comes back once the budget is gone. |
| `CallerShareTests.swift` | Unit | One member's share of the day: the arithmetic with no clock, one caller refused while everybody else is served, a refusal that pauses nothing and says nothing, a job no burst can hold refused with no date at all, a share that refills during the day and grants nothing back for a clock stepped backwards, the bounded tracking and what an unpause and a restart do not hand back. |
| `ChainFixtures.swift` | Fixture | The token, the configuration, the pools and the stub data source and probes every suite reads through. Nothing here can reach a network. |

## Requirement Coverage

| Requirement | Test File | Test Names |
|-------------|-----------|------------|
| REQ-chain-001 | `ChainConfigurationTests.swift` | "The token is handed in rather than read again, so there is one asset id in the process"; "With only the required variables set, the brakes take their documented defaults" |
| REQ-chain-002 | `TokenAmountTests.swift` | "An amount too large to count in smallest units refuses instead of wrapping"; "A threshold too large to count saturates instead, so the rung is unreachable rather than free"; "The two conversions agree on every amount that does fit"; "A token with two decimal places is not quietly given six" |
| REQ-chain-003 | `ChainConfigurationTests.swift` | "An asset id of zero is refused, because an unset variable arrives as zero" |
| REQ-chain-004 | `ChainReaderTests.swift` | "An asset whose precision disagrees with the configuration refuses to start"; "An asset whose precision matches lets the process carry on"; "An asset that does not exist on this node refuses to start"; "An operator who turns the check off spends no request on it" |
| REQ-chain-005 | `IncompleteReadingTests.swift`, `WalletCheckTests.swift` | "A complete reading hands over its number"; "A short reading refuses to hand over a number that may be acted on"; "A reading that never arrived has no number at all"; "Completeness survives being transformed, so nothing looks whole again on the way out"; "A wallet that could not be read holds nothing known, rather than nothing"; "One unreadable wallet makes the whole person's total short, not just that wallet's" |
| REQ-chain-006 | `BatchedChainReaderTests.swift`, `WalletCheckTests.swift`, `ChainReaderTests.swift` | "A pool that could not be read leaves its providers short instead of poor"; "A pool whose reserve account is not there leaves its providers short, not empty"; "A pool whose reserves could not be read leaves the total short, never smaller"; "A pool whose reserve account the node has never heard of refuses rather than reading empty"; "A pool token that names no account refuses rather than reporting an empty pool" |
| REQ-chain-007 | `IncompleteReadingTests.swift` | "Holding one of them grants the role even when another wallet could not be read"; "A wallet that could not be read never takes a collection role away"; "A complete read of somebody holding none of them does take the role away"; "A catalogue that did not answer decides nothing either way"; "A failed read is never written down as a wallet that holds nothing"; "A completed read is written down, including a wallet that really holds nothing" |
| REQ-chain-008 | `RequestGovernorTests.swift` | "Reading and signing spend the same budget, so the number is the whole process"; "A spent budget refuses the next request before it leaves the process"; "A provider refusing on quota pauses everything, not just the caller that saw it"; "An operator can lift a pause that turned out to be wrong"; "Lifting a pause does not hand back a budget that really is spent (RUN-10.a)"; "A pause ends by itself when the day rolls over" |
| REQ-chain-009 | `RequestGovernorTests.swift`, `RequestBudgetTests.swift` | "A restart picks the day's count back up instead of starting over"; "A crash loop cannot loosen the ceiling one restart at a time"; "The count is written every so often rather than on every single request"; "The count is written the moment the budget runs out, not only on a schedule"; "A count that cannot be read refuses to start rather than starting the day again"; "Yesterday's count is not spent against today"; "A restored count never undoes requests this process has already made" |
| REQ-chain-019 | `RequestGovernorTests.swift` | "Work that cannot be half done takes its requests up front or does not start"; "A reservation the day cannot cover spends nothing and pauses nothing (SEE-9)"; "A day with nothing left pauses whatever size the reservation was"; "A refusal to cover the work is not the provider refusing, and trips nothing"; "A reservation that leaps over the write interval is still written down (RUN-8.a)"; "With no budget set, what is left is unlimited rather than nothing"; "What is left is what is left of today, not of the day the counter last moved"; "Reserving nothing takes nothing and does not pause a spent day"; "A reservation that crosses several thresholds at once says so once" |
| REQ-chain-010 | `RateLimiterTests.swift` | "An hour of idleness does not buy an hour of requests to spend at once"; "Time going backwards leaves the bucket alone rather than emptying it"; "A rate too small to hold a single request is raised to one rather than stopping everything"; "A batch bigger than the bucket is taken a bucketful at a time rather than never"; "The limiter takes its rate from configuration rather than a number in the source" |
| REQ-chain-011 | `ChainHealthTests.swift` | "A listener that is up but has not connected yet does not report as working"; "Everything it has to reach, reached, is what ok means"; "The headers copied as proof are the ones an operator configured"; "Proof appears in the answer, and is escaped rather than trusted"; "A probe that failed never invents a success"; "Proof that has gone stale is dropped rather than served as though it were current" |
| REQ-chain-012 | `RequestGovernorTests.swift` | "A problem that started overnight is still there to read in the morning"; "A pause is announced once, not once for every request it refuses"; "Draining the notices hands them over once and leaves nothing behind"; "A host that never reads its notices cannot grow them without limit" |
| REQ-chain-013 | `PoolShareTests.swift`, `ChainReaderTests.swift` | "A share that does not divide evenly rounds down, never up"; "A pool and a holding both near the largest number the chain can hold still divide"; "A pool nobody has tokens in is worth nothing rather than dividing by zero"; "Holding more pool tokens than exist answers with the whole pool rather than trapping"; "A pool that minted its token at the maximum counts only what is really out there" |
| REQ-chain-014 | `WalletCheckCacheTests.swift` | "A wallet that could not be read is never remembered as empty"; "The same wallet twice in one list is one question, not two"; "A wallet asked about a moment ago is left alone even when a fresh read is demanded"; "An answer past its lifetime is read again" |
| REQ-chain-015 | `ChainFixtures.swift`, every suite | The suites reach the chain only through `StubAccountDataSource` and `StubHeaderProbe`, and every lifetime, cooldown and day boundary is passed a `now`. |
| REQ-chain-016 | `ChainConfigurationTests.swift`, `WalletCheckTests.swift` | "The pools an operator writes down are the pools this layer reads"; "A pool with no LP token is refused, because an unset variable arrives as zero"; "A pool whose own token is the counted token is refused, because it would count twice"; "A pool paired with itself is refused, because there is no other side to value it against"; "Two pools sharing an id are refused rather than one of them vanishing"; "Everything I hold is counted together, across every wallet I have linked" |
| REQ-chain-017 | `GatingBridgeTests.swift`, `WalletCheckTests.swift` | "A complete reading is known, and a short one is unknown rather than smaller"; "A member on the top rung keeps it when one pool's reserves cannot be read"; "With every pool read, the same holdings decide the rung they have earned"; "A wallet that could not be read at all holds every rung rather than losing them"; "No wallets at all is unknown, not a member holding nothing"; "Positions are summed across every wallet a member has verified"; "A pool the member is in none of is left out, and reads as a zero position"; "A collection nobody looked up holds its roles rather than losing them"; "A registry that answered counts what the wallets really hold"; "Nobody's wallets is not a total of nothing, because nobody looked" |
| REQ-chain-020 | `CallerShareTests.swift`, `ChainConfigurationTests.swift` | "A member spending their share is refused while the day still has plenty (RUN-11)"; "The refusal says when the next request is allowed, and names nobody (RUN-11, HOST-2)"; "A member at their share leaves everybody else working at the same instant (RUN-11)"; "Reaching a share is not a pause, however many times it happens (RUN-11, SEE-5)"; "A pause is answered before a share, so everybody hears the same story (RUN-11, SEE-11)"; "An indivisible job larger than what is left takes nothing from anybody (RUN-11)"; "A share comes back during the day rather than at midnight (RUN-11)"; "An allowance refills towards its burst and no further, however long the wait"; "With no daily budget nobody is ever refused by a share (RUN-11)"; "Throttling is visible in the snapshot every other figure comes from (RUN-11, SEE-9)"; "A caller whose share has refilled is forgotten (RUN-11, RUN-8.b)"; "At the bound a newcomer is refused, and nobody drawing is evicted (RUN-11)"; "Reaching the bound is one notice, not one per refused caller (RUN-11, SEE-5)"; "A restart hands a caller one fresh burst and no more of the day (RUN-11, RUN-8.b)"; "A job no burst can ever hold is refused with no date rather than a false one (RUN-11)"; "A clock stepped backwards hands a spent caller nothing back afterwards (RUN-11)"; "A clock that went backwards grants no refill, then or once it is corrected"; "A health body says whether anybody was refused, not only who is holding (RUN-11, SEE-9)"; "Limits built in Swift keep the range their own documentation states (RUN-11, ADOPT-2)"; "A share above the whole day refuses at boot and names the variable (ADOPT-2)"; "A share that is not a number, or a burst of nothing, refuses at boot (ADOPT-2)"; "A share is only a share once there is a day's budget to take part of (RUN-11, ADOPT-1)" |
| REQ-chain-021 | `ChainHealthTests.swift`, `RequestGovernorTests.swift` | "Assembling an answer spends no request and asks the chain nothing (SEE-1.b)"; "The snapshot answers for today too, not for the day the counter last moved (SEE-1.b, SEE-9)"; "The answer still comes back once the day's budget is spent (SEE-1.b, SEE-1.a)"; "The answer says when it is the provider refusing rather than the budget (SEE-1.b)"; "An instance with no budget set reads as having none rather than as having none left (SEE-9)"; "The budget on the answer is the one every other surface reports (SEE-9)"; "An instance with no proof configured opens no socket at all (SEE-1.b, SEE-10.a)"; "A proof that could not be taken leaves the answer without one, inventing nothing (SEE-10.a)"; "A report a host built itself carries the same body as an assembled one" |
| REQ-chain-022 | `RequestGovernorTests.swift`, `CallerShareTests.swift` | "Lifting a provider's pause with the day part spent returns none of it (RUN-10.a)"; "Lifting the same pause over and over is not a refund either (RUN-10.a)"; "An unpause writes nothing down, so a restart cannot read a lowered count (RUN-10.a, RUN-8.b)"; "Lifting a pause does not hand back a budget that really is spent (RUN-10.a)"; "Lifting a pause returns no part of a caller's share either (RUN-10.a, RUN-11)" |
| REQ-chain-023 | `ChainHealthTests.swift` | "The held read answers from what is already there, and probes nothing (SEE-1.b)"; "A held proof past its lifetime reads as absent rather than being refreshed (SEE-1.b, SEE-10.a)"; "An answer with no proof to give starts one probe, and the next answer carries it (SEE-10.a)"; "A stale answer is refreshed beside the next check rather than in front of it (SEE-1.b)"; "A provider that is down is not probed again by every check while it is down (SEE-1.b)" |
| REQ-chain-018 | `ChainConfigurationTests.swift` | "A number written with digit separators is a number in both layers"; "A variable written on the last line of a file is the value without its newline"; "A node url with no host refuses at boot rather than failing every read later"; "A node url that is not http refuses, naming what was expected" |

## Manual Testing

- [ ] Point a build at a real node with `TOKEN_DECIMALS` deliberately one out
      and confirm the process refuses at boot, naming both numbers.
- [ ] Set `CHAIN_DAILY_REQUEST_BUDGET` low, run a sweep, and confirm the
      notices arrive at 50, 75 and 90 percent and once more when the budget is
      spent, and that nothing is announced twice.
- [ ] Name a provider's own headers in `CHAIN_PROOF_HEADERS` and confirm the
      health body carries them, then revoke the token and confirm the provider
      section disappears rather than going stale.
- [ ] Read `hi/role.md`, `hi/see.md` and `hi/adopt.md` and confirm each
      criterion this module claims is either cited by a test name or named in
      `requirements.md`.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| A token whose asset id is zero | `ChainConfiguration.init` throws, naming `TOKEN_ASSET_ID`. |
| A node url of `http://` | Refused at boot. It used to boot clean and fail every read as a network error. |
| `CHAIN_DAILY_REQUEST_BUDGET=100_000` | Read as 100,000, the same as `TIER_1_MIN=100_000` always was. |
| A variable carrying the newline its file gave it | Read as the value without it, in both modules. |
| A pool whose LP token is the counted token | Refused by `LiquidityPool.validate`, because a direct holding would count twice. |
| No wallets at all | `BalanceCombiner.combine` answers `unavailable`, and `MemberHoldings.fromChain` answers unknown. Neither answers a zero. |
| A whole amount that overflows when scaled | `amountBaseUnits(whole:)` throws; `baseUnits(whole:)` saturates at `UInt64.max`. Both are deliberate and both are pinned. |
| An account the node has never heard of | An empty `ChainAccount`, and a complete reading. The node told us. |
| A request that did not complete | `WalletCheck.unreadable`, with everything `unavailable` rather than zero. |
| A pool whose reserves could not be read | Absent from the reserves map; a holder of its token reads `short`, never `complete(0)`. |
| A pool that minted its token at the maximum | The circulating supply is the total minus what the pool itself holds, so shares do not all round to zero. |
| A pool holding more of its own token than was minted | Answers zero rather than underflowing. |
| A holding larger than the circulating supply | Answers the whole pool rather than trapping on a quotient that will not fit. |
| The same wallet named twice in one list | One read, one answer, one request from the budget. |
| A forced fresh read inside the cooldown | The cached answer, because the cooldown exists precisely to bound how often a read can be forced. |
| A rate below one request per second | Refused at boot, and the bucket itself holds at one, because a bucket that cannot hold a request hands none out. |
| An ask larger than the bucket can hold | Taken a bucketful at a time. Slow, and it finishes. |
| The host clock stepped backwards mid sweep | Nothing happens: the limiter measures with `ContinuousClock`. |
| A restart in the same UTC day | The count resumes from the store, taking the larger of disk and this process. |
| A restart on a later UTC day | Yesterday's count is ignored, not spent against today. |
| A budget row that will not read | `restoreFromStore` throws; refusing to start beats starting with a budget nobody granted. |
| A budget row that will not write | A notice, and reading carries on. |
| A day's budget of zero | No budget: nothing is ever refused, and `hasBudget` says so rather than `remaining` reading as nothing left. |
| A pause lifted by hand while the budget really is spent | The next request pauses again. |
| A pause lifted by hand five times at one instant | Nothing moves: not the count, not what is left, not the day's start, not any caller's allowance, and nothing is written to the store. |
| A member's caller with a share of five percent of a thousand | Ten in a burst, then refused with `callerShareSpent`, while a second member and the role sweep are both served at the same instant. |
| A member's caller refused two thousand times | Two thousand refusals counted on the snapshot, no pause, and not one notice. |
| `CHAIN_CALLER_SHARE_PERCENT=5` with no daily budget | No share at all. There is no day's budget to take a part of, and nobody is refused. |
| A five percent share of a budget of ten | One request rather than none, because a share of nothing refuses every member every time; the day's budget is still the backstop. |
| A burst larger than the whole day's share | Clamped to the share and reported as clamped through `callerShareBurst`, rather than refusing the boot. |
| Ten thousand callers drawing at once | A caller nobody is tracking yet is refused, one notice a day says so, and no caller already drawing is evicted to make room. |
| A health answer wanted with no proof headers configured | Assembled with no socket opened at all, which is what makes "costs nothing" honest rather than a statement about a cache. |
| A health answer wanted with the day's budget spent | Still answered. The status is `ok` when everything declared has been reached, and the body's budget section says the budget is spent and when it comes back. |
| A provider that stamps no headers | No provider section at all, rather than an empty one. |
| A provider header containing a quote or a control character | Escaped in the JSON body; the answer stays parseable. |
| A `decimals` of 0, 2 or 19 | All read and printed at that precision. Twenty is refused at construction. |
