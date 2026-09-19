---
spec: surface.spec.md
---

## Tasks

- [x] Add a `Surface` library target with no chat-library dependency, a
      `SurfaceDiscord` adapter target that has it, and a `discord-bot`
      executable, published as one library product plus one executable.
- [x] Pin the chat library up to the next minor and commit the resolved
      graph.
- [x] `DiscordUserId`, checked, and a plain `externalId` below it.
- [x] Command definitions as values, and a validator that refuses offline
      everything Discord refuses at registration.
- [x] The illegal option order from the reference as a named fixture.
- [x] A catalogue built from configuration, emitting exactly four commands.
- [x] `ReplyLimits` counting UTF-16, with the boundary pinned by a test that
      uses a character whose two counts differ.
- [x] `ReplyBounds`, refusing or clamping per policy, including the whole
      embed total that every per-part check can pass.
- [x] `SurfaceCard`, `SurfaceField` and `ButtonSpec` with no closures, and a
      thumbnail guard that costs the picture rather than the message.
- [x] `SurfaceRouter`: guild check, policy enforcement, unknown command,
      unrouted component, autocomplete that never defers.
- [x] `CommandAuth` as a pure function on bits and strings.
- [x] `BootSequence` over four protocols, with the order and its refusals.
- [x] `SurfaceHealth` and `HealthState`, `503` until ready.
- [x] `SurfaceConfiguration`, `SurfaceConfigurationError` and the placeholder
      check.
- [x] `BootReport`, including the invite URL and the managed roles above the
      bot.
- [x] `VerificationClient` as a seam, matching `docs/VERIFICATION.md`.
- [x] `CallbackRouting`, the rate limiter and the constant-time compare, all
      with no socket.
- [x] `VerificationCallbackHandler`: admit, prove, read, decide, apply.
- [x] `RoleApplier`, with a read failure that holds rather than strips.
- [x] `MemberDeparture`.
- [x] `JobMailbox` with an injected clock.
- [x] `/ping`, `/help`, `/verify`, `/unlink`.
- [x] The adapter: command payloads, interaction decoding, card rendering,
      reply sending, role application, registration, gateway identify.
- [x] The HTTP client for the other half, and the socket listener this
      process owns.
- [x] `Sources/Bot/main.swift`, wiring only.
- [x] `specs/surface/` and `.specsync/config.toml`.
- [x] `docs/WHAT-IT-TALKS-TO.md`, `docs/CONFIGURATION.md`, `README.md`,
      `CHANGELOG.md`.

## Still To Do

- [ ] The role sweep loop and `/resync`, so a role stays true when somebody
      sells.
- [ ] A presence, once there is something project-neutral to say.
- [ ] The first real user of `JobMailbox`, which will be a payout.
- [ ] `guildMemberUpdate`, so a role removed by hand is noticed before the
      next sweep.
- [ ] A component handler with real work behind it. The seam is here and
      nothing in these four commands needs one.
