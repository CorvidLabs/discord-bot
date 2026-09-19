---
spec: sweep.spec.md
---

## Tasks

- [x] Read every member's accounts in one batched pass, as the instance's own
      work.
- [x] Apply `RoleRules.decide` per member through a chat seam this target
      declares.
- [x] Hold rather than demote on anything that did not read, including an
      account missing from the batch.
- [x] Write the run record before the work and again after it, with a run id
      on every line.
- [x] Split held on purpose from missed, with a named reason for each, and
      keep one journal entry per sweep rather than one per member.
- [x] Run the orphan pass behind `RoleRules.orphanSweep`, recording the
      baseline only when it passes.
- [x] Write back only complete readings.
- [x] Loop on an interval, with the first pass delayed by whatever is left of
      it since the last recorded sweep.
- [x] Read the records again at the last moment before each kind of write, so
      a member who unlinks or verifies while a pass is running is neither
      handed their roles back nor stripped as an orphan.
- [x] Leave a pass in flight to finish when the loop is stopped, so a
      redeploy does not write a chat-service outage that never happened.

## Gaps

- **Nothing in the package satisfies `SweepDirectory` yet.** No store protocol
  enumerates members: `Store.MemberDirectory` answers about one member and
  counts the rest. A host supplies the list today; the obvious fix is one
  method on `MemberDirectory` and one `SELECT` in each backend, which is a
  change to `Store` and is deliberately not made here.
- **Nothing satisfies `ServerRoster` yet.** `SurfaceDiscord` does not list
  guild members at this commit, so a host that wires the sweep gets the
  per-member pass and no orphan pass until it does.
- **Nothing in the package constructs a `RoleSweep`.** `Sweep` is a target
  and a product that only `SweepTests` depends on: `swift run bot` boots an
  instance in which no sweep exists and no role follows a holding. Wiring it
  needs the two seams above plus a `Sweep` edge and a `start(interval:)` in
  the composition root, and the first of those is a change to `Store`.
  `RoleGateway` does match `Surface.RoleApplier` method for method, so an
  empty extension would conform the Discord adapter, but only from a target
  that sees both and no such edge exists today. The manifest said the
  adapter "already satisfies" both protocols; it now says what this
  paragraph says, because a reader reaches for the manifest first.
- **`Sweep.RoleGateway` and `Surface.RoleApplier` are the same two methods
  declared twice**, with no compiler link between them. That is the price of
  a target that links no chat SDK, and it is only safe while the shapes stay
  identical: the day either grows a parameter, the other has to grow it in
  the same change or `DiscordRoleApplier` ends up conforming to two versions
  of one idea.
- There is no durable `SweepJournal`. `InMemorySweepJournal` loses everything
  on the restart that SEE-2 and SEE-5 exist to survive, and says so.
- A member handled in one batch and a member handled in the next are not
  ordered relative to each other, so a tally is deterministic but the log
  lines within a batch are not.

## Review Sign-offs

- **Product**: pending
- **QA**: pending
- **Design**: n/a
- **Dev**: pending
