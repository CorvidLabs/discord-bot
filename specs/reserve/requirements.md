---
spec: reserve.spec.md
---

## User Stories

- As somebody setting aside a finite pot, I want to promise it to a crowd over a
  long stretch and never be able to overspend it, so that the promise holds
  whoever arrives or leaves after it is made (RESERVE-1).
- As a recipient, I want what I am owed to be knowable on day one and to be the
  same number in the last epoch, so that nobody else's arrival changes my
  payment (RESERVE-3, RESERVE-5.b).
- As an operator, I want to see what an epoch will cost before anything moves,
  so that a limit or a short paying account is a warning rather than a
  half-finished payout (RESERVE-7).
- As a maintainer, I want the engine to know nothing about where records live or
  who does the paying, so that every failure path can be exercised by a test
  (RESERVE-8).

## Acceptance Criteria

### REQ-reserve-001

The reserve, its split into streams and the number of epochs it pays over SHALL
be configuration supplied by the host, and a configuration whose shares do not
sum to exactly the reserve, or whose share does not divide into whole smallest
units, SHALL be refused by the initializer.

- Covered by `ReserveConfigurationTests.swift` (RESERVE-1.a, RESERVE-1.b,
  RESERVE-1.c).

### REQ-reserve-002

A stream SHALL divide its allocation by a denominator fixed in advance, never by
the eligible count, and an unclaimed slot SHALL stay unclaimed rather than
enlarging another payment.

- Covered by `ReserveArithmeticTests.swift` (RESERVE-3.a, RESERVE-3.b,
  RESERVE-3.c).

### REQ-reserve-003

Every epoch of a schedule SHALL pay the identical per-slot figure, every figure
SHALL be a whole number of the asset's smallest unit, and the remainder that
will not divide SHALL be reported rather than paid, such that paid plus residue
equals the share exactly.

- Covered by `ReserveArithmeticTests.swift` (RESERVE-5.a to RESERVE-5.e,
  RESERVE-9.a, RESERVE-9.c).

### REQ-reserve-004

A slot SHALL be claimed and persisted before its payment is attempted, a claim
SHALL be released only when the payer proves nothing moved, and re-running a
half-finished epoch SHALL skip everyone it already paid.

- Covered by `ReserveRunnerTests.swift` (RESERVE-6.a, RESERVE-6.b, RESERVE-6.c,
  RESERVE-9.b).

### REQ-reserve-005

Only one epoch SHALL run at a time across every stream, a stream SHALL pay at
most one epoch per period key, and an epoch SHALL be finishable but never
skippable.

- Covered by `ReserveRunnerTests.swift`, `ReserveStateTests.swift` and
  `ReservePeriodTests.swift` (RESERVE-1.f, RESERVE-1.g, RESERVE-6.d,
  RESERVE-6.f).

### REQ-reserve-006

A stored row that will not decode SHALL throw rather than read as an epoch
nobody was paid for, and an eligibility list with holes in it SHALL pay nobody.

- Covered by `ReserveStoreTests.swift` and `ReservePlanningTests.swift`
  (RESERVE-6.e, RESERVE-7.e).

### REQ-reserve-007

An epoch that will not fit the payer's limits SHALL be refused before the first
payment, measured against what is left of the period rather than the whole
ceiling, and SHALL never be clamped to fit. Limits SHALL first be checked for
being current: a set whose `periodEnd` is at or before the instant the run
starts SHALL be refused with `ReserveError.spendLimitsExpired` before either
size check, because what they say is left of a period that has ended describes
nothing. Limits with no stated end SHALL be checked for size alone. Nothing
SHALL be refused on an estimate of how long a run will take, which is a fact
about the host's payer rather than about this module.

- Covered by `ReserveRunnerTests.swift` and `ReservePlanningTests.swift`
  (RESERVE-7.d).

### REQ-reserve-008

The module SHALL depend on Foundation alone, SHALL reach persistence and payment
only through `ReserveStore` and `ReservePayer`, and SHALL ship an in-memory
store so the rules can be exercised without anything durable.

- Covered by `Package.swift`, `ReserveStoreTests.swift` and source review
  (RESERVE-8.a, RESERVE-8.b, RESERVE-8.c).

## Constraints

- Swift 6 with strict concurrency enabled. Every type crossing a concurrency
  boundary is `Sendable`.
- Platforms: macOS 11, iOS 15, tvOS 15, watchOS 8, visionOS 1 and up.
- No floating point, no `NumberFormatter` and no locale-sensitive formatting
  anywhere near an amount.
- No force unwrap, no `try!`, no `as!`.
- No clock reads inside the module. `now` and the period key are parameters.

## Out of Scope

- Sending value. There is no network, no chain client and no key material here.
- Storing anything. There is no schema, no file format and no database.
- Deciding when an epoch is due. Cadence belongs to whatever schedules the host.
- Redistributing unclaimed slots, under any circumstances.
