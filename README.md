# discord-bot

A Discord bot for Algorand projects, so that holding something on chain means
something in a server. A member proves a wallet is theirs by signing a
challenge, the bot reads what that wallet holds, the role beside their name
follows, and holders can be paid from a finite reserve on a schedule.

That is the product this is meant to become. Almost none of it is written.

## State

**Early. Not runnable yet.** This repository is being built in the open, a piece
at a time, out of a private bot that has been running a live community for
months. There is no bot here: no gateway, no slash commands, no database, no
executable target and nothing you can deploy. What exists is four library
targets, all offline, all covered by tests, and none of them wired to anything.

| Target | What it is |
|--------|------------|
| `Reserve` | The payout engine. A finite pot, split into named streams, paid over epochs, with fixed shares and four guards against paying a period twice. Foundation only. |
| `Gating` | What holding something earns somebody in a server: the tier ladder, the collections, the pools, and the rule that turns what a member holds into the roles they should have. Pure values, no chain, no Discord, no clock. |
| `Games` | Three games of cards and chance, as reducers. Clock and randomness arrive as parameters, so a table replays from a seed. Nothing here can reach a chain or sign anything. |
| `Chain` | Reading what an account holds on an Algorand node, and the two brakes that stop it reading too much: a per-second limiter and a per-UTC-day request budget. |

```
swift test    # 571 tests in 39 suites: Reserve 105, Gating 133, Games 158, Chain 175
```

Everything runs offline. No test reaches a network, and none needs a key, a
funded wallet or a Discord server.

[`docs/WHAT-IT-TALKS-TO.md`](docs/WHAT-IT-TALKS-TO.md) is the disclosure:
every outside service this contacts, every secret it asks for, the commands
that check each claim, and a plain account of what a reader cannot check by
grepping this repository. Read it before installing anything.

### What is missing

Most of it, and what is missing is the part a person would actually use:

- **No Discord surface.** No gateway connection, no slash commands, no embeds,
  no buttons. A role is a plain string in `Gating` and nothing turns it into a
  Discord role.
- **No wallet verification.** Nothing signs a challenge and nothing records
  that an account belongs to a member, which is the first thing the product is
  for.
- **No persistence.** Every store in the package is a protocol with an
  in-memory implementation for tests. There is no schema and no file format.
- **No executable.** `Package.swift` declares four libraries and no binary, so
  there is nothing to run and nothing to deploy.
- **No host.** The four targets do not know about each other beyond `Chain`
  depending on `Gating`. Nothing sweeps, nothing schedules, nothing pays.
- **No giveaways, no draws, no cards to look at, no announcements.** The
  `hi/` families describing them have nothing behind them.

Four of the nineteen intent families have code standing behind part of what they
describe: RESERVE, ROLE, ADOPT and PLAY. The rest are wants that have been
written down and agreed, not features that work.
[`INTENT.md`](INTENT.md) indexes them and [`hi/`](hi/) holds them, every line
with an id that never moves.

The Discord surface, the wallet verification flow and a host that wires the four
libraries together come next, in that order.

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

Also useful: `runner.audit(eligible:)` previews the whole reserve without moving
anything, and `runner.rehearse(streamId:recipients:)` plans the next epoch
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

Reading an account, a pool and an asset from an Algorand node, behind two
brakes: a per-second rate limiter on a monotonic clock, and a per-UTC-day
request budget that counts reads and signing together and is written down so a
restart does not hand the process a fresh one.

The other half of its job is refusing to invent an answer. A request that did
not come back is not an account holding nothing, and a pool whose reserves could
not be read is not a pool worth nothing. Every figure it hands out is a
`ChainReading`, which carries whether it is the whole answer, and the only two
routes from one into a decision turn a short answer into **unknown** rather than
into a smaller number.

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
