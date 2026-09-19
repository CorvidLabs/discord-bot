---
hi: 1
families: [REPEAT]
---

# Repeat

## Intent

The regular payouts should not depend on somebody being awake. That is the whole reason this exists.

But automation that moves money is only worth having if it cannot surprise you. Nothing runs because it was written down: it runs because a person turned it on, deliberately, and said they meant it. And the thing it must never do is pay a period twice. Downtime, a restart, a duplicate tick: none of those are reasons for the community to be paid twice or to quietly miss a period.

The list of things that can be armed belongs to whoever is running it. A bot handed to somebody else must not arrive with recurring payments already written for collections they do not have, and a newer version must not walk back the times, the amounts and the switches they set. The calendar has to be the same calendar the spending cap counts in, and the same one on any machine, because a period that means two different things is a period that pays twice.

## Criteria

- **REPEAT-1**  The regular payouts can happen without me being awake for them
  - **REPEAT-1.a**  Nothing starts paying on its own until I have turned it on and said I mean it
  - **REPEAT-1.b**  If the bot was down for a week, that week gets paid once when it comes back, not twice and not never
  - **REPEAT-1.c**  Anything that can move money is armed more carefully than anything that cannot, and the bot knows which is which rather than leaving me to remember
  - **REPEAT-1.d**  Something that refuses waits before trying again, so a pot that cannot pay today does not retry every minute until the period is over
- **REPEAT-2**  I can see at a glance what is armed and what is not
  - **REPEAT-2.a**  The same list tells me when each one last ran and when it fires next, so armed is not the only thing I learn from it
- **REPEAT-3**  The recurring work I am offered is built from what I configured, not from collections somebody else had
  - **REPEAT-3.a**  A bot with nothing configured to pay for offers nothing to arm, rather than rows pointing at things I do not own
  - **REPEAT-3.b**  A newer version can add new recurring work without touching the times, the amounts and the switches I already set on the work that was there
- **REPEAT-4**  A period means the same thing everywhere
  - **REPEAT-4.a**  The week the timer counts is the week my spending cap counts, so one payout cannot fall in two different weeks depending on which of them is asking
  - **REPEAT-4.b**  Where the bot is running does not change when it fires
