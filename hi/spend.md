---
hi: 1
families: [SPEND]
---

# Spend

## Intent

Everything here is about the gap between what someone meant and what they typed. A person operating a hot wallet at speed will eventually type a wrong number, and the software's job is to be boring about it.

Caps refuse; they never clamp. A clamp silently turns "send 50,000" into "send 1,000" and the operator believes they did the thing they meant to do. A refusal is annoying for ten seconds and then correct. The same instinct covers restarts and lost replies: the bot should always resolve an ambiguity in the direction of spending less, never more.

A limit is only a limit if the number in it means what the person setting it thinks it means, and that stops being obvious the moment the same software is pointed at somebody else's asset. A thousand whole units of one token is not a thousand whole units of another, so how many decimals an asset has is something to ask the asset rather than something to assume. A setting named for a period has to govern that period: a ceiling labelled for a day that quietly covers a week is off by a factor of seven, with real money behind the difference. And nothing arrives with an amount, an account or an asset already filled in, because a default that spends is a default somebody finds out about afterwards.

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

## Retired

- **SPEND-3**  it only ever moves the thing I meant it to move
        retired: too vague to disagree with, so it asserted nothing SPEND-1 does not
