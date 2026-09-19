# Changelog

Everything worth knowing about between one version of this package and the
next, so that somebody running it can tell what changed without reading a
diff, and can tell whether a hole somebody found is still in the version they
have (TRUST-3.a).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
How a release is cut and how its number is chosen is in
[CONTRIBUTING.md](CONTRIBUTING.md#releases).

**Nothing has been released.** There are no tags, so there is no version you
can depend on yet and nothing below has shipped. Everything here is in `main`.
Comparison links appear beside each version once there is a first tag to
compare against.

## [Unreleased]

### Added

- **The package is a program.** A `Runtime` target holding the composition
  root and a `BotMain` executable published as `bot`, so `swift run` does
  something. Four verbs: `run`, `check`, `rehearse` and `help`.

  - **Eight boot gates in a fixed order** that no setting can change: the
    spending banner, the configuration, the store, the day's request count,
    the bind, the node, the chat service and the loops. Each either passes or
    stops the process with a code a supervisor can act on: 64 usage, 69
    something already here or unusable, 70 internal, 78 the configuration is
    wrong.
  - **Nothing can identify to a chat service before the listener has bound**,
    and that is enforced by a type rather than by the order of two statements:
    a completed bind returns a value whose initialiser is internal, and the
    chat seam's connect call requires one.
  - **The store's exclusive lease is taken before the socket**, because it
    asks the real question, which is whether another instance is using *this
    data*. A second instance pointed at the same store on a different port is
    refused with 69 and told the other copy keeps serving.
  - **One description of every variable this build reads**, with each name
    taken from the constant that owns it. A variable read but not described
    stops the boot; a variable in a prefix this build owns that nothing read
    is reported with the entry it is one edit from; a variable in a prefix
    reserved for a part this build has not got, such as `DISCORD_` or
    `VERIFY_`, stops the boot naming it.
  - **A startup report at every start**, including one that then refuses, that
    no setting can suppress, written section by section as the start makes it
    rather than in one go at the end: a start killed by a supervisor's
    timeout while the node is not answering has still printed the banner, the
    catalogue, what it made of your settings, whether it created the store
    and the address it bound. It says what the build made of the settings:
    every rung in whole tokens and in smallest units, every collection, every
    pool, the admin list in full, the node's host, which parts are off and
    why, and the variable each numbered list stopped at. It never prints a
    secret's value, length, prefix or hash, and never a URL's path or query.
  - **`GET /health`** on `HEALTH_ADDRESS` and `HEALTH_PORT`, answering 200 when
    every enabled part has been reached and 503 with `starting` until then. It
    costs no chain request and still answers when the day's budget is spent. A
    part you switched off contributes no part to wait for rather than one
    reported as reached by a gate that asked nothing. The provider proof it
    can carry is probed once at the start and after that only when somebody
    has asked for an answer, so an instance nobody checks costs your provider
    one request for its whole life. One slow client costs one connection: the
    request is read on a thread of its own, never on the accept loop. A
    listener that dies stops the instance with 70 and gives the store's lease
    back, rather than leaving a process up that nothing can check and no
    replacement can take over from.
  - **Whether a build can spend is a parameter of the composition**, never a
    reading of the settings. No payer is compiled in, so every build says so
    in its first line, and there is no `TEST_MODE`, `DRY_RUN` or `SAFE_MODE`.
  - Three new variables and no more: `STORE_PATH` (required, absolute),
    `HEALTH_PORT` (required) and `HEALTH_ADDRESS` (loopback by default).
  - No new package dependency. The chat seam is a protocol over Foundation
    types with a role and a member both `String`.
- **`Surface` and `SurfaceDiscord`: a chat surface, not yet wired to the
  program.** The command catalogue, the router, the cards and four command
  handlers — `/ping`, `/help`, `/verify` and `/unlink` — with the adapter that
  would carry them to Discord. The `bot` executable links `Runtime` and
  `StoreSQLite` only, so nothing in this release registers a command or opens
  a gateway; wiring is the next change. Four things in it are worth reading
  about before that happens.
  - **A command list Discord would reject fails a test, not a deploy.**
    `CommandValidator` refuses offline everything Discord refuses at
    registration, including a required option placed after an optional one,
    and the boot runs it before the registration call. A rejected registration
    fails a boot, and under a supervisor that restarts the process it fails
    again, for ever.
  - **The ports are bound before the gateway is identified.** Binding is how a
    process discovers that another copy is already running. A second copy that
    identified first would take the live copy's session away, because Discord
    invalidates the session a duplicate identify collides with, and would then
    exit anyway. Health therefore answers `503 starting` until the gateway is
    ready: a bound socket is not health. Ready means the gateway's own ready
    event, because asking a chat library to connect returns before the
    websocket is open; nothing else raises health, and the event stream
    ending lowers it again.
  - **Nothing that blocks runs on the cooperative pool.** `accept`, `recv`
    and `send` each run on a thread of their own and every accepted socket
    carries a timeout, so peers that connect and say nothing cost short-lived
    threads instead of stopping the gateway, every command and the health
    answer. A failed `accept` is retried with a doubling wait rather than
    ending the listener, and fifty failures in a row exit the process so a
    supervisor starts a working one: a bound port nothing serves goes on
    passing a health check while every callback is lost.
  - **Every payload is bounded in UTF-16 code units**, which is the unit
    Discord counts in. `String.count` counts grapheme clusters, so a card of
    emoji passes a `count` check and is refused by the API, and because the
    handler deferred first the member sees a thinking indicator that never
    resolves. An over-long payload is clamped, or refused with a sentence when
    truncating it would change what it says, and refusing covers the counted
    bounds too: a card over twenty-five fields, over twenty-five buttons or
    over the six thousand characters Discord adds an embed up to is refused
    rather than sent with the end of it missing.
  - **Every message edit carries an `attachments` array**, empty rather than
    absent, because an edit replaces the list and omitting it makes a card
    appear to freeze.
- **The chat client is confined to one target.** `Surface` holds the rules and
  the handlers and declares no chat client, so the whole of it is tested with
  no token, no network and no guild. `SurfaceDiscord` is the only target that
  imports it, which the manifest and a test both enforce. A member is a
  `String` below that boundary.
- **A verification callback that applies roles.** The listener validates the
  payload before it answers `200`, so a portal never records a verification
  this bot discarded. Then: admit the member, prove the account, read every
  account they have, build holdings with unknown rather than zero where a read
  failed, decide with `RoleRules`, and apply only the managed set in one call.
  A balance nobody could read holds the roles it decides rather than taking
  them away, and that rule holds on `/unlink` as well: an account that was
  proved and never read makes the total unknown rather than adding a zero to
  it. The rate limit counts the callback route and nothing else, because
  behind a reverse proxy every request shares one address and a scanner would
  otherwise lock the portal out. With no shared secret configured the route
  does not exist at all and answers `404`, and a callback that arrives before
  the store is open is answered `503` so the portal retries rather than
  recording a verification that was thrown away. Every role write is read
  back, because the chat client answers `200` and silently drops a role id it
  does not recognise.
- **`Reserve`**: a finite pot, split into named streams, paid to recipients
  over epochs at a fixed share per slot, with four independent guards against
  paying one period twice. It plans and it records. It never sends anything,
  and it has no idea what a database is: the ledger lives behind the
  `ReserveStore` protocol, which ships with an in-memory implementation for
  tests.
- **`Gating`**: what holding something on chain earns somebody in a server. A
  tier ladder, a collection catalogue with a match rule per collection, a pool
  catalogue, and the pure decision that turns what a member holds and the roles
  they have now into the roles they should have. A role the operator did not
  configure is never touched, and a fact nobody could read manages nothing
  rather than being read as zero.
- **`Games`**: three games of cards and chance as reducers over a context that
  carries the clock and the randomness, so a table replays exactly from a seed.
  Chips are a score: there is no path from a game to anything that moves value.
- **`Chain`**: reading an account, an asset and a pool from an Algorand node,
  behind a per-second rate limiter on a monotonic clock and a per-UTC-day
  request budget that survives a restart through the `RequestBudgetStore`
  protocol. Every figure it hands out says whether it is the whole answer, and
  a short answer becomes unknown rather than a smaller number.
- **`Verify`**: deciding whether an Algorand account is controlled by whoever
  presented a proof of it, in this process, with no second service. It mints
  the five lines a member's wallet asks them to sign, keeps the session those
  lines belong to, reads the signed transaction that comes back as a slice of
  the bytes that arrived rather than a re-encoding, and applies fifteen
  ordered refusals to it. Exactly one proof shape is accepted, a zero amount
  self payment whose fee is bounded at the network minimum, and `rekey`,
  `close`, `aclose`, `lx` and `grp` are each refused whether or not the
  signature is good, so nothing this bot blesses could empty or reassign an
  account if it leaked. There is no setting, flag or build configuration that
  skips the signature check. It opens no connection, reads no clock, reads
  nothing from outside the process and holds no key, and a suite reads its own
  sources to prove each of those. A member is an opaque string it never
  interprets.
- **A new direct dependency**: `apple/swift-crypto`, at the 3.15.1 the lock
  file already pinned, so no resolved version moved. It was arriving with
  `swift-algorand` and being used without being declared, which is a
  dependency this package could not pin (TRUST-1.b, TRUST-4).
- Every target's configuration is read from numbered environment variables,
  with no default that somebody else chose: a missing required variable is a
  refusal that names it.
- `hi/`, the intent catalogue: nineteen families of criteria with permanent
  ids, written before the code and cited by the tests.
- `specs/`, a contract per module, checked against the exported API by
  `specsync check --strict` in CI.
- 1131 tests in 91 suites, all offline. No test reaches a network, and none
  needs a key, a funded wallet or a Discord server. Every signature in the
  verification suite is produced by a real signer over a real challenge with a
  key generated inside the test, so the production path runs unchanged. The
  chat surface's own tests cannot reach a live host at all: the target holding
  most of them does not depend on the one that can build an HTTP client.
- `docs/CONFIGURATION.md`: every environment variable an operator sets,
  grouped by what they are deciding rather than alphabetically, each with its
  default and one sentence on what goes wrong when it is wrong. It states
  which mistakes refuse by name and which load silently, and ends in a worked
  `.env` for a small community, loaded through the real loaders while the
  document was written. Nothing re-runs it yet, and the document says so
  through the real loaders, so the example cannot quietly stop working
  (ADOPT-2, ADOPT-4).
- **`Reserve`**: an epoch's durable record now names the spending period each
  run of it was measured against, as an ordered list written before the first
  payment of that run. An epoch cut short on one side of a ceiling's boundary
  and resumed on the other names both periods, in the order they were charged,
  each with the figure that run was checked for, so an operator reconciling a
  payout against a weekly cap reads the answer instead of subtracting
  timestamps. A host that states no ceiling records nothing, and nothing is
  ever inferred (SPEND-9.c).
- **`Chain`**: one member's share of the day's request budget. Every read says
  whose it is, a member's caller may draw a configured percentage of the day
  with a burst on top, refilling as the day passes, and a caller who has drawn
  their share is refused at once with the instant their next request would be
  allowed. The refusal spends nothing of the day, pauses nothing and writes no
  notice, and the instance's own work carries no share. Two new variables,
  `CHAIN_CALLER_SHARE_PERCENT` (5) and `CHAIN_CALLER_BURST_REQUESTS` (10),
  neither of which does anything unless a day budget is set (RUN-11).
- **`Chain`**: a health answer that can be assembled without spending a
  request and still answers once the day's budget is gone, with what is left
  of the budget and any pause on it as a field rather than as a change of
  status. `ProviderProofProbe` gained a read that answers from the proof it
  already holds without going to fetch any, and a refresh that fills it in the
  background when the answer has none, so a check never waits on a provider
  and the next one carries proof. A probe that failed is kept for its cache
  lifetime, so a node that is down is not probed once per check. Nothing
  serves the answer yet (SEE-1.b, SEE-10.a).
- `docs/README.md`: which document owns which fact, and the rules that keep
  the set from drifting into contradiction.
- `docs/WHAT-IT-TALKS-TO.md`: every outside service the package contacts and
  every secret it asks for, derived from the source, with the commands that
  check each claim and a plain statement of what a reader cannot check by
  grepping this repository (TRUST-1).
- A Linux job in the test workflow, on a GitHub-hosted runner in an official
  Swift container image. The deployment target is a Linux container, and until
  now nothing had ever been built for one.
- This file, and a section in `CONTRIBUTING.md` on how a release is cut.

### Changed

These three are source-breaking for anything already compiled against the
library products. Nothing has been released, so nothing outside this
repository can be affected yet, but they are written down because the point of
this file is that somebody can tell.

- **`Games`**: `Chips.dailyStipend(_:perks:) -> Int` is now
  `Chips.dailyClaim(_:perks:) -> Chips.DailyClaim`. The old signature could
  only say how many chips, so a caller could not tell a claim that was refused
  because it had already happened today from one that paid nothing.
- **`Reserve`**: `ReservePlanner.requireWithinLimits(plan:limits:)` takes a
  `now: Date`, with no default. A spending ceiling belongs to a period, and a
  check that cannot see the clock cannot tell whether the ceiling it was handed
  still describes the period the payment will land in.
- **`Reserve`** and **`Chain`**: `ReserveError` gains `spendLimitsExpired` and
  `ChainError` gains `requestBudgetCannotCover`. Both break an exhaustive
  switch.
- **`Reserve`**: `ReserveEpochRecord` gains `charges` and
  `ReserveEpochOutcome.periodKey` is renamed `cadencePeriodKey`, so a
  memberwise initialiser call and any reader of that property written against
  the old shape no longer compile. The record is the only durable thing an
  operator can read after the fact, so the period belongs on it and not only
  on the value a run returns, and the rename is what stops the cadence period
  and the ceiling's period sharing a word on the same report. The runner's
  parameter and `ReserveError.periodAlreadyPaid` follow it for the same
  reason.
- **`Store`**: the schema gains version 3, one table holding those charges. A
  file written by this build is refused by the previous one, by name, pointing
  at the copy taken before the migration. That is the existing promise being
  kept rather than a new hazard. The reverse drops the table whole, because
  the oldest SQLite this package admits at open cannot drop a column.
- **`Chain`**: `RequestGovernor.reserveRequest` and `reserveRequests` take a
  `RequestCaller`, with no default. Breaking on purpose: a defaulted parameter
  would have made either the sweep or the next command somebody writes wrong
  in silence. `ChainReader`, `BatchedChainReader` and `WalletCheckCache` name
  their caller on every read for the same reason.
- **`Chain`**: `ChainError` gains `callerShareSpent` and
  `callerShareCannotCover`, which break an exhaustive switch. The second is
  the refusal for a reservation larger than any burst: it carries no instant,
  because no allowance ever holds more than its burst, so a date there would
  be a fixed point rather than a waiting time and a host honouring it would
  retry into the same refusal forever.
- **`Chain`**: the budget figures on `RequestGovernor.snapshot(now:)` answer
  for the day they are asked about, the way `remainingRequests(now:)` already
  did. A check run after midnight and before the day's first reservation read
  yesterday's spent budget as today's, which is loudest in the case it is
  read in: the previous day's budget was gone, so nothing was reserving, so
  nothing rolled the counter.
- **`Chain`**: the health body carries `caller_refusals` beside
  `throttled_callers`. The second is not evidence of throttling, because one
  request inside a refill interval puts a caller in it; the first is the only
  place a monitoring check can see that a member was turned away, since a
  share refusal deliberately writes no notice.
- **`Chain`**: a caller refused because the tracking table is full is told the
  next sweep rather than the next UTC midnight. A slot comes free as soon as
  any tracked caller refills, and the contract that refusal is written against
  says the instant is never midnight.
- **`Chain`**: `ChainLimits`'s memberwise initialiser holds the share
  percentage and the burst inside the range it documents. The environment
  loader still refuses both by name; built in Swift, a percentage above a
  hundred could overflow the share's arithmetic and a burst of zero switched
  the whole guard off in silence.
- **`Package.resolved` grows from three entries to twenty-eight.** The chat
  client is a direct dependency and brings a NIO-based HTTP and websocket
  stack with it. Every entry is listed in `docs/WHAT-IT-TALKS-TO.md`, read out
  of the lock file rather than estimated, because `TRUST-4` is that you can
  see what else comes with it and a graph this size arriving without a diff is
  the thing the narrow version range exists to prevent.
- **The package now listens and now writes a file.** Two ports, both named by
  you with no default, both bound to `LISTEN_ADDRESS` which defaults to
  loopback; and one SQLite database at `STORE_PATH`, which also has no
  default. `docs/WHAT-IT-TALKS-TO.md` previously said the package opened no
  socket and wrote no file, and now says the opposite in the same words rather
  than dropping the claim quietly.


- `Package.resolved` is committed instead of ignored, so two clones of one
  commit build the same code (TRUST-4).
- The `swift-algorand` dependency is `.upToNextMinor(from: "0.4.0")` instead of
  `from: "0.1.0"`. A 0.x release makes no compatibility promise across a minor
  bump, so the old range allowed a dependency to break this package without
  breaking its own rules.

### Fixed

- **`Chain`**: a caller's allowance no longer hands a spent member their whole
  burst back after the wall clock is stepped backwards. A refused reservation
  at the stepped clock moved the point the next refill was measured from back
  with it, so the same interval was counted twice once the clock was
  corrected, and the refused caller then read as full and was forgotten by the
  sweep as well. Handing out free requests when the clock goes backwards is
  the one thing a limiter exists to prevent, and it is why this package's
  platform floor was raised for the per-second limiter; the share bucket had
  reintroduced it on `Date` (RUN-11).
- **`Chain`**: a health answer can now carry provider proof at all. The read
  it takes proof from never probes, deliberately, and nothing else in the
  module ever called the probe, so every answer came back with no provider
  section however the headers were configured. The third part of the path
  this was ported from, the refresh started beside the answer, had been left
  behind (SEE-10.a).
- `swift-tools-version` was `6.0`, and the package could not be built with
  Swift 6.0. The resolved graph reaches `swift-asn1` 1.7.3, whose own manifest
  requires 6.1.0, so `swift build` on a fresh clone stopped with an error
  naming a package the reader had never heard of rather than saying that this
  manifest asked for the wrong toolchain. The declared floor is now `6.1`:
  6.0.3 fails, 6.1.3 builds and passes every test on Linux, and the new Linux
  job builds on 6.1 rather than on whatever is newest that week.

### Known gaps

Not a Keep a Changelog section, and here on purpose: an operator reading this
before installing should not have to infer it from what is missing above.

- There is no Discord surface, no wallet verification, no persistence, no host
  and no executable target. Nothing here can be run or deployed.
- There is no way to ask a running instance what it has been reaching, because
  there is nothing running (TRUST-1.a is half answered, by grep). The answer
  can now be assembled, with the budget and any pause on it, and nothing
  serves it: the listener, the route and the status codes belong to whoever
  builds the executable.
- A member's share of the day is held in memory, so a restart hands a caller
  at most one fresh burst. The day's own count is persisted and restored, so
  no restart trick creates requests out of nothing.
