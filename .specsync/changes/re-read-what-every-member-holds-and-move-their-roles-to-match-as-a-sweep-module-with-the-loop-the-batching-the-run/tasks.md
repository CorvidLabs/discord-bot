---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: tasks
---

# Tasks

- [x] The sweep values and the tallies an operator reads.
- [x] `RoleGateway`, the chat seam over `String`, so the module links no chat SDK.
- [x] The batch read, deduplicated, so one address listed twice is one balance.
- [x] The per-member decision, delegating to `Gating` and never comparing a
      balance to a threshold locally.
- [x] Unread rather than zero wherever a read failed, at every level.
- [x] The orphan pass and its guard, refusing on an empty or halved directory.
- [x] The re-reads: accounts before a write, records before the orphan verdict.
- [x] The schedule, the non-overlap rule and the restart behaviour.
- [x] The journal: record before and after, problems newest first and capped.
- [x] Sweep chain reads marked as the instance's own work, carrying no member share.
- [x] Fix `DiscordRoleApplier` to send the managed half of `target`, with tests
      written to fail against the old behaviour first.
- [x] The living contract in `specs/sweep/`, and the `specs/surface/` update
      for the applier.
- [x] `README.md` and `docs/WHAT-IT-TALKS-TO.md`.
- [x] `swift test`, `specsync check --strict`, `hi check`, verify lane.