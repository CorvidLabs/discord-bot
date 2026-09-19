---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: plan
---

# Plan

1. The values: `SweepRecord`, `SweepProblem`, `SweepTally`, `MemberSweepOutcome`.
2. The seams: `RoleGateway` over `String`, `SweepChainReader`, `SweepDirectory`.
3. The pass itself, with the batch read, the dedup and the per-member decision.
4. The orphan pass and its guard.
5. The schedule and the loop, including the restart behaviour.
6. The journal: the record written before and after, and the problems kept.
7. Separately, the `DiscordRoleApplier` fix, with tests written to fail first.

## Deliberately not in this change

Calling any of it. Boot gate eight, where the loops go, stays empty. Nothing
in the running program changes, which is what makes this reviewable as
arithmetic rather than as a behaviour change to a live bot.