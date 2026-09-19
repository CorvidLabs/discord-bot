---
id: adopt-the-verified-specsync-change-lifecycle-so-every-meaningful-change-carries-a-defined-approved-reviewed-and
state: verifying
type: operations
base_commit: c381eaed999fb232bafcc920f61dd82717309e18
---

# Adopt the verified SpecSync change lifecycle so every meaningful change carries a defined, approved, reviewed and archived workspace

## Intent

Adopt the verified SpecSync change lifecycle so every meaningful change carries a defined, approved, reviewed and archived workspace

## Affected Canonical Specs

- None

## Acceptance Criteria

- The gate is on: a change touching a gated path with no active workspace is refused by name. Proved twice, once locally and once in CI, because a rule that refuses on a contributor machine and passes on GitHub is the worst shape a rule can have.
- CI runs the refusal. `specsync change audit` is a step in the `verify` lane, which is the command `.trust.toml` already gives the Trust gate, so the local answer and the CI answer are the same answer rather than two that can drift.
- The gated paths are the `meaningful_paths` list in `.specsync/sdd.json` and nowhere else; no prose restates a shorter version of it.
- Adoption is covered by this workspace, which the gate refused before the workspace existed, and the lane refused again when `fledge.toml` was outside the scope. Both refusals are the feature.
- No claim is made that SpecSync runs `verification_commands` on `change check`. It does not for this change, whose own verification.json records `specsync check (no spec in scope)`.

## No-spec Rationale

This turns the lifecycle on. It changes no module behaviour and no canonical spec text; the contracts under specs/ are unchanged by it.
