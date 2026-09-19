---
spec: reserve.spec.md
---

## Tasks

- [x] Compute the split, the per-slot share and the per-epoch figure in smallest
      units, with the residue stated.
- [x] Refuse a configuration that does not add up, at construction.
- [x] Plan an epoch against the ledger, skipping slots already claimed.
- [x] Run an epoch behind the gate, the period key, the claim-before-pay
      ordering and the limit preflight.
- [x] Preview a whole schedule and rehearse the next epoch without writing or
      moving anything.
- [x] Ship an in-memory store that exercises the encode and decode path.
- [ ] Publish the module's documentation once the package is released.

## Gaps

- There is no test for a store whose save is slow enough to interleave with
  another run; the gate makes that unreachable through `ReserveRunner`, but a
  host that plans and pays by hand could still reach it.
- Periods are ISO week, month and day. A host wanting a fortnight or a quarter
  supplies its own key, and nothing here checks that the key it supplies matches
  the cadence its schedule claims.

## Review Sign-offs

- **Product**: pending
- **QA**: pending
- **Design**: n/a
- **Dev**: pending
