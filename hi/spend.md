---
hi: 1
families: [SPEND]
---

# Spend

## Intent

Everything here is about the gap between what someone meant and what they typed. A person operating a hot wallet at speed will eventually type a wrong number, and the software's job is to be boring about it.

Caps refuse; they never clamp. A clamp silently turns "send 50,000" into "send 1,000" and the operator believes they did the thing they meant to do. A refusal is annoying for ten seconds and then correct. The same instinct covers restarts and lost replies: the bot should always resolve an ambiguity in the direction of spending less, never more.

A limit is only a limit if the number in it means what the person setting it thinks it means, and that stops being obvious the moment the same software is pointed at somebody else's asset. A thousand whole units of one token is not a thousand whole units of another, so how many decimals an asset has is something to ask the asset rather than something to assume. A setting named for a period has to govern that period: a ceiling labelled for a day that quietly covers a week is off by a factor of seven, with real money behind the difference. And nothing arrives with an amount, an account or an asset already filled in, because a default that spends is a default somebody finds out about afterwards.

A period is also something a long job can fall out of the bottom of. A payout that starts inside one week's ceiling and is still running when the next week begins has to be charged to one of them, and the answer an operator can reason about is that a job is held to the period it was measured against, because the alternative is one run spending the end of one ceiling and the start of the next. The job still finishes: a payout cut off at midnight is the half-finished payout every other rule here exists to prevent.

The other half of this is the record, and who is allowed to make one. Spending is written down before the money moves, not as a courtesy log but because the record is what the remaining allowance is counted from: a payment nobody wrote down is a payment the limit has forgotten, and forgetting always fails in the expensive direction. The key that can sign belongs to whoever is running the thing. It is theirs to supply, it is never printed back out, and a bot with no key at all should run happily and simply be unable to pay, rather than pretend.

## Criteria

- **SPEND-1**  A number I typed wrong refuses to send, instead of sending it
- **SPEND-2**  The bot cannot spend more in a week than I said it could
  - **SPEND-2.a**  Restarting it does not hand it a fresh allowance
- **SPEND-4**  If a payment goes out and I never hear back, it is treated as spent rather than sent twice
- **SPEND-5**  I can look up every move the wallet made and who asked for it
  - **SPEND-5.a**  What is left of the week is counted from that record, so money that went out cannot be forgotten by a restart
  - **SPEND-5.b**  A move it cannot write down first is a move it does not make
  - **SPEND-5.c**  Every move names the person who asked for it, so there is no payment nobody can be asked about
- **SPEND-6**  Nobody but me moves money
  - **SPEND-6.a**  Every surface that can spend refuses anybody I have not made an operator, however they found it
  - **SPEND-6.b**  The key that can sign is one I supply; the software ships with none, prints none back out, and refuses to start on one it cannot read rather than discovering it at the first payment
  - **SPEND-6.c**  With no key at all it still runs and simply cannot pay, so a community that only wants roles never has to hand it one
- **SPEND-7**  A limit means the number I typed, in my own asset
  - **SPEND-7.a**  A cap of a thousand is a thousand of my token whatever its decimals, because the asset is asked rather than assumed
  - **SPEND-7.b**  A limit named for a period limits that period, so nothing named for a day quietly governs a week
  - **SPEND-7.c**  Nothing spends an amount, an asset or an account I did not set, and there is no default waiting behind any of the three
- **SPEND-8**  I can retire the key that signs and put a new one in without a single member proving a wallet again
  - **SPEND-8.a**  What the old key did stays readable afterwards, so the record does not start over when the key does
  - **SPEND-8.b**  Handing this over to somebody else and replacing a key that was on a laptop that left are the same operation, and neither asks anything of my members
- **SPEND-9**  A job long enough to cross from one period into the next is still held to one period's ceiling
  - **SPEND-9.a**  Everything one job spends is counted against a single period, so running slowly cannot spend the end of one ceiling and the start of the next
  - **SPEND-9.b**  A job that was allowed to start finishes even though the period rolled over under it, because stopping half way down the list is the thing the check was for
  - **SPEND-9.c**  I can tell which period a job that crossed the boundary was counted against, rather than working it out from timestamps

## Retired

- **SPEND-3**  it only ever moves the thing I meant it to move
        retired: too vague to disagree with, so it asserted nothing SPEND-1 does not
