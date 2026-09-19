---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: context
---

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
