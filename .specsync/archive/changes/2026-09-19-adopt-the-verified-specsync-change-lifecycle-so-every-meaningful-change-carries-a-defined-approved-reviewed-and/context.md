---
change: adopt-the-verified-specsync-change-lifecycle-so-every-meaningful-change-carries-a-defined-approved-reviewed-and
artifact: context
---

# Context

The repository had SpecSync's contract half and not its lifecycle half. `specsync check --strict` ran on every pull request through the Trust gate and held module contracts to full coverage, which is real and has already caught undocumented exports twice. But there was no `.specsync/sdd.json`, so no change ever had to be defined before it was built, approved before it was implemented, or reviewed against its own definition before it merged.

That was noticed and written down when the infrastructure landed, and then deferred: adopting the lifecycle would have demanded a workspace for the very commit that introduced it, and the person doing it judged that a decision rather than an assumption. It stayed deferred through eleven merged pull requests, which is exactly how a deferred decision becomes the way things are done.

The cost showed up in the shape of the work rather than in a defect. Several of those pull requests were built first and had their contracts written afterwards, in the same change, which satisfies the letter of "the contract ships with the code" and misses the point of it. One tranche had its scope discovered by an audit after the code was written, which is the lifecycle's job.

What a session picking this up needs to know:

The gate is enabled here with `require_change_for_meaningful_files` true. That is deliberate and it is the whole content of this change: adopting with it false, which is what `specsync change adopt` writes by default, records the intention without changing what anybody can merge.

`meaningful_paths` is trimmed to paths that exist in this repository. The default list carries entries for Cargo, npm, Go and Python projects, and a policy file that names things which cannot occur is a policy file nobody reads carefully.

`verification_commands` is `fledge lanes run verify`, which is the same command `.trust.toml` gives the Trust gate as its lifecycle step. They must not be two different definitions of passing, because the first time they disagree, whichever one is cheaper to satisfy becomes the real one.

`specs/` stays in `ignored_paths`. A contract is an output of a change rather than a change of its own, and requiring a workspace to edit one would make the cheapest good habit in the repository expensive.
