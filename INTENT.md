# discord-bot

A Discord bot for Algorand projects: the thing a token or NFT community runs so
that holding something on chain means something in the server. Verification,
roles, and — the part that is actually dangerous — paying people.

It is being built engine first, because the engine is the part that cannot be
patched after the fact. A bot that renders a card badly is embarrassing for an
afternoon. A bot that pays a finite reserve twice has spent value nobody can put
back. So the payout engine is written on its own, with no Discord and no chain
anywhere near it, where every figure it produces can be pinned by a test and
read by a person with a calculator. Everything social gets built on top of
something that is already known to be correct.

## Features

<!-- hi:index -->
- [reserve](hi/reserve.md): RESERVE (52 criteria)
<!-- /hi:index -->
