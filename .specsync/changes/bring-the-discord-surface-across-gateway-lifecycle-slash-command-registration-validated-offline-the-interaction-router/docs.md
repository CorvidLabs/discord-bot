---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: docs
---

# Docs

Which document owns which new fact, so the set does not gain a
second home for the same sentence. The map is
`docs/README.md`. Implementation edits these in the same PR as the
code. This definition session writes none of them except by naming
them.

## Already the owner

| Document | New facts it will own |
|----------|------------------------|
| `docs/WHAT-IT-TALKS-TO.md` | Discord HTTP API and gateway as hosts; `DISCORD_BOT_TOKEN` as a secret; the verification callback as inbound (not outbound); the DiscordBM pin list, counted from `Package.resolved`; greps that prove Store still has no Discord import. `TRUST-1`, `TRUST-1.b`, `TRUST-4`. |
| `docs/CONFIGURATION.md` | `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `DISCORD_ADMIN_ROLE_ID`, `HEALTH_PORT`, `VERIFY_CALLBACK_PORT`, `VERIFY_PORTAL_URL`, `VERIFY_SHARED_SECRET`: meaning, required, default (none that is somebody else's), what goes wrong. Invite URL and permission names live here next to the token, not in a new file. |
| `docs/VERIFICATION.md` | Already the contract. Implementation of the bot half does not rewrite it. If the bot's side learns a new status code, this file changes in that PR. `0001` stays proposed. |
| `docs/README.md` | A row for `specs/surface/` when it exists. README still does not own variables. |
| `README.md` | What exists (a Discord surface, four commands, no portal page) and what is missing (the rest of the commands, the sweep, `0001`). The test count remains whatever `swift test` prints. |
| `CHANGELOG.md` | Unreleased: Surface, executable, DiscordBM, four commands, the disclosure. |
| `INTENT.md` / `hi/` | No new criteria. This change implements existing wants. If a product decision appears (for example, renaming `/flex` to `/show`), that is a `hi/` edit in its own change, agreed first. |
| `Package.swift` / `Package.resolved` | The pin. Prose about the pin lives in WHAT-IT-TALKS-TO. |

## New, because a new module needs a contract

| Document | Owns |
|----------|------|
| `specs/surface/surface.spec.md` | Purpose, public API, invariants, behavioural examples, error cases, dependencies, change log. Same sections as every other module. |
| `specs/surface/requirements.md` | The `REQ-surface-*` ids, copied from this change's requirements as they land. |
| `specs/surface/context.md` | The decisions in this change's `design.md` that survive contact with code. |
| `specs/surface/testing.md` | The suite list from this change's `testing.md`. |
| `specs/surface/tasks.md` | Work remaining on the module after merge, if any. |

Do not add `docs/DISCORD.md`. Boot order, payload units and the
Snowflake boundary are invariants of the module spec, not a second
narrative.

## What README must say that it does not say today

Today it says there is no gateway, no command, no executable. After
this change that sentence is false. Replace it with:

- There is an executable.
- There are four slash commands: ping, help, verify, unlink.
- Verification still needs a portal that satisfies
  `docs/VERIFICATION.md`, and `0001` is not decided, so a stranger
  following the README cannot complete a real verify yet
  (`ADOPT-4`, `VERIFY-5.a`).
- The tests still run offline.

A short true paragraph beats a command reference for 26 commands
that do not exist here.

## WHAT-IT-TALKS-TO must gain

Outbound:

- `https://discord.com/api/` (command registration, interaction
  follow-up, role apply, guild fetch)
- Discord gateway (IDENTIFY, events)

Inbound:

- Health port
- Verification callback port

Secret:

- `DISCORD_BOT_TOKEN`
- `VERIFY_SHARED_SECRET` (already anticipated by VERIFICATION.md;
  listed here when the listener exists)

Not outbound from this package: Discord's CDN fetching
`TOKEN_LOGO_URL`. That URL is handed to Discord in an embed;
Discord fetches it. Same as today for `TOKEN_LOGO_URL` in Gating.

The pin table is rebuilt from `Package.resolved` after the first
`swift build` with DiscordBM, not from this definition's estimate
of "roughly 25".

## CONFIGURATION must gain

The variables in `design.md`. No default token, no default guild, no
default portal host. Placeholder values refuse. `HEALTH_PORT` and
`VERIFY_CALLBACK_PORT` have no inherited numbers from the private
bot's 3001/3004; if we pick defaults they are ours and documented as
such, and a clash still fails the bind before identify.

Permissions this process needs, in Discord's words, next to
`DISCORD_BOT_TOKEN`, plus the invite URL shape. That is `ADOPT-11`.

## What this definition does not write

- Member-facing help text. `/help` is generated from the catalog.
- A deploy guide. There is still no production host story (`HOST-1`
  is unbuilt).
- A rewrite of `docs/decisions/0001-verification-portal.md`.

## One fact, one owner, and the collisions to avoid

- A role is a string in `specs/gating/`. That Discord applies it is
  `specs/surface/`. Do not restate the ladder.
- A member key is minted in `specs/store/`. That a snowflake becomes
  `externalId` is `specs/surface/`.
- Payload clamp in Gating is graphemes and says so. UTF-16 clamp is
  Surface's. Do not "fix" Gating in this change to match.
- Verification endpoints live in `docs/VERIFICATION.md`. Surface
  specs say "speaks that contract", they do not copy the tables.
