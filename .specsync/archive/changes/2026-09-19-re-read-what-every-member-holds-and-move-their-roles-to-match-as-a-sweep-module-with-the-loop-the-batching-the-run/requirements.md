---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: requirements
---

# Requirements

The living contract is `specs/sweep/`, added by this change: `REQ-sweep-001` through
`REQ-sweep-024`, each traced to a criterion in `hi/`.

They cluster into four promises, and it is the clusters rather than the
individual rows that a future change should be held to:

1. **An unread fact holds.** `REQ-sweep-002`, `REQ-sweep-003`, `REQ-sweep-004`, `REQ-sweep-005`, `REQ-sweep-020`,
   `REQ-sweep-021`. A failed read must never look like a member who sold.
2. **The orphan pass cannot empty a server.** `REQ-sweep-007`, `REQ-sweep-008`, `REQ-sweep-009`,
   `REQ-sweep-022`. It refuses on a doubtful reading rather than proceeding.
3. **A sweep is honest about itself.** `REQ-sweep-010` through `REQ-sweep-015`, `REQ-sweep-023`. A
   record written before and after the work, so an unfinished sweep never
   reads as a finished one, and every problem names something an operator
   could change.
4. **A sweep is bounded.** `REQ-sweep-016`, `REQ-sweep-017`, `REQ-sweep-018`, `REQ-sweep-019`, `REQ-sweep-024`.
   One batch, deduplicated, no member share, no overlap, and a restart inside
   the interval waits rather than re-reading every wallet.

`specs/surface/` is modified for the applier: the list sent is the managed
half of the target, never `held`.