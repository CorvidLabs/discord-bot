# discord-bot

A Discord bot for Algorand projects: the thing a token or NFT community runs so
that holding something on chain means something in the server. Somebody proves a
wallet is theirs, the bot reads what that wallet holds, and the role beside
their name follows. Around that sit the rest of the things a community does with
it: badges for the collections it counts, a card that shows a piece off, a
standing among the other holders, giveaways and draws, a card table that pays in
nothing real, a timezone-free way to say when something starts, and the part
that is genuinely dangerous, paying a crowd real value on a schedule.

This file is the catalogue of what people want from it, family by family, every
line with an id that never moves. Most of those lines are written in the voice
of whoever ends up running this for their own community, because that is the
person the whole thing turns on: they did not write it, they cannot read it, and
everything their members see has to be something they chose rather than
something a stranger left behind.

**Almost none of it is built.** What exists today is one library, the payout
engine that RESERVE describes, and nothing else: no gateway, no commands, no
chain access, nothing that can be deployed. It is being built engine first
because the engine is the part that cannot be patched after the fact. A bot that
renders a card badly is embarrassing for an afternoon. A bot that pays a finite
reserve twice has spent value nobody can put back. So the payout engine is
written on its own, with no Discord and no chain anywhere near it, where every
figure it produces can be pinned by a test and read by a person with a
calculator. Everything social gets built on top of something already known to be
correct.

So read the families below as the product this is meant to become. A line here
is a want that has been written down and agreed, not a feature that works.

## Features

<!-- hi:index -->
- [adopt](hi/adopt.md): ADOPT (24 criteria)
- [catalog](hi/catalog.md): CATALOG (16 criteria)
- [gift](hi/gift.md): GIFT (13 criteria)
- [host](hi/host.md): HOST (13 criteria)
- [learn](hi/learn.md): LEARN (12 criteria)
- [picture](hi/picture.md): PICTURE (9 criteria)
- [play](hi/play.md): PLAY (10 criteria)
- [rain](hi/rain.md): RAIN (28 criteria)
- [repeat](hi/repeat.md): REPEAT (13 criteria)
- [reserve](hi/reserve.md): RESERVE (52 criteria)
- [role](hi/role.md): ROLE (9 criteria)
- [run](hi/run.md): RUN (10 criteria)
- [see](hi/see.md): SEE (15 criteria)
- [show](hi/show.md): SHOW (9 criteria)
- [spend](hi/spend.md): SPEND (16 criteria)
- [verify](hi/verify.md): VERIFY (8 criteria)
- [when](hi/when.md): WHEN (7 criteria)
<!-- /hi:index -->
