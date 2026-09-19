---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
module: surface
---

# Semantic delta: surface

## Modified

### REQUIREMENT REQ-surface-019

The verification callback SHALL, in order: refuse a foreign server and a
malformed id, admit the member, prove the account, read the chain, build
holdings with unknown rather than zero where a read failed, decide, and apply
only the managed set in one call. An unread fact SHALL NOT revoke the roles it
decides, and SHALL NOT grant them either. The list sent SHALL be the managed
half of the decision's target plus every role the member currently holds that
the decision does not manage, and SHALL NOT be built by unioning the
decision's held set: held names the roles the decision deliberately left
alone because the fact behind them was not read, so sending it turns every
unread fact into a grant. The arithmetic SHALL be a function over a decision
and a role set, needing no token and no server, so the list that goes out is
pinned by a test. (ROLE-1, ROLE-1.a, ROLE-5, VERIFY-2, VERIFY-2.a)

Acceptance Criteria
- `Tests/SurfaceDiscordTests/RoleListTests.swift` proves the list sent is the
  managed half of the target plus unmanaged roles the member already holds.
- The same suite proves a role in the decision's held set is neither granted
  nor revoked, which is the defect this modification exists to close: the
  verification callback builds holdings with no asset catalogue and therefore
  holds every collection, so the previous behaviour granted every collection
  badge on every verification.
- The same suite proves a badge granted by hand outside the managed set
  survives the write (ROLE-5).
- Five of its assertions fail against the previous implementation.
