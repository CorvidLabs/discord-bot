---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: context
---

# Context

## What led here

The catalogue under `hi/` is 19 families and 331 criteria, and it is written as
promises to the person who will run this: sentences in their words, with ids
that never move. The tests cite those ids by name, so a failing test names the
promise it broke. That arrangement only works while every criterion either has
a test citing it or is visibly absent. A criterion that is stated, quietly
unimplemented, and cited by nothing is the worst shape the catalogue can be in,
because everything reads as fine. Nothing fails, no gate goes red, and the gap
surfaces the first time an operator relies on it, which is the one moment they
cannot afford to find out.

Four of those were found by reading the catalogue against the exported surface
rather than the other way round: taking each criterion in `hi/spend.md`,
`hi/run.md` and `hi/see.md` and asking which file keeps it. Four had no answer.
They are unrelated as features and identical as a defect, which is why they are
one change rather than four: each is a promise with nothing behind it, and the
work in each case is mostly deciding what the promise actually means before any
of it is built.

This is also the first tranche written under the SpecSync lifecycle with the
gate on. The previous several tranches wrote code first and brought the contract
up behind it. That order is what let a criterion go unbuilt without anybody
noticing, so this change is deliberately defined in full, and argued about,
before a line of Swift exists.

## The four, and the state each is really in

**SPEND-9.c, which period a boundary-crossing payout was counted against.** The
engine already keeps SPEND-9.a and SPEND-9.b: an epoch is measured against one
period's ceiling before the first payment, and a run that was allowed to start
runs to the end of its list even if the period rolls over underneath it. What is
missing is the third sentence, which is the operator's half. `ReserveEpochRecord`
carries when the epoch started and when it finished and nothing else, and
`ReserveSpendLimits.periodKey`, the only value in the process that names the
ceiling an epoch was measured against, is read into one refusal message and
otherwise dropped. So an operator looking at a payout that began on a Sunday
night and finished on a Monday morning has two timestamps and a guess, which is
exactly what the criterion says they should not have to do. The record is
persisted, so the ordered list of charges it grows moves through `Reserve`,
`Store`, `StoreSQLite` and both of their contracts, and it needs a migration
story for every epoch already written without it.

**RUN-10.a, unpausing that cannot hand out a second day of budget. This one
turned out to be largely satisfied, and the change shrinks accordingly.**
`RequestGovernor.unpause(now:)` clears the breaker and does not touch the
counter, and there is already a test asserting that a spent day still refuses
the next request after a pause is lifted by hand. What is missing is smaller
than the item was written as: the test does not cite the criterion id, so the
promise and its proof are not connected; and it exercises only the boundary
where the budget is exactly spent, asserting a consequence rather than the
counter itself. A future change that made unpausing more generous in a subtler
way would slip past it. The work is a sharper test, not a feature, and this
document says so rather than inventing work to match the original framing.

**RUN-11, a per-caller share of the day.** Nothing implements it. There is a
per-wallet cooldown in `WalletCheckCache` that stops the same address being
re-read too often, and it covers the commonest shape of the problem, a member
asking about their own wallet in a loop. It is keyed by address, not by caller,
so anyone who varies the address they ask about gets a fresh cooldown every
time and the day's budget is theirs to spend. This is the item with real design
in it: the unit is not obviously a member, the share is not obviously a number
an operator sets, and refusing against queueing is a decision with reasons on
both sides. It is the part of this change most likely to be wrong, so the
research document argues it rather than asserting it.

**SEE-1.b, a health answer that costs nothing.** The pieces exist and the
assembly does not. `ChainHealthReport` is a pure value, `RequestBudgetSnapshot`
is a pure read off the governor, and `ProviderProofProbe` is deliberately
outside the governor so a monitoring check cannot spend the budget it is
checking on. What is absent is anything that puts those together, a test that
proves the request count did not move while a health answer was built, and a
non-awaiting way to read the last proof so that assembling an answer cannot
block on a network call. The surface itself, the listener and the route, belongs
to the runtime, which is a separate change being defined at the same time. The
danger is the ordinary one when two changes are defined in parallel: each
assumes the other owns the middle, and nobody builds it.

## Constraints that bind all four

- **There is no executable.** Six library targets, 635 offline tests, no
  gateway, no slash command, no verification. Nothing here can be run, so every
  behaviour has to be provable by a test that takes its clock and its inputs as
  parameters. No part of this change may need a live node, a live chat client or
  a wall clock to be believed.
- **The catalogue is the authority and it is not being edited.** All four
  criteria already exist, worded as they are. This change satisfies them; it
  does not reword them. If a criterion turns out to be impossible as written,
  that is a finding to raise, not a silent edit.
- **Every test cites the criterion id it protects, in its name.** That is the
  convention the repository already follows and the acceptance criterion repeats
  it. Four ids, four citations, at minimum.
- **A spec moves in the same commit as the code it describes.** `specsync check
  --strict` reads every source directory listed in `.specsync/config.toml`, and
  all three affected modules are listed. A new public member without a spec row
  turns the gate red, which is the point of it.
- **Money is integer arithmetic in the asset's smallest unit, and nothing near
  an amount is a `Double` or locale sensitive.** The SPEND-9.c field is text and
  not an amount, so this bites less than usual, but the migration it needs runs
  over the same tables the ledger lives in.
- **A claim is written and persisted before a payment is attempted.** Anything
  added to the epoch record has to land in the same write that claims the first
  line, or a crash leaves a payment on the chain and no record of which ceiling
  it was charged to, which is the failure this whole area exists to prevent.
- **Nothing below the chat boundary holds an identifier that came from a
  person.** This is decisive for RUN-11: whatever names a caller inside `Chain`
  is a key the instance drew, never a chat account id, and `Chain` cannot reach
  the existing minted key type because that lives in `Store` and `Store` depends
  on `Chain`, not the other way round.
- **A fact nobody could read is unknown, not zero and not empty.** An epoch
  written before the period field existed has no answer, and it has to read as
  no answer rather than as a plausible one.
- **This repository is public.** No real address, asset id, chat snowflake,
  personal path or naming of the private project any of it was ported from, in
  code, tests, specs or commit messages.

## Already ruled out

- **Editing an existing migration to add a column.** `SchemaMigration` takes a
  fingerprint of its own text and the migrator refuses a file whose applied
  migration does not match the one this build ships. Editing migration two is a
  refusal to start, for everybody who already ran it. Whatever SPEND-9.c needs
  is a new migration.
- **Dropping a column in a migration's reverse.** The SQLite floor this code
  declares is older than the release that learned to drop a column, so a reverse
  written that way would fail on a machine the package says it supports. Either
  the storage is shaped so its reverse is a plain drop of something whole, or
  the floor moves, and moving the floor is a different decision.
- **Deriving the period from the two timestamps that are already there.**
  Working it out from timestamps is the thing SPEND-9.c exists to stop, and the
  derivation would be wrong anyway: the timestamps are the engine's, the period
  is the host's, and a host whose ceiling runs on a month while the schedule
  runs on a week cannot be reconstructed from either.
- **Recording only the cadence period an epoch claimed.** The runner already
  takes a period key naming the firing, and `ReserveState` keeps the latest one
  per stream. That is a different period from the one a payout is charged
  against, and SPEND-9.c asks about the ceiling. Recording the cadence key
  instead would look like an answer and be the wrong one.
- **Putting the health surface in `Chain`.** `Chain` has no listener, no route
  and no business acquiring one, and the runtime change owns the endpoint. What
  is in scope here is only what `Chain` must hand over so the runtime can
  assemble an answer without spending a request.
- **Making a per-caller share apply to background work.** A role sweep across a
  whole community legitimately costs one request per member. Giving it a
  member-sized share would break the sweep, which is the thing the budget was
  sized for in the first place.
- **Queueing a caller who has reached their share.** Both the governor and the
  payout gate already refuse rather than queue, for reasons written in their own
  doc comments, and a queue does not satisfy RUN-11 in any case: the requests
  still get made, just later.

## What a session picking this up mid-flight needs to know

Read `change.md` first, then the four criteria in `hi/spend.md`, `hi/run.md` and
`hi/see.md` in their own words, then `research.md` beside this file, which has
the state of the code with file and line and the decisions that are still open.

Three things are easy to get wrong and are worth holding in mind before
touching anything:

1. **There are two different periods in the payout engine** and they are not
   interchangeable. One identifies a firing, so the same epoch cannot be paid
   twice in a week. The other names the ceiling the paying account is measured
   against, which is the host's and may run on a different calendar. SPEND-9.c
   is about the second.
2. **An epoch that was resumed has more than one honest answer.** A run that
   dies half way and is finished the following week was measured twice, against
   two ceilings. A single-valued field forces a choice between two lies. The
   research document recommends a shape that can hold both and says why.
3. **RUN-10.a is not a feature.** Anyone who reads the item and starts changing
   `unpause` has misread it. The behaviour is correct today; the gap is the
   proof.

## Why this workspace was finalized weeks after its code merged

The work here merged as #21 and the workspace was never carried past
`approved`. #22 then partially reverted it, cutting 238 lines out of
`approvals.json` and most of `state.json`, which is what a rebase does to a
file two branches both rewrote. The result sat on `main` failing
`specsync change audit` while CI stayed green, because `audit` had been taken
out of the `verify` lane for an unrelated reason.

Three things had to be repaired, and each one names a rule worth keeping:

1. **The deltas said `## Added` for blocks already in the living tree.** They
   were added by #21 itself, so re-materializing them was a conflict. They are
   `## MODIFIED` now. The rule the tool is enforcing is that a delta describes
   a move *from the living tree*, not from the author's memory of it.
2. **`tasks.md` was entirely unticked** although every task was implemented and
   merged. Each was checked against the tree before ticking; the
   `Gaps and open questions` section was converted from checkboxes to plain
   bullets, because its own opening sentence says none of them blocks the work
   and a checkbox that is never meant to be ticked blocks `check` forever.
3. **There was no requirement evidence table**, so it is reconstructed from
   the living specs rather than from a run recorded at the time, and it says
   so in its own first paragraph.

The lesson is the one `finalize --help` states and this repository learned the
expensive way: **finalize before merging.** Merging first orphans the
verification evidence, and the workspace then decays every time another branch
touches it. One task in Stage 0 could not be completed even now — recording the
ordering with `specsync change depend` against the runtime change — because
that workspace never coexisted with this one in a single tree.
