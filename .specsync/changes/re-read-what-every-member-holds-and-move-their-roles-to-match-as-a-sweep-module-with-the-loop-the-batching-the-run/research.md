---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: research
---

# Research

## What exists before this change

Roles are written exactly once per member, in the verification callback. There
is no second pass, so the moment somebody sells, their rung is wrong and stays
wrong. `hi/` has asked for the sweep since the beginning (`ROLE-1`), and
`Gating` has had the decision half all along: `RoleRules` turns holdings into
a `RoleDecision`. What is missing is the loop that calls it repeatedly.

## The failure modes a sweep has, which are not the ones a first write has

A one-shot write is forgiving: if a read fails, nobody had the role yet. A
sweep is not, because the member already has the role and a failed read now
looks exactly like a member who sold.

- **An unread fact must hold, never demote.** `ROLE-1.a`. This is the single
  rule most of the requirements below exist to protect, and it has to survive
  a partial batch, a short liquidity reading and a collection catalogue that
  did not answer.
- **An orphan pass can empty a server.** If the member records fail to load,
  every member looks like an orphan. `ROLE-5.a` asks for a guard, and the
  guard has to refuse rather than proceed on a doubtful reading.
- **A restart loop can multiply the day's chain spend.** `SEE-9`. A sweep that
  starts from scratch on every boot, under a supervisor that restarts it, is
  a way to exhaust a provider quota in minutes.

## The bug found while reading the existing applier

`DiscordRoleApplier` built the list it sends by unioning
``Gating/RoleDecision/held``. `held` is every configured role the decision
deliberately left alone because the fact behind it was not read. Unioning it
**grants** them. The verification callback builds holdings with no asset
catalogue, so it holds every collection, which means every collection badge
would go out on every `/verify`. It is `ROLE-1.a` exactly backwards, and it is
already on `main`, so it is fixed here rather than after the sweep lands.