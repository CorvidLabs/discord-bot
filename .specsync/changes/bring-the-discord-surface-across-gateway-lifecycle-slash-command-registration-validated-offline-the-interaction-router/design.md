---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: design
---

# Design

The shape to disagree with. Types named here are illustrative; the
implementation may rename them if the spec stays true.

## Where it sits

```
                    Discord gateway / HTTP API
                              │
                              ▼
                    Sources/Surface   (this change)
                              │
          ┌─────────┬─────────┼─────────┬──────────┐
          ▼         ▼         ▼         ▼          ▼
        Store     Gating    Chain   (Games)    (Reserve)
```

`Games` and `Reserve` are not dependencies of the smallest surface.
They join when those commands do. `StoreSQLite` is opened by the
executable, not by `Surface`. `Surface` talks to `BotStore`.

```
Sources/Surface/          library product Surface
Sources/Bot/              executable product discord-bot
Tests/SurfaceTests/
specs/surface/            written with the code
```

The executable loads environment, constructs `GatingConfiguration`,
`ChainConfiguration`, a `BotStore`, a `Surface`, and runs `start()`.
It contains no command logic.

## Layers inside Surface

Four layers, one direction.

```
1. Values     CommandCatalog, InteractionRequest, SurfaceReply,
              SurfaceCard, ButtonSpec, AcknowledgePolicy
2. Domain     handlers, CommandAuth, RoleApplier protocol,
              VerificationClient protocol, BootSequence
3. Adapter    DiscordBM mapping, Snowflake conversion,
              HTTP listener bind, gateway identify
4. Host       executable wiring
```

A test of (1) or (2) constructs values. A test of (3) may import
DiscordBM and still opens no socket. (4) is thin enough that a boot
test drives `BootSequence` with fakes rather than `main`.

Dependency direction: 4 → 3 → 2 → 1. 1 imports Foundation. 2 imports
Store, Gating, Chain. 3 imports DiscordBM. 2 does not import DiscordBM.

## Identity

```
Discord user snowflake
        │  adapter only
        ▼
externalId: String          Store.admitMember / member(externalId:)
        │
        ▼
MemberKey                   minted, random, 32 lowercase hex
```

`DiscordUserId` (Surface, adapter) wraps a string of 1–20 digits and
exposes `var externalId: String`. Handlers take `externalId`.
`RoleDecision.memberId` remains `String`. Mentions are formatted in
the adapter as `<@externalId>`.

Enforced by the compiler: Store has no DiscordBM product. A cycle
Store → Surface is a build failure. A `TargetShape` test greps
`import DiscordBM` under `Sources/` and allows only
`Sources/Surface`.

Role ids from Gating are strings. The adapter converts them to
DiscordBM role snowflakes only at the `add/remove guild member role`
call. `CommandAuth` takes `[String]` role ids and a permission bit
set as a `UInt64` (or an opaque bits type of our own), not
`RoleSnowflake`.

## Catalog and validator

A command is a tree of our types: name, description, default member
permissions, options. An option is a name, type, required flag,
description, nested options, choices, min/max, autocomplete flag.

`CommandCatalog.build(config:)` returns the four commands of
`REQ-surface-015`, and later will omit spend/game commands when the
config says so (`REQ-surface-021`).

`CommandValidator.validate(_:)` walks every options array and
applies `REQ-surface-006`. It is a function from catalog to
`Result<Void, [ValidationIssue]>`. Issues name the command path
(`raffle.draw.confirm`) and the rule (`requiredAfterOptional`).

Boot: validate, then map to `Payloads.ApplicationCommandCreate`,
then `bulkSetGuildApplicationCommands`. A validation failure stops
boot and prints the issues. It never calls Discord.

The validator does not need DiscordBM. The mapping does. Both are
tested.

## Router

```
Gateway event
    → adapter decodes Interaction
    → InteractionRequest
         kind: command | autocomplete | component
         commandName, options, customId
         guildId, userExternalId, memberRoleIds, permissionBits
         interactionId, token, receivedAt
    → Router
         guild check (REQ-surface-007)
         auth if the command is operator-only (none yet)
         acknowledge per policy (REQ-surface-009)
         handler → SurfaceReply
    → adapter sends
```

`SurfaceReply` is a value:

- `.immediate(VisibleMessage)`
- `.deferredEphemeral` / `.deferredPublic` then `.followUp(VisibleMessage)`
- `.longRunning(job: JobId, started: VisibleMessage)`
- `.updateMessage(VisibleMessage)` (component)
- `.autocomplete([Choice])`
- `.refuse(String)` (always ephemeral)

`VisibleMessage` holds optional text, a `SurfaceCard`, components
already on the card, files, and `attachments:` as `[AttachmentSpec]`: **always present**, empty if none (`REQ-surface-012`).

The router, not the handler, emits the defer. A handler for a deferred
command returns the follow-up body only.

## Cards

```
struct SurfaceCard: Sendable, Equatable {
    var title: String
    var description: String
    var fields: [SurfaceField]
    var color: Int?            // 0xRRGGBB, operator's or none
    var footer: String?
    var thumbnailURL: String?  // http(s) only; unusable drops the picture
    var imageURL: String?
    var buttons: [ButtonSpec]
    var attachmentName: String?
}

struct ButtonSpec: Sendable, Equatable {
    var id: String             // empty iff style == .link
    var label: String
    var style: ButtonStyle     // primary, secondary, success, danger, link
    var url: String?
    var disabled: Bool
}
```

No DiscordBM types. No closures. No protocol.

Builders live next to their commands (`VerifyCard.disclosure(...)`,
`HelpCard.commands(catalog:)`). They take configuration values, not
a client.

Renderer in the adapter: UTF-16 clamp (`REQ-surface-011`), embed
construction, action rows in fives, thumbnail guard (http/https with
a host, else nil, because a CID must not reject the whole message).

`GameMessage` mapping is a later function `SurfaceCard.init(game:)`.
Not this change. Do not resurrect `GameCard` as a DiscordBM enum.

Button work: namespaces as prefixes, short because custom ids are
100 UTF-16.

| Prefix | Owner | This change? |
|--------|-------|--------------|
| `verify:` | verify / add-another-wallet (link buttons do not need it) | link only |
| `unlink:` | confirm unlink | yes, if confirmation is a button |
| `ng_` | games | no |
| `claim:` | gifts | no |

Unrouted prefix → ephemeral "this button is no longer valid".

## Reply limits

A single type `ReplyLimits` in Surface, counting `String.utf16.count`.

Clamp algorithm: if `utf16.count <= limit`, unchanged; else keep a
prefix whose UTF-16 length is `limit - ellipsis.utf16.count`, append
`…`. Do not use `String.prefix(limit)`: that is graphemes.

`joinWithinLimit` subtracts in UTF-16, drops whole lines, appends
`and N more`. A list of URLs that cannot fit one whole URL is
dropped wholesale, not sliced through an href (the rain-receipt
lesson).

Refuse rather than clamp: `/say` (later), any payload whose truncated
form would still look like a complete answer. `/help` and `/unlink`
lists clamp and say so.

`GatingFormatting.clamp` may have already shortened a field.
`ReplyLimits` runs again at the adapter. The test that matters is
the thumbs-up test at this layer.

## Boot sequence

```
load configuration          refuse missing / placeholder
open BotStore               InstanceLease, or refuse
bind health port            refuse if in use
bind verification port      refuse if in use
probe verification secret   REQ-surface-025
validate command catalog    REQ-surface-006
register guild commands     HTTP, after bind
identify                    gateway.connect
mark health ready
run event loop
```

No role-sync loop, no schedule loop, no offer sweeper in this change.

Health payload, illustrative:

```
503 {"status":"starting"}
200 {"status":"ok","discord":"ready","store":"ok","verification":"ok"}
200 {"status":"degraded","discord":"ready","store":"ok","verification":"down"}
```

Degraded is not "process alive". A process that cannot verify is
not `ok` (`SEE-1.a`, `SEE-7`: verification down loses verification
and nothing else, so `/ping` and `/help` still answer).

## Verification client

```
protocol VerificationClient: Sendable {
    func health() async throws
    func probeSharedSecret() async throws    // keyed, for VERIFY-5.b
    func createSession(externalId: String, guildId: String) async throws -> Session
    func deleteSession(externalId: String) async throws
}
```

`Session` has `url`, `token`, `expiresAt`. HTTP status `201` on
create, ids as strings, one `X-API-Key`. The inbound webhook is not
this protocol; it is a small HTTP listener that validates the key
in constant time, reads a bounded body, and calls
`VerificationCallbackHandler`.

`0001` decides whether the client is a loopback to an in-process
page or a remote portal. The protocol does not care.

## Role application

```
protocol RoleApplier: Sendable {
    func apply(_ decision: RoleDecision, currentRoleIds: [String]) async throws
}
```

The Discord implementation: one guild-member-role payload for the
managed set, not a round trip per role. Tests use a recording fake.
`RoleDecision` is Gating's. Surface does not re-derive rungs.

Current role ids come from the interaction (on a command) or from
a guild-member fetch (on a webhook). Fetch failures are unknown, not
empty: applying against an empty set would strip (`ROLE-1.a`,
`ROLE-5.a` spirit on a single member).

## Long-running jobs

A `JobMailbox` records `JobId → outcome`. The reply layer:

1. Acknowledge (defer or a "started" message).
2. Run the work.
3. If `now < tokenIssuedAt + 15min`, follow up.
4. Else send the fallback.

This change ships the mailbox, the clock parameter, and tests. No
command uses it yet except a test double. Rain will.

The fallback destination is configuration (`SEE-13.a` later). For
now: DM the invoker; if that fails, log. Do not invent an operator
channel default.

## What we refuse from the reference

- One `Bot` actor that constructs every service and switches on
  command names. A router table plus per-command handlers.
- `DiscordClient` in handler signatures.
- `GameCard` / `NFTEmbed` as DiscordBM namespaces.
- Fluent models as the member record. Store already replaced that.
- A second admin HTTP UI in this target.
- Presence text that names a token we do not know.
- `guildMessages` intent. Smallest surface needs `guilds` and
  `guildMembers` (leave events, role application). Message content
  is how sneak-peek snuck in; it stays out.
- Two verification secrets.
- Counting payload length in `Character`s.

## Intents and permissions

Gateway intents: `guilds`, `guildMembers`. Not `guildMessages`, not
message content.

Bot permissions to print at boot and to encode in the invite
(`ADOPT-11`, `ADOPT-11.b`), in Discord's words:

- Manage Roles
- Send Messages
- Embed Links
- Attach Files
- Use Slash Commands (applications.commands scope)

Manage Roles is the one that fails quietly when a managed role sits
above the bot. Boot compares the bot's highest role to
`GatingConfiguration.allRoleIds` and names every role that sits
above it (`ADOPT-11.a`). That comparison needs a guild-role fetch
after ready, not before identify; report it on the first ready, and
on health.

## Configuration this target adds

Owned by `docs/CONFIGURATION.md` when the code lands. No defaults
that are somebody else's.

| Variable | Required | Notes |
|----------|----------|-------|
| `DISCORD_BOT_TOKEN` | yes | Secret. Placeholder refused. |
| `DISCORD_GUILD_ID` | yes | Decimal snowflake as string. |
| `DISCORD_ADMIN_ROLE_ID` | no | Extra operator role. Empty = Administrator only. |
| `HEALTH_PORT` | yes | Bind before identify. |
| `VERIFY_CALLBACK_PORT` | yes | Bind before identify. |
| `VERIFY_PORTAL_URL` | until `0001` says otherwise | No default host. |
| `VERIFY_SHARED_SECRET` | with a portal | One secret, both directions. |

Listen addresses default to loopback only if we can still receive
the portal's callback; an operator who needs `0.0.0.0` sets it.
Do not ship `0.0.0.0` as a silent default on a process that may
later hold a signing key.

`VERIFIED_ROLE_ID` and the rest of the ladder already belong to
Gating.

## File-level sketch (not a promise of names)

```
Sources/Surface/
  Catalog/          definitions, validator, builder
  Router/           InteractionRequest, Router, CommandAuth
  Reply/            SurfaceReply, ReplyLimits, JobMailbox
  Cards/            SurfaceCard, ButtonSpec, builders
  Identity/         DiscordUserId, externalId conversion
  Boot/             BootSequence, Health
  Verify/           VerificationClient, callback listener, handler
  Roles/            RoleApplier
  Adapter/          DiscordBM mapping only
Sources/Bot/
  main.swift
```

Adapter is the only directory allowed to `import DiscordBM`.
The target-shape test can enforce a path prefix if that is cheaper
than a second target. A second target (`SurfaceDiscordBM`) that only
the adapter lives in is stricter and is allowed if it does not
split the public product. Prefer one library product so an operator
depends on `Surface`, not on two.

## Open, and left open on purpose

- `0001-verification-portal`: where the page is served. The protocol
  is the seam.
- The operator-channel fallback for long-running jobs, beyond DM.
  `SEE-13` is a later command.
- Whether `/help` is a card or plain text. Card, because `/help` in
  the reference was a card and mobile copy is `WHEN`'s problem, not
  help's. Disagree here if you want plain text.
- Whether unlink confirmation is a button or a required option. A
  required option cannot come after an optional list-the-wallets
  flow; the two-step (list, then `/unlink wallet:`) is the reference
  and is enough.
