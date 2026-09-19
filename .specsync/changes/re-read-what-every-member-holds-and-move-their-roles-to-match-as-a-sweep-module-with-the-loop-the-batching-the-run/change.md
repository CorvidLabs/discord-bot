---
id: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
state: implementing
type: feature
base_commit: 3efbbf9e8ad527116e959424063fedfdb869a5a5
---

# Re-read what every member holds and move their roles to match, as a Sweep module with the loop, the batching, the run record and the per-member reasons, that nothing calls yet

## Intent

Re-read what every member holds and move their roles to match, as a Sweep module with the loop, the batching, the run record and the per-member reasons, that nothing calls yet

## Affected Canonical Specs

- `sweep`
- `surface`

## Acceptance Criteria

- A Sweep module exists that re-reads what every member holds and moves their roles to match, with the loop, the batching, the schedule, the run record, the per-member reasons and the operator tallies. It depends on Gating, Chain and Store, declares its own chat seam over String so it links no chat SDK, opens no socket and reads no environment variable, and reads the chain only through Chain so a sweep spends the same daily budget under the same three brakes as every other read. A balance nobody could read holds a member's rung rather than dropping it. Separately, DiscordRoleApplier stops unioning RoleDecision.held into the list it sends: held is every configured role the decision deliberately left alone for want of a read, so unioning it granted them, and in the verification callback, which builds holdings with no asset catalogue, that meant every collection badge on every /verify. The list is now the managed half of target plus every role the member holds that the decision does not manage, so a badge a moderator granted by hand survives and an unread rung is held rather than granted. Nothing calls the sweep: boot gate eight is empty, so no behaviour changes for anyone running the bot. 1269 tests in 106 suites pass and specsync check --strict reports 226/226 files.

## No-spec Rationale

Not applicable
