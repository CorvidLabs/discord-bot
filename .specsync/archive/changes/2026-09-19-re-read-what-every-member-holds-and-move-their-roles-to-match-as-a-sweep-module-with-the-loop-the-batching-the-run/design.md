---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: design
---

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