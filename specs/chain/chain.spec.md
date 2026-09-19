---
module: chain
version: 2
status: active
files:
  - Sources/Chain/AccountDataSource.swift
  - Sources/Chain/BalanceCombiner.swift
  - Sources/Chain/BatchedChainReader.swift
  - Sources/Chain/CallerShare.swift
  - Sources/Chain/ChainConfiguration.swift
  - Sources/Chain/ChainConfigurationError.swift
  - Sources/Chain/ChainEnvironment.swift
  - Sources/Chain/ChainError.swift
  - Sources/Chain/ChainFormatting.swift
  - Sources/Chain/ChainHealth.swift
  - Sources/Chain/ChainHealthAssembly.swift
  - Sources/Chain/ChainNotice.swift
  - Sources/Chain/ChainReader.swift
  - Sources/Chain/ChainReading.swift
  - Sources/Chain/DailyRequestBudget.swift
  - Sources/Chain/ExpiringMap.swift
  - Sources/Chain/GatingBridge.swift
  - Sources/Chain/NodeAccountDataSource.swift
  - Sources/Chain/PoolCounting.swift
  - Sources/Chain/PoolReserves.swift
  - Sources/Chain/ProviderProofProbe.swift
  - Sources/Chain/RequestBudgetSnapshot.swift
  - Sources/Chain/RequestBudgetStore.swift
  - Sources/Chain/RequestCaller.swift
  - Sources/Chain/RequestGovernor.swift
  - Sources/Chain/RequestRateLimiter.swift
  - Sources/Chain/TokenBucket.swift
  - Sources/Chain/TokenProfile+Amounts.swift
  - Sources/Chain/UTCDay.swift
  - Sources/Chain/WalletCheck.swift
  - Sources/Chain/WalletCheckCache.swift
db_tables: []
depends_on: []
---

# Chain

## Purpose

Read what an account holds on an Algorand node, and stop the process reading
too much. The module turns one account, or a whole community's worth of
accounts, into readings a caller may act on, and it carries the two brakes
that keep those reads inside what a provider allows: a per-second rate limiter
and a per-UTC-day request budget shared by every caller in the process.

The other half of its job is refusing to invent an answer. A request that did
not come back is not an account holding nothing, and a pool whose reserves
could not be read is not a pool worth nothing. Every figure this module hands
out is a `ChainReading`, which carries whether it is the whole answer, so a
caller that means to take a role away has to ask for a complete reading by a
name that says so (ROLE-1.a).

It decides nothing about roles, sends nothing, signs nothing and stores
nothing. Which token to read, which pools to count, which node to read through
and how hard to read it are all the operator's, handed in as configuration
(ADOPT-12). Persistence of the day's request count is a protocol the host
implements. There is no Discord type here and no database.

## Public API

Every exported symbol of the `Chain` library target, in source order, one row
per name. Where several types share a name, the row is merged and says which
type each sense belongs to: `assetId`, `amount`, `name`, `decimals`, `id`,
`init` and the rest are one row covering all of their senses.

| Export | Description |
|--------|-------------|
| `ChainHolding` | One asset an account holds. |
| `assetId` | An asset's on chain id: the asset a `ChainHolding` is of, and on `PoolSide` the side's asset, where zero names the chain's own currency, held as an account balance rather than as an asset. |
| `amount` | How much of an asset, in its smallest unit: the field on `ChainHolding`, the lookup over a list of holdings that answers zero for an account that never opted in, and `ChainFormatting.amount`, which writes smallest units out at the precision passed in rather than an assumed one. |
| `isFrozen` | Whether the holding is frozen by the asset's manager. |
| `init` | Memberwise, except where it validates. `ChainConfiguration.init` refuses an asset id of zero and a node url that is not an `http` or `https` URL with a host; `TokenBucket.init` holds the rate at one or more. `ChainLimits`, `ChainCacheLifetimes`, `RequestGovernor` and `RequestRateLimiter` each also take one built from the environment or from `ChainLimits`. The ones on `WalletCheck`, `PoolShare` and `RequestBudgetSnapshot` are public so a host can rebuild one from figures it stored earlier. |
| `ChainAccount` | What an account holds, as one read of the chain returned it. |
| `address` | An account's address: the account a `ChainAccount` describes, and the wallet a `WalletCheck` describes. |
| `nativeBalance` | The chain's own currency, in its smallest unit. Fees and the minimum balance come out of this; nothing in this layer pays anybody with it. |
| `holdings` | Everything an account has opted into, held or not: the field on `ChainAccount`, the reading on `WalletCheck`, and the reader method that fetches it. |
| `createdAssets` | Assets an account created: the field on `ChainAccount`, filled when the read included them, and the reader method that fetches it. |
| `ChainAssetDetails` | What the chain says about an asset. |
| `id` | The asset's on chain id, on `ChainAssetDetails`. |
| `creator` | The account that created it. |
| `decimals` | Decimal places, on `ChainAssetDetails`. The chain's own, kept at the chain's width so comparing them with the configured value compares what is really there. |
| `total` | The whole supply, in the asset's smallest unit. |
| `unitName` | The short name, when it has one. |
| `name` | A name: the asset's long name on `ChainAssetDetails`, the configured header on `ProofField`, and what a component is called in the health answer. |
| `url` | The asset's url, when it has one. |
| `reserveAddress` | The account named as the asset's reserve, when it has one. For a pool token this is the account holding the pool. |
| `AccountDataSource` | Where readings of the chain come from. A seam rather than a concrete client, because the paths that matter here are all failures and each of them is reachable from a test only because this protocol exists. |
| `account` | One account: the data source reads everything it holds in one request, the node implementation translates the client's error into this layer's, and the reader answers a 404 with an empty account, because the node told us and that is a complete answer rather than a failed read. |
| `assetDetails` | What the chain says about one asset: the data source requirement, its node implementation which turns a 404 into `assetNotFound`, and the reader method that spends one request from the budget on it. |
| `isValidAddress` | Whether a string is a canonical address on this chain. Checked before a request goes out, so a typo costs nothing from the day's budget. |
| `positiveBalanceAssetIds` | The assets actually held. An opt-in with a zero balance is not a holding. |
| `directBalance` | The configured token held directly in one wallet, as a reading. |
| `liquidityAmount` | The counted token attributable to one wallet's pool positions. Short when a pool's reserves were not available, because calling that zero is how a liquidity provider is demoted for providing liquidity. |
| `combinedBalance` | Direct holding plus pool positions, which is the number a tier is decided on. Complete only when both parts are. |
| `BalanceCombiner` | Adding a person's wallets up without losing what could not be read. The total it produces is `Gating.CombinedBalance.Totals`; this module's own `CombinedBalance` is gone, because two types of one name written for one incident is how the third version of that incident happens. |
| `combine` | The total, complete only when nothing is missing from it. No wallets at all is `unavailable`, never a total of nothing, which is the answer `Gating.CombinedBalance.across` gives the same question. A stored figure may stand in for a wallet nobody read this time, and is recorded as having done so. |
| `BatchedChainReader` | Reads many wallets at once, at a rate the provider will tolerate, keeping the answers in the order the wallets were asked for. |
| `poolReserves` | A pool's reserves: the reader fetches them in two requests, the batched reader reuses a cached set until its lifetime is up, and the configured lifetime says how long that is. Short by default, because reserves move with every trade. |
| `reserves` | Reserves for every pool that could be read. A pool that could not is absent rather than present with zeroes, and the run stops early once the provider has refused on quota. |
| `check` | Readings for a list of wallets, in the order asked for: the batched reader reads them in batches, and the cache answers from what it remembers first and never overrides the cooldown. |
| `clearReservesCache` | Drops every cached set of reserves, so the next read is fresh. |
| `cachedReservesCount` | How many sets of reserves are cached, usable or not. |
| `ChainConfiguration` | Everything this layer needs to know before it reads anything. Every number that was a literal in the bot this was ported from is a validated variable here. |
| `token` | The token balances are read for, as the layer above loaded it: on the configuration, and on the reader that holds it. |
| `nodeURL` | The node to read from: the configured URL, and `CHAIN_NODE_URL`, the variable it is read from. Required. |
| `apiToken` | The node's API token, when it needs one: the configured value, and `CHAIN_API_TOKEN`. |
| `limits` | The two brakes, and how work is batched. |
| `cacheLifetimes` | How long each cached answer stays usable. |
| `proofHeaderNames` | Response headers copied onto a health answer as proof of which provider served the request. |
| `verifiesAssetDecimals` | Whether to read the token's decimals from the chain at boot and refuse to start when they disagree with what was configured. |
| `load` | Reads the chain-layer configuration out of a set of environment variables, around a token that has already been read. |
| `loadFromProcessEnvironment` | The same, from the process environment. |
| `ChainLimits` | The two brakes on how hard the chain is read, and how work is batched. Both are needed: they measure different things. |
| `requestsPerSecond` | Requests per second: the configured rate, `CHAIN_REQUESTS_PER_SECOND` which sets it, and the bucket's own rate, which is also the most the bucket ever holds. Conservative by default, because the first run of this belongs to somebody pointing it at a free tier. |
| `batchSize` | How many wallets are read in parallel per batch, and `CHAIN_BATCH_SIZE`, the variable that sets it. |
| `dailyRequestBudget` | Requests permitted per UTC day, counting reads and signing together, and `CHAIN_DAILY_REQUEST_BUDGET`, the variable that sets it. Zero means no budget. A budget counts requests and is never a spending cap. |
| `budgetPersistEvery` | How many requests pass between writes of the day's counter, and `CHAIN_BUDGET_PERSIST_EVERY`, the variable that sets it. A crash loses at most this many requests of the day's count. |
| `callerSharePercent` | The share of the day's budget one member's caller may draw, as a percentage: the configured value, and `CHAIN_CALLER_SHARE_PERCENT`, the variable that sets it. Five by default, zero turns shares off, above a hundred is refused at boot. A percentage rather than a count, because budgets differ by orders of magnitude between a free tier and a paid one. |
| `callerBurstRequests` | The most one member's caller may take before their allowance has to refill: the configured value, and `CHAIN_CALLER_BURST_REQUESTS`, the variable that sets it. Ten by default, clamped to the day's share when it is larger. A burst as well as a rate, because however fast somebody types is a rate problem. |
| `callerShare` | The `CallerShareRule` those two settings and the day's budget work out to, or nil when there is no share at all. Derived rather than configured, so the three cannot drift into a share nobody wrote down. |
| `ChainCacheLifetimes` | How long each cached answer stays usable. Every one of these was a literal in the bot this came from. |
| `walletCheck` | Seconds a completed wallet reading stays usable. |
| `walletCheckCooldown` | Seconds before the same wallet may be read again on demand. Separate from `walletCheck` on purpose: the cache answers cheaply, the cooldown refuses to ask the chain the same question over and over. |
| `healthProbe` | Seconds a health probe's answer is reused, so a monitoring check every few seconds does not become traffic to the node. |
| `ChainConfigurationError` | Why this layer refused to start. Every case names the variable an operator has to set or correct. |
| `missing` | A required variable is not set. There is deliberately no fallback. |
| `invalidValue` | A variable is set to something this cannot use. |
| `amountOverflows` | Whole units times the token's scale does not fit in `UInt64`. |
| `duplicatePoolId` | Two pools share an id, so one of them would be silently dropped. |
| `errorDescription` | The refusal written out for a person: on `ChainConfigurationError` naming the variable to fix and what was expected, on `ChainError` naming the variable, the provider or the account to act on. |
| `ChainEnvironment` | The names of the environment variables this layer reads, held in one place so a refusal can name the exact variable. None of them names the asset. |
| `verifyAssetDecimals` | The boot-time check of configured precision against the chain: `CHAIN_VERIFY_ASSET_DECIMALS` turns it on or off, defaulting to on, and the reader method performs it and refuses to carry on when the two disagree. |
| `proofHeaders` | `CHAIN_PROOF_HEADERS`: response header names copied onto a health answer as proof of which provider served the request. Comma separated, empty by default. |
| `poolCacheSeconds` | `CHAIN_POOL_CACHE_SECONDS`: seconds a pool's reserves stay usable before they are read again. |
| `walletCacheSeconds` | `CHAIN_WALLET_CACHE_SECONDS`: seconds a completed wallet reading stays usable. |
| `walletCooldownSeconds` | `CHAIN_WALLET_COOLDOWN_SECONDS`: seconds before the same wallet may be read again on demand. |
| `healthProbeSeconds` | `CHAIN_HEALTH_PROBE_CACHE_SECONDS`: seconds a health probe's answer is reused. |
| `ChainError` | Why a read of the chain did not produce an answer. |
| `invalidAddress` | A string that has to be a canonical address was not one. |
| `api` | The node answered, and said no. |
| `network` | The request did not complete, or the answer could not be understood. |
| `assetNotFound` | The asset does not exist, as far as the node is concerned. |
| `assetDecimalsDisagree` | The chain says the asset has a different precision from the configured one. Every balance would be wrong by a factor of ten per missing place. |
| `requestBudgetSpent` | Today's request budget is spent. Reads and signing are paused until the UTC day rolls over. |
| `providerRefusedQuota` | The provider refused with its own quota error: as a `ChainError`, as a `ChainNotice.Kind` and as a pause reason. The same pause a spent budget causes, deliberately kept a separate fact, because an operator does something different about it. |
| `requestBudgetCannotCover` | Today's budget cannot cover a reservation that had to be taken whole. Deliberately neither a pause nor a spent budget: the day still has requests in it, and they belong to every caller that can use them one at a time. |
| `callerShareSpent` | One caller has taken their share of today's requests, carrying what they asked for, what is left of their share and the instant their next request would be allowed. Deliberately not `requestBudgetSpent`: the day is not spent, nothing is paused, and every other caller carries on. It names nobody. |
| `callerShareCannotCover` | One caller asked for more requests at once than any allowance can hold, carrying what was asked for and the burst. Deliberately carrying no instant: an allowance never holds more than its burst, so no waiting makes it fit and a date here would send a host away to retry into the same refusal forever. The share's version of `requestBudgetCannotCover`. It names nobody. |
| `incompleteRead` | Something a caller needed could not be read, so there is no complete answer to give it. |
| `poolAddressNotFound` | A pool's reserve account could not be found, so its reserves cannot be read. |
| `isProviderQuotaRefusal` | Whether an error is a provider refusing because its own quota is spent, recognised on both the raw refusal and this layer's own pauses. |
| `isNotFound` | Whether an error means the account or asset simply is not there. A 404 is a complete negative answer, not a failed read. |
| `ChainFormatting` | Writing integer smallest units out for a person to read, with no `Double`, no `NumberFormatter` and no locale anywhere in it. |
| `grouped` | `1234567` as `1,234,567`. |
| `percent` | A share of a pool, in millionths, written as a percentage with four decimal places, computed on the integers. |
| `shortenAddress` | An address with its middle removed, keeping enough of both ends that two addresses a person holds are still told apart. |
| `ProofField` | One header copied from a provider's own answer. |
| `value` | What the provider sent. |
| `ProviderProof` | Proof of which provider actually served a request, built only from headers the operator named and only from values that were really present. |
| `fields` | The headers that were present, in the order they were configured. |
| `parse` | Picks the configured headers out of a response's headers, case insensitively and only where a value was really present. One overload takes a plain dictionary, the other the loosely typed one a URL response has. |
| `httpHeaders` | The fields as headers to copy onto a health answer. |
| `ChainHealthStatus` | Whether the instance is doing its job. |
| `ok` | Everything the instance has to reach, it has reached. |
| `starting` | It is up, and something it needs is not there yet. |
| `ChainHealthComponent` | One thing the instance has to have reached before it is working. |
| `reached` | Whether this instance has actually reached it. |
| `ChainHealthReport` | What a health check answers. A health answer is not "the process is alive": it states what this instance has actually reached. |
| `components` | The things this instance has to reach, and whether it has. |
| `budget` | What is left of today's requests on a health answer, as the same `RequestBudgetSnapshot` every other surface reports. Optional, because a host with no chain configured has no budget to report, which is a different fact from a budget with nothing left. |
| `proof` | Proof of which provider served the last probe: the field on a health report, and the probe method that refreshes it when stale and never invents a success. |
| `status` | `ok` only when every component has been reached. |
| `waitingOn` | What is not there yet, in the order it was declared. |
| `jsonBody` | The answer as JSON, hand built so the shape a monitoring check greps for cannot be reordered by an encoder, and with every provider value escaped. The budget section is appended after the existing keys, says whether a budget is configured at all, and carries the pause, the number of callers currently held and the number of reservations refused at a share only when there are any. The refusals are there because the callers held are not evidence of throttling: one request inside a refill interval puts a caller in that count. |
| `ChainHealthAssembler` | Puts a health answer together without spending a request: it asks the governor for a snapshot and the proof probe for what it already holds, and touches no reader and no data source. It owns no listener and no route. |
| `report` | The assembled answer, for components only the host knows, having spent nothing and still answering once the day's budget is gone. Where no usable proof is held it starts one probe beside the answer rather than in front of it, so the answering path never waits on a provider and the next answer carries proof. |
| `ChainNotice` | Something that happened to the request budget which somebody should read. A value rather than a log line, because a library that logs decides for its host where the words go. |
| `kind` | What happened. |
| `at` | When it happened. |
| `message` | One line, written for an operator mid incident. |
| `Kind` | The kinds of notice this layer produces. |
| `budgetThresholdCrossed` | A percentage of the day's request budget has been reached for the first time today. |
| `budgetSpent` | Today's request budget is spent: as a `ChainNotice.Kind` announcing the pause, as a `ChainReadGap` on a reading that stopped part way, and as a pause reason on the snapshot. |
| `pauseLiftedByHand` | An operator lifted a pause by hand. |
| `budgetNotPersisted` | The day's count could not be written down. |
| `callerTrackingFull` | As many callers are being tracked for their share as this process will track, so a caller nobody is tracking yet is being refused. Recorded once a day, never once per refusal. |
| `ChainReader` | Reading the chain, one account at a time, behind the day's budget. Nothing here retries. |
| `configuration` | What this reads, and how hard. |
| `balance` | How much of the configured token an account holds. |
| `poolTokenBalance` | Pool tokens held: the reader method that asks how much of a pool's token an account holds, and the holding a `PoolShare` was computed from. |
| `budgetSnapshot` | What has been spent of today's request budget. |
| `pausedUntil` | When the current pause ends, or nil when nothing is paused: on the governor, on the reader that asks it, and on the snapshot they both report. |
| `ChainReadGap` | A number the chain could not finish telling us, and what was missing. Each case is a way a reading can come back looking exactly like a real, small answer. |
| `requestFailed` | The request failed. The account may hold anything at all. |
| `poolReservesUnavailable` | A pool's reserves were not available, so a holding of its pool token could not be converted into an amount of the counted asset. |
| `notRead` | Nobody has read this yet. Distinct from a failure: nothing went wrong, the question was simply never asked. |
| `summary` | One line naming what is missing, for a message a person will read. |
| `ChainReading` | An answer from the chain, carrying whether it is the whole answer. The type exists because of a production incident, and the shape of it is the fix. |
| `complete` | Everything this reading needed was read. |
| `short` | Part of it could not be read. The value is what was read, and is known to be short by an unknown amount. |
| `unavailable` | None of it could be read. |
| `completeValue` | The value, only when the reading is complete. |
| `valueEvenIfShort` | The value even though it may be short, named so that reaching for it is a decision somebody can see in review. |
| `requireComplete` | The value, or a refusal naming what was missing. |
| `isComplete` | Whether the whole answer arrived. |
| `gaps` | What was missing. Empty when the reading is complete. |
| `map` | The same reading with its value transformed, keeping completeness, because the moment a transformation drops it the number at the other end looks whole again. |
| `DailyRequestBudget` | The per day brake: how many requests this process may make in a UTC day, counting reads and signing together. Pure and synchronous, so all of its arithmetic is exercised with no clock and no network. |
| `warningThresholds` | Percentages worth warning about the first time they are reached in a day: 50, 75 and 90. |
| `limit` | Requests permitted per UTC day, on the budget and on the snapshot of it. Zero means no budget is set. |
| `used` | Requests reserved so far in the current UTC day: the property, and `used(at:)`, which answers for the day the given instant falls in and is zero once the day has turned, because nothing rolls the counter until the day's first reservation and a surface read at one minute past midnight would otherwise report yesterday's spending as today's. |
| `dayStart` | Midnight UTC at the start of the day a count belongs to: on the budget, on the snapshot, and stored with the written count rather than inferred on read, so yesterday's number is recognised as yesterday's. `dayStart(at:)` is the day the figures asked about an instant belong to, which is the day that instant falls in. |
| `remaining` | Requests left today: the property, always zero when there is no budget, so a caller sizing a batch has to look at `limit` as well; and `remaining(at:)`, which answers for the day the given instant falls in and is nil when there is no budget, because a consumer that has to take its whole allowance at once cannot read a zero as either answer. |
| `Decision` | What happened when a request was reserved. |
| `allowed` | The request may proceed. The crossed threshold is set only on the first reservation to reach that percentage today. |
| `exhausted` | The budget is spent. The caller pauses until the given time, the same pause a provider's own refusal causes. |
| `notEnoughBudget` | The day has requests left, but fewer than a reservation that has to be taken whole asked for. Nothing was reserved, and nothing is paused: pausing because one indivisible consumer did not fit would hand the rest of the day to nobody. |
| `reserve` | Reserves requests against today's budget, before they are sent rather than counted after they return. One request, or a count taken all or nothing for work that cannot be half done. |
| `restore` | Applies a counter written earlier in the same UTC day, taking the larger of what is on disk and what this process has already spent. A snapshot from another day is ignored. |
| `nativeCurrencyAssetId` | The asset id that names the chain's own currency rather than an asset. Zero, on this chain, and a side that is it is read from the account's balance rather than from a holding. Declared on `Gating.LiquidityPool` by this module, which is the module that knows what zero means. |
| `isNativeCurrency` | Whether a side of a pair is the chain's own currency. |
| `validate` | Refuses a catalogue of pools this layer could not read honestly: a pool token of zero, a pool whose own token is the counted token, a pool paired with itself, and two pools sharing an id. A host calls it at boot against the catalogue `Gating.LiquidityConfiguration` loaded. |
| `gatingReading` | A `ChainReading` as the `Gating.Reading` the rules read. `complete` becomes `known`; both `short` and `unavailable` become `unknown`, because a short answer is not a smaller true answer. |
| `fromChain` | A `Gating.MemberHoldings` built from the wallets read for one member, plus the pools and collections the operator configured. The other half of the join: one wallet short makes the whole member unknown, no wallets at all is unknown rather than zero, the positions are all or nothing, and a collection nobody looked up is left out so its roles are held. |
| `NodeAccountDataSource` | The real data source: a node, over HTTP. Thin on purpose; everything it does is translate. |
| `PoolReserves` | What a pool held when it was last read. |
| `pool` | The pool this describes. |
| `poolAddress` | The account holding the pool's reserves. |
| `circulatingPoolTokens` | Pool tokens in circulation, which is what a provider's holding is a share of: on the reserves as read, and on the share computed from them. |
| `readAt` | When this was read, so a caller can say how stale it is. |
| `countedAssetBalance` | How much of the counted asset the pool holds, in its smallest unit. |
| `otherAssetBalance` | How much of the other side the pool holds, in that asset's smallest unit. |
| `share` | What a holding of this pool's token is worth of each side. Integer arithmetic throughout, rounded down always. |
| `PoolShare` | What one provider's pool tokens are worth. |
| `poolId` | The pool this is a share of. |
| `shareMillionths` | The share of the pool, in millionths, so that what is printed is what was computed. |
| `countedAssetId` | Which asset the counted amount is of. |
| `countedAssetAmount` | The provider's part of the counted asset, which is the part that counts toward a member's balance. |
| `otherAssetAmount` | The provider's part of the other side, which does not. |
| `formattedSharePercent` | The share as a percentage with four decimal places. |
| `HTTPHeaderProbe` | One cheap request whose response headers are what is wanted. A seam, so the caching and the never invent a success rule are testable without a network. |
| `probeHeaders` | Makes the request and returns its response headers. The URL session implementation refuses an answer that is not an HTTP response. |
| `ProviderProofProbe` | The last thing a provider said about itself, kept for a little while. Deliberately outside the request governor, because a health check must keep working when the budget is spent and must not spend the last of it either. |
| `heldProof` | The proof already held, making no request and leaving the cache exactly as it was. A held answer past its lifetime reads as absent rather than being refreshed, and this is the read a health answer takes its proof from, because `proof(now:)` would put a network call on the one path that must never make one. |
| `refreshInBackground` | Starts one probe in the background when nothing usable is held, and returns at once. The third part of the health path, and the one without which the other two answer nothing: the held read never goes and gets proof, so something has to, and it must not be the call that is answering. One at a time, never while what is held is still within its lifetime, and never at all for an operator who named no headers. |
| `flushRefresh` | Waits for a background probe already started to finish. Tests wait on this, and so should a host shutting down deliberately. |
| `invalidate` | Forgets something cached so the next call is fresh: the probe's proof, or one wallet's answer and its cooldown. |
| `URLSessionHeaderProbe` | A probe that makes a plain HTTP request and reads the response headers, because a typed client hands back a decoded body with the headers thrown away. |
| `RequestCaller` | Who a request is being made for, as a closed set of two cases so that which side of the rule a call sits on is visible in review. |
| `member` | Work done on behalf of one member, rationed to a share of the day. The key is one this instance minted: nothing that came from a chat account may be passed, and the value is never logged, persisted or repeated in an error. |
| `system` | The instance's own work, which carries no share. A sweep is not a person, cannot type fast, and is already bounded by its batch size and its interval. |
| `shareKey` | The key a share is counted against, or nil for work that carries none. |
| `isRationed` | Whether this caller is held to a share of the day. |
| `CallerShareRule` | How big one caller's share is and how fast it comes back, derived from a percentage of the day's budget and a burst. Pure, with no clock in it. |
| `dailyShareRequests` | Requests one caller may take across a whole UTC day. Held at one rather than zero when a percentage of a small budget rounds away, because a share of nothing refuses every member every time. |
| `burstRequests` | The most one caller may take before their allowance has to refill, clamped to the day's share rather than refused, so the clamp is visible in what a status surface reports. |
| `refillPerSecond` | Requests that come back per second, being the day's share spread over a UTC day. |
| `freshAllowance` | A caller nobody is tracking yet, with their whole burst in hand. Full rather than empty, so a caller the table has forgotten is indistinguishable from one it has never heard of. |
| `CallerShare` | One caller's allowance, refilling as the day passes. Held in memory and never written down: a restart hands a caller at most one fresh burst, and the day's own count is persisted, so no restart trick creates requests out of nothing. |
| `rule` | How big the share is and how fast it comes back. |
| `isFull` | Whether the allowance has come all the way back, which is what makes forgetting a caller safe. |
| `nextAllowed` | When a count of requests would next be allowed. Never the next UTC midnight: an allowance that only came back at midnight would lock a member out for fifteen hours after a busy morning. |
| `RequestBudgetSnapshot` | What has been spent of today's request budget, and whether work is paused. One value, so the health page, the status command and the logs cannot disagree. |
| `usedRequests` | Requests reserved so far in the day, on the snapshot and on the count as it is written down. |
| `remainingRequests` | Requests left today: on the snapshot, zero when no budget is set, so read `hasBudget` before drawing a conclusion from it; on the governor, nil when no budget is set, and reporting the counter rather than the breaker, so a caller that means "may I read?" asks `pausedUntil` too. |
| `pauseReason` | Why work is paused, or nil when nothing is paused. |
| `hasBudget` | Whether a budget is set at all. |
| `isPaused` | Whether reads and signing are refused right now. |
| `percentUsed` | Percentage of the budget consumed, or nil when no budget is set. |
| `callerShareBurst` | The most one member's caller may take before their allowance has to refill, as it is in force. Zero when shares are off, or when no budget is set and so there is no day to take a share of. |
| `throttledCallers` | How many callers are holding an allowance that has not refilled. A count, never a list of who: nothing that names a caller leaves this layer. It does not mean anybody was refused, because a caller appears in it for making a single request inside a refill interval, which is ordinary use. |
| `callerRequestsToday` | Requests taken on behalf of members today, out of `usedRequests`, so an operator can see whether members or the instance's own work is spending the day. |
| `callerRefusalsToday` | How many reservations were refused at a share today. The one figure that says a member was actually turned away, since a share refusal deliberately writes no notice, and the reason the health body carries it beside the callers held. |
| `hasCallerShare` | Whether one member's caller is bounded at all. |
| `PauseReason` | Why work is paused. Two different facts, deliberately not merged. |
| `RequestBudgetUsage` | The day's request count as it is written down. |
| `RequestBudgetStore` | Where the day's request count is kept between restarts. This layer has no idea what a database is and must not acquire one. |
| `loadBudgetUsage` | The last count written, or nil when nothing has ever been written. A row that cannot be read must throw, never come back empty: an unreadable count read as nothing recorded hands the process a fresh budget. |
| `saveBudgetUsage` | Writes the day's count, periodically rather than on every request. |
| `InMemoryRequestBudgetStore` | A count kept in memory, for tests and for trying things out. Rows do not survive the process, which is the situation a real store exists to fix. |
| `failReads` | Makes the next read throw, so a caller's handling of an unreadable row can be exercised. |
| `storedUsage` | The count as it stands, without going through the protocol. |
| `RequestGovernor` | The single daily ceiling on requests, shared by every caller. One counter and one breaker for reading and signing both. It refuses rather than queues. |
| `maxRetainedNotices` | How many notices are kept for a host that has not drained them: enough that an overnight incident is still readable, bounded so a process that never drains cannot grow without limit. |
| `maxTrackedCallers` | The most callers whose shares are tracked at once. A constant rather than a setting, because it bounds this process's memory rather than stating a policy. At the bound a caller nobody is tracking yet is refused rather than admitted untracked, and a caller part way through their allowance is never evicted, because an evicted caller returns with a full one. |
| `restoreFromStore` | Applies a counter written earlier in the same UTC day. Called once at boot; an unreadable row throws rather than granting a budget nobody gave. |
| `reserveRequest` | Spends one request from today's budget on behalf of a named caller, throwing before the request leaves rather than finding out about the ceiling by being cut off mid sweep. The caller has no default value. |
| `reserveRequests` | Spends a count of requests for a named caller, all of them or none, for a consumer whose work cannot be half done. A reservation that does not fit takes nothing and pauses nothing; a day with nothing left pauses exactly as one request would. A member's caller is held to the same rule against their own share. There is no way to hand a reservation back. |
| `recordRequestFailure` | Trips the breaker when the error is the provider's own quota refusal, and returns the error the caller should throw. |
| `unpause` | Lifts a pause by hand, for a refusal that turned out to be a revoked token or a misread. The budget itself is untouched, nothing is written to the store, and no caller is handed back any part of their share. |
| `snapshot` | Everything a status surface needs, in one value. |
| `notices` | The notices kept so far, oldest first, leaving them in place. |
| `drainNotices` | The notices kept so far, oldest first, and forgets them. |
| `flushPersistence` | Waits for every write scheduled so far to finish. |
| `RequestRateLimiter` | The per second brake, which answers to the provider's published rate and is emphatically not the daily budget. |
| `acquire` | Waits until the requests asked for are allowed, then takes them. An ask larger than the bucket can ever hold is taken a bucketful at a time rather than waiting forever. |
| `tryAcquire` | Takes the requests asked for if they are available, without waiting. |
| `availableRequests` | Requests available right now. |
| `execute` | Runs an operation once a request is allowed. |
| `TokenBucket` | The arithmetic behind the per second limiter, with no clock in it, so the boundaries are checked by a test that finishes instantly. |
| `refill` | Adds the requests that have accrued since the last refill, never above capacity. |
| `take` | Takes `count` requests if they are there, taking nothing on a refusal. |
| `waitSeconds` | How long to wait before `count` requests would be available. |
| `amountBaseUnits` | Whole tokens converted to smallest units, refusing an amount that will not fit rather than saturating. The counterpart to the ladder's saturating conversion, named apart so the two intentions cannot be confused. |
| `wholeUnits` | Smallest units as whole tokens, rounded down, so a figure shown to a member is never more of the token than they hold. |
| `UTCDay` | The day boundary the request budget counts against. UTC, never the host's local day, because the day being rationed belongs to the provider. |
| `start` | Midnight UTC at the start of the day the date falls in. |
| `nextMidnight` | Midnight UTC at the start of the following day, which is when a spent budget becomes spendable again. |
| `stamp` | An ISO 8601 instant in UTC, for a message a person will read. |
| `WalletCheck` | One wallet, read once: what it holds directly, what its pool positions are worth, and which parts of that could not be established. |
| `poolTokenBalances` | Pool tokens held, by pool id, for the pools that were read. |
| `poolCountedAmounts` | What each pool position is worth of the counted token, by pool id. A pool whose reserves were missing is absent rather than present as a zero, and a zero here would travel into a position worth nothing and demote the provider. |
| `read` | Builds a check from a completed read of a wallet's holdings. All of the interpretation lives here, away from the network, so every case can be pinned by a test. |
| `unreadable` | Builds a check for a wallet that could not be read at all. Everything is unavailable rather than zero. |
| `heldAssetIds` | The assets this wallet actually holds. Opted-in zeros are not holdings. |
| `canDecideEntitlements` | Whether this reading may be used to decide what the wallet's owner has earned. |
| `LiquidityCompleteness` | Whether a combined balance may be used to decide what somebody has earned. Split out from the code that acts on it so the rule itself can be tested. |
| `canDecideTier` | False when the total is short by an unknown amount, in which case roles are left exactly as they are rather than recomputed. |
| `CollectionCompleteness` | Whether a role that depends on holding something from a collection may be granted or taken away. |
| `decidedHoldsCollection` | True to grant, false to take away, nil to leave the member's roles exactly as they are. Granting on a partial positive read is safe; taking one away requires a complete negative read. |
| `HoldingsCacheWrite` | Whether a reading of what a wallet holds may be written to a store that other work reads later. |
| `persistableAssetIds` | The ids to store, or nil when the caller must write nothing at all and leave whatever is already there. One overload takes the flag and the list, the other reads the rule straight off a reading. |
| `WalletCheckCache` | Recently read wallets, so the same question does not become traffic. Only a complete reading is ever cached. |
| `isOnCooldown` | Whether this wallet was read recently enough that it should be left alone. |
| `shouldCheck` | Whether this wallet may be read on demand right now. |
| `invalidateAll` | Forgets everything. |
| `cachedCount` | How many answers are held. |
| `cooldownCount` | How many wallets are within their cooldown. |

The `ChainEnvironment` constants `nodeURL`, `apiToken`, `requestsPerSecond`,
`dailyRequestBudget`, `budgetPersistEvery` and `batchSize` share their names
with the configuration fields they fill, so each is described once, in the
`ChainConfiguration` or `ChainLimits` row that names the variable. The same
goes for `NodeAccountDataSource`'s three methods, which are described in the
`AccountDataSource` rows they implement.

Three further members are public to read and private to write, which the
export extractor does not currently see, so they are named here rather than in
the table above:

- `ProviderProofProbe.lastFailure`: why the last probe failed, when it did, so
  a health surface can say what is wrong rather than only that proof is
  missing.
- `InMemoryRequestBudgetStore.writeCount`: how many times a count has been
  written, for tests that care about write volume.
- `TokenBucket.tokens`: requests available right now.

`ExpiringMap` is internal and is not part of the exported surface. It is the
small time-bounded map behind the reserves cache, the wallet cache and the
cooldown, and it takes `now` as a parameter so every expiry boundary is
checked by a test that finishes instantly.

## Invariants

1. There is exactly **one** representation of the operator's token in the
   package, `Gating.TokenProfile`, read from the environment in one place and
   handed to `ChainConfiguration` as a value. This module declares no asset
   variables of its own, so an operator cannot write the asset id or the
   decimal places down twice and cannot write them down differently
   (ADOPT-1.d).
1a. The same holds for a pool and for a person's total. `LiquidityPool` and
   `CombinedBalance` belong to `Gating`, which is where their loaders and the
   rules that read them live. This module declared a second of each, and both
   `CombinedBalance` comments named the same morning. The pool was worse than
   untidy: nothing could load it, because it wanted a symbol and a decimal
   count for each side of the pair that no variable sets, and it treated a
   pool id as a free-form key where the loader slugs it, so a host that built
   one with a display id got a pool lookup that returned nil for ever and a
   badge nobody was ever granted.
2. Whole tokens become smallest units by exactly two named conversions, and
   they behave differently on purpose. `TokenProfile.baseUnits(whole:)`
   saturates, because its callers are ladder thresholds and a typo should
   produce a rung nobody reaches. `TokenProfile.amountBaseUnits(whole:)`,
   defined in this module, throws, because its callers are amounts and a typo
   should produce a refusal (RAIN-15.b). Neither is an overload of the other.
3. A figure that could not be fully read is never handed out as a plain
   integer. It is a `ChainReading`, and the value a caller may act on comes
   only from `completeValue` or `requireComplete()` (ROLE-1.a).
3a. Crossing into the rules, **a short answer becomes unknown, never a smaller
   number**. `gatingReading` and `MemberHoldings.fromChain` are the only two
   ways across, and neither has a variant taking a default. Without them the
   one line a host had to write was
   `.known(reading.valueEvenIfShort ?? 0)`, which is the original incident
   spelled out: one pool's reserves fail, the total reads as a member who sold
   up, and every liquidity provider in the server is demoted (ROLE-1.a,
   ROLE-2).
4. A 404 from the node is a **complete** negative answer and a failed request
   is not. `ChainReader.account(_:)` answers an unknown account with an empty
   complete reading; a pool read never goes through that helper, because an
   empty pool would demote every provider in it.
5. A pool that could not be read is **absent** from the reserves map rather
   than present with zeroes, and a wallet holding its pool token comes back
   short rather than poorer (ROLE-2).
6. Every request against the node is reserved from `RequestGovernor` before it
   leaves the process, and a provider refusal is reported back to the same
   governor. The counter covers reads and signing together, so the number an
   operator sets is the whole process (SEE-9).
6a. The budget has two kinds of consumer and only one of them can stop
   anywhere. A sweep of everybody's roles reads an account at a time; a payout
   run pays the whole list or should never have begun. The second kind takes
   its requests with `reserveRequests` before it starts, because the errors a
   spent budget raises mid-run are not that run's own refusal, so its claims
   are all correctly kept and the epoch under-pays and closes nothing. A
   reservation that does not fit is refused without spending anything and
   without pausing, so what is left of the day still reaches the consumers that
   can use it in pieces (SEE-9, RESERVE-7.d).
7. The day the budget counts is a UTC day from `UTCDay`, never the host's
   local day, and the counter is written to `RequestBudgetStore` every
   `budgetPersistEvery` requests so a restart does not hand the process a
   fresh budget (RUN-8.a).
8. There are two brakes and both are needed. `RequestRateLimiter` bounds
   requests per second against the provider's published rate;
   `DailyRequestBudget` bounds requests per UTC day. At the limiter's rate a
   free daily quota is reachable in minutes, and the provider's refusal
   arrives only once the quota is spent.
9. `RequestRateLimiter` measures with `ContinuousClock`, never the wall clock,
   and an ask larger than the bucket can hold is taken a bucketful at a time
   rather than waiting forever.
10. Nothing in the module logs. Everything an operator should read about the
    budget is a `ChainNotice` value kept in a bounded buffer the host drains,
    so a problem that started overnight is still there in the morning (SEE-5).
11. A health answer never means only that a process is listening.
    `ChainHealthReport.status` is `ok` only when every declared component has
    been reached, and `waitingOn` names the rest (SEE-1, SEE-1.a).
11a. **A spent budget is a field of the answer and never a status.** An
    instance that has reached everything and is refusing chain work, because
    the day's budget is gone or the breaker is tripped, answers `ok` and says
    which of the two it is in the budget section. The readiness rule that
    follows is part of this contract rather than a host's choice: an unreached
    component is not ready, and a reached instance whose budget is gone is
    ready. A gate that failed on the second would replace a working version
    because a provider quota ran out at four in the afternoon, which is RUN-3's
    failure by the other door; monitoring alerts on the field instead
    (SEE-1.a, RUN-3).
11b. **Assembling a health answer spends nothing.** `ChainHealthAssembler`
    asks the governor for a snapshot, which costs nothing and works while
    paused, and asks `ProviderProofProbe.heldProof` for proof already held,
    which makes no request and leaves the cache as it was. It touches no
    reader and no `AccountDataSource`, and it still answers once the day's
    budget is gone. An instance for which no proof headers are configured
    produces an answer that opens no socket of any kind, which is what makes
    that promise honest rather than a statement about a cache (SEE-1.b).
11d. **A read that never probes needs something that does.** Where no usable
    proof is held, the assembly starts one probe beside the answer through
    `refreshInBackground` and answers without waiting for it, so the next
    answer carries proof and this one still costs nothing. A synchronous
    probe on this path stalled the accepts of the listener this was ported
    from for up to four seconds on a cold miss, and a held read with nothing
    driving it is an answer that can never carry proof at all. One probe at a
    time, none while what is held is within its lifetime, and a probe that
    failed is kept for that same lifetime, or a check on a timer becomes the
    load on a node that is already down (SEE-1.b, SEE-10.a).
11c. This module owns **no listener, no route and no HTTP status code**. What
    an instance has to have reached is a list only a composition root knows,
    and it arrives as a parameter.
12. Provider proof is never invented. `ProviderProofProbe` drops a stale answer
    on a failed probe rather than serving it on, and `ProviderProof.parse`
    contributes nothing for a header that was absent or blank (SEE-10.a,
    HOST-5.a).
13. Only a complete reading is ever cached. `WalletCheckCache` writes a
    reading into its cache only when `combinedBalance.isComplete`, so one bad
    moment cannot be served as a wallet's balance for the whole lifetime of an
    entry.
14. Nothing that touches an amount touches `Double`, `NumberFormatter` or a
    locale. `Double` appears only in the rate limiter, where a rate is a rate
    and nothing is ever converted into an amount (LEARN-7.b).
15. Every read of the chain goes through `AccountDataSource`, so the whole
    test suite runs with no network and cannot reach a real node whatever is
    configured on the machine (BUILD-2, BUILD-2.a).
16. Time arrives as a parameter. Every cache, cooldown, budget roll and expiry
    takes `now`, so no test sleeps and no boundary is checked at one lifetime
    only.
17. Nothing in this module falls back to a value somebody else chose. There is
    no default asset, no default pool, no default proof header and no default
    node; a missing required variable is a refusal naming it (ADOPT-2,
    ADOPT-6.a).
18. The environment has **one set of rules**, and they live in
    `Gating.NumberedEnvironment`. What counts as set, what counts as blank,
    whether `100_000` is a number and whether a URL needs a host are answered
    once for the whole package rather than once per module. They used to be
    answered three different ways: `TIER_1_MIN=100_000` loaded while
    `CHAIN_DAILY_REQUEST_BUDGET=100_000` was refused, a trailing newline was
    fine here and a refusal there, and `CHAIN_NODE_URL=http://` booted clean
    and then failed every read as a network error. An operator has one
    environment, not one per module (ADOPT-2).
19. **Every reservation names who it is for, with no default**, and the
    caller is one of two cases: work on behalf of a member, or the instance's
    own. Only the first is rationed. A default would mean a host that forgot
    got the unrationed path in silence, which is the guard bypassed by an
    omission, and the caller reaches the governor from the call that started
    the work because the one place that spends a request can only charge
    somebody it was told about (RUN-11).
19a. A member's caller is held to a share of the day: a percentage of the
    budget with a burst on top, refilling as the day passes rather than being
    withheld until midnight. A caller who has drawn their share is refused at
    once with `callerShareSpent`, never queued, and that refusal spends
    nothing of the day, trips no breaker, pauses nothing and writes no notice.
    The pause is checked **before** the share, so an instance refusing
    everybody tells everybody the same story (RUN-11, SEE-11). A reservation
    larger than the burst is refused with `callerShareCannotCover` and **no
    instant at all**, because no allowance ever holds more than its burst and
    a date there would be a fixed point rather than a waiting time (RUN-11).
19b. The tracking is bounded. A caller whose allowance has refilled completely
    is forgotten, because a full allowance is indistinguishable from a caller
    nobody has heard of; at `maxTrackedCallers` a caller not already tracked
    is refused rather than admitted untracked, and one already drawing is
    never evicted, because an evicted caller returns with a full allowance.
    The allowances are not persisted, so a restart hands a caller at most one
    fresh burst while the day's own count is restored from the store
    (RUN-11, RUN-8.b).
19c. **This bounds one caller and not a crowd.** Twenty members each inside
    their share can still finish a small day's budget between them, and the
    day's budget is the backstop for that. Nothing in the documentation may
    imply otherwise (RUN-11).
20. Lifting a pause by hand returns no part of the day and no part of any
    caller's share. The count, what is left of it, the limit, the day's start
    and every allowance are unchanged across an unpause, whatever tripped the
    pause and however many times it is lifted, and nothing is written to
    `RequestBudgetStore`, so a repeated unpause cannot walk the persisted
    figure downward (RUN-10.a, RUN-8.b).

## Behavioral Examples

### Scenario: One unreadable wallet does not demote the person who owns it

- **Given** a member with four linked wallets, three of which read cleanly and
  one of which fails
- **When** `BalanceCombiner.combine` adds them up with no stored balance for
  the failed wallet
- **Then** the result is `.short`, carrying the three real balances and the
  gap that names the failed request, and `canDecideEntitlements` is false, so
  the caller leaves every role exactly where it is (ROLE-1.a)

### Scenario: A pool that could not be read leaves its providers short, not poor

- **Given** a wallet holding pool tokens of a configured pool, and a reserves
  map that has no entry for that pool because the read failed
- **When** `WalletCheck.read` interprets the holdings
- **Then** `liquidityAmount` is `.short` with
  `ChainReadGap.poolReservesUnavailable`, never `.complete(0)`, and the
  combined balance inherits the gap (ROLE-2)

### Scenario: A pool that could not be read does not cost a member their rung

- **Given** a member on the top rung of the ladder, one configured pool, and a
  read in which the pool's reserves did not load
- **When** `MemberHoldings.fromChain` builds the member and `RoleRules.decide`
  runs on them
- **Then** the combined balance is `unknown`, every rung's role drops out of
  the managed set, nothing is revoked and the member keeps the rung. The join
  is the whole test: the only accessor that hands a number back from a short
  reading is named `valueEvenIfShort`, and there is no route from it into a
  `Reading` (ROLE-1.a, ROLE-2)

### Scenario: The pools an operator wrote down are the pools this layer reads

- **Given** `POOL_1_ID`, `POOL_1_LP_ASA`, `POOL_1_PAIRED_ASA` and
  `POOL_1_DECIMALS` set, and nothing else about pools anywhere
- **When** `Gating.LiquidityConfiguration` loads them and the catalogue is
  handed straight to `WalletCheck.read` or `BatchedChainReader.check`
- **Then** a wallet's pool position is valued, with no field a host had to
  invent to get there (ADOPT-1.b, ADOPT-2)

### Scenario: The configured precision is checked against the chain at boot

- **Given** `TOKEN_DECIMALS` set to 6 and a node that reports the asset as
  having 2
- **When** `ChainReader.verifyAssetDecimals()` runs at startup
- **Then** it throws `ChainError.assetDecimalsDisagree`, and the message names
  both numbers and the two variables to correct, rather than the process
  coming up and reporting every balance ten thousand times too large
  (ADOPT-12.a, ADOPT-2)

### Scenario: The day's budget is spent before the provider says so

- **Given** a `RequestGovernor` with a daily budget of 4,000 requests and 4,000
  already reserved
- **When** anything calls `reserveRequest`
- **Then** it throws `ChainError.requestBudgetSpent(until:)` before a request
  leaves the process, one notice is recorded rather than one per refusal, and
  `snapshot` reports the same pause to every surface that asks (SEE-9, SEE-5)

### Scenario: Work that cannot be half done does not start half covered

- **Given** a `RequestGovernor` with a daily budget of 100 requests, 96 of them
  spent, and a payout that needs 10 requests or none
- **When** the host calls `reserveRequests(10)`
- **Then** it throws `ChainError.requestBudgetCannotCover(requested: 10,
  remaining: 4)`, the counter still reads 96, nothing is paused, and the next
  `reserveRequest` from the role sweep succeeds: the four that are left belong
  to the caller that can use them (SEE-9)

### Scenario: A restart does not hand the process a fresh budget

- **Given** a store holding 3,000 requests used against today's UTC day start
- **When** a new `RequestGovernor` calls `restoreFromStore`
- **Then** the counter resumes at 3,000, the thresholds already crossed are not
  announced again, and a count from an earlier day is ignored rather than
  spent against today (RUN-8.a)

### Scenario: One member typing fast cannot spend the day

- **Given** a daily budget of 1,000 requests, a share of five percent and a
  burst of ten, and a member whose commands have taken ten requests in a few
  seconds
- **When** that member's caller reserves an eleventh
- **Then** it is refused with `callerShareSpent`, naming when their next
  request would be allowed as their allowance refills; the day's counter still
  reads ten, nothing is paused, no notice is recorded, and a second member and
  the role sweep are both served at the same instant (RUN-11)

### Scenario: A member orders a job no allowance could ever hold

- **Given** the same budget, share and burst of ten
- **When** a member's caller reserves twenty requests together
- **Then** it is refused with `callerShareCannotCover(requested: 20, burst:
  10)`, which carries no instant, because there is none: an allowance never
  holds more than its burst, so a host retrying at a promised time would be
  refused identically forever. Nothing is taken from the caller or from the
  day (RUN-11)

### Scenario: A health answer on a cold start

- **Given** an instance whose operator named proof headers, and a probe that
  has never run
- **When** a monitoring check asks for a health answer, and asks again a
  moment later
- **Then** the first answer comes back at once with no provider section, one
  probe having been started beside it, and the second carries the headers the
  provider stamped. The answering path waits on no provider either time
  (SEE-1.b, SEE-10.a)

### Scenario: A health answer during an outage

- **Given** an instance that has reached everything it declared, whose day's
  budget is spent
- **When** a monitoring check asks for a health answer
- **Then** the answer is assembled without reserving a request and without the
  data source being called at all; the status is `ok`, because reachability is
  what the status is about, and the body's budget section says the budget is
  spent and when reading resumes (SEE-1.b, SEE-1.a, RUN-3)

## Error Cases

| Condition | Behavior |
|-----------|----------|
| A token whose asset id is zero | `ChainConfigurationError.invalidValue` naming `TOKEN_ASSET_ID`, because zero names the chain's own currency and an unset variable arrives as zero |
| A token with more than 19 decimals | `GatingConfigurationError.unsupportedDecimals` from `TokenProfile.init`, before anything exists that could misreport a balance |
| `CHAIN_NODE_URL` unset or blank | `ChainConfigurationError.missing` naming the variable |
| A node url that is not `http` or `https`, or has no host | `ChainConfigurationError.invalidValue` naming what was expected. `http://` used to boot clean and fail every read afterwards |
| A rate below one request per second | `ChainConfigurationError.invalidValue`, because a bucket that cannot hold one request hands none out and its callers wait forever |
| A batch size below one, or a persist interval below one | `ChainConfigurationError.invalidValue` naming the variable |
| A cache lifetime that is negative or not a number | `ChainConfigurationError.invalidValue` naming the variable |
| A budget that is not a whole number | `ChainConfigurationError.invalidValue` naming what was expected |
| A pool LP asset id of zero | `ChainConfigurationError.invalidValue` from `LiquidityPool.validate`, because an unset variable arrives as zero and nobody holds asset zero as a holding |
| A pool whose own token is the counted token | `ChainConfigurationError.invalidValue`, because a direct holding would be counted a second time as a pool position |
| A pool paired with itself | `ChainConfigurationError.invalidValue`, because there is no other side to value a position against |
| Two pools sharing an id | `ChainConfigurationError.duplicatePoolId` from `LiquidityPool.validate` |
| A number written with digit separators | Read as the number. `100_000` is `100000` wherever this package reads one |
| A variable carrying the newline its file gave it | Read as the value without it, in both modules |
| No wallets at all handed to `BalanceCombiner.combine` | `unavailable(gaps: [.notRead])`, never a complete total of nothing |
| Whole tokens that overflow when scaled | `ChainConfigurationError.amountOverflows` from `amountBaseUnits(whole:)`; the ladder's own conversion saturates instead, by design |
| An address that is not canonical | `ChainError.invalidAddress`, raised before a request is spent on it |
| The node answering 404 for an account | Not an error: an empty `ChainAccount`, because the node told us |
| The node answering 404 for an asset | `ChainError.assetNotFound` |
| The node answering anything else | `ChainError.api(statusCode:message:)`, with the status code kept |
| A request that did not complete | `ChainError.network`, and the wallet reads as `.unreadable` rather than empty |
| Configured decimals disagreeing with the chain | `ChainError.assetDecimalsDisagree`, refusing to start |
| Today's request budget spent | `ChainError.requestBudgetSpent(until:)`, paused until UTC midnight |
| A 403 from the provider mentioning a quota | `ChainError.providerRefusedQuota(until:)`, the same pause from a different cause |
| A bulk reservation larger than what is left of the day | `ChainError.requestBudgetCannotCover(requested:remaining:)`. Nothing reserved, nothing paused, no notice recorded: the refusal is answered to its caller, and a scheduled run that repeats it must not be able to push the pause announcement out of a bounded buffer |
| A bulk reservation on a day with nothing left | `ChainError.requestBudgetSpent(until:)` and the ordinary pause, because at that point every size is refused |
| A bulk reservation of zero | Allowed, spending nothing and recording nothing, so sizing an empty job cannot be what pauses a process |
| A member's caller reserving more than their share has left | `ChainError.callerShareSpent(requested:shareRemaining:nextAllowedAt:)`. Nothing is taken from the day or from the caller, nothing is paused, and no notice is recorded: one member refused thousands of times must not push a pause announcement out of a bounded buffer |
| A member's caller reserving more at once than the burst | `ChainError.callerShareCannotCover(requested:burst:)`, carrying no instant, because no allowance ever holds more than its burst and a date there would be a fixed point rather than a waiting time |
| A member's caller arriving when `maxTrackedCallers` are already drawing | The same refusal as a spent share, because admitting a caller untracked is the hole the share exists to close, and the instant it names is the next sweep rather than midnight: a slot comes free as soon as any tracked caller refills. One notice a day records that the bound was reached, and the day's budget is the backstop underneath it |
| A share above one hundred percent, or a burst of zero | `ChainConfigurationError.invalidValue` naming the variable. Refused rather than clamped: an operator who wrote 500 meant something. Built in Swift rather than read from the environment, the same two are held inside the range the initialiser documents, because a percentage above a hundred can overflow the share's arithmetic and a burst of zero switches the guard off in silence |
| A share configured with no daily budget | No share at all, and nobody is ever refused by one. There is no day's budget to take a part of |
| A caller asking a short reading for a number | `ChainError.incompleteRead(gaps:)` from `requireComplete()` |
| A pool token naming no reserve account | `ChainError.poolAddressNotFound`, rather than reporting an empty pool |
| A budget row that cannot be read at boot | `restoreFromStore` rethrows the store's error; refusing to start beats starting with a budget nobody granted |
| A budget row that cannot be written | A `ChainNotice.Kind.budgetNotPersisted`, and the process carries on reading |
| A proof probe that failed | No provider section in the health body, and `lastFailure` says why. A stale answer is dropped, never served as current, and the failure is kept for the probe's lifetime so a check on a timer does not probe a node that is down once per check |
| A health answer wanted while the budget is spent or the breaker is tripped | Still answered, with the status unchanged and the budget section naming which of the two it is and when reading resumes |
| A health answer wanted with no proof held yet | Answered at once without one, and a single probe is started beside it so the next answer carries proof. The answering path never waits on a provider |
| A snapshot taken after midnight and before the day's first reservation | Answers for the day it was asked about: nothing used, the whole budget left, no caller figures. Nothing rolls a counter but a reservation, and the case is widest when yesterday's budget was spent and so nothing is reserving |

## Dependencies

- Foundation, and `FoundationNetworking` on platforms that split it out.
- `Gating`, for the types the two layers share and for the rules an operator's
  environment is read by: `TokenProfile`, `LiquidityPool`,
  `LiquidityPosition`, `CollectionCatalog`, `Reading`, `MemberHoldings`,
  `CombinedBalance` and `NumberedEnvironment`. This module adds to them in
  extensions, and declares no rival of any of them. `Gating` has no spec of
  its own yet, so `depends_on` is empty rather than naming one that does not
  exist.
- `Algorand` (the `swift-algorand` package), used only inside
  `NodeAccountDataSource`. Nothing above that file names the client library.
- The host supplies `RequestBudgetStore` for the day's counter and, in a test,
  its own `AccountDataSource` and `HTTPHeaderProbe`.
  `InMemoryRequestBudgetStore` ships with the module.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-09-18 | maintainers | Spec written for the `Chain` library target, after `ChainAsset` was removed and the module took `Gating.TokenProfile` as its one token. |
| 2026-09-18 | maintainers | `RequestGovernor.reserveRequests` takes a whole job's requests at once for a consumer that cannot be half done, refusing without spending or pausing when they do not fit; `remainingRequests` answers nil when there is no budget. |
| 2026-09-18 | maintainers | One `LiquidityPool` and one `CombinedBalance`, both `Gating`'s; `PoolReserves` and `PoolShare` renamed their sides counted and other; `GatingBridge` added, so a `ChainReading` reaches the rules as a `Reading` and a `[WalletCheck]` reaches them as a `MemberHoldings`; the environment read through `Gating.NumberedEnvironment`. |
| 2026-09-19 | maintainers | Every reservation names a `RequestCaller`, with no default, and a member's caller is held to a refilling share of the day; the snapshot carries what throttling is happening; `ChainHealthAssembler` and `ProviderProofProbe.heldProof` assemble a health answer that spends nothing and still answers once the budget is gone, with the budget as a field of the report and never a status; the unpause guarantee is stated normatively. |
| 2026-09-19 | maintainers | The health answer starts a probe in the background when it holds no proof, so the read that never probes has something filling it, and a failed probe is cached for its lifetime; `callerShareCannotCover` refuses a count no burst can hold rather than naming an instant that will never come; a caller refused at the tracking bound is told the next sweep rather than midnight; the snapshot answers for the day it is asked about; the health body carries the refusals as well as the callers held; `ChainLimits` built in Swift holds the share range its own documentation states. |
| 2026-09-19 | SpecSync | satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted: Satisfy four criteria the catalogue states and the code does not: which period a boundary-crossing payout was counted against, unpausing that cannot hand out a second day of budget, a per-caller share of the day, and a health answer that costs nothing |
