---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: context
---

# Context

## What led here

This repository is six library products and no bot. `Reserve`, `Gating`,
`Games`, `Chain`, `Store` and `StoreSQLite` can decide a payout, a role, a
hand and a chain read, and they can remember a member. Nobody can run any of
it. The product this is meant to become is a Discord bot for an Algorand
project, so that holding something on chain means a role in a server. That
product starts at the Discord surface, and the surface is the largest unbuilt
piece.

The private reference this was read out of has been serving one community for
years. Its Discord surface is `Sources/CorvidBot/Bot.swift` and
`Sources/CorvidBot/Commands/`: about 35 files, 11,300 lines, 26 slash
commands, DiscordBM reaching into 62 of 157 files. It works. It is also four
years of one community's scar tissue, welded to two collections, one token,
one presence string and a second web application that this repository does
not ship. Copying it would give a stranger somebody else's bot.

This change is the definition of the public surface. No Swift. The point of
the order is that the shape can be disagreed with before the code exists.

## What already stands, and must not be disturbed

- `Gating` decides roles from values. A role is a `String`. A
  `RoleDecision` grants nothing; a caller at a chat boundary applies it.
- `Store` names a member by a minted `MemberKey` and records who they are to
  a chat client as a plain `String` (`MemberRecord.externalId`). It declares
  no chat client. `import DiscordBM` there is a missing module.
- `Games` already builds `GameMessage` / `GameButton` with no client types.
- `Chain` reads an Algorand node behind two brakes. It has no Discord.
- `StoreSQLite.InstanceLease` already refuses a second process on the same
  store, and its comment already names the reconnect storm that follows if
  that process had identified to Discord first.
- `docs/VERIFICATION.md` is the bot↔portal contract. Decision
  `0001-verification-portal` is **proposed, not decided**. This surface
  speaks that contract. It does not decide where the page is served from.
- `GatingFormatting.clamp` counts Swift `Character`s and says so. It is not
  the Discord boundary and must not be trusted as one.

## Constraints that are not negotiable

- Work only in this worktree, on `feature/def-discord`. Do not commit. Do
  not push. Write no Swift in this change.
- Approval of this definition is somebody else's.
- Money is integer arithmetic. Limits abort. A claim is persisted before a
  payment. Nothing below the chat boundary holds an identifier that came
  from a person.
- A fact nobody could read is unknown, not zero.
- Nothing falls back to a value somebody else chose.
- This repository is public. No real address, asset id, Discord snowflake or
  personal path in the artifacts.
- `.specsync/sdd.json` already lists `Sources/`, `Tests/` and
  `Package.swift` as meaningful. Implementation of this definition needs
  this workspace. `specs/` is ignored by the path gate; a new
  `specs/surface/` still belongs in the same delivery PR as the code.
- `fledge trust verify` remains the completion gate. An Augur block is a
  hard stop.

## Already known, so this definition does not rediscover them

These failed in the reference, in front of a live community:

1. **Required slash options must precede optional ones** on the same
   subcommand. Discord answers 400 on register. The boot treats that as
   fatal, so the process crash-loops. The reference rolled back a deploy
   over `/raffle draw`. A definition that does not make this checkable
   offline has missed the most expensive failure in the surface.
2. **Three seconds to acknowledge, fifteen minutes to finish.** A payout of
   fifty wallets does not fit in fifteen minutes, and neither does a full
   role sweep. Any command that moves money or touches every member has to
   outlive its own interaction.
3. **Payload limits fail after the fact and silently.** The handler has
   already deferred, so the member sees a permanent thinking indicator.
   Discord counts UTF-16 code units, not Swift characters. `👍` is one
   grapheme and two units. `GatingFormatting.clamp` counts graphemes.
4. **Editing a message replaces its attachment list.** Omitting an explicit
   empty `attachments` array leaves the old image in place, so a card
   appears frozen. The reference learned this on the game hand picture.
5. **Bind listening ports before identifying to Discord.** A second
   instance that identifies first makes Discord invalidate the live
   session. Under a supervisor that is an unrecoverable reconnect storm.
   The store lease is necessary and not sufficient: two processes can share
   a token without sharing a store.
6. **Every merged layer takes a `String` where the reference takes a
   Snowflake.** That has to survive contact with this target by the
   compiler, not by a reviewer.
7. **DiscordBM takes the resolved graph from 3 packages to roughly 25.**
   The pitch to a stranger is that they can read everything this depends
   on. That cost belongs in the definition.

## Ruled out

- Porting all 26 commands in this change. The surface is the catalog, the
  validator, the router, the reply layer, the cards, the boot, and the
  smallest set of commands after which a member can prove a wallet and
  receive a role.
- Fluent, Vapor, Fork, Cache, and the private bot's ORM. `StoreSQLite`
  exists. DiscordBM already brings NIO. A webhook listener is a small bind
  of our own, not a web framework.
- `GameCard` as an enum of static functions that import DiscordBM and live
  next to the games. `Games` already has the value. This target maps it.
- Closures on buttons. They are not `Equatable`, not `Sendable` without
  ceremony, and they pull side effects into the card.
- Global command registration. This instance serves one guild (`HOST-10`).
- Default presence text, default logos, default command copy, or any
  collection name from the project this was built for (`ADOPT-1.c`,
  `ADOPT-6.a`).
- Deciding `0001-verification-portal`. The surface talks to a
  `VerificationClient` protocol. In-process page or separate portal is a
  later substitution.
- A `/test-balance` command, an `/admin-nft-registry` command, a
  sneak-peek message handler, and a Pera-gated admin HTTP UI. Those are
  one community's tools. Catalog-as-a-page is `CATALOG`, a different
  surface.
- Changing `Gating`, `Store`, `Games`, `Chain` or `Reserve` canonical
  specs. This change adds a target. It does not edit the ones that already
  passed.

## What a session picking this up mid-flight needs

- Change id:
  `bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router`
- State at definition: `draft`, interview answered
  (`architecture_risk=yes`, `public_contract=yes`), artifacts selected,
  approval not recorded.
- Private reference (read only):
  `/Users/leif/Development/_CorvidLabs/corvid-bot`
- Next human gate after these artifacts: `specsync change approve` by
  somebody who is not the author of the definition.
- Implementation does not start in this session.
