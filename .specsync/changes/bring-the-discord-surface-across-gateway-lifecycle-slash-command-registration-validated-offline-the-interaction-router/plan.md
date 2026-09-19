---
change: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
artifact: plan
---

# Plan

Implementation, after this definition is approved by somebody else.
No Swift in this change. No slice is "and also the other 22
commands".

## Order

The expensive failures are boot and registration. They go first, so
a later slice cannot ship a command Discord would 400.

```
1. Target skeleton, DiscordBM pin, identity, target-shape test
2. Catalog values + validator (required-before-optional fixture)
3. Reply limits (UTF-16) + SurfaceCard + attachments-on-edit
4. Router + acknowledge policy + CommandAuth
5. Boot sequence (lease, bind, identify) + health
6. Verification client protocol + callback listener
7. Four commands: ping, help, verify, unlink
8. Role application on the callback
9. Executable wiring
10. Documents (WHAT-IT-TALKS-TO, CONFIGURATION, README, CHANGELOG)
11. Canonical spec specs/surface/ in the same PR
12. fledge lanes run verify, specsync check --strict,
    specsync change check, fledge trust verify
```

Slices 1–5 are the surface. Slices 6–9 are the smallest product.
Slice 10 is `TRUST-1` and is not optional. Slice 11 is the contract
gate: adding `Sources/Surface` to `.specsync/config.toml`
`source_dirs` without a spec turns the gate red, which is the
point.

## Slice notes

### 1. Skeleton

Add `Surface` and `Bot` to `Package.swift`. Pin DiscordBM with
`.upToNextMinor` and commit `Package.resolved`. Record the actual
pin count. Target-shape test: no `import DiscordBM` outside
`Sources/Surface`; Store/Gating/Games/Chain/Reserve/StoreSQLite do
not list the product.

Do not take Fluent, Vapor, Fork, or Cache.

### 2. Catalog

Our types only. Validator table tests include the reference
`/raffle draw` illegal order as a fixture named for that incident.
No Discord HTTP.

### 3. Cards and limits

`ReplyLimits` with the thumbs-up test copied in spirit from
`SayCommandTests.lengthIsUTF16`. `SurfaceCard` / `ButtonSpec` with
no function types. Adapter encoding test that an update payload
always has `attachments`.

### 4. Router

`InteractionRequest` as a value. Guild check. Policy. Unknown
command and unknown component. Autocomplete never defers.
`CommandAuth` as a pure function on strings.

### 5. Boot

`BootSequence` with fake binder and fake gateway. Bind failure
skips identify. Health `503` until ready. Store lease is the
existing `InstanceLease`; Surface does not reimplement it, it
calls `BotStore` open and treats `alreadyHeldByAnotherProcess` as
a boot refusal **before** bind? Open already takes the lease.
Order in `REQ-surface-003`: lease (open store), bind, identify.
If open fails, do not bind and do not identify.

### 6. Verification

Protocol plus fake. Callback listener binds on the configured
port. Foreign guild ignored. Malformed id ignored. Secret probe
at boot (`REQ-surface-025`).

### 7. Commands

`/ping` immediate, no chain. `/help` from the catalog.
`/verify` defer, fake portal, disclosure card. `/unlink` list or
remove. Catalog-contents test asserts exactly these four.

### 8. Roles

Callback → admit → prove → chain read (injected data source) →
`RoleRules.decide` → `RoleApplier`. Unknown balance holds roles.
One apply call.

### 9. Executable

`main` loads env, wires fakes-or-reals, `await surface.start()`.
No logic.

### 10–12. Disclosure and gate

`WHAT-IT-TALKS-TO.md` lists discord.com, the gateway, the new
secret, the new pins, and the greps that check them.
`CONFIGURATION.md` owns the new variables.
`README.md` still says what exists; it now says a Discord surface
exists and that verification still needs a portal (`0001`).
`CHANGELOG.md` under Unreleased.
`.specsync/config.toml` `source_dirs` gains `Sources/Surface`.
`specs/surface/` companions in the same PR.

## What waits for a later change

- Role-sweep loop and `/resync`
- `/status`, `/leaderboard`, `/show`, holdings browser
- `/time` (parser can move almost as-is)
- `/game` and `SurfaceCard.init(game:)`
- Money commands and the first real user of `JobMailbox`
- `/ops`, `/say`, `/settings`, `/schedule`
- `0001` (in-process page or shipped portal)
- `CATALOG` HTTP
- `guildMessages` intent

## Risks

- **Pin count and CI time.** swift-syntax will show up in compile
  time. If Linux CI becomes unusable, that is a TRUST-4 problem to
  surface, not to silence with a cache nobody documented.
- **0001.** Smallest surface lets a contributor fake a portal. A
  stranger following the README still cannot verify a real wallet.
  README must say so (`VERIFY-5.a`, `ADOPT-4`).
- **Bind-vs-lease.** Two machines, one token: we cannot see it.
  Documents say so.
- **UTF-16 in Swift.** Easy to call `.count` by habit.
  `ReplyLimits` is the only allowed counter at the boundary; a
  target-shape grep for `.count` in `Adapter/` is allowed to be
  noisy and still worth having as a review aid, not as a gate.

## Verification of the implementation, when it exists

```
fledge lanes run verify
specsync check --strict
specsync change check bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
fledge trust verify
```

No live Discord. No token in CI.
