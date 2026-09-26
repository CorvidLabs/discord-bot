# discord-bot

A Discord bot for Algorand projects, so that holding something on chain means
something in a server. A member proves a wallet is theirs by signing a
challenge, the bot reads what that wallet holds, the role beside their name
follows, and holders can be paid from a finite reserve on a schedule.

That is the product this is meant to become. Some of it is now written.

## State

**Early. It runs, and it is not yet a bot.** This repository is being built in
the open, a piece at a time, out of a private bot that has been running a live
community for months. There is a binary: it reads your settings, tells you what
it made of them, opens its store, checks your asset against your node and
answers a health endpoint. Give it a `DISCORD_BOT_TOKEN` and a
`DISCORD_GUILD_ID` and it also opens a gateway and registers two commands,
`/ping` and `/help`. Set neither and it starts exactly as it did before,
identifying to nothing. `/verify` and `/unlink` are written and are **not**
registered, because the half of verification that answers a wallet is not
assembled here and offering a command that cannot finish is worse than not
offering it. What is missing is listed below rather than implied.

| Target | What it is |
|--------|------------|
| `Reserve` | The payout engine. A finite pot, split into named streams, paid over epochs, with fixed shares and four guards against paying a period twice. Foundation only. |
| `Gating` | What holding something earns somebody in a server: the tier ladder, the collections, the pools, and the rule that turns what a member holds into the roles they should have. Pure values, no chain, no Discord, no clock. |
| `Games` | Three games of cards and chance, as reducers. Clock and randomness arrive as parameters, so a table replays from a seed. Nothing here can reach a chain or sign anything. |
| `Chain` | Reading what an account holds on an Algorand node, and the three brakes that stop it reading too much: a per-second limiter, a per-UTC-day request budget, and one member's share of that budget. |
| `Store` | What one instance remembers between restarts: members, the accounts they proved, the sweep baseline, the payout ledger and the day's request count. Records, protocols, and a store in memory that needs nothing installed. No Discord in its package graph. |
| `StoreSQLite` | The same store on a file, using the SQLite the operating system already ships. One connection, every durability setting read back at start, an exclusive lease so two instances cannot pay the same week, and no new entry in `Package.resolved`. |
| `Sweep` | Re-reading what every member holds and moving their roles to match: the loop, the batching, the per-member reasons and the run record. The decision itself stays in `Gating`. It declares its own chat seam over `String`, so it links no chat SDK, and nothing calls it yet. |
| `Runtime` | The composition root: eight boot gates in a fixed order, the one description of every variable this build reads, the startup report, and a health endpoint that answers `starting` until the parts that must be up are up. Links no chat client and no database. |
| `Verify` | Deciding whether somebody controls an Algorand account, from a signature their own wallet produced. The five lines they sign, the session those lines belong to, a tolerant reader for what a wallet sends back, and fifteen ordered refusals. It reads nothing: no network, no clock, no key, no setting. |
| `VerifyHTTP` | The other half a member touches: the page their wallet signs against, the routes it answers, and the rate limit in front of them. The page interpolates no value and loads no third-party script — the name, the code and the expiry are fetched and written as text nodes — so there is no escaping rule to get wrong. It imports no other target in this package and reads no setting. Nothing links it yet. |
| `Surface` | What a member touches, minus the chat client: the command catalogue, the validator that refuses offline a catalogue Discord would refuse, the interaction router and its acknowledgement rules, the payload bounds counted in UTF-16, the cards, the boot order and four command handlers. It declares no chat client, so all of it is tested with no token, no network and no guild. |
| `SurfaceDiscord` | The adapter, and the only target that knows what a snowflake is. Payload mapping, interaction decoding, card rendering, role application, a listening socket and the HTTP client for the verification portal. |
| `BotMain` | The program, as the `bot` executable. The arguments, the one snapshot of the process environment, the live seams, the signals and the exit. It decides nothing: it is the only place that links `Runtime`, `StoreSQLite`, `Surface` and `SurfaceDiscord` together, and it builds a chat gateway only when you have configured one. |

```bash
swift test    # 1131 tests in 91 suites
swift run bot help
```

The store's conformance suite is one test with thirty four behaviours, run
against three backends, so it is a hundred and two checks rather than one.

### What the binary takes

| Verb | What it does |
|------|--------------|
| `run` | Walks the eight boot gates, binds the health endpoint and stays up. The default with no argument. |
| `check` | Loads your settings and prints the report a start would, opening no socket, no store file and no connection. What to point a new version at before you take it. |
| `rehearse` | Runs the role rules over members and holdings it invents, against **your** ladder, collections and pools. Opens nothing. The thing to run on a laptop with no keys. |
| `help` | The four, and the exit codes. |

Exit codes are the conventional `sysexits` ones, so a supervisor can tell them
apart: **0** stopped cleanly, **64** an argument nobody recognises, **69**
something is already here or cannot be used (a store another process holds, an
address in use, a volume that cannot promise a write), **70** internal, **78**
the configuration is wrong. 69 is the one to put in a supervisor's
do-not-restart list.

### Its own three variables

Everything else an operator sets is in
[`docs/CONFIGURATION.md`](docs/CONFIGURATION.md). These three belong to the
program itself.

| Variable | Required | What it is |
|----------|----------|------------|
| `STORE_PATH` | yes | Where this instance keeps what it remembers. **Absolute**: a supervisor restarting from another directory would otherwise open a different and empty store, which looks exactly like a first boot. |
| `HEALTH_PORT` | yes | The port `GET /health` listens on. No default, because several communities on one machine each need their own. Zero lets the operating system choose. |
| `HEALTH_ADDRESS` | no | The address to bind. Loopback unless you set it. |

A start with nothing set names the first variable to set, says what it is for,
and exits 78. A bound socket is **not** health: the endpoint answers
`503 {"status":"starting","waiting":[...]}` until every part it is waiting for
has been reached, so a deploy gate cannot promote a version that came up half
way.

Everything runs offline. No test reaches a network, and none needs a key, a
funded wallet or a Discord server.

[`docs/WHAT-IT-TALKS-TO.md`](docs/WHAT-IT-TALKS-TO.md) is the disclosure:
every outside service this contacts, every secret it asks for, the commands
that check each claim, and a plain account of what a reader cannot check by
grepping this repository. Read it before installing anything.

[`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) is what an operator sets:
every environment variable, its default, and what goes wrong when it is wrong,
ending in a worked example that a test loads through the real loaders.
[`docs/README.md`](docs/README.md) maps which document owns which fact.

### The four commands, two of which are registered

`/ping` and `/help` are registered and answered by `swift run bot` once you
set a token and a server. `/verify` and `/unlink` are written, tested and
deliberately **not** registered: they need the verification half — a callback
listener and a portal client — which the executable does not assemble, so
every `VERIFY_` variable is still refused by name rather than half-honoured.

| Command | What it does |
|---------|--------------|
| `/ping` | Says the bot is awake. Reads nothing: no chain, no store, no portal. |
| `/help` | What this bot can do **in this server**, generated from the same list the registration is, so a command that is switched off cannot be described. |
| `/verify` | Hands a member a link to prove an account, after a card saying who is asking, what is kept and what other members will see. Never asks for a key or a seed phrase. |
| `/unlink` | Lists a member's accounts, or removes one. Removing the last forgets them entirely. |

Verification needs a second piece you run, and **this repository does not
ship it**. `/verify` hands a member a link to a portal that connects a
wallet, takes a signature and calls this bot back.
[`docs/VERIFICATION.md`](docs/VERIFICATION.md) is that contract, written so
the other half can be built from it and nothing else, and
[`docs/decisions/0001-verification-portal.md`](docs/decisions/0001-verification-portal.md)
is the open question of whether it should stay a separate service at all.
Until you have one, leave `VERIFY_PORTAL_URL` unset: the boot skips
verification entirely rather than failing on it.

### What is missing

Still most of it, and what is missing is most of what a community would
actually use:

- **Verification has no way in.** The surface is wired to the program now,
  but only `/ping` and `/help` are registered. Reading a member's roles and
  setting them is implemented against the chat client and nothing calls it
  yet, so no role string from `Gating` reaches Discord.
- **No way for a member to reach wallet verification.** The part that decides
  whether somebody owns an account is here, offline and tested: `Verify` mints
  the challenge, keeps the session, reads the signed transaction a wallet sends
  back and applies fifteen ordered checks to it, with no second service
  anywhere in it. The page their wallet signs against is here too, in
  `VerifyHTTP`, served from your own machine. What is missing is the link: no
  executable assembles either target, so `/verify` stays unregistered.
  [`docs/VERIFICATION.md`](docs/VERIFICATION.md) is the contract, and
  `specs/verify/` is what was built against it, with the host's own
  obligations written down and marked as not yet evidenced.
- **The role sweep is written and nothing runs it.** `Sweep` has the loop,
  the batching, the run record and the rule that a balance nobody could read
  holds a rung rather than dropping it. Boot gate eight, where the loops go,
  is still empty, so somebody who sells keeps their rung until something
  calls it.
- **Only the smallest store.** Six tables: members, accounts, the sweep
  baseline, the payout ledger and the day's request count. No cache of what an
  account holds, no payments table, no audit log, no claim offers, no scheduled
  tasks, no game rows and no saved timezone. `specs/store/store.spec.md` lists
  each absence and what would have to read it.
- **Nothing that moves value.** No payouts, no giveaways, no draws. The
  `Reserve` engine is finished and nothing calls it, which is deliberate: the
  surface that will call it had to exist first, and it has to be trustworthy
  before it is handed a key. No payer is compiled in, every start says so in
  its first line, and there is no variable that would change it.
- **No games in the server.** `Games` is finished and no command reaches it.
- **No sweep, no scheduler and nothing that pays.** The boot has a gate where
  the loops go and it is empty. `Runtime` wires the store, the node and the
  health endpoint together and stops there.
- **No operator surfaces**: nothing to look at holdings with, nothing to make
  an announcement with, nothing to read what the last sweep did.
- **No schedule.** Nothing recurs. Nothing fires on a timer at all.
- **No presence**, because this package does not know what your token is
  called until you tell it, and a shipped one would be somebody else's.

Seven of the nineteen intent families have code standing behind part of what
they describe: RESERVE, ROLE, ADOPT, PLAY, VERIFY, LEARN and RUN. The rest are
wants that have been written down and agreed, not features that work.
[`INTENT.md`](INTENT.md) indexes them and [`hi/`](hi/) holds them, every line
with an id that never moves.

Wiring the surface into the program comes next, so that the four commands
which already exist can be typed in a server. After that the role sweep, so a
role stays true when somebody sells; then the surfaces that read rather than
write; and then the first thing that can spend.

## Why the engine first

Paying a whole community at once is the most useful thing a bot like this does
and the most dangerous. A transfer cannot be taken back, so the interesting part
is not the Discord glue: it is the arithmetic, the record that stops a week
paying twice, and the rule that a payout built from stale data pays nobody rather
than paying a short list.

That part generalises past this bot and past Discord, so it is what gets built
and documented first.

---

# The `Reserve` engine

The first of the four, and the one with the most written down about it. A finite
**reserve**, split into named **streams**, paid to **recipients** over
**epochs**. It plans and it records. It never sends anything, and it has no idea
what a database is.

## The shape

- A **reserve** is a total amount of an **asset** with some number of decimals.
  Everything is computed in whole numbers of that asset's smallest unit. There is
  no `Double`, no `NumberFormatter` and no locale anywhere in the package.
- A **stream** is a named slice: an id, a share of the reserve, a fixed
  denominator, and a payout rule. Streams are values you configure, not cases in
  an enum, so a reserve can have one stream or six.
- The shares must add up to exactly the reserve, in smallest units, or the
  configuration refuses to exist.
- A **schedule** is a count of epochs. Which durations are offered is
  configuration too.
- A **payout rule** is either `oncePerRecipient`, meaning one slot per person
  however many things they hold and however many accounts they spread them
  across, or `oncePerHeldUnit`, meaning one slot per thing held.

The rule that matters most: **a stream divides its share by its fixed
denominator, never by however many happen to be eligible today.** That is what
makes a payment knowable in advance. Divide by the eligible count instead and
every arrival shrinks everybody's payment, every departure grows it, and nobody
can be told what they will receive. Fixing the denominator means a slot nobody
claims simply stays unclaimed.

## A worked example

Ten billion whole units of a six-decimal asset. Seventy percent to a
once-per-recipient stream with a denominator of 1,000; thirty percent to a
per-unit stream with a denominator of 4,096. Paid over 26 epochs.

```
Reserve                     10,000,000,000  whole  =  10^16 smallest units

members   70%                7,000,000,000  whole
  / 1,000 slots                  7,000,000  whole  per slot, whole schedule
  / 26 epochs                      269,230.76923   per slot, per epoch
  residue                                    20    smallest units, never paid

passes    30%                3,000,000,000  whole
  / 4,096 slots                    732,421.875     per slot, whole schedule
  / 26 epochs                       28,170.072115  per slot, per epoch
  residue                                    10    smallest units, never paid
```

Every epoch pays the identical figure. A recipient told `269,230.76923` in the
first epoch is still being paid `269,230.76923` in the twenty-sixth. The
alternative, spreading the remainder so a few epochs pay one unit more, makes
every epoch a slightly different number and makes that promise impossible.

The residue is never paid and never hidden:

```
26 x 269,230,769,230  =  6,999,999,999,980
              +   20  =  7,000,000,000,000   <- the share, exactly
```

Paid plus residue equals the share, so somebody with a calculator can account for
every smallest unit. Across the full 4,096 slots of the per-unit stream, the same
reconciliation closes on exactly 3,000,000,000.

And with only 215 of the 1,000 member slots claimed:

```
in use      215 x 7,000,000  =  1,505,000,000  whole
unclaimed   785 slots        =  5,495,000,000  whole   stays in the reserve
```

Those 785 empty slots buy nobody a larger payment. That is the point.

## The guards, and why each one exists

Four separate things stop a period being paid twice, and all four were needed.
Each is here because removing it reintroduces a specific failure.

**One epoch at a time.** Reading the ledger, planning against it and paying all
suspend. Two overlapping runs see the same untouched ledger, build the identical
plan, and pay *everybody* twice, walking straight past the per-epoch record,
because the record is only read once at the start. One gate covers every stream,
not one gate each, because the reserve's state is a single value written back
whole: two streams saving snapshots taken before each other's would lose one
stream's finished epoch while its epoch record still said "complete".

**One epoch per period.** The per-epoch record does not object to running epoch 2
immediately after epoch 1, so without a cadence key the entire schedule can be
spent in an afternoon by running the command repeatedly. A firing is identified
by its *period*: an ISO week, a month. Never by a timestamp, so two runs an
hour apart collide and a genuinely missed period is still paid late.

**The claim is written before the payment.** The window between handing value
over and recording it is where one payment becomes two: the value has left,
nothing on disk says so, and the next run pays again. Claiming first inverts the
risk. A crash now leaves a claim with no payment, under-paying by one slot and
leaving the value in the reserve, which is the direction you can recover from.

**Limits are checked before the first payment.** An epoch that pays 111 of 200
recipients before hitting a ceiling is exactly the half-finished payout the whole
design exists to prevent. The period limit is measured against what is *left* of
it, not the raw ceiling, because something else may already have spent part of
it.

Two smaller rules with the same motivation:

- An epoch can be **finished but never skipped**. Marking completion used to be a
  high-water mark, which meant closing the last epoch first marked every earlier
  one done and forfeited the whole schedule without paying anybody.
- A record that will not parse **throws**. Reading an unparseable row as "nothing
  recorded" would look like an epoch nobody was paid for, and the next run would
  pay all of it again. Refusing to run is strictly better than paying twice.

## Using it

```swift
import Reserve

let reserve = try ReserveConfiguration(
    asset: try ReserveAsset(symbol: "TOKEN", decimals: 6),
    totalWholeUnits: 10_000_000_000,
    streams: [
        ReserveStream(id: "members", share: .percent(70), denominator: 1_000,
                      rule: .oncePerRecipient),
        ReserveStream(id: "passes", share: .percent(30), denominator: 4_096,
                      rule: .oncePerHeldUnit)
    ],
    schedules: [
        ReserveSchedule(id: "6m", label: "six months", epochCount: 26),
        ReserveSchedule(id: "1y", label: "one year", epochCount: 52)
    ]
)

let runner = ReserveRunner(
    configuration: reserve,
    store: InMemoryReserveStore(),   // or your own ReserveStore
    payer: myPayer                   // you implement ReservePayer
)

try await runner.activate(scheduleId: "6m")

let outcome = try await runner.run(
    streamId: "members",
    recipients: eligible,
    periodKey: ReservePeriod.isoWeek(Date())
)
```

You supply two things.

**`ReserveStore`** is where the ledger lives: four async methods, load and save
for the reserve's state and for one epoch's record. An implementation has two
obligations: a row that cannot be read must throw rather than come back empty,
and a save must be durable before it returns, because the claim-before-pay
discipline rests on the claim being on disk when the payment is attempted. An
`InMemoryReserveStore` ships for tests.

**`ReservePayer`** is whoever actually moves the value, and it may optionally
declare spending limits and an available balance. It returns a reference: a
transaction id, a receipt number. A payment is evidenced rather than
asserted. It throws `ReservePaymentRefusal` when it can *prove* nothing moved, in
which case the slot is handed back; anything else it throws keeps the claim,
because a payment that might have gone through must never be retried.

Limits are checked for being current before they are checked for being big
enough: a set whose `periodEnd` has passed is refused, because a ceiling from a
period that is over says nothing about what is left of this one, and a host
that computes its figures from a stored total can hand one over without
noticing.

Also useful: `runner.audit(eligible:)` previews the whole reserve without moving
anything, and `runner.rehearse(streamId:recipients:now:)` plans the next epoch
through the very same guards a real run uses, writes nothing, and refuses exactly
where a real run would.

## What it deliberately will not do

- It does not send. There is no network, no chain, no key material.
- It does not store. No SQLite, no schema, no file format.
- It does not read a clock to decide anything. Periods and timestamps are passed
  in, so every test pins them.
- It does not redistribute unclaimed slots, ever.
- It does not clamp an amount to fit a limit. It refuses the whole run.

---

# The other three

## `Gating`

What holding something earns. A **tier ladder** an operator numbers from 1, a
**collection catalogue** with its own match rule per collection, a **pool
catalogue**, and `RoleRules.decide`, which takes what a member holds and the
roles they have now and answers which roles they should have.

Two rules run through all of it. **A role the operator did not configure is
never touched**, so a badge a moderator handed out by hand survives every sweep.
And **a fact nobody read manages nothing**: the roles that fact would have
decided drop out of the managed set and are held rather than stripped. That
second rule is why `Reading` exists, and why it deliberately has no accessor
that hands back a value with a default. Silence from a data provider is not
evidence that somebody sold up, and a sweep that acts as though it were takes
roles away from people who did nothing.

Nothing in it is a fact about one project. The ladder, the thresholds, the
collections, the pools and every role id are read from numbered environment
variables, the first gap ends each list, and a half-written entry is a refusal
naming the variable rather than a default somebody else chose.

## `Games`

Games of cards and chance as reducers over a `GameContext` that carries the
clock and the randomness. A table replays exactly from a seed, so a rule can be
pinned by a test rather than played until it looks right.

Chips are a **score**. There is no path from a game to anything that moves
value, no conversion in either direction, and the target has no dependency
through which it could acquire one.

## `Chain`

Reading an account, a pool and an asset from an Algorand node, behind three
brakes: a per-second rate limiter on a monotonic clock, a per-UTC-day request
budget that counts reads and signing together and is written down so a restart
does not hand the process a fresh one, and one member's share of that budget.

The third one is a different kind from the first two. They bound how hard the
instance reads; it bounds how much of that any one person can cause. Every
read says whose it is, with no default, and only work done on behalf of a
member is rationed: a share of the day's budget with a burst on top, refilling
as the day passes, so a member who spends it in a minute waits minutes rather
than until tomorrow. The instance's own work, the sweep and a scheduled payout,
carries no share at all, because a sweep is not a person and is already bounded
by its batch and its interval. With no day budget set there is no share either,
because there is nothing to take a part of. It bounds one member and not a
crowd; the day's budget is the backstop for that.

It can also say whether it is working without spending any of the budget it is
reporting on, and it still answers once that budget is gone, which is exactly
when somebody is looking. Assembling the answer reserves nothing, touches no
data source, and takes provider proof from what the probe already holds rather
than going to fetch some. When it holds none it starts one probe beside the
answer instead of in front of it, so the check never waits on a provider and
the next one carries the proof.

The other half of its job is refusing to invent an answer. A request that did
not come back is not an account holding nothing, and a pool whose reserves could
not be read is not a pool worth nothing. Every figure it hands out is a
`ChainReading`, which carries whether it is the whole answer, and the only two
routes from one into a decision turn a short answer into **unknown** rather than
into a smaller number.

The budget has two kinds of consumer and only one of them can stop anywhere. A
sweep of everybody's roles reads an account at a time; a payout either pays the
whole list or should never have begun, so it takes its requests in one piece
with `reserveRequests`, before the first one leaves. A reservation that does
not fit is refused without spending anything and without pausing, so what is
left of the day still reaches the work that can use it in pieces.

It shares `Gating`'s token, pool, readings and totals rather than declaring its
own, so an operator writes each of them down once and cannot write one down
twice differently.

---

## How this repository works

Intent is written down before code, as plain sentences about what somebody wants,
each with an id that never moves. [`INTENT.md`](INTENT.md) indexes the families
and `hi/` holds them. [`hi/reserve.md`](hi/reserve.md) is the fullest: the
engine's 52 criteria were written before any of it was built, and the tests cite
them by id. Module contracts live in `specs/` beside the code and change in the
same pull request it does. All four targets have one, and every source
directory is registered with the gate, so an export that grows without a
contract fails a pull request rather than passing unread.

Every change arrives through a pull request.

```bash
swift build
swift test
specsync check --strict
```

Both gates run on every pull request, on macOS and on Linux. Linux is not
decoration: the deployment target is a container, and the first layer where
the two platforms genuinely differ is the persistence being written now.

`Package.resolved` is committed, and the one dependency is pinned to a single
minor, so two clones of one commit build the same code.
[`CHANGELOG.md`](CHANGELOG.md) is what changed between two versions, and
[`CONTRIBUTING.md`](CONTRIBUTING.md#releases) says how a release is cut and
how its number is chosen. Nothing has been released yet, and there are no
tags.

## Licence

MIT. See [LICENSE](LICENSE).
