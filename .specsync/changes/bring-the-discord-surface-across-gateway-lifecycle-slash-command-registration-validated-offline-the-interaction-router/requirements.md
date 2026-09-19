---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: requirements
---

# Requirements

Normative for the Discord surface. Each `REQ-surface-*` id is stable.
A SHALL is testable. Criterion ids were read from `hi ls` and are not
invented.

The module name is `surface`. Canonical spec `specs/surface/` is
written in the same delivery PR as `Sources/Surface`, not in this
definition.

## User stories

- As a member, I want to prove a wallet is mine without handing anyone
  a key, and I want the role beside my name to follow (`VERIFY-1`,
  `ROLE-1`).
- As a member, I want to unlink and stop being tracked (`VERIFY-3`).
- As a member, I want to find out from Discord whether the bot is
  awake and what it can do here (`LEARN-3`, `LEARN-4`, `LEARN-8`).
- As somebody running this, I want a second copy started by accident
  to die without taking the live session (`RUN-7`, `RUN-7.a`).
- As somebody running this, I want a command Discord would reject to
  fail a test and fail boot, not crash-loop a deploy (`ADOPT-2`).
- As somebody running this, I want to run only the parts I want
  (`ADOPT-10`, `ADOPT-10.b`).
- As a contributor, I want the tests to need no token, no network and
  no guild (`BUILD-2`, `BUILD-2.a`, `BUILD-2.b`).
- As somebody deciding whether to install this, I want every new host,
  secret and package named in one place (`TRUST-1`, `TRUST-1.b`,
  `TRUST-4`).

## Acceptance criteria

### REQ-surface-001

A new library target `Surface` and a thin executable target `Bot`
(product `discord-bot`) SHALL be added. `Surface` SHALL be the only
target that depends on DiscordBM. `Reserve`, `Gating`, `Games`,
`Chain`, `Store`, `StoreTestKit` and `StoreSQLite` SHALL NOT depend on
DiscordBM and SHALL NOT `import DiscordBM`.

- Covered by `Package.swift` and by a target-shape test that fails on
  an import or a dependency edge outside `Sources/Surface`.
- `BUILD-2`, `TRUST-4`.

### REQ-surface-002

A member's chat account id SHALL enter `Store` only as
`MemberRecord.externalId: String`. DiscordBM `Snowflake` types SHALL
exist only in Surface adapter code. `MemberKey` SHALL be minted by
`Store.admitMember` and SHALL NOT be derived from a snowflake, a
hash of one, or any other fact about the person.

- Covered by the compiler (Store cannot name the type), by store
  `REQ-store-006`, and by a Surface test that a handler signature
  taking a DiscordBM snowflake does not exist outside the adapter.
- `VERIFY-4`, `VERIFY-7`.

### REQ-surface-003

Boot SHALL take the store lease, THEN bind every listening port this
process owns, THEN identify to the Discord gateway. Identify SHALL NOT
be called if the lease or any bind failed. Command registration over
HTTP MAY occur after bind and before identify; it is not identify.

- Covered by a boot-sequence test with a fake binder and a fake
  gateway: bind failure ⇒ identify count stays 0; bind success ⇒
  identify called once, after bind.
- `RUN-7`, `RUN-7.a`.

### REQ-surface-004

The health listener SHALL bind before identify. Until the gateway
reports ready, it SHALL answer `503` and SHALL NOT report healthy. A
`200` SHALL name, separately, whether Discord, the store, and the
verification half are up, and SHALL spend no chain-request budget.

- Covered by health-payload tests against a fake clock and a fake
  chain governor whose request count does not move.
- `SEE-1`, `SEE-1.a`, `SEE-1.b`, `SEE-10`.

### REQ-surface-005

Every slash command this process will register SHALL be a value in a
`CommandCatalog`. Registration SHALL map that catalog. Tests SHALL
assert on the catalog, not on a live guild.

- Covered by catalog equality tests and by a single registration
  mapping test that does not open a socket.
- `BUILD-2`.

### REQ-surface-006

A `CommandValidator` SHALL refuse a catalog Discord would refuse,
before any HTTP call, including at least:

- a required option appearing after an optional option on the same
  command, subcommand, or subcommand-group options array
- a name or description empty, over Discord's length, or (for names)
  outside Discord's allowed charset
- duplicate option or subcommand names in one array
- more than 25 options in one array
- a command name over 32 or a description over 100, counted the way
  Discord counts (UTF-16 code units)

A catalog the validator refuses SHALL fail a unit test and SHALL fail
boot naming the command and the rule. The `/raffle draw` shape from
the reference (optional `collection` before required `confirm` /
`asa`) SHALL be a failing fixture even though `/raffle` is not
shipped.

- Covered by validator table tests.
- `ADOPT-2`.

### REQ-surface-007

This instance SHALL serve one configured guild. An interaction whose
guild is missing or is not that guild SHALL be refused with an
ephemeral message and SHALL NOT read or write another community's
store. Commands SHALL be registered as guild commands of that guild,
not as global commands.

- Covered by router tests with a foreign guild id.
- `HOST-6`, `HOST-10`, `HOST-10.a`.

### REQ-surface-008

Every inbound interaction this process receives, whether slash command,
autocomplete or message component, SHALL be answered. An unknown
command name and an unrouted component `custom_id` SHALL receive an
ephemeral refusal, not silence.

- Covered by router tests for each of the three kinds, including the
  unknown cases.
- A dropped interaction is Discord's "This interaction failed".

### REQ-surface-009

Each command SHALL declare its acknowledge policy: immediate reply,
defer within three seconds, or long-running. Autocomplete SHALL be
immediate and SHALL NOT defer. A handler whose work can exceed three
seconds SHALL defer (or be long-running) before that work. The router
SHALL enforce the policy; a handler SHALL NOT be able to forget.

- Covered by policy tests: a deferred command's first recorded action
  is a defer; an autocomplete recorded action is never a defer.
- Discord's 3-second rule.

### REQ-surface-010

A command that can outlive a fifteen-minute interaction token SHALL be
long-running. While the token is live, the report SHALL go to the
interaction. After it expires, the report SHALL reach the invoker by a
configured fallback (a DM to the invoker, or a message in an operator
channel the operator named). Losing the report SHALL NOT lose the
work's record.

This change SHALL ship the reply-layer seam and tests against a fake
clock that advances past fifteen minutes. Rain, reserve and full
resync SHALL use it later; they are not registered in this change.

- Covered by a fake-clock follow-up test and a fallback test.
- `RAIN-13`, `RAIN-13.a`, `RAIN-13.b`.

### REQ-surface-011

Every outbound payload SHALL be bounded in UTF-16 code units, using
Discord's published limits (message 2000, embed title 256, description
4096, field name 256, field value 1024, footer 2048, button label 80,
custom id 100). `GatingFormatting.clamp` counts Swift `Character`s and
SHALL NOT be treated as sufficient.

When truncation would change meaning (an announcement, a URL, a
receipt link), the send SHALL be refused with an ephemeral message
rather than truncated. Otherwise the send SHALL clamp on a whole-line
boundary, say how much was omitted, and keep warnings above detail
(`RAIN-1.d`). An over-long payload SHALL fail in this layer, never as
a Discord 400 after a defer.

- Covered by tests that include `👍` (one `Character`, two UTF-16
  units) at the boundary, and by a refuse-vs-clamp matrix.
- `RAIN-1.d`, `LEARN-7.b` (amounts still go through
  `GatingFormatting.amount`, not `compact`, when they must be
  checkable).

### REQ-surface-012

Every message edit SHALL include an `attachments` array. A card with
no file SHALL send an empty array. Omitting the key SHALL fail a test
of the encoded payload.

- Covered by an adapter encoding test.
- The frozen-hand-picture failure.

### REQ-surface-013

A card SHALL be a `Sendable` `Equatable` value (`SurfaceCard`) with no
DiscordBM type on it. The renderer SHALL be a pure mapping in the
adapter. `Games.GameMessage` SHALL map to `SurfaceCard` when games
exist; this change SHALL NOT put Discord types into `Games`.

- Covered by card equality tests and by the target-shape import test.
- `BUILD-2`, `PLAY-11` (games remain chain-free; the mapping is
  Surface's).

### REQ-surface-014

A button that does work SHALL be a `ButtonSpec` carrying a namespaced
id, not a closure and not a method on the card. The router SHALL match
the namespace. A link button MAY carry a URL and SHALL NOT be routed
as work. An unrouted id SHALL still be answered (`REQ-surface-008`).

- Covered by router tests and by a compile-time absence of function
  types on `ButtonSpec`.
- `BUILD-2`.

### REQ-surface-015

This change SHALL register exactly four slash commands: `ping`,
`help`, `verify`, `unlink`. No other command SHALL appear in the
shipped catalog. Adding a fifth is a different change.

- Covered by a catalog-contents test.
- `LEARN-3`, `LEARN-4`, `VERIFY-1`, `VERIFY-3`.

### REQ-surface-016

`/help` SHALL be ephemeral, SHALL need no wallet, and SHALL list only
member commands actually present in the catalog. It SHALL NOT name an
admin command, a command this server has switched off, or a word from
the project this was built for.

- Covered by help-card tests against catalogs of different shapes,
  including a catalog with games absent.
- `LEARN-4`, `LEARN-8`, `LEARN-8.a`, `ADOPT-1.c`.

### REQ-surface-017

`/verify` SHALL be ephemeral. It SHALL NOT ask for a key, a seed
phrase, or a pasted signature. It SHALL talk to verification through a
protocol whose HTTP shape matches `docs/VERIFICATION.md`. Tests SHALL
use a fake. Before a member is sent to sign, the card SHALL say what
this server keeps, who runs it, and which of it other members will see,
from this instance's configuration, not from shipped copy.

- Covered by verify-handler tests against `FakeVerificationClient` and
  by a disclosure-card test that fails if operator-supplied strings
  are missing.
- `VERIFY-1`, `VERIFY-5`, `VERIFY-5.a`, `VERIFY-6`.

### REQ-surface-018

`/unlink` with no wallet SHALL list the member's accounts (bounded,
`REQ-surface-011`) and SHALL NOT unlink. `/unlink` with a wallet SHALL
remove that account (`AccountStore.unlink`) and SHALL re-decide roles.
Removing the last account SHALL forget the member (`MemberDirectory.forget`)
if and only if no accounts remain. `guildMemberRemove` for the served
guild SHALL forget the member.

- Covered by unlink and leave tests against `InMemoryStore` and a fake
  role applier.
- `VERIFY-3`, `VERIFY-7`.

### REQ-surface-019

The verification callback SHALL, in order: reject a foreign guild and
a malformed id; `admitMember`; `prove` the account; read the chain;
build `MemberHoldings` with unknown, never zero, where a read failed;
call `RoleRules.decide`; apply only roles in `RoleDecision.managed`,
in one Discord API call. An unread fact SHALL NOT revoke the roles it
decides.

- Covered by callback tests with complete holdings, with an unknown
  balance, and with a foreign guild.
- `ROLE-1`, `ROLE-1.a`, `ROLE-5`, `VERIFY-2`, `VERIFY-2.a`.

### REQ-surface-020

Authorisation for an operator command SHALL be a pure function over
permission bits and role id **strings**, granted when the member has
Administrator or holds the configured extra admin role. Registration
`default_member_permissions` SHALL NOT be trusted alone. This change
SHALL ship the function and its tests even though no admin command is
registered yet.

- Covered by the same cases as the reference `CommandAuthTests`,
  without DiscordBM types in the function signature.
- `SPEND-6.a`.

### REQ-surface-021

The catalog SHALL be built from configuration. With no paying key, no
command that can spend SHALL be registered. With games switched off,
`/game` SHALL NOT be registered. A community that only wants roles
SHALL still boot (`SPEND-6.c`, `ADOPT-10`, `ADOPT-10.b`, `PLAY-9`).
This change's four commands are all role-path commands; the builder
rule SHALL still exist so a later command cannot be added as always-on.

- Covered by catalog-builder tests with a missing key and with games
  off.
- `ADOPT-10`, `ADOPT-10.a`, `ADOPT-10.b`, `PLAY-9`, `SPEND-6.c`.

### REQ-surface-022

`SurfaceTests` SHALL run with no network, no Discord token, no guild
and no signing key. Injected fakes only. A test that cannot be written
without a live Discord is a missing seam, not a skip. Configuration on
the developer's machine SHALL NOT be able to point a test at a real
host (`BUILD-2.a`).

- Covered by the suite itself, and by a guard that fails if a test
  target lists a live URL or reads `DISCORD_BOT_TOKEN`.
- `BUILD-2`, `BUILD-2.a`, `BUILD-2.b`, `BUILD-1.b`.

### REQ-surface-023

The same pull request that adds DiscordBM SHALL edit
`docs/WHAT-IT-TALKS-TO.md` with: every new host, every new secret,
the new pin list taken from `Package.resolved` (not an estimate), and
the commands that check those claims. It SHALL edit `CHANGELOG.md`
under Unreleased. A DiscordBM bump that widens the graph is the same
kind of change.

- Covered by document review in that PR and by the existing "one
  fact, one owner" rule in `docs/README.md`.
- `TRUST-1`, `TRUST-1.a`, `TRUST-1.b`, `TRUST-4`, `TRUST-4.a`.

### REQ-surface-024

`DISCORD_BOT_TOKEN` and `DISCORD_GUILD_ID` SHALL be required, with no
default. A placeholder value SHALL refuse boot (`ADOPT-7.a`). Boot
SHALL print what it made of the Discord settings, the invite URL that
grants the permissions this process needs, those permissions in
Discord's own words, and any configured role that sits above the bot
(`ADOPT-9`, `ADOPT-11`, `ADOPT-11.a`, `ADOPT-11.b`). A missing
permission SHALL be named as the permission to grant.

- Covered by configuration tests and by a boot-report snapshot that
  contains no project-of-origin names.
- `ADOPT-2`, `ADOPT-7.a`, `ADOPT-9`, `ADOPT-11`, `ADOPT-11.a`,
  `ADOPT-11.b`, `RUN-9.a`, `RUN-9.b`.

### REQ-surface-025

When a verification portal is configured, boot SHALL detect that the
two halves disagree about the shared secret, and SHALL refuse to start,
rather than learning it from a member whose `/verify` returned 401.
One secret, not two, matching `docs/VERIFICATION.md`.

- Covered by a boot test against a fake portal that answers 401 to a
  keyed probe.
- `VERIFY-5.b`.

### REQ-surface-026

No string a member can read SHALL contain a name, a collection, a
token ticker, a URL or a threshold from the project this was built
for. Command descriptions, presence, help, verify copy and card chrome
SHALL come from this instance's configuration (`TokenProfile` and the
operator's bot name) or from project-neutral words. An unset picture
is no picture.

- Covered by a source grep over `Sources/Surface` for the forbidden
  names, and by help/verify card tests with a blank `TokenProfile`
  logo.
- `ADOPT-1.c`, `ADOPT-1.f`, `ADOPT-6`, `ADOPT-6.a`.

### REQ-surface-027

`/ping` SHALL answer that the bot is awake. It SHALL NOT read the
chain, SHALL NOT spend the day's request budget, and SHALL NOT be the
operator health check (`SEE-1` is HTTP).

- Covered by a ping test whose fake chain governor is untouched.
- `LEARN-3`, `RUN-11`, `SEE-1.b`.

## Constraints

- Swift 6, strict concurrency, `Sendable` on every exported type.
- Explicit access control, K&R braces, four-space indent, no force
  unwrap, no `try!`, no `as!`.
- Platforms already declared in `Package.swift` (macOS 13+, iOS 16+);
  DiscordBM's floor matches.
- Linux and macOS CI. The suite is offline on both.
- One guild per process.
- Money still does not move in this change. The reply-layer seam is
  the only money-adjacent work, and it sends no payment.
- `hi/` criteria are wants, not types. A requirement may name a type;
  a criterion may not.

## Out of scope

- `/status`, `/leaderboard`, `/show`, `/time`, `/game`, `/rain`,
  `/giveaway`, `/raffle`, `/claim`, `/wallet`, `/schedule`, `/ops`,
  `/say`, `/settings`, `/resync`.
- `/test-balance`, `/admin-nft-registry`, `/nft` as a registry lookup,
  sneak-peek.
- The role-sweep loop. First verify applies roles; staying true when
  a member sells is the next change.
- Deciding `docs/decisions/0001-verification-portal.md`.
- Building the portal page, WalletConnect, or an in-process browser
  surface.
- `CATALOG` as an HTTP page.
- Editing `Gating`, `Store`, `Games`, `Chain` or `Reserve` canonical
  specs.
- Fluent, Vapor, Fork, Cache.
- Global Discord commands.
- A default ladder, default logo, default presence, default
  collection list.
