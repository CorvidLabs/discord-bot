---
hi: 1
families: [ROLE]
---

# Role

## Intent

The role beside your name is the visible payoff for holding. It should be true without anyone maintaining it, and it should be true about everything you hold: a person who put their tokens into a pool has not stopped being a holder, and it would feel like a punishment to treat them as though they had.

The failure that actually matters here is not being slow to promote. It is demoting someone who did nothing wrong because we could not see their balance for a minute. Silence from a data provider is not evidence that a person sold up, and we should never act as though it is.

All of that is about one number. A community also hands out badges for collections, and there can be any number of those, with whoever runs the server deciding what holding one is worth. The same fear comes back in the plural: a read that came back short for one collection must not take that badge away, and it must not hold up the collections that did read either.

And this arrives in a server that already has roles in it, nearly all of which have nothing to do with holding anything. The bot is a guest. It adds and removes the roles it was told to manage and leaves everything else alone, and a sweep that suddenly cannot see anybody is a reason to stop rather than a reason to strip a server bare.

## Criteria

- **ROLE-1**  The role beside my name matches what I actually hold, without me asking for it
  - **ROLE-1.a**  If the bot cannot see my balance right now, I keep the role I had rather than being quietly demoted
  - **ROLE-1.c**  I do not lose my tier because the project changed something behind the scenes
- **ROLE-2**  What I have parked in a liquidity pool counts toward my tier, the same as what sits in my wallet
- **ROLE-4**  A collection this server counts earns me its badge when I hold one, whichever collection it is
  - **ROLE-4.a**  Holding more of a collection can move me up a rung, the same way holding more of the token does
  - **ROLE-4.b**  A collection the bot could not read leaves that badge exactly as it was, while the collections it could read still update
- **ROLE-5**  The bot adds and removes only the roles I told it to manage, and every other role in my server is untouched
  - **ROLE-5.a**  A sweep that suddenly sees almost nobody refuses rather than clearing the server in one pass

## Retired

- **ROLE-1.b**  if I sell up or sell down, the role follows on its own
        retired: ROLE-1 already says the role matches what I hold; this restated it
- **ROLE-3**  if I leave the server, my wallet stops being tracked
        retired: real, but about leaving rather than about roles; wrong family
