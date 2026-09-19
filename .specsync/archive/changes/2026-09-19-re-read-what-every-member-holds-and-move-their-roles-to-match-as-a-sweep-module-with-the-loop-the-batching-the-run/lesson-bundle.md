# Lesson bundle — re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Re-read what every member holds and move their roles to match, as a Sweep module with the loop, the batching, the run record and the per-member reasons, that nothing calls yet
- **Kind**: Feature
- **Specs**: sweep, surface
- **Paths**: Sources/Sweep, Tests/SweepTests, Sources/SurfaceDiscord/DiscordRoleApplier.swift, Tests/SurfaceDiscordTests/RoleListTests.swift, Package.swift, Package.resolved, .specsync/config.toml, specs/sweep, specs/surface
- **Acceptance**: A Sweep module exists that re-reads what every member holds and moves their roles to match, with the loop, the batching, the schedule, the run record, the per-member reasons and the operator tallies. It depends on Gating, Chain and Store, declares its own chat seam over String so it links no chat SDK, opens no socket and reads no environment variable, and reads the chain only through Chain so a sweep spends the same daily budget under the same three brakes as every other read. A balance nobody could read holds a member's rung rather than dropping it. Separately, DiscordRoleApplier stops unioning RoleDecision.held into the list it sends: held is every configured role the decision deliberately left alone for want of a read, so unioning it granted them, and in the verification callback, which builds holdings with no asset catalogue, that meant every collection badge on every /verify. The list is now the managed half of target plus every role the member holds that the decision does not manage, so a badge a moderator granted by hand survives and an unread rung is held rather than granted. Nothing calls the sweep: boot gate eight is empty, so no behaviour changes for anyone running the bot. 1269 tests in 106 suites pass and specsync check --strict reports 226/226 files.

## Evidence

- Verification commit: `bb32957309fa39882371188f47bfd7c26c45cfaa`
- Base commit: `3efbbf9e8ad527116e959424063fedfdb869a5a5`
- Verified by: `specsync check --spec surface --spec sweep`

## From the change's context.md

# Context

**The decision stays in `Gating` and the sweep never compares a balance to a
threshold.** `CLAUDE.md` in the bot this was ported from records the same rule
the expensive way: four always-false `tier == .none` comparisons shipped
because the ladder was being re-derived at the call site. `Sweep` assembles
holdings and asks `RoleRules`; that is the whole of its role logic.

**Unread is not zero, and it has to survive three levels.** A partial batch, a
short liquidity reading and a collection catalogue that did not answer are
three different ways to get a number that looks like a balance and is not one.
Each is marked unread separately, because collapsing them into an optional is
how `?? 0` gets written later and how a sweep starts demoting people.

**A sweep's reads are the instance's own work.** They carry no member share
(`SW-016`). A share exists to bound one person typing in a channel; charging
the sweep to somebody would either throttle the sweep or exhaust a member's
allowance for work they did not ask for.

**The orphan guard refuses on doubt rather than proceeding.** If the records
fail to load, every member looks like an orphan, and an orphan pass that
proceeds on that reading empties a server's roles. It refuses when nobody is
on record and when more than half the members have gone since the last pass
that ran.

**The applier bug is the sharpest thing in this change.** Unioning
``Gating/RoleDecision/held`` into the list sent turns every unread fact into a
grant. `held` means "left alone", and leaving a role alone is neither granting
nor revoking it. In the verification callback, which builds holdings with no
asset catalogue and therefore holds every collection, it meant every
collection badge on every `/verify`. It was already on `main`. Five tests were
written that fail against the old behaviour before the fix was made, because a
test written to agree with today's behaviour would have passed on the day it
was written.

**Nothing calls any of this.** Boot gate eight is empty. That is deliberate:
the module is reviewable as arithmetic, and the change that starts the loop is
then about starting a loop.
## Two things the lifecycle caught in the contract itself

The module was written before this workspace, so the deltas describe a move
from a living tree that already held the target state and say `Modified`
rather than `Added`. That is the same ordering that stranded the workspace
#21 merged without, and the reason it cost nothing here is that it was caught
before merge rather than after.

It also caught two real defects in `specs/sweep/requirements.md` that no test
would have:

- **The ids were `SW-001`, not `REQ-sweep-001`.** Every other module in this
  repository uses `REQ-<module>-<number>`, and a private scheme in one module
  is a scheme somebody has to learn twice.
- **The requirements were not normative.** They were written as plain
  statements — "A sweep visits every member on record" — where every other
  module writes SHALL. A requirement that does not say SHALL is a description,
  and a description cannot be violated.

Both are fixed here. The rewrite changed no behaviour and no test: it changed
what the contract obliges, from something a reader infers to something a
reader can hold the code to.

## From the change's design.md

# Design

## A module, not a loop bolted to the boot

`Sweep` is its own target depending on `Gating`, `Chain` and `Store`. It
declares **its own chat seam over `String`** (`RoleGateway`), so it links no
chat SDK and a member is a plain identifier inside it. That is the same
boundary `Store` and `Surface` keep, and it is what lets the whole sweep be
tested with no token and no server.

Reading the chain goes **through** `Chain`, never around it, so a sweep spends
the same daily budget under the same three brakes as every other read. Sweep
reads are the instance's own work and carry no member share (`SW-016`): a
share exists to bound a person, and a sweep is not one.

## What protects the rule that an unread fact holds

The decision stays in `Gating`. `Sweep` never compares a balance to a
threshold; it assembles holdings, marks what it could not read as unread
rather than zero, and hands that to `RoleRules`. Every "hold rather than
demote" requirement then follows from one place instead of from care at each
call site.

## Two reads, not one

A member's accounts are read again immediately before their roles are written
(`SW-021`), and the orphan pass re-reads the records immediately before
deciding who is an orphan (`SW-022`), treating anybody in either reading as
known. Both exist because a batch read and a write are separated by time, and
in that gap a member can link or unlink.

## The applier fix

The list sent is the managed half of ``Gating/RoleDecision/target`` plus every
role the member currently holds that the decision does not manage. A badge a
moderator granted by hand survives (`ROLE-5`); a rung whose balance nobody
could read is held rather than granted (`ROLE-1.a`). The arithmetic is a
static function over a decision and a role set, so it needs no token and is
pinned by tests.

## From the change's testing.md

# Testing

Every test is offline. The chat gateway is a double over `String`, the chain
reader is a double, and the clock arrives as a parameter, so a sweep replays
exactly.

## Requirement evidence

| Requirement | Evidence | What it proves |
|-------------|----------|----------------|
| REQ-sweep-001, REQ-sweep-024 | `Tests/SweepTests/SweepLoopTests.swift` | Every member on record is visited and the decision applied; one address listed twice for a member is one balance. |
| REQ-sweep-002, REQ-sweep-003, REQ-sweep-004, REQ-sweep-005 | `Tests/SweepTests/NeverDemoteTests.swift` | An unread fact holds at every level: a partial batch, a short liquidity reading and a collection catalogue that did not answer each hold rather than demote. |
| REQ-sweep-006 | `Tests/SweepTests/OrphanSweepTests.swift` | Only configured roles are touched; everything else survives, including through the orphan pass. |
| REQ-sweep-007, REQ-sweep-008, REQ-sweep-009 | `Tests/SweepTests/OrphanSweepTests.swift` | The guard refuses on an empty directory and on a halved one; a refusal leaves the previous baseline; an unreadable baseline refuses rather than reading as a first run. |
| REQ-sweep-010, REQ-sweep-011, REQ-sweep-012 | `Tests/SweepTests/SweepRecordingTests.swift` | The record is written before and after, so an unfinished sweep never reads as finished; a sweep that threw reads as finished with a reason; unchanged members split into held and missed with named reasons. |
| REQ-sweep-013, REQ-sweep-014, REQ-sweep-015 | `Tests/SweepTests/SweepRecordingTests.swift` | Every line carries the run id; problems survive a restart, newest first and capped by count; each names something an operator could change. |
| REQ-sweep-016 | `Tests/SweepTests/CallerAndBalanceTests.swift` | Sweep reads are the instance's own work and carry no member share. |
| REQ-sweep-017, REQ-sweep-018, REQ-sweep-019, REQ-sweep-023 | `Tests/SweepTests/SweepScheduleTests.swift`, `Tests/SweepTests/SweepLoopTests.swift` | One deduplicated batch per pass; a restart inside the interval waits out the remainder; two passes never overlap; stopping leaves a pass in flight to finish. |
| REQ-sweep-020, REQ-sweep-021, REQ-sweep-022 | `Tests/SweepTests/MidSweepChangeTests.swift` | Only a complete reading is written back; accounts are re-read before the write and a list that emptied holds it; the orphan pass re-reads and treats anybody in either reading as known. |
| REQ-surface-019 | `Tests/SurfaceDiscordTests/RoleListTests.swift` | The list sent is the managed half of the target plus unmanaged roles the member holds; `held` is never granted; a hand-granted badge survives. Five assertions that fail against the previous behaviour. |

## The whole suite

1269 tests in 106 suites pass. `specsync check --strict` reports 8/8 specs and
226/226 files.

## Where these lessons go

- `specs/sweep/context.md`
- `specs/surface/context.md`
