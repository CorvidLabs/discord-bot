---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
module: reserve
---

# Semantic delta: reserve

## MODIFIED

### REQUIREMENT REQ-reserve-009

A run of an epoch that was measured against spending limits the host stated
SHALL append one charge to that epoch's durable record, naming the period key
of those limits and the whole-unit figure the run was checked for, and
SHALL write that charge before the first payment of the run is attempted. The
charges SHALL be an ordered list that only ever grows at the end, so that an
epoch cut short and resumed under a later ceiling names both periods in the
order they were charged, and an ordinary epoch names exactly one. The period
SHALL be taken from the stated limits, and SHALL NOT be derived from a clock
of the module's own, from either of the record's timestamps, or from the
cadence key that stops a schedule paying the same period twice. A run for a
host that states no limits SHALL record no charge, and no charge SHALL be
invented for it, so this requirement answers the criterion only for a host
that states a ceiling. The same ordered list SHALL be carried on the value a
finished run hands back, so a host can report which ceiling the run was
counted against without reading the store a second time.

Acceptance Criteria
- `ReserveRunnerTests` proves a clean run records exactly one charge, naming
  the period of the limits it was checked against and the whole-unit figure
  the planner computed (SPEND-9.c).
- `ReserveRunnerTests` proves an epoch whose payer fails part way, re-run
  under limits naming a later period, reads back two charges in the order they
  were charged (SPEND-9.c, SPEND-9.a).
- `ReserveRunnerTests` proves that limits keyed to a different calendar from
  the cadence are recorded as themselves, so an implementation reaching for
  the cadence parameter already in scope fails (SPEND-9.c).
- `ReserveRunnerTests` proves the charge reaches the store before the first
  payment is attempted, using the store double that records its save order
  (SPEND-9.c, RESERVE-6.a).
- `ReserveRunnerTests` proves a run for a host stating no limits records no
  charge, and that a rehearsal records none either (SPEND-9.c, RESERVE-7.a).
- `ReserveRunnerTests` proves the charge keeps the figure the run was measured
  for even when part of the epoch went unpaid, so the charge and the paid
  total are allowed to disagree and the record says which is which
  (SPEND-9.c).
- `ReserveStoreTests` proves a record encoded by a build from before this
  field existed loads as a record with no charges rather than throwing
  (ADOPT-5).
