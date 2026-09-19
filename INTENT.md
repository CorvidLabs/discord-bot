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

Two of the families speak in other voices, because a repository anybody can
read acquires two people a private one never had. BUILD is whoever turns up
wanting to change the code, with a laptop and none of the things this normally
runs on: no server of their own, no funded wallet, nowhere live to prove a
wallet. TRUST is whoever is reading this to work out whether to install a bot
that can move tokens at all, before they have run a single command and while
everything they can check is still only what the repository says. Neither family
describes anything that exists yet, any more than the rest do. They are wants
that have been written down, in the voices of the two people most likely to
arrive next.

**Almost none of it is built.** What exists today is four libraries: the payout
engine that RESERVE describes, the role rules that ROLE and ADOPT describe, the
game engine that PLAY describes, and a layer that reads an Algorand node. There
is **no gateway, no command, no database and nothing that can be deployed**, so
no member has ever seen any of it and no operator has ever configured it.

It is being built engine first because the engine is the part that cannot be
patched after the fact. A bot that renders a card badly is embarrassing for an
afternoon. A bot that pays a finite reserve twice has spent value nobody can put
back. So the payout engine was written on its own, with no Discord and no chain
anywhere near it, where every figure it produces can be pinned by a test and
read by a person with a calculator. The three libraries beside it keep the same
shape: no Discord type, no clock read inside a decision, no network in a test.
Everything social gets built on top of something already known to be correct.

So read the families below as the product this is meant to become. A line here
is a want that has been written down and agreed, not a feature that works. Four
families have code standing behind part of what they describe, which is not the
same as being finished: RESERVE, ROLE, ADOPT and PLAY. The other fifteen have
nothing behind them at all.

## Features

<!-- hi:index -->
- [adopt](hi/adopt.md): ADOPT (30 criteria)
- [build](hi/build.md): BUILD (12 criteria)
- [catalog](hi/catalog.md): CATALOG (16 criteria)
- [gift](hi/gift.md): GIFT (13 criteria)
- [host](hi/host.md): HOST (18 criteria)
- [learn](hi/learn.md): LEARN (12 criteria)
- [picture](hi/picture.md): PICTURE (9 criteria)
- [play](hi/play.md): PLAY (10 criteria)
- [rain](hi/rain.md): RAIN (28 criteria)
- [repeat](hi/repeat.md): REPEAT (13 criteria)
- [reserve](hi/reserve.md): RESERVE (52 criteria)
- [role](hi/role.md): ROLE (11 criteria)
- [run](hi/run.md): RUN (13 criteria)
- [see](hi/see.md): SEE (18 criteria)
- [show](hi/show.md): SHOW (9 criteria)
- [spend](hi/spend.md): SPEND (19 criteria)
- [trust](hi/trust.md): TRUST (10 criteria)
- [verify](hi/verify.md): VERIFY (12 criteria)
- [when](hi/when.md): WHEN (7 criteria)
<!-- /hi:index -->
