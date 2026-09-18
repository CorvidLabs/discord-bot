# discord-bot

A Discord bot for Algorand projects. Members link a wallet by signing a
challenge, the bot reads what those wallets hold, grants the roles the project
defines, and pays holders from a finite reserve on a schedule.

## State

**Early. Not runnable yet.** This repository is being built in the open, a piece
at a time, out of a private bot that has been running a live community for
months. Nothing here is a product yet.

What exists, or is arriving first, is the payout engine: a finite reserve split
into named streams, paid out over epochs, with fixed shares that cannot move when
new holders arrive, integer arithmetic in the asset's smallest unit throughout,
and guards against paying the same period twice.

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

## How this repository works

Intent is written down before code, as plain sentences about what somebody wants,
each with an id that never moves. See `hi/`. Module contracts live alongside the
code and are kept in step with it.

Every change arrives through a pull request.

## Licence

MIT. See [LICENSE](LICENSE).
