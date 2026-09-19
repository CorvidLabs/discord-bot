# Lesson bundle — adopt-the-verified-specsync-change-lifecycle-so-every-meaningful-change-carries-a-defined-approved-reviewed-and

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Adopt the verified SpecSync change lifecycle so every meaningful change carries a defined, approved, reviewed and archived workspace
- **Kind**: Operations
- **Paths**: .specsync/config.toml, .specsync/sdd.json, fledge.toml
- **Acceptance**: The gate is on: a change touching a gated path with no active workspace is refused by name. Proved twice, once locally and once in CI, because a rule that refuses on a contributor machine and passes on GitHub is the worst shape a rule can have.
- **Acceptance**: CI runs the refusal. `specsync change audit` is a step in the `verify` lane, which is the command `.trust.toml` already gives the Trust gate, so the local answer and the CI answer are the same answer rather than two that can drift.
- **Acceptance**: The gated paths are the `meaningful_paths` list in `.specsync/sdd.json` and nowhere else; no prose restates a shorter version of it.
- **Acceptance**: Adoption is covered by this workspace, which the gate refused before the workspace existed, and the lane refused again when `fledge.toml` was outside the scope. Both refusals are the feature.
- **Acceptance**: No claim is made that SpecSync runs `verification_commands` on `change check`. It does not for this change, whose own verification.json records `specsync check (no spec in scope)`.

## Evidence

- Verification commit: `3a8d46214e3517f61d7b729c27de51161684df62`
- Base commit: `c381eaed999fb232bafcc920f61dd82717309e18`
- Verified by: `specsync check (no spec in scope)`

## From the change's context.md

# Context

The repository had SpecSync's contract half and not its lifecycle half. `specsync check --strict` ran on every pull request through the Trust gate and held module contracts to full coverage, which is real and has already caught undocumented exports twice. But there was no `.specsync/sdd.json`, so no change ever had to be defined before it was built, approved before it was implemented, or reviewed against its own definition before it merged.

That was noticed and written down when the infrastructure landed, and then deferred: adopting the lifecycle would have demanded a workspace for the very commit that introduced it, and the person doing it judged that a decision rather than an assumption. It stayed deferred through eleven merged pull requests, which is exactly how a deferred decision becomes the way things are done.

The cost showed up in the shape of the work rather than in a defect. Several of those pull requests were built first and had their contracts written afterwards, in the same change, which satisfies the letter of "the contract ships with the code" and misses the point of it. One tranche had its scope discovered by an audit after the code was written, which is the lifecycle's job.

What a session picking this up needs to know:

The gate is enabled here with `require_change_for_meaningful_files` true. That is deliberate and it is the whole content of this change: adopting with it false, which is what `specsync change adopt` writes by default, records the intention without changing what anybody can merge.

`meaningful_paths` is trimmed to paths that exist in this repository. The default list carries entries for Cargo, npm, Go and Python projects, and a policy file that names things which cannot occur is a policy file nobody reads carefully.

`verification_commands` is `fledge lanes run verify`, which is the same command `.trust.toml` gives the Trust gate as its lifecycle step. They must not be two different definitions of passing, because the first time they disagree, whichever one is cheaper to satisfy becomes the real one.

`specs/` stays in `ignored_paths`. A contract is an output of a change rather than a change of its own, and requiring a workspace to edit one would make the cheapest good habit in the repository expensive.

## From the change's testing.md

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

## Where these lessons go

This change declared no affected specs, so there is no module context to fold into.
