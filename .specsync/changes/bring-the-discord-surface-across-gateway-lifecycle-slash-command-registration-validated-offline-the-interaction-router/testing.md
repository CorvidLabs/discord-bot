---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: testing
---

# Testing

The surface is tested with no Discord, no token, no network and no
guild. If a behaviour cannot be tested that way, the seam is wrong
(`REQ-surface-022`, `BUILD-2`, `BUILD-2.a`).

## The seam

Handlers and the router take and return our values. DiscordBM stays
in the adapter. Doubles:

| Double | Stands in for | Already exists? |
|--------|---------------|-----------------|
| `InMemoryStore` | `BotStore` | yes |
| `FakeVerificationClient` | portal HTTP | no, this change |
| `FakeRoleApplier` | Discord role HTTP | no, this change |
| `FakeBinder` | listen sockets | no, this change |
| `FakeGateway` | IDENTIFY / events | no, this change |
| `RecordingSender` | interaction HTTP | no, this change |
| `FixedClock` | 3s / 15min | no, this change |
| `Chain` test data source | algod | yes, `ChainTests` fixtures |

A test constructs an `InteractionRequest` (or a JSON fixture decoded
by the adapter) and asserts on `SurfaceReply` and on what the fakes
recorded.

`DISCORD_BOT_TOKEN` in the environment must not be readable by the
suite. If a test target calls `getenv` for it, that is a failure.

## Suites to add under `Tests/SurfaceTests`

Names cite the requirement they protect, the way existing tests cite
criterion ids.

| Suite | Protects | Concrete cases |
|-------|----------|----------------|
| `TargetShapeTests` | REQ-surface-001, 002 | `import DiscordBM` only in `Sources/Surface`; Store et al. do not list the product; `ButtonSpec` has no function-typed property |
| `CommandValidatorTests` | REQ-surface-006 | required after optional (raffle-draw fixture); empty name; description 101 UTF-16; duplicate subcommand; 26 options; thumbs-up pushing a description over 100 |
| `CommandCatalogTests` | REQ-surface-015, 021 | exactly four shipped commands; builder omits spend/game when config says so |
| `ReplyLimitsTests` | REQ-surface-011 | `utf16Count("👍")==2`; thumbs-up string at the 2000 boundary; join drops whole lines; a URL list that cannot fit one URL is empty plus a note, not a sliced href |
| `AttachmentEditTests` | REQ-surface-012 | encoded update with no file contains an empty attachments array; with a file contains the name |
| `RouterTests` | REQ-surface-007, 008, 009 | foreign guild refused; unknown command answered; unknown custom_id answered; autocomplete recorded action is not defer; deferred command's first action is defer |
| `CommandAuthTests` | REQ-surface-020 | Administrator grants; extra role grants; ordinary member denied; nil permissions denied |
| `BootSequenceTests` | REQ-surface-003, 004, 025 | bind fail ⇒ identify 0; bind ok ⇒ identify once after bind; health 503 then 200; secret mismatch refuses start; chain budget unchanged by health |
| `IdentityTests` | REQ-surface-002 | admitMember mints a key; snowflake string stored only as externalId; forgotten member's key does not come back |
| `VerifyCommandTests` | REQ-surface-017, 026 | fake portal URL on the card; no key asked; disclosure uses operator strings; blank logo is no thumbnail |
| `UnlinkCommandTests` | REQ-surface-018, 011 | no wallet ⇒ list, bounded; one wallet removed; last account forgets; leave event forgets |
| `VerificationCallbackTests` | REQ-surface-019 | happy path applies a decision; unknown balance holds roles; foreign guild no store writes |
| `HelpCommandTests` | REQ-surface-016 | lists ping/verify/unlink; does not list resync/wallet/rain; a catalog without games does not mention games; no origin names |
| `PingCommandTests` | REQ-surface-027 | replies; fake governor untouched |
| `JobMailboxTests` | REQ-surface-010 | clock +14 min ⇒ follow-up; clock +16 min ⇒ fallback; outcome recorded either way |
| `CardTests` | REQ-surface-013, 014 | equality; link button has url and empty id; work button has id and no url; renderer mapping test may import DiscordBM |
| `ConfigurationTests` | REQ-surface-024 | missing token refuses; placeholder refuses; invite URL contains Manage Roles |

## Fixtures

- Interaction JSON for a slash command, an autocomplete, a button,
  a foreign guild, and a missing guild. Taken from Discord's payload
  shape, with zeros for snowflakes (`000000000000000001`), never a
  real id.
- Illegal catalog: required option after optional, copied from the
  reference `/raffle draw` before the fix.
- `MemberHoldings` with `Reading.unknown` for the balance, to prove
  hold-not-revoke.
- A 58-character made-up address and a 52-character made-up txid
  only if a later slice lists receipts; not this change.

No real Discord snowflake, no real wallet, no real asset id
(`ADOPT-7`).

## What the existing suites already cover

Do not duplicate:

- `RoleRulesTests`: the decision. Surface tests that we *apply*
  it, not that the ladder stacks.
- `Store` conformance covers admit, prove, forget and unlink.
- `GatingFormattingTests`: amounts. Surface still re-clamps
  payloads in UTF-16.
- `GameCommandTests` / `HelpCommandTests` in the private reference
  These are patterns to copy, not code to import.

## Manual QA (later, not a substitute)

When an executable exists and someone has a throwaway guild:

- Boot with the health port taken: process exits, live bot (if any)
  keeps its session.
- Register a catalog that would 400: never happens, because
  validator already refused.
- `/verify` with the portal down: boot already refused, or `/verify`
  names the verification half (`SEE-7`, `SEE-10`).
- `/ping` while the day's chain budget is zero: still answers.

Manual QA does not close `REQ-surface-022`. The gate is `swift test`.

## Edge cases the suite must not miss

- `👍` at every published limit.
- Empty attachments key vs empty attachments array.
- Autocomplete + defer (forbidden).
- Identify called from `init` of a gateway wrapper (forbidden;
  only `BootSequence` after bind).
- Callback body larger than the fixed-size read (refuse, do not
  parse a prefix).
- Discord id as a JSON number in a fixture (must not decode into
  a usable id; snowflakes do not fit in Double).
- Help card against a catalog of four commands and against a
  future catalog with games, so `LEARN-8.a` stays a property of
  the builder.

## Requirement coverage

| REQ | Suite |
|-----|-------|
| 001, 002 | `TargetShapeTests`, `IdentityTests` |
| 003, 004, 025 | `BootSequenceTests` |
| 005, 015, 021 | `CommandCatalogTests` |
| 006 | `CommandValidatorTests` |
| 007, 008, 009 | `RouterTests` |
| 010 | `JobMailboxTests` |
| 011 | `ReplyLimitsTests` |
| 012 | `AttachmentEditTests` |
| 013, 014 | `CardTests` |
| 016 | `HelpCommandTests` |
| 017, 026 | `VerifyCommandTests` |
| 018 | `UnlinkCommandTests` |
| 019 | `VerificationCallbackTests` |
| 020 | `CommandAuthTests` |
| 022 | the suite, plus no-getenv guard |
| 023 | document review in the delivery PR |
| 024 | `ConfigurationTests` |
| 027 | `PingCommandTests` |
