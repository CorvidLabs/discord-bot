---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: tasks
---

# Tasks

Worked in the order of `plan.md`. Each item is meant to be obviously done or
obviously not. Anything that turns out to be wrong when the code is in front of
you goes in **Gaps and open questions** at the bottom rather than being quietly
absorbed.

Every test added below cites its criterion id in the test's own name or its
comment, the way `Tests/ReserveTests` already cites `RESERVE-*`. `ChainTests`
cites no ids today, so this change introduces the habit there; the id goes in
the test file **and** in the `Covered by` line of the matching requirement in
`specs/chain/requirements.md`.

## Stage 0: coordination, before any code

- [ ] Re-read the runtime change's definition in its own workspace and confirm
      it still adds no health value type of its own. Its REQ-runtime-032 says
      so, and its boundary table matches the one in `requirements.md` here; if
      either moves, both move together.
- [ ] Confirm the second edge with that change as well: stage 3 makes the
      caller required on `ChainReader`, and the runtime's boot gate calls
      `verifyAssetDecimals`, which becomes the instance's own work. Whichever
      change lands second carries that one-line edit.
- [ ] Record the ordering with `specsync change depend` once both workspaces
      are in one tree, so the runtime change declares this one as its
      predecessor for the `Chain` health values. Until then the boundary is
      recorded in both definitions in writing, which is what stops the gap.
- [ ] Confirm with the approver which of the two readings of RUN-11 is wanted
      (open question 1 in `plan.md`) before stage 3 starts. Stage 3 is the
      largest diff in the change and the answer moves it.

## Stage 1: RUN-10.a, the test that must fail

- [ ] Add a test to `Tests/ChainTests/RequestGovernorTests.swift` citing
      RUN-10.a, over a **provider quota refusal** pause on a budget with
      headroom (budget 100, 40 spent), not an exhausted budget.
- [ ] Assert the snapshot before and after `unpause` is identical in
      `usedRequests`, `remainingRequests` and `dayStart`.
- [ ] Assert `remainingRequests(now:)` still answers the same number after the
      unpause.
- [ ] Assert the day still ends where it would have: the sixtieth further
      request is allowed and the sixty-first throws
      `ChainError.requestBudgetSpent`.
- [ ] Assert against a store double that the counts written are non-decreasing
      and never drop below what was spent before the unpause.
- [ ] Run the five mutations in the table in `plan.md` by hand against the new
      test plus the existing one at
      `Tests/ChainTests/RequestGovernorTests.swift:208`, and record which test
      catches which. A mutation nothing catches is a missing assertion, not a
      note.
- [ ] Leave the existing test in place and add the RUN-10.a citation to it too.
- [ ] Add the criterion id to the `Covered by` line of `REQ-chain-008` in
      `specs/chain/requirements.md`, and state the unpause guarantee in
      `specs/chain/chain.spec.md` if it is not already stated normatively.

## Stage 2: SEE-1.b, what `Chain` exposes

- [ ] Add a non-probing read to `ProviderProofProbe` that answers with the
      cached proof only while it is still fresh, answers nil otherwise, makes no
      request and leaves `cachedProof`, `cachedUntil` and `lastFailure`
      untouched.
- [ ] Leave `proof(now:)` exactly as it is, including the rule that a failed
      probe drops the stale answer rather than serving it on.
- [ ] Add the `RequestBudgetSnapshot` to `ChainHealthReport` as an optional
      member, with a documented reason it is optional: a host with no chain
      configured has no budget to report.
- [ ] Extend `jsonBody` with the budget section, appended after the existing
      keys, with the same hand-built escaping discipline and a fixed key order.
- [ ] Leave `status` at its two cases (R-HEALTH-4): assert in a test that a
      paused budget reports `ok` with a budget section rather than `starting`,
      and write the readiness rule and its reason into the doc comment so the
      next person does not "fix" it.
- [ ] Add a test citing SEE-1.b that builds a report from a governor and a
      recording data source and asserts the request count did not move and the
      data source was never called.
- [ ] Add a test citing SEE-1.b that exhausts the budget, confirms the governor
      is paused, then builds a report and asserts it still answers and its body
      names the pause.
- [ ] Add a test that the non-probing read makes no call against a counting
      `HTTPHeaderProbe` double, including when the cache is stale.
- [ ] Extend `REQ-chain-011` in `specs/chain/requirements.md` and the matching
      section of `specs/chain/chain.spec.md` with the budget section, the
      status rule and the costs-nothing guarantee.
- [ ] Write down, in `specs/chain/chain.spec.md`, that `Chain` owns no listener
      and no route, so the boundary is in the contract and not only in this
      workspace.

## Stage 3: RUN-11, a caller's share of the day

- [ ] Add the caller value to `Chain`: a `Sendable`, `Hashable` value that is
      either the system or a member named by the key the instance drew. Document
      that a chat account id must never be passed.
- [ ] Add the two settings to `ChainEnvironment` and `ChainLimits`, the share
      percentage and the burst, parsed through the existing
      numbered-environment rules and refused at boot when unusable, naming the
      variable. Defaults 5 percent and 10 requests (R-SHARE-3).
- [ ] Implement the share as a refilling allowance: the sustained rate is that
      percentage of the day's budget spread over the UTC day, the capacity is
      the burst capped by the day's share, and there is no share at all when no
      budget is set (R-SHARE-4).
- [ ] Refuse a percentage above one hundred at boot, naming the variable, and
      treat zero as shares off. A burst larger than the day's share clamps to
      it and is reported, not refused.
- [ ] Put the arithmetic in a pure value beside the actor, the way `TokenBucket`
      sits beside `RequestRateLimiter`, so every boundary has a test that
      finishes instantly.
- [ ] Enforce the share inside `RequestGovernor.spend` and nowhere else: pause
      check first, share second without mutating anything, day third.
- [ ] Make the per-caller reservation take the caller with **no default**, on
      `RequestGovernor` and on the read surfaces of `ChainReader`,
      `BatchedChainReader` and `WalletCheckCache`.
- [ ] Update every call site in `Sources/` and `Tests/` to say whose work it is.
      A call site that is genuinely system work says so explicitly.
- [ ] Add a `ChainError` case for a caller over their share, distinct from
      `requestBudgetSpent`, naming when the share returns and how much was used,
      with an `errorDescription` in the register the other cases use.
- [ ] Apply the all-or-nothing rule to `reserveRequests(_:now:)` for a member
      caller as well: the whole count against the remaining share, or nothing.
- [ ] Hold one refilling allowance per caller in memory, dropping an entry once
      it is full again because a full allowance carries no information, and
      clearing nothing else at the day roll the budget already uses.
- [ ] Cap the number of tracked callers with a constant. At the cap, refuse a
      caller nobody is tracking yet rather than admitting them untracked, never
      evict a caller who is part way through their allowance, and record one
      notice the first time the cap is reached in a day.
- [ ] Add the share size and the number of callers that reached it today to
      `RequestBudgetSnapshot`. A count, never a list of who (R-SHARE-9).
- [ ] Test, citing RUN-11: one member cannot spend the day. A member spending
      their share is refused with the new error while the day still has requests
      left, and a second member is served normally in the same test.
- [ ] Test: a refusal on the share does not pause the process, does not change
      the day's counter, and records no notice.
- [ ] Test: system work is not metered, so a sweep larger than a member's share
      completes.
- [ ] Test: an allowance refills towards the burst and no further, so a member
      is not locked out for the rest of the day and an idle member does not
      accumulate the whole day's share.
- [ ] Test: a restart hands a caller at most one fresh burst, while the day's
      own count is restored from the store (R-SHARE-8, RUN-8.b).
- [ ] Test: with no daily budget set there is no share, and nothing is refused.
- [ ] Test: at the tracked-caller cap, a new caller is refused and one notice is
      recorded, not one per refusal.
- [ ] Extend the stage 1 test so that `unpause` also returns none of the
      caller's share, and add that mutation to the table in `plan.md`.
- [ ] Add a new requirement to `specs/chain/requirements.md` with the next free
      `REQ-chain-<number>`, stating the share, the refusal, the no-pause rule
      and the caller being required rather than defaulted, and update
      `specs/chain/chain.spec.md` to match.
- [ ] Note in the contract that the ledger does not survive a restart, so the
      gap is written where somebody will read it.

## Stage 4: SPEND-9.c, which period an epoch was counted against

- [ ] Add the charge value to `Reserve`: the period key of the limits a run was
      measured against, the whole units it was checked for, and when the
      measurement was taken. `Codable`, `Sendable`, `Equatable` (R-PERIOD-1).
- [ ] Add the ordered list of charges to `ReserveEpochRecord`, empty by
      default, and the derived list of period keys in order for a reader that
      only wants the answer.
- [ ] Append a charge in the runner after the limits check and before the first
      claim of that run, saving the record once per run rather than once per
      recipient (R-PERIOD-2).
- [ ] Append rather than overwrite, so a resumed epoch names both periods in
      the order they were charged, and say so in the doc comment with the
      resumed-epoch case named (R-PERIOD-3).
- [ ] Add the same list to `ReserveEpochOutcome` so a caller can report it
      without loading the record back (R-PERIOD-8).
- [ ] Check whether `StoreDate.recorded(_:)` needs anything for the charge's
      recorded instant, which is an instant like every other in this store.
- [ ] Confirm `ReserveCoding` round-trips a record with charges, and decodes a
      record encoded before the key existed as an empty list rather than
      throwing, and only for that key (R-PERIOD-6).
- [ ] Add schema migration version 3 to `Sources/StoreSQLite/Schema.swift`
      creating one new table for the charges, keyed by stream, epoch and
      ordinal, with the same cascade the claims rows use, and a `down` that
      drops the table whole, which is the reverse the migrator's
      revert-everything test requires.
- [ ] Read and write the new table in
      `Sources/StoreSQLite/SQLiteStore+Reserve.swift`, memoising the write the
      way the claims rows already are so the saves inside one epoch cost one
      charge write between them, and invalidating that memo when a resumed run
      appends a second charge.
- [ ] Carry the charges through `Sources/Store/InMemoryStore.swift` and the
      `Reserve` in-memory store, and confirm both agree with the file-backed
      one.
- [ ] Add conformance behaviours in
      `Sources/StoreTestKit/StoreConformance+Reserve.swift`: an epoch round
      trips with its charges in order, an epoch gains a charge on a second
      save, and a row written verbatim without the new table reads back with no
      charges rather than throwing (R-PERIOD-7).
- [ ] Add a test citing SPEND-9.c that a finished epoch names the period it was
      charged to, using the injected clock so any boundary is crossed
      deterministically.
- [ ] Add a test citing SPEND-9.c and SPEND-9.a that an epoch cut short part way
      through and resumed in a later period names both, in run order.
- [ ] Add a test that an epoch run under a payer stating no limits records no
      charge at all, and that nothing is invented from the cadence key
      (R-PERIOD-4).
- [ ] Update `specs/reserve/reserve.spec.md`: the `ReserveEpochRecord` and
      `ReserveEpochOutcome` tables, the invariant that a charge is written after
      the limits check and before the first claim and that a resumed run appends
      rather than overwrites, and the Change Log.
- [ ] Update `specs/store/store.spec.md`: the new table, the conformance
      behaviour list, the migration log entry for version 3, and the Change
      Log.
- [ ] Update `specs/reserve/testing.md` and `specs/store/testing.md` with the
      new tests.

## Stage 5: closing the change

- [ ] Write the semantic deltas into the workspace's `deltas/` directory, one
      per affected canonical spec: `reserve`, `chain`, `store`.
- [ ] Confirm `affected_paths` still covers what the change touches. It now
      lists `specs`, `README.md`, `AGENTS.md`, `CHANGELOG.md` and `docs`
      alongside `Sources` and `Tests`, because `docs.md` edits all of them and
      a path outside the list is a path outside the gate.
- [ ] Check every `Covered by` line touched names a real test that really covers
      it, by running that test alone and watching it fail against a deliberate
      break.
- [ ] `specsync change check <id>` clean.
- [ ] `specsync check --strict` clean, with coverage unchanged at full.
- [ ] `fledge lanes run verify` green, which is `swift build` then `swift test`,
      and is the same command the Trust gate runs.
- [ ] Confirm the suite still runs with no network, no credentials and no
      database anybody installed, including the new tests.
- [ ] Confirm no new public symbol lacks a doc comment and no new declaration
      lacks an access modifier.
- [ ] Read the whole diff once for the house rules: no force unwrap, no `try!`,
      no `as!`, no single-letter generics, no `Double` near an amount.
- [ ] Record in `context.md` anything decided differently from `plan.md`, with
      the reason, before asking for review.

## Gaps and open questions

Carried forward from `plan.md` so that whoever works the checklist does not have
to reconstruct them. None of these blocks the work; each is something a reviewer
may reverse.

- [ ] **The strict reading of RUN-11.** With no daily budget set there is no
      share and nothing is refused, so in a default deployment the criterion is
      satisfied vacuously. Confirm this is what the approver wants, and say so
      in the contract either way.
- [ ] **A resumed epoch names both ceilings.** Settled that way because a
      single value is a lie in the only case SPEND-9.c is about. The cost is a
      table, a conformance behaviour and a read, and a reviewer who thinks a
      boundary-crossing resume is rare enough to document rather than record
      may still reverse it.
- [ ] **The per-member allowance does not survive a restart.** A crash loop
      hands a member at most one fresh burst. The day's total still holds, so
      the ceiling the share is carved from is intact.
- [ ] **The cadence period is still not recorded per epoch.** Only the newest
      per stream is kept. "Which week did epoch seven pay in" remains
      unanswerable, and that is a separate criterion from SPEND-9.c.
- [ ] **The share defaults are a judgement.** Five percent and a burst of 10
      have no deployment behind them. Revisit with the first operator who has
      members and a metered provider.
- [ ] **A percentage of a small budget can be smaller than one command.**
      Whether the share needs an absolute floor as well is open question 8 in
      `plan.md`; a third knob is the cost of closing it.
- [ ] **Health body compatibility.** A new key in the hand-built JSON is a
      compatibility event for anybody grepping it. Nobody is running this yet,
      which is the argument for doing it now rather than the argument that it
      does not matter.
- [ ] **An admin command classified as system work is unmetered.** Accepted, and
      worth one sentence in the operator documentation when that documentation
      exists.
