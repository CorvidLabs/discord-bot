---
spec: surface.spec.md
---

## Automated Testing

`swift test` runs the whole package: 812 tests in 66 suites. This module's
own share is 177 tests in 19 suites, with no token, no network, no guild and
no key (`swift test --filter SurfaceTests` gives 150 in 16, and
`swift test --filter SurfaceDiscordTests` gives 27 in 3). Five of them open a
socket, on the loopback address and on port zero so the kernel picks a free
port; nothing else here touches the machine it runs on.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `CommandValidatorTests.swift` | Unit | Every rule Discord enforces at registration, including the illegal option order from the reference kept as a named fixture, a subcommand nested inside another beside the legal one inside a group, and a description whose character count and code-unit count disagree. |
| `CommandCatalogTests.swift` | Unit | Exactly four commands, what a roles-only community gets, what disappears when verification is off, and the acknowledge policy each command declares. |
| `ReplyBoundsTests.swift` | Unit | The UTF-16 boundary, clamping that never splits a character, lists that drop whole lines, a link list dropped rather than sliced, refuse against clamp for a string and for each counted bound, the custom id that is always a refusal, and the embed total every per-part check can pass. |
| `SurfaceCardTests.swift` | Unit | Cards as values, the thumbnail guard over four unusable shapes, an unset picture being no picture, and buttons carrying ids rather than closures. |
| `SurfaceRouterTests.swift` | Unit | The foreign server, the direct message, the unknown command, the unrouted button, the defer that comes first, the handler whose answer is corrected, autocomplete that never defers, operator authorisation three ways, the bounded answer, and the tracked job with its fifteen minutes. |
| `BootSequenceTests.swift` | Unit | The order, health still `starting` when the boot returns and `ok` only once the gateway says ready, a bind failure reaching zero identifies, a held store reaching zero binds, a secret mismatch, a portal that offers no probe, an unreachable portal, verification switched off, and an invalid catalogue never reaching the registration call. |
| `ConfigurationTests.swift` | Unit | Every required variable named in its refusal, four placeholder shapes, blank as unset, a server id that is not digits, two ports the same, a portal with no secret, the loopback default, and the boot report's permissions, invite, governed role set and roles above the bot. |
| `HealthTests.swift` | Unit | `503` while starting, each piece named at `200`, degraded that is still `200`, verification switched off, a store that is gone, and an answer built with no reader, no store handle and no portal client in the test. |
| `CommandHandlerTests.swift` | Unit | Ping reading nothing, help following the catalogue and wearing the operator's chrome, the disclosure card's four fields and when the link stops working, verify's ephemerality and its clean refusal, and unlink listing, removing, forgetting the last one, refusing an unknown account, holding roles it could not read, holding them when an account that is left was never read, and adding two enormous accounts without wrapping. |
| `VerificationCallbackTests.swift` | Unit | The refusals before anything is written, the whole path once, two accounts counted together, an unreadable balance holding roles, a role read failure stopping the apply, a Discord failure keeping the record, the chain beating the portal's figure, and proving twice being idempotent. |
| `CallbackRoutingTests.swift` | Unit | Parsing one read, health outside the rate limit and the key, a wrong path not counted, an unset secret refusing everybody, the limit asked once and only for the callback route, `429`, `401` with no detail, invalid JSON, the payload checked before `200`, the constant-time compare, and the limiter's window. |
| `RoleWriteCheckTests.swift` | Unit | The difference between a role list sent and the one that came back, and the sentence naming the ids the chat client accepted and ignored. |
| `CallbackResponderTests.swift` | Unit | A callback before the store is open refused rather than dropped, a scanner that cannot spend the portal's budget, the callback route itself counted, verification off closing the route to any key, and health answered on that port throughout. |
| `ListenerTests.swift` | Unit and socket | The accept failure policy's backoff, its forgiveness and its giving up; one request answered end to end on a real socket; and more silent peers than the machine has cores failing to stop anybody else being served. |
| `TargetShapeTests.swift` | Unit | The chat library confined to one directory, the manifest naming it once, no snowflake type below the adapter, no inherited name, no literal account or chat id, no inherited host, and a suite that cannot read the environment or open a session. |
| `AdapterTests.swift` | Unit | `attachments` present on every edit and every first reply, inert mentions, embeds, button rows of five, command payloads including a subcommand that is never required, and four interaction shapes decoded from the JSON Discord actually sends. |

## Manual Testing

None of this needs a live server, and none of it is a substitute for the
suite. What cannot be tested offline, and what somebody should therefore look
at once before trusting a deployment:

1. **The invite actually grants what the report says.** Open the printed URL,
   add the bot to a test server, and compare the permission list Discord
   shows against `DiscordPermission.requiredNames`.
2. **The four commands appear.** Guild registration is immediate, so they
   should be in the picker within a few seconds of the boot line that says
   they were registered.
3. **A second copy dies quietly.** Start a second process with the same
   ports. It should print a refusal naming the port, and the first bot should
   not disconnect.
4. **`/help` reads as this server's.** Every word on it should be one the
   operator set or a project-neutral one.
5. **A real portal callback.** The transport constraint is a single read of
   8,192 bytes with no chunked encoding and no `Expect: 100-continue`, and a
   portal that violates it fails in a way the `400` does not clearly explain.

## Coverage Gaps

- **The socket listener's death.** The accept loop's retries and its policy
  are tested, and so are one real exchange and a flood of silent peers, all
  on port zero so nothing collides with whatever else is running. What is
  not exercised is the fiftieth consecutive failure, because it calls
  `exit(1)` on purpose: the decision to give up is pinned by
  `AcceptFailurePolicy`, and the line that acts on it is not.
- **The gateway event loop.** `DiscordSurface.run` is wiring over tested
  parts, and driving it needs a gateway. Three pieces of it are therefore
  read rather than run: health raised on the ready event and lowered when
  the stream ends, the roles-above-the-bot read after ready, and the role
  write read back in `DiscordRoleApplier`. The decisions each of them makes
  are pure functions with tests of their own; the calls are not.
- **`HTTPVerificationClient`.** Its request shaping is injectable and its
  status handling is small, and it is not exercised: the test target cannot
  see the adapter, which is the guard that stops a test reaching a live host.
  Moving the status rules into `Surface` would fix this and is worth doing
  when a second caller needs them.
- **`JobMailbox` has no production caller**, so what is tested is the seam
  and not a real long-running job.
