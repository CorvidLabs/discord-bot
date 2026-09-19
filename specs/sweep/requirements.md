---
spec: sweep.spec.md
---

## Requirements

Each is traceable to a criterion in `hi/`.

| Id | Requirement | Criterion |
|----|-------------|-----------|
| SW-001 | A sweep visits every member on record and applies the decision the rules return. | ROLE-1 |
| SW-002 | A fact that could not be read holds the roles it decides, and nothing is taken away. | ROLE-1.a |
| SW-003 | An account absent from the batch is read as unread, never dropped from the member's total. | ROLE-1.a |
| SW-004 | A liquidity reading that came back short holds the ladder rather than demoting the provider. | ROLE-1.a, ROLE-2 |
| SW-005 | A collection whose catalogue did not answer holds only that collection's roles; every other role is still decided. | ROLE-4.b |
| SW-006 | Only roles the operator configured are added or removed. Everything else survives, including through the orphan pass. | ROLE-5 |
| SW-007 | The orphan pass refuses when nobody is on record, and when more than half the members have gone since the last pass that ran. | ROLE-5.a |
| SW-008 | The orphan pass records a baseline only when its guard passes, and a refusal leaves the previous baseline in place. | ROLE-5.a |
| SW-009 | A baseline that cannot be read refuses the pass rather than reading as a first run. | ROLE-5.a |
| SW-010 | A run record is written before the work and again after it, so an unfinished sweep never reads as a finished one. | SEE-2 |
| SW-011 | A sweep that threw reads as finished with a reason, which is not the same as abandoned. | SEE-2 |
| SW-012 | Members whose roles did not change are split into held on purpose and missed, each with a named reason. | SEE-2.a |
| SW-013 | Every line one sweep writes carries that sweep's run id. | SEE-6 |
| SW-014 | Problems are kept where a restart cannot take them, newest first and capped by count rather than by age. | SEE-5 |
| SW-015 | Every problem names something an operator could change rather than the code that gave up. | SEE-11 |
| SW-016 | Chain reads made by a sweep are the instance's own work and carry no member share. The other side of RUN-11: a share exists to bound a person, and a sweep is not one. | RUN-11 |
| SW-017 | Every account is read in one batch, deduplicated, so a pool's reserves are read once per pass. Protects the budget SEE-9 asks an operator to watch. | SEE-9 |
| SW-018 | A restart inside the interval waits out the remainder rather than reading every wallet again, so a restart loop cannot multiply the day's spend. | SEE-9 |
| SW-019 | Two passes never overlap; the second does nothing and writes nothing. | SEE-2 |
| SW-020 | Only a complete reading is written back to the store. | ROLE-1.a |
| SW-021 | A member's accounts are read again immediately before their roles are written, and a list that has emptied since the batch read holds the write instead of applying it. | ROLE-1.a, ROLE-5 |
| SW-022 | The orphan pass reads the records again immediately before it decides who is an orphan, and treats as known anybody in either reading. | ROLE-1.a, ROLE-5.a |
| SW-023 | Stopping the loop leaves a pass in flight to finish, so no member is recorded as missed for a shutdown. | SEE-2, SEE-5 |
| SW-024 | The same address listed twice for one member is one balance, not two. | ROLE-1, SEE-9 |

## Out Of Scope

- Deciding which roles a member should hold. That is `Gating`.
- Anything that knows what a snowflake is. That is the adapter.
- Handing every granted role back when an operator switches the bot off
  (ROLE-6). The decision for it exists in `Gating`; the surface for ordering
  it does not exist yet, and this module does not invent one.
- Telling an operator about a problem where they are already sitting
  (SEE-13). Problems are kept; nothing here pushes them anywhere.
