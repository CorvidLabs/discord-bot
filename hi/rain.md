---
hi: 1
families: [RAIN]
---

# Rain

## Intent

Paying a whole community at once is the most useful thing this does and the most dangerous. It is a bulk transfer of real value to a list assembled from cached data, started by one person at a keyboard.

So the guiding feeling is: no surprises, and no half-finished payouts. You see the cost first. If the list might be wrong, because the bot is working from stale information about who holds what, nothing goes out at all, because a short payout is worse than no payout: it looks like favouritism and it cannot be undone. And afterwards there is proof rather than a claim.

A payout is also a long job with money on the end of it. It spends requests to the chain, it spends writes to the bot's own records, and it can outlive the reply that started it. So there is a rehearsal that sends nothing and says what the real run would cost, and a finished run reaches the person who asked for it even after the reply they started has expired. Losing the report is survivable. Losing the record of who was paid is not.

The part that only matters because other people run this: the bot has no opinion about which collections exist. Whether a payout is one payment per holder or one payment for every item somebody holds is a thing the operator declares, never something inferred from a collection's name. Guess it, and a collection of four thousand pieces is paid like a single pass, or a single pass is paid four thousand times, and both are a great deal of money going the wrong way.

The fixed pot that some of these payouts come out of is a separate family. reserve.md says how a finite reserve is divided, why the division never moves, how an epoch refuses to be paid twice, and why a list handed to it with holes in it is refused rather than paid. This family is about the paying itself, whether it comes from that pot or from an operator deciding today to pay everybody something, and about the bot noticing its own picture of who holds what has gone stale before it builds a list at all. The spending ceilings, what a number in one means and who is allowed to move money past them, belong to SPEND.

## Criteria

- **RAIN-1**  I can pay everyone holding one of my collections in one go, without naming them one at a time
  - **RAIN-1.a**  I can see exactly what it will cost before anything moves
  - **RAIN-1.b**  If the bot is working from stale information about who holds what, it pays nobody rather than paying a short list
  - **RAIN-1.c**  A payout that will not fit inside the spending caps is refused before the first payment, not discovered part way down the list
  - **RAIN-1.d**  What I am shown before anything moves fits in one message, and the first thing it leaves out is detail rather than a warning
- **RAIN-2**  If I cannot receive it yet, I am told how to get ready rather than passed over in silence
  - **RAIN-2.a**  What I am told is written for me rather than lifted from the operator's error, and it never sends me to something only an operator can run
- **RAIN-3**  Afterwards I can show people it actually arrived, not just say so
  - **RAIN-3.a**  A scheduled payout's public post tells members which epoch of the schedule it is, what one holder received, what the epoch cost and how much of the allocation has gone out
- **RAIN-11**  Before a payout runs for real, I can see what it will cost the bot to make, not only what it will cost the pot
  - **RAIN-11.a**  I can ask for a full plan of the next payout that sends nothing: who would be paid, how much each, the total, and what it would spend of the day's chain-request budget
  - **RAIN-11.b**  The rehearsal plans through the same code the real run plans through, so a figure I read there is the figure I get
  - **RAIN-11.c**  A rehearsal never claims anybody's slot, never closes an epoch, never counts against a cap, and leaves nothing behind that a later run would skip
  - **RAIN-11.d**  It tells me how much it would write to the bot's own records, so I can tell whether a full-size payout is affordable before I find out on the day
- **RAIN-12**  A payout does not spend more of the day's chain-request budget than the work needs
  - **RAIN-12.a**  Work that is identical for every payment in one payout is done once for the payout rather than once per payment
  - **RAIN-12.b**  Where doing it once would stop being valid part way through a long payout, it is renewed rather than used past its life, and a payout never fails because something was reused too long
- **RAIN-13**  A payout that takes a long time still tells me how it went
  - **RAIN-13.a**  If the reply I started can no longer be updated by the time the payout finishes, the report reaches me another way rather than being lost
  - **RAIN-13.b**  Losing the report never means losing the payout: what was paid, and to whom, is written down before I am told about it either way
- **RAIN-14**  I can pay a crowd for whichever collections I have, not for the ones somebody else had
  - **RAIN-14.a**  Each collection I set up says whether a payout pays its holders once each or pays for every item they hold, and the payout obeys what I declared instead of guessing from the collection's name
  - **RAIN-14.b**  Adding a collection gives me a payout for it without a new version of the bot, and the collections I am offered when I start one are the collections I configured
  - **RAIN-14.c**  I can run payouts and giveaways alongside the scheduled reserve programme, on a timer or by hand, and the bot does not refuse the combination
  - **RAIN-14.d**  A prize I hand out some other way comes out of the paying account and never out of the reserve's arithmetic, so it changes nobody's promised payout
- **RAIN-15**  A payout is counted in my token's own units, at whatever precision my token has
  - **RAIN-15.a**  The amount I type and the figure a member reads mean the same thing, and neither assumes a number of decimals my token does not have
  - **RAIN-15.b**  An amount too large to hold refuses rather than wrapping round into a small one
