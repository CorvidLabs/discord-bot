---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: research
---

# Research

Evidence for the shape in `design.md` and the verdicts in
`requirements.md`. The private reference is treated as a source of
failures and of working contracts, not as a design to copy.

## What the reference actually registered

`Bot.registerCommands` bulk-sets 26 guild commands. Handler files are
more than 26 because games were later folded under `/game` and some
files are shared plumbing (`CommandAuth`, `NestReply`, `PublicGallery`,
`TimeParser`).

Counted from the registration array in `Bot.swift` and from
`specs/commands/commands.spec.md`.

### Member commands

| Command | What it is in the reference | Verdict | Why |
|---------|-----------------------------|---------|-----|
| `/ping` | Alive check; then edits in a latency. | **This change.** | `LEARN-3`. Must not read the chain (`RUN-11`). |
| `/help` | Ephemeral pages; game numbers read from play constants. | **This change**, stripped to what is actually registered. | `LEARN-4`, `LEARN-8`, `LEARN-8.a`. `LEARN-5`/`LEARN-6` wait for `/game`. |
| `/verify` | Defers, talks to a portal, button with a URL. | **This change.** | `VERIFY-1`. The product exists for this. |
| `/unlink` | Remove one wallet, or list them. | **This change.** | `VERIFY-3`. A verify that cannot be undone is not a verify. |
| `/status` | Ephemeral standing; cache only, no algod. | Later. | Useful (`SHOW-2` pointed at the self). Not required to receive a role. |
| `/togglepublic` | Leaderboard opt-out. | Later. | `SHOW-2.a`. |
| `/leaderboard` | Standing among holders. | Later. | `SHOW-2`. Must be this server's token and collections (`SHOW-4`). |
| `/tokens` | What the token is and where to trade it. | Later. | `LEARN-1`, `LEARN-7`. Content is `TokenProfile`, already loaded. |
| `/community` | Server-wide stats. (`StatsCommand.name = "community"`.) | Later. | `LEARN-2`. |
| `/flex` | Post one NFT in the channel. | Later, renamed. | `SHOW-1`. "Flex" is one community's voice. `/show` (or the operator's word) over any configured collection (`SHOW-4.a`). Never include a wallet (`SHOW-1.b`). |
| `/mynft` | Paginated holdings; `public:true` was `/gallery`. | Later, renamed. | `SHOW-3`. Generic holdings browser, not two hardcoded collections. |
| `/nft` | Look up one asset in the Nevermore/Baby Jay registry. | **Do not port.** | Not a want in `hi/`. Lookup of a stranger's registry is one community's explorer. Showing *your* piece is `/show`. |
| `/claim` | Member side of an NFT offer. | Later, with gifts. | `GIFT-1`. No offer command means no claim command (`ADOPT-10.b`). |
| `/time` | Typed time → `<t:unix:style>`, saved IANA zone. | Later. | `WHEN-*`. `TimeParser` is already the right shape (pure, `now` and `TimeZone` as parameters) and can move almost as-is. Not verify-and-role. |
| `/game` | `me` `daily` `call` `jack` `forage`. | Later, optional. | `PLAY-*`. Off unless the operator wants a table (`PLAY-9`, `ADOPT-10`). |

### Admin commands

| Command | What it is in the reference | Verdict | Why |
|---------|-----------------------------|---------|-----|
| `/resync` | Kick the role sweep. | Later. | `ROLE-1` staying true. First verify applies roles once; the loop is the next change. |
| `/ops` | Last sweep, budget, errors. Reads no chain. | Later. | `SEE-2`, `SEE-5`, `SEE-6`, `SEE-9`. Health HTTP covers `SEE-1` now. |
| `/say` | Announce as the bot; audit row first. | Later. | `RUN-4`, `RUN-5`. `SayCommand.plan` (UTF-16 refuse, empty allowed-mentions) is the pattern to copy, not the command to ship. |
| `/settings` | A few database-backed knobs. | Later. | `RUN-2`. Most settings stay environment variables until `CATALOG`. |
| `/wallet` | Hot wallet address/status/log/opt-in/unpause. No send. | Later, only with a key. | `SPEND-*`. Absent key → not registered (`ADOPT-10.b`, `SPEND-6.c`). |
| `/rain` | Preview/send, plus reserve. | Later, only with a key. | `RAIN-*`, `RESERVE-*`. Long-running; needs `REQ-surface-010` first. |
| `/giveaway` | Offers, inventory, fund card, CORVID send. | Later, only with a key. | `GIFT-*`, `SPEND-*`. |
| `/raffle` | Draw among holders. | Later, only with a key. | `GIFT-6`, `GIFT-8.b`. The required-before-optional bug lived here. |
| `/schedule` | Arm recurring work. | Later. | `REPEAT-*`. Seeded disabled; nothing fires until enabled (`REPEAT-1.a`). |

### Do not port, even later, under these names

| Command / piece | Why it is not a general product |
|-----------------|----------------------------------|
| `/test-balance` | Operator debug. Spends the day's chain budget. Not in `hi/`. `RUN-11` is that no one member can spend that budget; an admin debug command is how they would. |
| `/admin-nft-registry` | One community's off-chain registry admin. `PICTURE` is a later cache, not this UI. |
| `SneakPeekService` | Fun replies on ordinary messages. Not in `hi/`. Needs the `guildMessages` intent for a joke. |
| `AdminServer` (Pera-gated HTTP catalog) | `CATALOG`, a different surface, with a wallet sign-in. Out of this change and out of the Discord target. |
| Hardcoded collection choices (`Nevermore` / `Baby Jay`) on `/rain`, `/raffle`, `/flex` | `RAIN-14`, `GIFT-8`, `SHOW-4`. The catalog of collections is the operator's list. |
| Default ladder, default logo, default LP pools, presence `watching CORVID holdings` | `ADOPT-6`, `ADOPT-6.a`, `ADOPT-1.f`. |
| `/wallet send` | Already removed in the reference. Sends are `/rain` and `/giveaway`. |

Saying a command should not be ported is the point of this table. Three
commands and one message handler are one community's tools. Several
others are real wants and still not this change.

## Question 1. Which of the 26 should a general product have at all?

**Have, in a general product, eventually:** ping, help, verify, unlink,
status, togglepublic, leaderboard, tokens, community, a holdings
browser, a show-one-piece command, time, game (optional), claim (with
gifts), resync, ops, say, settings, wallet, rain, giveaway, raffle,
schedule.

**Have in this change:** ping, help, verify, unlink.

**Do not have:** test-balance, admin-nft-registry, nft-as-registry-lookup,
sneak-peek.

The test of "general" is `hi/`, not the reference README. If a command
has no criterion, it is a habit. If a command's options name two
collections, it is not general yet even when the family is real.

## Question 2. Smallest surface after which somebody can verify a wallet and get a role

Not "the whole bot". This:

1. An executable that loads configuration and refuses a missing required
   variable by name (`ADOPT-2`, `RUN-9.a`).
2. Open of the store, which takes `InstanceLease` (`RUN-7`).
3. Bind of the health port and the verification-callback port, **before**
   any Discord IDENTIFY (`RUN-7.a`).
4. A `VerificationClient` that speaks `docs/VERIFICATION.md`. Tests use
   a fake. A real member still needs a portal, and that is `0001`, not
   this change. Honest about `ADOPT-4`: README-alone verification waits
   on `0001`.
5. Guild slash registration of `/ping`, `/help`, `/verify`, `/unlink`,
   validated offline first.
6. Gateway identify, then event loop.
7. `/verify`: ephemeral, defer, create a session, show a button whose
   URL is the portal's. No key, no seed (`VERIFY-1`).
8. Inbound callback: admit member (`Store.admitMember`), prove account
   (`AccountStore.prove`), read the chain, `RoleRules.decide`, apply
   only `managed` roles in one Discord API call (`ROLE-1`, `ROLE-5`,
   `ROLE-1.a`).
9. `/unlink` one account; `guildMemberRemove` forgets the member
   (`VERIFY-3`, `VERIFY-7`).
10. Health: `503` until the gateway is up; `200` names Discord, store,
    and the verification half, and spends no chain budget (`SEE-1`,
    `SEE-1.a`, `SEE-1.b`, `SEE-10`).

Not in the smallest surface: the 30-minute sweep, games, money, cards of
NFTs, `/time`, `/ops`, `/say`, catalog HTTP. After verify, the member
has a role *now*. Keeping it true when they sell is the sweep, and that
is the next change.

Without a portal process, a contributor still exercises the whole path
with a fake client and an `InMemoryStore` (`BUILD-1.b`, `BUILD-2`).

## Question 3. How to test a Discord surface with no Discord

The reference's mistake is the seam, not the lack of fixtures. Almost
every handler takes `any DiscordClient` and talks to it. The tests that
work are the ones that never did that:

- `GameCommandTests`: asserts on `definition` values.
- `CommandAuthTests`: pure function over permission bits and role ids.
- `HelpCommandTests`: `HelpCommand.card(topic)` returns `GameMessage`.
- `SayCommandTests`: `SayCommand.plan(...)` returns `.post` or
  `.refuse`, and counts UTF-16 with `👍`.
- `TimeCommandTests` / `TimeParser`: `now` and `TimeZone` as
  parameters.
- `DiscordLimitsTests`: clamp and join, still counting Swift
  characters, which is the remaining hole.

`DiscordBM` advertises "abstractions for easier testability". Using
`DiscordClient` in the handler *is* that abstraction, and it is the
wrong one. It still needs a client. It still cannot assert "this is the
card" without building Discord payload types. It still cannot run the
acknowledge policy.

**The seam this definition uses:**

```
fixture JSON  →  Adapter  →  InteractionRequest (our value)
                                    ↓
                              Router / handler
                                    ↓
                              SurfaceReply (our value)
                                    ↓
                         Adapter  →  RecordingGateway
```

Three layers, and only the adapter imports DiscordBM.

1. **Our values.** `CommandDefinition`, `InteractionRequest`,
   `SurfaceReply`, `SurfaceCard`, `ButtonSpec`. `Sendable` and
   `Equatable`. Tests construct them with literals.
2. **The adapter.** Maps our catalog onto
   `Payloads.ApplicationCommandCreate`. Maps a decoded Discord
   interaction onto `InteractionRequest`. Maps `SurfaceReply` onto
   HTTP calls. This is the only place `Snowflake` exists. Tests of the
   adapter use DiscordBM types and still no network.
3. **Recording doubles.** `RecordingGateway` captures what would have
   been sent. `FakeVerificationClient` implements the portal protocol.
   `FakeRoleApplier` captures `RoleDecision`s. `InMemoryStore` is
   already real. `Chain` already accepts a data source.

What a test looks like, concretely:

- **Catalog.** A definition with a required option after an optional
  one fails `CommandValidator`. The `/raffle draw` shape from the
  reference is a fixture in that test, even though `/raffle` is not
  shipped. Description over 100 characters fails. Duplicate
  subcommand names fail. The shipped catalog passes, and is the
  payload that would be registered.
- **Boot.** A fake binder that fails on the health port; a fake
  gateway whose `identify` count stays zero. A fake binder that
  succeeds; `identify` is called once, after bind.
- **Router.** An `InteractionRequest` for `/ping` yields an immediate
  `SurfaceReply`. An unknown command yields an ephemeral refusal, not
  silence. An unknown `custom_id` yields an ephemeral refusal. An
  autocomplete request is answered without a defer flag.
- **Verify.** `/verify` against `FakeVerificationClient` that returns
  a URL; the reply is a card with a link button; `InMemoryStore` has
  not yet admitted anyone. A callback fixture admits, proves, decides,
  applies. A callback for a foreign guild is ignored (`HOST-10.a`).
- **UTF-16.** `ReplyLimits.utf16Count("👍") == 2`. A string of
  `messageLimit/2 + 1` thumbs is refused or clamped, matching
  `SayCommandTests.lengthIsUTF16`.
- **Attachments.** An edit of a card with no file includes
  `attachments: []`. A test that encodes the adapter payload fails if
  the key is missing.
- **Identity.** `StoreTests` already prove a key is not derived. A
  `TargetShape` test in `SurfaceTests` greps `Sources/` for
  `import DiscordBM` and allows only `Sources/Surface`.
  `swift package dump-package` (or the manifest as data) asserts
  `Store`, `Gating`, `Games`, `Chain`, `Reserve`, `StoreSQLite` do
  not list the DiscordBM product.

No `DISCORD_BOT_TOKEN` in the environment can change this. If a test
reaches a network, that is a failed seam, not a skipped test
(`BUILD-2.a`).

## Question 4. Is the card renderer a value type, a protocol, or something else?

**A value type.** Not a protocol. Not an enum-of-static-functions that
imports DiscordBM.

### What the reference did

- `GameMessage` is a value. That part is right, and it already lives
  in `Games`.
- `GameCard` is an `enum` with no cases, used as a namespace, that
  imports DiscordBM and maps `GameMessage` onto `Embed` and
  `ActionRow`. Clamping, routing of `custom_id`, and rendering all
  live there.
- `NFTEmbed` is the same pattern for Nevermore/Baby Jay, with colours
  and field shapes welded to those collections.
- Buttons that do work are `custom_id` strings routed in
  `Bot.handleComponentInteraction` with a long `if hasPrefix` chain.

### Why a protocol is the wrong upgrade

A `CardRenderable` protocol grows `handle()`, then `defer()`, then a
`DiscordClient`, then the card is a handler. Tests need a gateway.
`Games` cannot produce one. A button that does work becomes a method
on the card, so a claim card depends on a wallet service, which is how
the reference became one 11,300-line target.

A protocol of `var card: SurfaceCard { get }` is a value with extra
steps.

### Why a DiscordBM namespace enum is not enough

It puts client types on the wrong side of the seam. `HelpCommand.card`
returning `GameMessage` is why `HelpCommandTests` exist.
`GameCard.embed` returning `Embed` is why game tests stop at the
message and never see the payload that Discord would reject.

### The cost of a value, when a card needs a button that does work

The card cannot carry the work. A `ButtonSpec` has an id, a label, a
style, an optional URL, and a disabled flag. The renderer maps it. The
router matches the id's namespace (`verify:`, `unlink:`, later
`claim:`, `ng_` for games). The handler does the work and returns a
**new** card value.

That is a tax: a one-off button needs a registered route, not a
closure at the call site. It is also the thing that keeps `Store`,
`Gating` and `Games` compilable without Discord, and the thing that
lets a test assert "this card has a Claim button with this id" without
claiming.

Link buttons (URL, no interaction) stay on the card. They do no work
in-process. `/verify`'s portal button is a link.

### What we actually ship

One `SurfaceCard` struct: title, description, fields, colour, footer,
thumbnail URL, image URL, buttons, optional attachment name. Builders
(`helpCard`, `verifyCard`, later `GameMessage` mapping) produce it.
The adapter renders it. No sum type of twelve kinds until a kind needs
a Discord feature the struct cannot express (a modal, a select menu).
Select menus and modals are later; the router must not assume every
component is a button.

`GatingFormatting.clamp` may pre-shape a field. The adapter clamps
again in UTF-16. Two clamps are cheaper than one stuck "thinking…".

## Discord's constraints, as this surface has to encode them

From Discord's application-command and interaction docs, as the
reference encoded them after being burned:

| Rule | Number | Where it bites |
|------|--------|----------------|
| Acknowledge an interaction | 3 seconds | Every handler. Autocomplete cannot defer. |
| Finish or follow up | 15 minutes | Rain, reserve, full resync. |
| Message content | 2000 UTF-16 | `/say`, logs, receipts. |
| Embed title | 256 | Every card. |
| Embed description | 4096 | Help, status. |
| Embed field name / value | 256 / 1024 | Unlink wallet lists, rain previews. |
| Embed footer | 2048 | |
| Embed total | 6000 across 10 embeds | |
| Button label | 80 | |
| Button custom id | 100 | Namespaces must stay short. |
| Buttons per row / rows | 5 / 5 | `GameCard.maxButtons` is this. |
| Command name | 1–32, lowercase `[\w-]` | |
| Command description | 1–100 | |
| Options per command | 25 | |
| Required options before optional | per options array | Register 400, boot loop. |
| Autocomplete choices | 25 | `/time` tz, later `/flex` nft. |
| Guild vs global commands | guild updates in seconds | One guild (`HOST-10`). |

UTF-16 is not documented as loudly as the 2000-character figure, which
is why the reference counted graphemes until `/say` was given a
thumbs-up test. This definition treats UTF-16 as the unit everywhere
a payload is bounded.

## DiscordBM, and what it costs

Today `Package.resolved` has three pins: `swift-algorand` 0.4.0,
`swift-crypto` 3.15.1, `swift-asn1` 1.7.3.

DiscordBM 1.16.2 (the version the reference resolved) declares eight
direct dependencies:

- `apple/swift-nio` (from 2.100.0)
- `apple/swift-log`
- `swift-server/async-http-client`
- `vapor/multipart-kit`
- `jpsim/Yams` (code generator, not the bot runtime)
- `swiftlang/swift-syntax` (UnstableEnumMacro; a compile-time cliff)
- `facebook/zstd` (gateway decompression)
- `hummingbird-project/swift-websocket`

Those pull NIO-SSL, HTTP2, extras, transport-services, atomics,
collections, algorithms, numerics, system, certificates, HTTP types,
metrics, tracing, service-context, and others. Two of the three pins
we already have (`swift-crypto`, `swift-asn1`) reappear as
transitives. A bot that adds **only** DiscordBM, not Fluent and not
Vapor, still lands around two dozen resolved packages. The
implementation PR prints the actual pin count from `Package.resolved`
and lists every new host in `docs/WHAT-IT-TALKS-TO.md`. This paragraph
is an estimate; that file is the disclosure (`TRUST-1`, `TRUST-4`).

Specifically expensive:

- **swift-syntax** at build time. CI on Linux and macOS will feel it.
- **zstd** as native code in the graph.
- **Hosts.** `discord.com` (HTTP API, command registration) and the
  gateway (IDENTIFY, events). Both are new outbound calls.
- **Secret.** `DISCORD_BOT_TOKEN`. Currently the package has one
  optional secret, `CHAIN_API_TOKEN`.

Not taken, on purpose: Fluent, FluentSQLiteDriver, Vapor, Fork, Cache,
compress-nio-as-a-direct-pin. The private graph is ~40 pins because of
those, not because of DiscordBM. Store already replaced Fluent.

DiscordBM's `DiscordClient` protocol is not our test seam. It is the
adapter's dependency.

## Identity, as Store already chose it

`MemberKey` is 32 lowercase hex characters, minted from
`SystemRandomNumberGenerator`, derived from nothing about the person.
`MemberRecord.externalId` is "who they are to the chat client, as a
plain string". The directory row is the only place they appear
together. Delete it and every surviving mention refers to nobody
(`VERIFY-7`, store `REQ-store-006`).

The reference stored Discord snowflakes on `verified_users` and passed
`UserSnowflake` through every layer. That is the thing Store was
written to make unrepresentable.

Survival at this target:

- Surface adapters convert `UserSnowflake.rawValue` (decimal digits)
  to `String` once, on the way in.
- Handlers call `store.admitMember(externalId:at:)` and
  `store.member(externalId:)`.
- `RoleDecision.memberId` stays a `String`.
- DiscordBM types do not appear in handler signatures.
- Mentions in replies (`<@id>`) use the snowflake string at the
  adapter, not a key, and never land in the ledger.

The compiler's version of that: Store's target does not depend on
DiscordBM, Surface depends on Store, SwiftPM refuses a cycle, and a
test fails the build if `import DiscordBM` appears outside Surface.

## Boot order, as the reference learned it

From the reference `CLAUDE.md` and `Bot.start()`:

1. Construct services (including `BotGatewayManager`, which does **not**
   identify in `init`).
2. Bind webhook port.
3. Bind admin port.
4. Register slash commands over HTTP (uses the token; this is not
   IDENTIFY).
5. `gateway.connect()`: IDENTIFY.
6. Start loops (role sync, sweeper, schedule).

The fatal order is bind **before** step 5. Registering commands over
HTTP does not invalidate a session. IDENTIFY of a second connection
does.

Two independent duplicate-process brakes already exist or will:

- `InstanceLease` on the store file. Same machine, same store.
- Bind of the configured listen ports. Same machine, same ports,
  possibly different stores.

Neither stops two machines with one token. `HOST-6` says an instance
is mine alone; two hosts sharing a token is an operator mistake this
software cannot see. The definition does not pretend otherwise.

Health: the reference reports `503 {"status":"starting"}` until the
gateway connects, because a bound socket is not health. Keep that
(`SEE-1.a`).

## Verification, as this repository already wrote it

`docs/VERIFICATION.md` is the contract. The bot's half, for this
change:

- `GET {base}/health` at boot, no key, abort on failure.
- `POST /api/v1/verification` with `X-API-Key`, expect `201`.
- Inbound `POST /webhook/verification` with the same key, fixed-size
  read, `200`.
- `DELETE` on unlink.
- Discord ids as decimal **strings**, never JSON numbers.
- One shared secret, not two (`VERIFY-5.b` is otherwise unanswerable
  at boot).

The page itself is `0001`. Surface depends on a protocol, not on a
process layout.

## What the merged libraries already give the surface

- `RoleRules.decide` → `RoleDecision` with `managed`, `granted`,
  `revoked`, `unknowns`, `held`. Apply at the boundary. Do not
  reimplement.
- `TokenProfile` for card colour, logo URL, links, symbol, decimals.
- `GatingConfiguration.allRoleIds` as the only roles the bot may
  touch.
- `MemberDirectory.admitMember` / `forget` / `disclosure`.
- `AccountStore.prove` / `unlink` / `recordBalances`.
- `Chain` for the post-verify read, behind the governor the host
  already holds.
- `GameMessage` when games arrive. Not this change.
- `Reserve` when rain arrives. Not this change. The reply layer's
  long-running path exists so rain does not have to invent it.

## Intent ids this research actually used

Checked with `hi ls`. Requirements cite only live criterion ids.
Retired ids are not used as coverage.
