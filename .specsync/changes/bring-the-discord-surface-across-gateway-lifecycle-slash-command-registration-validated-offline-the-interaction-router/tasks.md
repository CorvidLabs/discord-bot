---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: tasks
---

# Tasks

Implementation tasks for after approval. None of these is done.
None of them is this definition session.

## Skeleton

- [ ] Add `Surface` library target and `Bot` executable target to
      `Package.swift`
- [ ] Pin DiscordBM `.upToNextMinor` and commit the resolved graph
- [ ] Record the actual pin count for `WHAT-IT-TALKS-TO.md`
- [ ] Add `Tests/SurfaceTests` with a target-shape test:
      `import DiscordBM` only under `Sources/Surface`; no DiscordBM
      product on Store, Gating, Games, Chain, Reserve, StoreSQLite,
      StoreTestKit
- [ ] Add `Sources/Surface` to `.specsync/config.toml` `source_dirs`
      in the same PR as `specs/surface/`

## Identity

- [ ] `DiscordUserId` wrapping 1–20 digit strings, `externalId: String`
- [ ] Adapter-only conversion from DiscordBM snowflakes
- [ ] Handler signatures take `externalId: String` / `MemberKey`
- [ ] Test: a snowflake does not appear in Store records

## Catalog and validator

- [ ] `CommandDefinition` tree as values
- [ ] `CommandValidator` for required-before-optional, lengths in
      UTF-16, duplicates, charset, option cap
- [ ] Fixture: the illegal `/raffle draw` option order fails
- [ ] `CommandCatalog.build` emits exactly ping, help, verify, unlink
- [ ] Builder tests: no spend commands without a key; no `/game`
      when games are off (even though those commands are not shipped)

## Cards and replies

- [ ] `SurfaceCard`, `SurfaceField`, `ButtonSpec` with no closures
- [ ] `ReplyLimits` counting UTF-16; thumbs-up boundary test
- [ ] `joinWithinLimit` in UTF-16; URL lists dropped whole
- [ ] `VisibleMessage.attachments` always present
- [ ] Adapter encoding test: edit with no file sends `[]`
- [ ] Unusable thumbnail URL (CID, relative) drops the picture, not
      the message

## Router

- [ ] `InteractionRequest` value
- [ ] Guild check (`HOST-10.a`)
- [ ] Acknowledge policy enforced by the router
- [ ] Autocomplete never defers
- [ ] Unknown command and unknown `custom_id` answered
- [ ] `CommandAuth` pure function on permission bits and role id
      strings

## Boot and health

- [ ] `BootSequence`: lease, bind, validate catalog, register,
      identify
- [ ] Fake binder / fake gateway: bind failure ⇒ identify count 0
- [ ] Health `503` until ready; `200` names discord, store,
      verification; chain budget untouched
- [ ] Placeholder token and placeholder guild id refuse boot
- [ ] Boot report: invite URL, permissions in Discord's words,
      managed roles above the bot

## Verification

- [ ] `VerificationClient` protocol matching
      `docs/VERIFICATION.md`
- [ ] `FakeVerificationClient` for tests
- [ ] Callback listener binds before identify
- [ ] Secret probe at boot (`VERIFY-5.b`)
- [ ] Callback: foreign guild ignored; malformed id ignored
- [ ] Callback: admit, prove, read, decide, apply
- [ ] Unknown chain read holds roles
- [ ] `/verify` ephemeral, defer, disclosure card, link button
- [ ] `/unlink` list or remove; last account forgets
- [ ] `guildMemberRemove` forgets

## Commands

- [ ] `/ping` no chain read
- [ ] `/help` lists only the catalog's member commands; no origin
      names
- [ ] Catalog-contents test: exactly four commands

## Roles

- [ ] `RoleApplier` protocol
- [ ] Recording fake
- [ ] Discord adapter applies `managed` only, one API call
- [ ] Fetch failure is unknown, not empty

## Long-running seam

- [ ] `JobMailbox` with injected clock
- [ ] Follow-up inside 15 minutes; fallback after
- [ ] No production command uses it yet; a test double does

## Executable and docs

- [ ] `Sources/Bot/main.swift` wiring only
- [ ] `docs/WHAT-IT-TALKS-TO.md`: hosts, secret, pins, greps
- [ ] `docs/CONFIGURATION.md`: new variables, no inherited defaults
- [ ] `README.md`: what exists, what still needs a portal
- [ ] `CHANGELOG.md` Unreleased
- [ ] `docs/README.md` map if a new fact owner appeared
- [ ] `specs/surface/` canonical spec and companions
- [ ] Forbidden-name grep over `Sources/Surface`

## Gate

- [ ] `fledge lanes run verify`
- [ ] `specsync check --strict`
- [ ] `specsync change check <id>`
- [ ] `fledge trust verify`
- [ ] Human review, then `specsync change review`
- [ ] Do not finalize or merge in the authoring session
