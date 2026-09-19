---
spec: gating.spec.md
---

## Key Decisions

Almost every rule below is here because the private bot this was ported from
got it wrong once in front of real members. The incident is written beside the
decision so the next person can tell a rule from a habit.

- An unread fact is its own case, not an optional. The original had it as a
  bare `Bool?` in one place, a cached balance standing in silently in another,
  and nothing at all in a third. The third cost the most: a transient provider
  error read a liquidity position as zero, the zero read as a member who had
  sold up, and roles came off somebody who had done nothing. They came back on
  the next sweep, which is not the same as never having lost them. `Reading`
  has no accessor that hands back a value with a default, because an optional
  here gets `?? 0` written against it by the first caller in a hurry.
- A role an unread fact decides is taken out of the managed set at the very
  end, from a separate `blocked` set. Accumulating the managed set per fact is
  not enough: when two facts decide one role id, the fact that was read puts
  the role in and the fact that was not read cannot take it out again. An
  operator may point two collections at one badge, or the liquidity provider
  badge at a rung's role, and no loader forbids either.
- The no-rung case is not a `Tier`. The original modelled "holds too little" as
  a tier value with the id `none`, which meant `tier == .none` compiled: Swift
  resolved it to `Optional.none`, the comparison was always false, and four of
  them shipped. The compiler warned about every one and nobody was reading
  warnings. `TierStanding` has no `none` to compare against, and separates
  `unranked` from `unread` because those two lead to opposite decisions.
- The token's decimal count is required configuration. The original assumed six
  as a named constant in one file and as a bare literal in eight others, which
  is correct for exactly one asset. A zero-decimal asset read through that
  assumption is a millionth of itself, so every rung becomes unreachable and
  every member is demoted at once. `TokenProfile.baseUnits(whole:)` is the only
  conversion in the module, and `GatingConfiguration.load` reads the token
  before anything else because the ladder cannot be converted and the pools
  cannot be given an asset id without it.
- Each pool carries the gated asset id rather than reaching for a shared one.
  The original kept a global token id and, for a while, a second literal inside
  the pool table. When the two disagreed the pooled side of every balance read
  as zero and every liquidity provider in the server was quietly demoted. One
  answer, written once by the operator, copied into each pool at load.
- There is no default ladder. The original shipped six rungs at one project's
  thresholds and fell back to them whenever the first rung was unset, which was
  right for that project and a trap for anybody else: a stranger's server would
  grant roles at numbers nobody there had chosen. Set nothing and the load
  refuses, naming `TIER_1_NAME`.
- There is no default collection creator. The original filled a missing one in
  from a literal mint account written into the source, so a server that never
  set it granted roles for holding another project's art.
- Collections are a configured list, not two cases. The original had exactly
  two welded in, and fifty-seven places asked "is this that one specific
  collection?" to work out what somebody had earned. It also carried a policy
  flag separating a pass collection, which drove one globally named role, from
  a collectible one, which was forbidden from granting it. That distinction
  survives without the flag, because every collection now carries its own role
  and its own count rungs and there is no shared role to grant by accident.
- A collection's supply ceiling is configuration. A collection minted as
  editions of twenty-five is an ordinary collection; a rule saying "a piece has
  a supply of one" written into the source would match none of it and take
  every one of those holders' roles away with nothing said. The ceiling is
  still a real rule, and it is what stops a creator's fungible token being
  counted as one of their pieces by whoever happens to hold a million of it.
- Pools are numbered like everything else. The original shipped four written
  into the source with their asset ids and read each pool's roles from a
  variable whose name was built out of the pool's id, so a fifth pool meant
  editing Swift. Both sides of a pool are required, because the original let
  either be absent and then skipped any pool missing one: a half-written pool
  counted for nothing and said nothing about it.
- The first gap ends every numbered list, and reaching the scan limit with no
  gap is a refusal. Skipping a missing number and carrying on would renumber
  every entry above a typo without saying so, and an operator who mistyped
  `TIER_4_NAME` would get a five-rung ladder whose rungs four and five are
  their five and six. Dropping entries is visible in the server within a
  minute; renumbering them is not. The refusal at the limit is for the one
  case the gap rule cannot cover: that list stopped for a reason that is
  nowhere in the operator's file, and an administrator they wrote down and
  this module discarded is somebody locked out of their own deployment with
  nothing said.
- The overflow refusal probes one number, and covers an unbroken list only.
  A loader is handed a lookup rather than an environment it can list, so it
  cannot ask what else was written: it can only name a variable and ask about
  that one, and the number it names is the one the list would have carried on
  with. Any wider sweep needs a second arbitrary ceiling, and the entry above
  that one is dropped in the same silence, one number further along. So
  `ADMIN_WALLET_1` to `ADMIN_WALLET_32` followed by `ADMIN_WALLET_34` leaves a
  gap at 33 and drops the 34th, exactly as a gap at 4 drops a 5th. That is the
  gap rule doing what it does at every size rather than a hole in the refusal,
  and ADOPT-9.a, not a refusal, is what is supposed to make a dropped entry
  visible: reading back what the bot made of the settings names the entries it
  loaded, and an operator who wrote 33 sees 32.
- Rung thresholds are compared after conversion, not as typed. Two different
  whole numbers that both exceed what the token's precision can express land on
  the same ceiling, and comparing what was typed would let that ladder load:
  two rungs at one threshold, one of them unreachable, nothing said.
- `TierLadder.storedRung` matches the id, then the id ignoring case, then the
  display name ignoring case. Rows written by an earlier version stored the
  name rather than the id, and matching on the id alone would read every one of
  them as no rung at once and demote the whole server on the first sweep after
  an upgrade. The leniency has a price: renaming a rung orphans every row that
  named it until the next sweep rewrites them, and a rung may not be named
  after the no-rung label, because a stored row naming the label would resolve
  to the rung and grant its role to somebody on no rung at all.
- The leniency carries its own guards rather than borrowing the loader's. Each
  pass answers only when exactly one rung matches, and the no-rung label always
  answers with no rung. `TierConfiguration.load` refuses the ladders that would
  make any of that ambiguous, so this changes nothing for a loaded ladder, but
  `TierLadder` and `Tier` are public values with initializers that check
  nothing, and a host building a ladder in code used to get the leniency with
  none of the refusals behind it: two rungs of one name resolved to whichever
  sorted lowest, and a rung named after the label answered to the label. Under-
  granting for one sweep is recoverable; granting a rung to somebody who
  reached none is the thing the loader's rule exists to stop.
- The orphan sweep is a decision, not a `Bool`. With zero verified members
  every member holding a managed role looks like an orphan and the whole server
  is stripped in one pass, which is what a wrong database path produces, and a
  wrong database path is a typo. A zero floor alone is not enough, because a
  wrong path with one leftover row passes it, so a count that has fallen under
  half of a recorded baseline of ten or more is refused too. The baseline
  travels only with a `run`: a caller that recorded the count it just observed
  would lower the bar to the wrong database's own tiny count, and the next
  sweep would pass the halving check against itself and strip the server
  anyway, buying one interval and nothing more. With a refusal there is no
  count to record, so the mistake cannot be written.
- Verification decides roles on every account the member has, not on the one
  that just signed. Deciding on the new account alone demoted a member on the
  top rung for linking an empty second wallet, which happened on a real morning
  to a real person, and it is why `CombinedBalance.afterLinking` exists instead
  of a one-line sum at the call site.
- Summing no accounts is unknown. A caller reaches an empty array two ways and
  they want opposite decisions: the member really has no account, or the
  accounts could not be listed because the store was locked, a migration was
  halfway through, or the member unlinked between one query and the next. A
  member who provably has no account is `MemberHoldings.unlinked`, which says
  so and reads as read.
- Every sum saturates. A wrapped sum puts the largest holder in the server on
  no rung at all, which is the one failure nobody would think to look for. A
  threshold with too many zeros saturates for the same reason: a rung nobody
  reaches is visible and fixable in a minute, a rung everybody reaches is not.
- A server that counts no pools decides the ladder from the direct balance
  alone. Insisting on both halves there freezes every ladder in the server for
  ever, because there is no pool to read, so the natural caller leaves the
  positions unread and the ladder waits on a fact that does not exist.
- `MemberHoldings.collectionCounts` is private. A subscript returning `Int?`
  would be read as `?? 0` by the first caller in a hurry, and a collection that
  was never looked up would strip the role of everybody who holds one.
- `LoadedTiers.rungsWithoutRoles` exists because a mistyped `TIER_n_ROLE_ID`
  is otherwise invisible: the rung grants nothing, so it is in no decision's
  managed set and in no decision's held set, and nothing an operator could look
  at would ever mention it. A boundary reads it at boot and says it once.
- Number formatting is hand-rolled. `NumberFormatter` is locale-sensitive and
  is not identical between Darwin and Linux, and a grouping separator that
  moves between machines turns a reconciliation into an argument.
- `GatingFormatting.amount` moves the point through the digits rather than
  dividing. Dividing needed ten to the power of the precision to fit in a
  `UInt64`, which trapped at twenty places, so the guard against the trap
  answered a precision above nineteen with the smallest units themselves: one
  base unit of a twenty-decimal asset printed as "1", a whole one, with
  nothing said. Shifting a string
  of digits has no divisor to overflow, so the answer is exact at every
  precision, and `decimals` is a `UInt8` so a precision below zero, which has
  no honest answer at all, cannot be asked for. `TokenProfile` still refuses
  more than nineteen decimals, for its own reason: `baseUnitsPerWholeUnit` has
  to fit in a `UInt64` for a threshold to be converted.
- `MemberHoldings.isVerified` has no default, and it is the only field of that
  type without one. The readings default to `.unknown`, which holds roles, so
  a caller who leaves one out errs toward changing nothing. There is no
  equivalent for a `Bool`: `true` grants the verified badge on a sweep that
  read nothing about anybody, `false` takes the badge off every member who has
  one, and it used to default to `true`. The caller knows whether the member
  has a linked account, because it is this bot's own record; it says so.
- Two ladder rungs that collide report the amount they collided at.
  Thresholds are written in whole tokens and compared in the token's smallest
  unit, so a refusal that quoted a typed number named a threshold neither rung
  sits at whenever both numbers saturated: "both sit at 18,000,000,000,000,000,000"
  for two rungs that actually met at the ceiling, with the other rung's number
  nowhere in the sentence. `duplicateThreshold` carries both whole numbers and
  the converted amount, and the message prints all three. Count rungs keep
  `duplicateMinimum`, where the comparison really is on the number written.
- `GatingFormatting.compact` was kept, and kept labelled. It goes through
  `Double` and throws digits away on purpose, which is right for a card where
  the exact figure is not the point and wrong everywhere else. The original
  carried the same warning; it is repeated in the source because the function
  keeps looking like the convenient one.
- The Discord payload limits are named constants. The original had `256` and
  `4096` written out in dozens of places, and because a handler defers first, a
  rejected payload surfaces to a member as a stuck "thinking" rather than as an
  error, so a card that grew a field was one forgotten clamp away from a
  handler that never answered. Clamping here counts Swift `Character`s, which
  makes a rejection unlikely rather than impossible: the receiving end counts
  something smaller, so a boundary that knows the smaller unit should check
  again in it.
- The administrator list starts empty and can be emptied. Nothing is added to
  it at boot by anybody, and there is no entry it refuses to remove, including
  the last one, because an allowlist somebody cannot empty is an allowlist
  somebody does not own. Accounts are compared exactly: folding case would be
  this layer guessing at an encoding it deliberately knows nothing about.
- A role is a plain string and the decision is a value. In the original the
  decision was spread across a sweep loop, a role service and a Discord client,
  tangled with a database, a rate limiter and an HTTP call, and the only way to
  find out what it did was to run it against a real server.

## Files to Read First

- `Sources/Gating/RoleRules.swift`: the decision, and the only file worth
  arguing about. Read the two rules in its header before changing anything in
  it.
- `Sources/Gating/Reading.swift`: why an unread fact is a case and not a zero.
- `Sources/Gating/MemberHoldings.swift`: what a caller has to hand in, and
  which of it is allowed to be missing.
- `Sources/Gating/NumberedEnvironment.swift`: the shape every loader follows
  and the two rules that make a typo visible.
- `Sources/Gating/Tier.swift`: the ladder, the three standings, and the
  leniency in `storedRung`.
- `hi/role.md` and `hi/adopt.md`: the criteria the tests cite by id.

## Current Status

Implemented and covered by 131 tests in 10 suites, all offline. This is the
second library target in the package, beside `Reserve`, and the two do not
depend on each other. There is no bot target yet: no gateway, no commands, no
chain access and no store, so nothing here is wired to a live server and no
decision this module produces is applied to anybody.

## Notes

- `Sources/Gating` is in `.specsync/config.toml`'s `source_dirs`, so the
  repository's file and LOC coverage figures count this target. They read
  41/41 files and 5,829/5,829 lines; before it was registered they read 24/24
  and 2,880/2,880, which was 100% of `Sources/Reserve` and none at all of the
  2,949 lines here.
- Some tests cite criterion ids in their names or their suite documentation:
  HOST-3, ADOPT-1.a, ADOPT-1.b, ADOPT-2, ROLE-1.a, ROLE-1.c and ROLE-2. The
  rest carry their promise in the sentence instead, and `requirements.md` is
  where a criterion is tied to a file.
- `GatingFixtures.swift` is a server shaped like a real one: three rungs, two
  collections (one badge, one count ladder), two pools (one badged, one not), a
  verified role and one administrator. The shape is the point. It has a role
  for every branch of the decision and a fact for every kind of unread, so a
  new rule usually needs no new fixture.
- `TierLadder` and `Tier` still have public initializers that check nothing.
  The duplicate id, duplicate name, duplicate threshold and reserved-label
  rules live in `TierConfiguration.load`, and a host that builds a ladder by
  hand gets none of them. What `storedRung` used to borrow from those rules it
  now enforces itself, so the leniency is unambiguous on any ladder; the rest
  of the loader's rules are still the loader's, and a hand-built ladder can
  still hold two rungs at one threshold or a rung with an empty id. Those are
  visible in the ladder a host built rather than silently deciding somebody's
  roles, which is why they are not worth a throwing initializer.
