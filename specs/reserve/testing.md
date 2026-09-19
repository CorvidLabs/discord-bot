---
spec: reserve.spec.md
---

## Automated Testing

`swift test --filter ReserveTests` runs this target's suite, all offline.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `ReserveArithmeticTests.swift` | Unit | The split, fixed denominators, the identical per-epoch figure, and paid plus residue reconciling to the share exactly. |
| `ReserveConfigurationTests.swift` | Unit | Every configuration refusal: shares that do not sum, indivisible splits, duplicate ids, zero denominators and zero-epoch schedules. |
| `ReservePeriodTests.swift` | Unit | ISO week, month and day keys, the Monday to Monday boundary, and independence from the host's timezone. |
| `ReservePlanningTests.swift` | Unit | Slot counting under both payout rules, skips, incomplete lists, and plans that stay inside the allocation. |
| `ReserveRunnerTests.swift` | Unit | The four guards end to end: the gate, the period key, claim before pay, and limits checked before the first payment, for being current as well as for being big enough. |
| `ReserveStateTests.swift` | Unit | Duration locking, epoch completion that cannot skip, spend recorded and released, and the three claim lists only ever growing at the end. |
| `ReserveStoreTests.swift` | Unit | Round-tripping state and epoch rows, and a row that will not decode throwing rather than reading as unpaid. |
| `ReserveFixtures.swift` | Fixture | The worked example reserve the other suites plan against. |

## Manual Testing

- [ ] Recompute the worked example in the README with a calculator and confirm
      paid plus residue equals the share exactly for both streams.
- [ ] Read `hi/reserve.md` and confirm each criterion is either cited by a test
      name or named in `requirements.md`.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| Two runs started at the same moment | The second throws `alreadyRunning`, writes nothing and pays nobody. |
| Two runs inside one period key | The second throws `periodAlreadyPaid`. |
| A crash between the claim and the payment | The slot stays claimed, the value stays in the reserve, and the next run skips that slot. |
| A payer that proves nothing moved | The claim is released and the slot can be paid later in the same epoch. |
| A payer that fails ambiguously | The claim is kept, because a payment that might have gone through must never be retried. |
| A held unit moved between two known accounts inside one epoch | Paid once: the claimed holding ids are checked, not just the account. |
| A person forgotten mid-epoch who returns under a freshly minted recipient id | Skipped on the holding, because the line that paid them claimed every wallet of theirs rather than only the one paid. |
| More eligible units than the denominator has slots | The run is refused rather than paying the first slots in sort order. |
| An epoch number of zero, or past the last epoch | Refused with `epochOutOfRange` or `scheduleComplete`, never wrapped. |
| An asset with 20 or more decimals | Refused at construction, because ten to the twentieth does not fit in 64 bits. |
| A stored row that will not decode | The store throws; it never reads as an unpaid epoch. |
| Limits from a period that ended before the run starts | Refused with `spendLimitsExpired` before anything is claimed, and the period is left unclaimed so the epoch is postponed rather than lost. |
| Limits with no stated `periodEnd` | Checked for size only; an undated boundary is not an expired one. |
