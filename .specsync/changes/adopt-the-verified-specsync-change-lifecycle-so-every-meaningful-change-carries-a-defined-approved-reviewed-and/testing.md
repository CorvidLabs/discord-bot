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
| The lifecycle and CI agree on what passing means | `verification_commands` in `.specsync/sdd.json` is byte-identical to the `[lifecycle] command` in `.trust.toml` |
| The package is untouched | `swift build` and `swift test` report the same 635 tests in 47 suites as the base commit |

The one thing not proved here is that a future pull request touching `Sources/` without a workspace is actually refused in CI rather than only locally. That needs a pull request to exist, and the next one will demonstrate it.
