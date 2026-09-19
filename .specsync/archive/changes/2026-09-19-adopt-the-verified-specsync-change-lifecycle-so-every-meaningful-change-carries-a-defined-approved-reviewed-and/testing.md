---
change: adopt-the-verified-specsync-change-lifecycle-so-every-meaningful-change-carries-a-defined-approved-reviewed-and
artifact: testing
---

# Testing

This change adds no code, so it has no unit tests. What has to be true is checkable by running the tools, and each line below was run rather than assumed.

| What must be true | How it was checked |
|---|---|
| The gate is on and refuses uncovered work | `specsync change audit` with the policy in place and no workspace open reported `.specsync/sdd.json` as an uncovered meaningful path and named the command to fix it. That refusal is the feature. |
| Opening a workspace clears it | `specsync change audit` after this workspace exists |
| The contract gate is unaffected | `specsync check --strict`: five specs, no warnings, full file and line coverage, the same as before |
| The lifecycle and CI are configured to agree on what passing means | `verification_commands` in `.specsync/sdd.json` names the same four tokens as the `[lifecycle] command` in `.trust.toml`, though not in the same form: this file holds one string and `.trust.toml` holds four. **Declared, not yet demonstrated here**: `specsync change check` on this change ran only `specsync check (no spec in scope)` and did not invoke the lane, which its own `verification.json` records. The lane does run for some changes: the reference project's adoption change has `fledge lanes run verify` with exit 0 in its archived evidence, so the single-string form is not the problem. What decides it is not established here, and the honest statement is that the declaration is correct and untested. The lane runs on every pull request through the Trust gate regardless, so nothing is unguarded; it is the lifecycle's own copy that is unproven. |
| The package is untouched | `swift build` and `swift test` report the same 635 tests in 47 suites as the base commit |

The one thing not proved here is that a future pull request touching `Sources/` without a workspace is actually refused in CI rather than only locally. That needs a pull request to exist, and the next one will demonstrate it.
