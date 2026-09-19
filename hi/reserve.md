---
hi: 1
families: [RESERVE]
---

# Reserve

## Intent

Somebody sets aside a fixed amount of something valuable and promises to pay it
out to a crowd, a slice at a time, over a long stretch. The amount is finite.
Nobody can top it back up. That single fact is where every rule here comes from.

The fear is not that the arithmetic is slightly wrong. It is that the arithmetic
moves. A person told in the first week what they will receive has to still be
receiving that number in the last week, however many people join after them and
however many drop out. So the division is fixed in advance: each stream divides
its share by a denominator chosen up front, never by however many happen to be
eligible on the day. A slot nobody claims stays unclaimed. It does not quietly
make everybody else's cheque bigger, because a cheque that grows is a cheque
somebody else's arrival can shrink.

The second fear is paying twice. The dangerous window is between handing money
over and writing down that you handed it over: a process that dies in there has
spent real value with no record of it, and the next run pays the same person
again. So the record is written first and the payment attempted second. A crash
now under-pays by one slice and leaves the value in the reserve, which is the
recoverable direction. Under-paying is a mistake you can fix next week.
Over-paying is gone.

The third fear is quiet loss. A share that will not divide evenly by the number
of epochs leaves a residue of a few smallest units. That residue is never paid
and it is never swallowed either: it is stated, and what was paid plus what was
held back equals the share exactly, so every smallest unit can be accounted for
by somebody checking with a calculator.

There is a fourth thing and it is not arithmetic. The row that stops a second payment is read before the next payment rather than written after one, which makes it a guard rather than a record of money moved, and it cannot be defended as a record when somebody asks to be forgotten in the middle of an epoch. It stays true alongside that request by holding only enough to recognise a share already taken, in a form nobody can read back as a person, and by being let go once the epoch closes.

Nothing here sends anything, stores anything, or talks to anybody. It works out
what is owed and remembers what has been settled. Who holds the money and where
the records live belong to whoever is using it.

## Criteria

- **RESERVE-1**  I can promise a finite pot to a crowd over time and never be able to overspend it
  - **RESERVE-1.a**  The size of the reserve, how it is split, and how many epochs it pays over are all things I choose, not things baked into the code
  - **RESERVE-1.b**  The reserve is divided into named streams, and the streams' shares add up to the whole reserve exactly
  - **RESERVE-1.c**  A split that will not divide into whole smallest units is refused when I configure it, not discovered on payday
  - **RESERVE-1.d**  The calculation can never spend more than the reserve, or more than any one stream's share
  - **RESERVE-1.e**  Putting more into the paying account funds what was already promised; it does not resize the reserve and it never changes anybody's payout
  - **RESERVE-1.f**  Two runs can never overlap; a second is refused while the first is still paying, so nobody is paid twice by two runs racing each other
  - **RESERVE-1.g**  A stream pays at most one epoch per period, so the whole schedule cannot be spent in an afternoon by running it repeatedly
- **RESERVE-2**  I choose how long the reserve takes to pay out before it starts, and it is fixed once it has
  - **RESERVE-2.a**  A schedule is simply a number of epochs, and the durations I can pick from are configuration rather than code
  - **RESERVE-2.b**  The duration I choose changes the per-epoch figure but never what a recipient receives over the whole schedule
  - **RESERVE-2.c**  The duration can still be changed until the first epoch has been paid, and is refused after that
  - **RESERVE-2.d**  A duration is named deliberately; nothing quietly falls back to a default that would halve or double every payment
- **RESERVE-3**  What a recipient is owed is knowable on day one and is the same number in the last epoch
  - **RESERVE-3.a**  Each stream divides its share by a fixed denominator, never by however many are eligible today
  - **RESERVE-3.b**  A new eligible recipient does not recalculate or reduce anybody else's payout
  - **RESERVE-3.c**  Slots nobody claims stay unclaimed and are never redistributed to enlarge somebody else's payment
  - **RESERVE-3.d**  More eligible units than the denominator has slots is refused rather than quietly overspending
- **RESERVE-4**  Each stream pays by its own rule, and the rule cannot be gamed
  - **RESERVE-4.a**  A once-per-recipient stream pays one slot per recipient, however many units they hold and however many accounts they spread them across
  - **RESERVE-4.b**  A per-unit stream pays one slot for every unit held, across every account the recipient has
  - **RESERVE-4.c**  Moving a held unit between accounts inside one epoch cannot produce two payouts for it
  - **RESERVE-4.d**  Holding the unit in an account I know about is the whole eligibility rule; there is no separate step to complete
  - **RESERVE-4.e**  Epochs between a unit changing hands and the new holder becoming known are paid to nobody and stay in the reserve
- **RESERVE-5**  The amounts are exact, and I can check them by hand
  - **RESERVE-5.a**  Every figure is a whole number of the asset's smallest unit; no floating point and no locale anywhere near the money
  - **RESERVE-5.b**  Every epoch of a schedule pays the identical figure, so what I tell somebody in week one is still true in the last week
  - **RESERVE-5.c**  A share that will not divide by the epoch count leaves a residue that is stated plainly and never paid
  - **RESERVE-5.d**  What was paid plus the stated residue equals the share exactly, so every smallest unit is accounted for
  - **RESERVE-5.e**  An amount written out for a person keeps every digit rather than being rounded into something prettier
  - **RESERVE-5.f**  A silly input refuses or returns something sane instead of taking the process down with it
- **RESERVE-6**  Nobody is paid twice, even if the process dies half way through an epoch
  - **RESERVE-6.a**  A slot is claimed before the payment is attempted, so a crash under-pays and leaves the value in the reserve rather than paying somebody there is no record of
  - **RESERVE-6.b**  A claim is handed back only when the payment provably moved nothing; a payment that might have gone through keeps its claim
  - **RESERVE-6.c**  Re-running a half-finished epoch skips everyone it already paid
  - **RESERVE-6.d**  An epoch can be finished but never skipped, so no epoch can be marked done without being paid
  - **RESERVE-6.e**  A record that will not parse raises rather than reading as an epoch nobody has been paid for
  - **RESERVE-6.f**  Only one epoch runs at a time, across every stream, because the streams share one piece of state
- **RESERVE-7**  I see what it will cost before anything moves
  - **RESERVE-7.a**  I can preview the whole-schedule projection and the next epoch's cost without sending anything
  - **RESERVE-7.b**  Allocation in use and projected spend are separate figures, and the gap between them is the residue the preview states
  - **RESERVE-7.c**  I can see how many more epochs the paying account can still cover, as a warning that never blocks a run that could otherwise go ahead
  - **RESERVE-7.d**  An epoch that will not fit the spending limits is refused before the first payment, measured against what is left of the period rather than the whole limit
  - **RESERVE-7.e**  If the eligibility list is incomplete, nobody is paid rather than a short list being paid
- **RESERVE-8**  The engine knows nothing about where its records live or who does the paying
  - **RESERVE-8.a**  Persistence is a protocol I implement; the engine never names a database
  - **RESERVE-8.b**  Paying is a protocol I implement; the engine never sends anything itself
  - **RESERVE-8.c**  An in-memory store comes with it, so the rules can be exercised before I have written anything durable
- **RESERVE-9**  The rules above are pinned by tests rather than asserted in prose
  - **RESERVE-9.a**  The stated example figures are checked in smallest units, not approximated
  - **RESERVE-9.b**  A transfer inside an epoch, a half-finished epoch and a second concurrent run each have a test that would fail if the guard were removed
  - **RESERVE-9.c**  The residue reconciliation is checked for every stream on every schedule
- **RESERVE-10**  Somebody asking to be forgotten in the middle of an epoch does not turn into a second payment to them
  - **RESERVE-10.a**  What stops a second payment holds only enough to recognise a share already taken, in a form that cannot be read back as who took it, so honouring a forgetting is not giving the guard up
  - **RESERVE-10.b**  Which of an epoch's rows a store may erase on request, and which it must keep until the epoch closes, is something the engine states rather than something left to whoever implements it
