---
id: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
state: verifying
type: feature
base_commit: b848c0ea12f88511c6da86562bf793b407526d35
---

# Satisfy four criteria the catalogue states and the code does not: which period a boundary-crossing payout was counted against, unpausing that cannot hand out a second day of budget, a per-caller share of the day, and a health answer that costs nothing

## Intent

Satisfy four criteria the catalogue states and the code does not: which period a boundary-crossing payout was counted against, unpausing that cannot hand out a second day of budget, a per-caller share of the day, and a health answer that costs nothing

## Affected Canonical Specs

- `reserve`
- `chain`
- `store`

## Acceptance Criteria

- SPEND-9.c: an epoch record names the period it was counted against, so an operator reads it rather than inferring it from two timestamps. RUN-10.a: a test fails if unpausing ever returns any of the day's spent budget. RUN-11: one caller cannot spend the whole day's requests, and what happens when they reach their share is decided and documented rather than emergent. SEE-1.b: a health answer can be assembled without spending a request, proved by a test asserting the request count did not move, and it still answers after the budget is gone. Each criterion is cited by id in the test that protects it.

## No-spec Rationale

Not applicable
