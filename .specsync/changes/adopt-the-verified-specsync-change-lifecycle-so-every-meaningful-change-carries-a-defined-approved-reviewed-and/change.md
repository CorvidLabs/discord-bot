---
id: adopt-the-verified-specsync-change-lifecycle-so-every-meaningful-change-carries-a-defined-approved-reviewed-and
state: implementing
type: operations
base_commit: c381eaed999fb232bafcc920f61dd82717309e18
---

# Adopt the verified SpecSync change lifecycle so every meaningful change carries a defined, approved, reviewed and archived workspace

## Intent

Adopt the verified SpecSync change lifecycle so every meaningful change carries a defined, approved, reviewed and archived workspace

## Affected Canonical Specs

- None

## Acceptance Criteria

- specsync change audit passes with the gate on. A change touching Sources, Tests, hi, Package.swift or the workflows without an active workspace is refused by name rather than merged. The verification command is the same fledge verify lane the Trust gate already runs, so the lifecycle and CI cannot disagree about what passing means. Adoption itself is covered by this workspace, which is the first proof the gate works.

## No-spec Rationale

This turns the lifecycle on. It changes no module behaviour and no canonical spec text; the contracts under specs/ are unchanged by it.
