# discord-bot

A Discord bot for Algorand projects. Members link a wallet by signing a
challenge, the bot reads what those wallets hold, grants the roles the project
defines, and pays holders from a finite reserve on a schedule.

## State

**Early. Not runnable yet.** This repository is being built in the open, a piece
at a time, out of a private bot that has been running a live community for
months. Nothing here is a product yet.

What exists today is one library target, `Reserve`: the payout engine. A finite
reserve split into named streams, paid out over epochs, with fixed shares that
cannot move when new holders arrive, integer arithmetic in the asset's smallest
unit throughout, and guards against paying the same period twice. It builds, it
is covered by 105 tests, and it knows nothing about Discord or Algorand.

There is no bot here yet: no gateway, no commands, no chain access, nothing you
can deploy.

The Discord surface, the role synchronisation and the wallet verification flow
come after that, in that order.

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

The one library target that exists today. A finite **reserve**, split into named
**streams**, paid to **recipients** over **epochs**. It plans and it records. It
never sends anything, and it has no idea what a database is.

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
- A **payout rule** is either `oncePerRecipient` — one slot per person, however
  many things they hold and however many accounts they spread them across — or
  `oncePerHeldUnit`, one slot per thing held.

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
alternative — spreading the remainder so a few epochs pay one unit more — makes
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
plan, and pay *everybody* twice — walking straight past the per-epoch record,
because the record is only read once at the start. One gate covers every stream,
not one gate each, because the reserve's state is a single value written back
whole: two streams saving snapshots taken before each other's would lose one
stream's finished epoch while its epoch record still said "complete".

**One epoch per period.** The per-epoch record does not object to running epoch 2
immediately after epoch 1, so without a cadence key the entire schedule can be
spent in an afternoon by running the command repeatedly. A firing is identified
by its *period* — an ISO week, a month — never by a timestamp, so two runs an
hour apart collide and a genuinely missed period is still paid late.

**The claim is written before the payment.** The window between handing value
over and recording it is where one payment becomes two: the value has left,
nothing on disk says so, and the next run pays again. Claiming first inverts the
risk. A crash now leaves a claim with no payment — under-paying by one slot and
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

**`ReserveStore`** is where the ledger lives — four async methods, load and save
for the reserve's state and for one epoch's record. An implementation has two
obligations: a row that cannot be read must throw rather than come back empty,
and a save must be durable before it returns, because the claim-before-pay
discipline rests on the claim being on disk when the payment is attempted. An
`InMemoryReserveStore` ships for tests.

**`ReservePayer`** is whoever actually moves the value, and it may optionally
declare spending limits and an available balance. It returns a reference — a
transaction id, a receipt number — so a payment is evidenced rather than
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

## How this repository works

Intent is written down before code, as plain sentences about what somebody wants,
each with an id that never moves. See `hi/`, and
[`hi/reserve.md`](hi/reserve.md) in particular: the engine's 52 criteria were
written before any of it was built, and the tests cite them by id. Module
contracts live alongside the code and are kept in step with it.

Every change arrives through a pull request.

```bash
swift build
swift test
```

## Licence

MIT. See [LICENSE](LICENSE).
