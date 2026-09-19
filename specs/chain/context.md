---
spec: chain.spec.md
---

## Key Decisions

- **One token, not two.** `Gating.TokenProfile` is the single representation of
  the operator's asset. This module briefly shipped a `ChainAsset` of its own,
  read from its own asset id, ticker and decimals variables, because the two
  layers were ported in parallel by people who could not see each other's work.
  That is an operator-facing defect rather than an untidiness: the asset had to
  be written down twice, could be written down differently, and two `decimals`
  that disagreed would read balances at one precision and decide tiers at
  another. One decimal place out is a factor of ten on every rung of the
  ladder, and that whole class of mistake is what this port exists to remove.
- **One pool, and it belongs to `Gating`.** This module carried a second
  `LiquidityPool` with a `PoolSide` for each end of the pair, and it was not
  merely a duplicate: **nothing could load it.** It wanted a symbol and a
  decimal count per side and `POOL_n_` sets neither, so a host wiring the two
  layers together had to invent a precision for the paired side, which is
  exactly what that field's own comment forbade. The two also disagreed about
  what an id is, the loader slugging it and this one taking it as a free-form
  key, so a host that built a pool with a display id got a pool lookup
  returning nil for ever and a badge nobody was ever granted. The fields that
  went with it, `symbol`, the per-side `decimals` and `poolTokenDecimals`,
  were read by no source file in this module and only ever by tests.
- **The two sides are counted and other, not A and B.** A and B needed a third
  fact saying which end the counted asset sat at, and the pool an operator
  writes down does not have one: it says which asset counts and which it is
  paired with. Keeping the letters would have meant inventing an ordering and
  making every reader look up which end the real answer was at.
- **One `CombinedBalance`, and it belongs to `Gating` too.** Both modules
  declared one and both carried a comment about the same morning: a member
  demoted for linking a second, empty wallet. Two types of one name, written
  for one incident, in two modules a host imports together, is how the third
  version of that incident happens. `Gating`'s stays, because it is the layer
  the rules are decided in. The two facts this one had that it lacked, how
  many accounts went into the total and which of them stood in on a stored
  figure, moved into `Gating.CombinedBalance.Totals`. **`hasLiquidity` did
  not**, and that is the one deliberate omission: `Gating` already answers it,
  better, as `LiquidityPosition.isProviding`, which reads the LP holding
  rather than what the position is worth today. A `Bool` on a totals struct
  would have meant "has a position" when this module filled it in and
  "liquidity is above zero" when `across(_:)` did.
- **An empty list of wallets is not a total of nothing.** `combine([])` used
  to answer a complete zero while `Gating.CombinedBalance.across([])` answered
  unknown, and the two now produce the same type. A caller reaches an empty
  list both when a member genuinely has no account and when nobody could list
  the accounts they have, and a confident zero for the second strips every
  rung from somebody whose holdings nobody read.
- **The join between the two readings lives here, because `Chain` depends on
  `Gating` and not the other way round.** `ChainReading` says whether an
  answer is whole and `Reading` says whether a fact was read, and for a while
  nothing converted between them, which left a host exactly one accessor that
  hands a number back from a short answer. `.known(reading.valueEvenIfShort ??
  0)` is the obvious line and it is the original incident: a pool's reserves
  fail, the total reads as a member who sold up, and every provider in the
  server is demoted. So both `short` and `unavailable` become `unknown`, and
  there is no variant of the conversion that takes a default.
- **One set of rules for one environment.** There were three ways to refuse
  the same mistake: `Gating` stripped digit separators and this module did
  not, `Gating` trimmed spaces and this module trimmed newlines too, and
  `Gating` required a URL to have a host while this module checked only the
  scheme. So `TIER_1_MIN=100_000` loaded and
  `CHAIN_DAILY_REQUEST_BUDGET=100_000` was refused, a trailing newline was a
  value here and a refusal there, and `CHAIN_NODE_URL=http://` booted clean
  and then failed every read as a network error. The rules are
  `Gating.NumberedEnvironment`'s now, called rather than restated, and where
  this module's rule was the better one it moved down rather than being kept
  here: trimming spaces and not newlines is wrong for a variable read out of a
  file. The refusals stay `ChainConfigurationError`, because each carries the
  sentence saying what *this* variable expected, and "a batch of at least one
  wallet" is worth more to the person reading it than "is not a whole number".
- **The two whole-to-base conversions behave differently, on purpose, and are
  named apart.** `TokenProfile.baseUnits(whole:)` saturates because its callers
  are thresholds: an operator who types too many zeros gets a rung nobody
  reaches, which is visible in the server and fixable in a minute, where a
  wrapped `UInt64` would give them a rung everybody reaches. The conversion
  this module adds, `amountBaseUnits(whole:)`, throws, because its callers are
  amounts and a clamped amount is a number nobody asked for. They are not
  overloads of each other: an overload picked by context is exactly the wrong
  way to choose between refusing and clamping.
- **Zero is refused as an asset id here rather than in `Gating`.** On this
  chain zero names the chain's own currency, which is not an asset an account
  opts into. A ladder measured in the chain's own currency is a coherent thing
  to configure; balances read from asset zero are not, so the guard belongs to
  the layer that does the reading. An unset variable arrives as zero, and
  without the guard every member is reported as holding nothing.
- **There is no default asset, and deliberately no default number of decimal
  places.** The bot this was ported from assumed six decimals in nine separate
  places, which welds a project to one token and misreports every balance of an
  asset with any other precision by a factor of ten per missing place, silently,
  because every balance still looks like a balance.
- **An incomplete reading is not an empty one.** `ChainReading` exists because
  of a production incident: a transient provider error read a liquidity
  position as zero, which read as a member who had sold up, which stripped
  roles from people who had done nothing. The earlier fix carried a `Bool`
  beside the number, which worked only for as long as every caller remembered
  the `Bool` existed, and one caller not remembering is what demoted a room
  full of people. The value a caller may act on now comes only from
  `completeValue` or `requireComplete()`, and a short one has to be asked for
  by a name that says it is short.
- **A 404 is a complete negative answer and a failed request is not.**
  `ChainReader.account(_:)` answers an unknown account with an empty account,
  because the node told us. A pool read deliberately does not go through that
  helper: an empty pool is a complete reading, every provider's share of it
  works out to nothing, and the sweep demotes the people who put the liquidity
  there.
- **Both brakes are needed and they measure different things.** The rate
  limiter answers to the provider's published requests per second. At nine
  hundred requests a second a free daily quota is gone in minutes and the
  limiter is doing its job perfectly the whole time, which is why the per-day
  budget exists beside it. Removing either leaves a hole the other does not
  cover.
- **One counter for reading and signing together.** Before the shared
  governor, each path counted separately and in practice only the read path
  counted at all, so the configured number was not the number of requests the
  process could make, and a provider refusal met while paying somebody did not
  slow down the loop reading everybody's balances.
- **A budget counts requests; a cap counts money.** They never share a word.
  The criteria catalogue this was ported from had to retire a criterion over
  exactly this: one sentence said "today's allowance" and a reader took the
  daily request budget and the weekly spending limit for the same thing.
- **The day is a UTC day.** A box in Sydney rolling its counter at local
  midnight would hand itself a second day's budget ten hours before the
  provider agreed, and would then be cut off mid afternoon with a counter
  reading half spent.
- **The counter is written to a store, and an unreadable row throws.** A
  restart used to zero the counter while the provider's day kept running, so a
  crash loop quietly handed the process a fresh budget every time it came back
  and the ceiling an operator set was whatever the last restart left of it. A
  row read as "nothing recorded" would reintroduce exactly that, so `nil` means
  genuinely never written and nothing else.
- **The count is written periodically, not per request.** Writing on every
  request would put a database write in front of every read of the chain. A
  crash therefore loses a few requests of the count, which is a trade made
  deliberately and bounded by `budgetPersistEvery`.
- **The governor refuses rather than queues.** Work that waits for the budget
  to come back is work that lands hours later, when the thing that asked for it
  has gone.
- **A pause is announced once, not once per refused request.** A pause refuses
  everything for the rest of the day, so announcing it on every refusal buries
  the announcement under thousands of copies of itself at exactly the moment
  somebody is trying to read it.
- **The module has no logger and must not grow one.** A library that logs
  decides for its host where the words go. Notices are values in a bounded
  buffer the host drains, which also means a problem that started overnight is
  still readable in the morning rather than having scrolled past in a terminal
  nobody was watching.
- **A health answer is never "the process is alive".** The incident this exists
  for ran for three hours: the process was up, the port answered, the check
  said ok, every one of those was true and none of them was useful, and the
  first anybody knew was somebody asking whether the bot was down. A listener
  bound while the connection it exists to serve has not been made reports
  `starting` and names what it is waiting for, which also stops a deployment
  gate replacing a working version with one that does not work.
- **Proof of which provider served a request is never invented.** A stale
  answer is dropped rather than served on: proof that a provider served a
  request half an hour ago is not proof that it is serving them now, and the
  whole point of the field is that it is evidence. Which headers count is
  configuration; the version this was ported from named one company's five
  headers in the source.
- **Only a complete reading is cached.** Caching an incomplete one takes a
  single failed request and serves it as that wallet's balance for the whole
  lifetime of the entry, turning one bad moment into minutes of wrong answers.
- **The rate limiter measures with `ContinuousClock`.** A limiter that reads
  the wall clock hands out free requests whenever the clock is stepped
  backwards, which is the one thing a limiter exists to prevent. The package's
  platform floor was raised for this rather than the clock being changed.
- **An ask larger than the bucket is taken a bucketful at a time.** The bucket
  is capped at a second's worth on purpose, so a pool read asking for two
  requests against a configured rate of one would otherwise sleep, refill, ask
  again, and go on doing that for as long as the process lived. No error, no
  notice, and a role sweep that never came back.
- **The circulating supply is not the minted supply.** A pool that minted its
  token at the largest number the chain can hold keeps the unissued remainder
  in its own account. Dividing a provider's holding by the minted figure makes
  every share round to zero and every provider's balance disappear.
- **Pool share arithmetic is full-width integer arithmetic.** The obvious
  spelling multiplies two balances together and overflows 64 bits long before
  either is unreasonable: a pool holding ten to the fifteenth of each side,
  ordinary for a six-decimal asset, overflows against a holding of the same
  size.
- **Nothing here logs, stores, signs or decides a role.** The chain client is a
  protocol, because in the bot this was ported from the money-adjacent code
  talked to a real node through a concrete type and not one of its failure
  paths had ever been run. The paths that matter here are all failures.

## Files to Read First

- `Sources/Chain/ChainReading.swift`: the shape of an answer that may be short,
  and the incident it is the fix for.
- `Sources/Chain/WalletCheck.swift`: all of the interpretation, away from the
  network, including the three completeness rules a caller must obey.
- `Sources/Chain/ChainConfiguration.swift`: what is configuration, what is
  handed in, and what has no default.
- `Sources/Chain/TokenProfile+Amounts.swift`: why there is one token and two
  conversions.
- `Sources/Chain/GatingBridge.swift`: the join between the two readings, and
  the one line it exists to make unwritable.
- `Sources/Chain/PoolCounting.swift`: why there is one pool type, what this
  layer adds to it, and what a host has to call at boot.
- `Sources/Chain/RequestGovernor.swift` and
  `Sources/Chain/DailyRequestBudget.swift`: the one counter, the one breaker,
  and the notices.
- `Sources/Chain/RequestRateLimiter.swift` and `Sources/Chain/TokenBucket.swift`:
  the other brake, and why it is not the same brake.
- `hi/role.md`, `hi/see.md` and `hi/adopt.md`: the criteria the tests cite.

## Current Status

Implemented and covered by 175 tests in 13 suites, all offline. The module
builds against `Gating` for the token, the pool, the collections, the two
readings and the environment rules, and against `swift-algorand` for the node
client. There is no bot target yet: nothing here is wired to a live sweep, a
live health endpoint or a live payout, and `NodeAccountDataSource` is the only
file that has ever spoken to a node.

## Notes

- `ChainFormatting` is deliberately a copy of the same idea in the payout
  engine rather than a shared dependency. This layer knows about the chain and
  that layer knows about money, and neither should have to import the other to
  print a number. `TokenProfile.format` and `ChainFormatting.amount` are pinned
  against each other by a test, so the copy cannot drift.
- Every fixture address is an obvious label and every fixture asset id is
  small, because a fixture that looks like somebody's real wallet ends up
  pasted into an explorer by the next person to read it.
- Nothing is declared twice across the two modules any more. `LiquidityPool`
  and `CombinedBalance` were, and the fixtures had to qualify the names to say
  which they meant; both now belong to `Gating` and this module extends them.
- `LiquidityPool.validate(_:)` is not called by anything inside this module,
  because nothing here loads a pool. A host calls it at boot against the
  catalogue `Gating.LiquidityConfiguration` returned. Until there is a host
  there is nothing to enforce that, and it is the one rule in the module whose
  enforcement lives outside it.
