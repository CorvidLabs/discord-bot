---
spec: gating.spec.md
---

## Tasks

- [x] Load a server's ladder, token, collections, pools, verified role and
      administrators from its own numbered variables, refusing rather than
      defaulting.
- [x] Make an unread fact its own case, with no accessor that hands back a
      default.
- [x] Decide a member's roles from configuration and holdings alone, holding
      every role an unread fact would have decided.
- [x] Count pooled holdings toward the ladder, across every pool and every
      account.
- [x] Sum a member's accounts without deciding on the one that just signed.
- [x] Guard the sweep that strips members with no verified account, and hand
      the baseline back only with a run.
- [x] Write amounts out at the operator's own precision with no digit lost,
      and keep a payload inside Discord's bounds.
- [x] Register `Sources/Gating` in `.specsync/config.toml`'s `source_dirs`, so
      the repository's coverage figures count this target.
- [ ] Surface `LoadedTiers.rungsWithoutRoles` at boot. Nothing reads it yet,
      so the mistyped role id it exists to catch is still invisible.
- [ ] Publish the module's documentation once the package is released.

## Gaps

- Nothing applies a `RoleDecision`. There is no Discord boundary in this
  repository yet, so the decision is produced and nothing consumes it.
- Nothing produces a `MemberHoldings` either: the chain reads, the store reads
  and the counting all belong to a caller that does not exist. The module's
  contract with that caller, that a partial list must arrive as `.unknown`
  rather than as a short list, is stated and cannot yet be enforced.
- `TierLadder` and `Tier` still have public initializers that check nothing.
  `storedRung` no longer depends on them being checked, but a hand-built ladder
  can still hold two rungs at one threshold, or a rung whose id is empty. Both
  are visible in the ladder the host built rather than deciding anybody's roles
  behind their back, which is why neither has turned the initializer into a
  throwing one.
- An entry written above a gap is dropped, at any number. That is the gap rule
  working as designed, and the overflow refusal is narrower on purpose: it
  covers the unbroken list that stopped at the scan limit, which is the one
  case with nothing in the operator's file to see. Nothing yet reads the
  loaded configuration back at boot, so a dropped entry is currently visible
  only in the server (ADOPT-9.a); the task above is what will name it.
- Nothing here takes every granted role back in one action when an operator
  retires the bot (ROLE-6, ROLE-6.a).

## Review Sign-offs

- **Product**: pending
- **QA**: pending
- **Design**: n/a
- **Dev**: pending
