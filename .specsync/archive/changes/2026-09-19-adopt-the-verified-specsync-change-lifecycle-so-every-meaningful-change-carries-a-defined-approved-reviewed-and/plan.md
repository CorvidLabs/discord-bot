---
change: adopt-the-verified-specsync-change-lifecycle-so-every-meaningful-change-carries-a-defined-approved-reviewed-and
artifact: plan
---

# Plan

1. Run `specsync change adopt`, which writes `.specsync/sdd.json`, the workflow-v2 baseline and an adoption report.
2. Rewrite `.specsync/sdd.json`: turn `require_change_for_meaningful_files` on, reduce `meaningful_paths` to paths this repository actually has, and point `verification_commands` at the verify lane the Trust gate already runs.
3. Open this workspace to cover the adoption, which is itself a meaningful change under the policy it installs. This is the first evidence the gate works, and it is cheaper to prove here than on somebody's feature.
4. Document the lifecycle where a contributor and an agent will each look: the order of work in `AGENTS.md`, and how to run it in `CONTRIBUTING.md`.
5. Verify: `specsync change audit` clean, `specsync check --strict` unchanged, `fledge lanes run verify` green.

Not in this change: retrofitting workspaces onto the eleven pull requests already merged. Their evidence is the pull requests themselves and the contracts they carry, and manufacturing approval records after the fact would be worse than having none, because a ledger that contains an invented approval cannot be trusted anywhere.
