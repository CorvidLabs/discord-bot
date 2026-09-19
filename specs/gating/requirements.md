---
spec: gating.spec.md
---

## User Stories

- As somebody running this for my own community, I want the rungs, the
  collections, the pools and the token to be mine, so that nobody in my server
  ever reads a name, a threshold or an address from the project this was built
  for (ADOPT-1.a, ADOPT-1.b, ADOPT-1.c, ADOPT-1.d, ADOPT-1.e).
- As a member, I want the role beside my name to follow what I actually hold,
  and to keep the role I had when nobody could see my balance, so that an
  outage that lasted a minute does not read as my having sold up (ROLE-1,
  ROLE-1.a).
- As a member who put tokens into a pool, I want them to count toward my rung
  the same as the ones in my wallet, so that providing is not a punishment
  (ROLE-2).
- As somebody setting this up for the first time, I want a mistake to be a
  refusal that names the variable I typed, before my members see it, rather
  than a default that quietly works for somebody else's project (ADOPT-2,
  ADOPT-6, SEE-11).
- As an operator, I want the bot to touch only the roles I told it about, and
  to refuse to strip the server when it suddenly sees almost nobody (ROLE-5,
  ROLE-5.a).
- As a maintainer, I want the whole rule set to be values in and values out, so
  that every branch can be exercised without a guild, a chain or a database
  (BUILD-2, BUILD-2.a).

## Acceptance Criteria

### REQ-gating-001

The ladder, the token, the collections, the pools, the verified role and the
administrators SHALL all be read from the operator's own numbered variables,
and the module SHALL contain no default ladder, default creator, default asset,
default threshold, default link or default administrator.

- Covered by `TierConfigurationTests.swift` (ADOPT-1.a), `TokenProfileTests.swift`
  (ADOPT-1.d), `CollectionConfigurationTests.swift` (ADOPT-1.b),
  `LiquidityConfigurationTests.swift` (ADOPT-1.e), `AdminAllowlistTests.swift`
  (HOST-3) and `GatingConfigurationTests.swift` (ADOPT-1.c, ADOPT-6.a).

### REQ-gating-002

A server SHALL be able to run with as many or as few rungs, collections and
pools as it has, including none of a kind, and a server that gates on a balance
alone SHALL be a whole configuration rather than a broken one.

- Covered by `TierConfigurationTests.swift`, `CollectionConfigurationTests.swift`,
  `LiquidityConfigurationTests.swift` and `GatingConfigurationTests.swift`
  (ADOPT-6.b, ADOPT-10, ADOPT-10.a, SHOW-4, SHOW-4.a).

### REQ-gating-003

A numbered list SHALL be read from 1 upward and SHALL end at the first gap, a
half-written entry SHALL be refused rather than completed from a default, and
an unbroken list that carries on past `NumberedEnvironment.maxEntries` SHALL be
refused rather than silently cut short. An entry written above a gap SHALL be
dropped by the gap rule at every number, the limit included, because a loader
is given a lookup and cannot ask what else was written. Every refusal SHALL
name the variable to fix.

- Covered by `TierConfigurationTests.swift` (ADOPT-2, ADOPT-9.a),
  `CollectionConfigurationTests.swift`, `LiquidityConfigurationTests.swift`,
  `TokenProfileTests.swift` and `AdminAllowlistTests.swift` (ADOPT-2, SEE-11).

### REQ-gating-004

A fact that could not be read SHALL be `Reading.unknown` and never a zero or an
empty list, the roles that fact decides SHALL be reported in
`RoleDecision.held` rather than revoked, and a role that a read fact and an
unread fact both decide SHALL be held as well. No field of `MemberHoldings`
SHALL default in the direction of granting: the readings default to unknown,
and `isVerified`, which is this bot's own record rather than a reading, SHALL
have no default at all.

- Covered by `ReadingTests.swift` and `RoleRulesTests.swift` (ROLE-1, ROLE-1.a,
  ROLE-4.b, SEE-2.a).

### REQ-gating-005

The gated token inside a member's liquidity positions SHALL count toward their
rung alongside what they hold directly, summed across every pool and every
account, and a server that counts no pools SHALL decide the ladder from the
direct balance alone rather than waiting for a half nobody will read.

- Covered by `RoleRulesTests.swift` and `ReadingTests.swift` (ROLE-2).

### REQ-gating-006

Holding a piece of a configured collection SHALL earn that collection's badge,
holding more SHALL reach its stacked count rungs while keeping the ones
underneath, and each collection SHALL decide only its own roles.

- Covered by `CollectionConfigurationTests.swift` and `RoleRulesTests.swift`
  (ROLE-4, ROLE-4.a, ROLE-4.b).

### REQ-gating-007

An asset SHALL belong to a collection only when it satisfies that collection's
own creator, name, unit name and supply rules, the supply ceiling SHALL be
configuration rather than a rule written into the module, and an asset matching
nothing configured SHALL belong to no collection.

- Covered by `CollectionConfigurationTests.swift` (PICTURE-6, PICTURE-6.a).

### REQ-gating-008

The module SHALL add or remove only roles in `GatingConfiguration.allRoleIds`,
`RoleDecision.revoked` SHALL always be a subset of `RoleDecision.managed`, and
every other role a member holds SHALL be carried through untouched.

- Covered by `RoleRulesTests.swift` (ROLE-5).

### REQ-gating-009

A sweep that would strip members with no verified account SHALL be refused when
no member is verified at all, and, where a baseline of at least
`RoleRules.orphanSweepBaselineMinimum` was recorded, when the count has fallen
below half of it. A refusal SHALL carry no baseline to record.

- Covered by `RoleRulesTests.swift` (ROLE-5.a).

### REQ-gating-010

A member's accounts SHALL be added up as one holding, verifying a further
account SHALL never decide roles from that account alone, and re-verifying an
account already on record SHALL use the figure just read rather than the one
stored beside it. Summing no accounts at all SHALL be unknown rather than zero.

- Covered by `ReadingTests.swift` (VERIFY-2.a, ROLE-1.a).

### REQ-gating-011

A rung SHALL keep a stable id apart from its display name, a row that recorded
a rung by display name SHALL still resolve to that rung, and a rung SHALL NOT
be allowed to share the no-rung label's name or id. Resolving a stored row
SHALL answer only when exactly one rung answers to it and SHALL never answer
with a rung for the no-rung label, on a ladder built in code as much as on one
the loader accepted.

- Covered by `TierLadderTests.swift` (ROLE-1.c), `TierConfigurationTests.swift`
  and `GatingConfigurationTests.swift` (ADOPT-5, ADOPT-5.a).

### REQ-gating-012

Every whole-token threshold SHALL be converted to base units through the
operator's own `TokenProfile.decimals`, an amount written out for a person
SHALL keep every digit at that precision and at every precision the type can
hold, and no figure anybody has to check SHALL pass through `Double`,
`NumberFormatter` or a locale. Two thresholds that collide only after
conversion SHALL be refused naming both numbers written and the amount they
collided at.

- Covered by `TokenProfileTests.swift` and `GatingFormattingTests.swift`
  (ADOPT-1.d, LEARN-7.b).

### REQ-gating-013

A card's thumbnail, colour and links SHALL be the operator's, an unusable URL
or colour SHALL be refused at load rather than rendered broken, and a server
that picked no links SHALL have none.

- Covered by `TokenProfileTests.swift` (ADOPT-1.f, LEARN-7.a, ADOPT-6.a).

### REQ-gating-014

Text bound for Discord SHALL be clamped to the named payload limits, a list too
long to fit SHALL lose whole lines and say how many, and a single line longer
than the whole limit SHALL be clamped rather than dropped.

- Covered by `GatingFormattingTests.swift` (RAIN-1.d).

### REQ-gating-015

The accounts allowed to administer SHALL start empty, SHALL contain nobody the
operator did not name, and SHALL allow any entry to be removed including the
last one.

- Covered by `AdminAllowlistTests.swift` (HOST-3, HOST-3.a, CATALOG-7,
  CATALOG-7.a, CATALOG-7.b).

### REQ-gating-016

The module SHALL depend on Foundation alone and SHALL reference no Discord
type, no chain client, no store and no clock. Configuration SHALL arrive
through a lookup, holdings SHALL arrive as values, and a `RoleDecision` SHALL
be applied by the caller.

- Covered by `Package.swift`, the whole suite running offline, and source
  review (BUILD-2, BUILD-2.a, BUILD-1.b).

## Constraints

- Swift 6 with strict concurrency enabled. Every exported type is `Sendable`.
- Platforms: macOS 11, iOS 15, tvOS 15, watchOS 8, visionOS 1 and up.
- No force unwrap, no `try!`, no `as!`. Explicit access control on every
  declaration, four-space indentation, opening brace on the same line.
- Amounts are `UInt64` base units. Sums saturate; they never wrap.
- A Discord role is a `String` here and becomes a snowflake at the boundary.
- No environment read, no clock read and no I/O of any kind inside the module.

## Out of Scope

- Applying a decision. Adding and removing roles is the caller's, at the
  Discord boundary.
- Reading a chain. Balances, positions and collection counts arrive already
  read, already summed and already counted.
- Persistence. Nothing here has a schema, a row or a file format.
- Pool arithmetic. `LiquidityPosition` carries a split somebody else computed.
- Handing every granted role back at once when an operator retires the bot
  (ROLE-6, ROLE-6.a). A decision can express it, but nothing here drives it.
- Editing the configuration at runtime (CATALOG-1, CATALOG-8). The
  configuration is a value loaded once.
