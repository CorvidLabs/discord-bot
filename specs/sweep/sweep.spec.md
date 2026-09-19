---
module: sweep
version: 1
status: active
files:
  - Sources/Sweep/CollectionRegistry.swift
  - Sources/Sweep/MemberSweepOutcome.swift
  - Sources/Sweep/RoleGateway.swift
  - Sources/Sweep/RoleSweep.swift
  - Sources/Sweep/SweepChainReader.swift
  - Sources/Sweep/SweepDirectory.swift
  - Sources/Sweep/SweepJournal.swift
  - Sources/Sweep/SweepLimits.swift
  - Sources/Sweep/SweepLog.swift
  - Sources/Sweep/SweepProblem.swift
  - Sources/Sweep/SweepRecord.swift
  - Sources/Sweep/SweepReport.swift
  - Sources/Sweep/SweepSchedule.swift
  - Sources/Sweep/SweepTally.swift
db_tables: []
depends_on: [gating, chain, store]
---

# Sweep

## Purpose

Make a member's roles follow what they hold, over and over, without anybody
asking for it (ROLE-1).

The decision itself is not here. `Gating.RoleRules.decide` turns what a member
holds and what the operator configured into a set of roles to grant and a set
to take away, from values, with no clock and no network. This module is the
half that cannot be a function of its arguments: the loop, the batching of
chain reads into one pass, reading and writing roles through a chat service it
never names, the record written before the work and again after it, and the
reason kept for every member whose roles did not change.

It names no chat client and no database engine. The chat side is two protocols
declared here over `String`, the store side is the two narrow protocols
`Store` already declares, and the chain side is one protocol with a live
implementation over `Chain.BatchedChainReader`. The whole sweep is therefore
exercised with no token, no network and no server.

## Public API

Every exported symbol of the `Sweep` library target, grouped by file.

| Export | Description |
|--------|-------------|
| `RoleGateway` | Putting one decision into effect in the chat service. |
| `currentRoleIds` | Every role a member holds now, including ones this bot manages nothing about. Throws rather than answering with an empty set. |
| `apply` | Applies one decision, touching only the roles it manages. |
| `ServerMember` | One member of the served server, as the chat service lists them. |
| `externalId` | The member, as the chat service names them. |
| `roleIds` | Every role they hold, including ones this bot knows nothing about. |
| `ServerRoster` | Listing the server, which is the only way to find an orphan. Optional to supply. |
| `members` | On `ServerRoster`, every member holding at least one of the roles this bot manages. On `SweepTally`, how many members have been accounted for so far. |
| `SweptMember` | One member the sweep is going to visit, with the accounts they proved. |
| `member` | Who they are to this instance, and to the chat service. |
| `accounts` | Every account they proved, oldest first. Empty is a real answer. |
| `addresses` | The addresses to read, in the order they were proved. |
| `SweepDirectory` | Everybody this instance has on record, as one list. |
| `verifiedMembers` | Every member on record, with the accounts they proved. |
| `StaticSweepDirectory` | A fixed list, for a test or a host with nothing durable yet. |
| `SweepChainReader` | Reading the accounts a sweep is about to decide on, in one batch. |
| `check` | A reading for each address, in the order asked for. Never throws. |
| `BatchedSweepReader` | The live reader, bound to the pools an operator counts. |
| `CollectionRegistry` | Which collection each asset belongs to. |
| `assetCollections` | The collection id each known asset belongs to, keyed by asset id. |
| `StaticCollectionRegistry` | A catalogue that is simply known. |
| `assets` | The catalogue handed back every time. |
| `SweepLog` | Where a sweep's lines go. One `async` method, so an implementation can be an actor. |
| `write` | Writes one line, already carrying its run id. |
| `SilentSweepLog` | A log that keeps nothing. The default, so a host opts in to output. |
| `StandardErrorSweepLog` | A log that writes to standard error. |
| `SweepJournal` | Where the run record and the problems are kept. Nothing here throws. |
| `begin` | Records that a sweep has started, before any work. |
| `end` | Records that a sweep has ended, cleanly or not. |
| `record` | Keeps problems worth reading later. |
| `lastSweep` | The last sweep written down, finished or not. |
| `recentProblems` | Problems kept, most recent first. |
| `InMemorySweepJournal` | A journal in memory, which does not survive a restart and says so. |
| `problemLimit` | How many problems are kept before the oldest are dropped. |
| `SweepSkipReason` | Why a sweep left one member's roles alone (SEE-2.a). |
| `factsUnread` | Something the rules needed was not read. |
| `noAccounts` | The member has proved no account. |
| `rolesUnreadable` | The member's current roles could not be read. |
| `applyFailed` | The chat service refused the write. |
| `unlinkedMidSweep` | The member's last account was unlinked between the batch read and the write, so the decision was thrown away rather than applied. |
| `isDeliberate` | Whether this is the bot's own decision rather than a failure. |
| `sentence` | One plain sentence an operator can act on, naming something outside the code. |
| `SweepDisposition` | The four things a sweep can do to one member. |
| `changed` | Roles were written. |
| `unchanged` | Compared and already correct. |
| `held` | Deliberately not written. |
| `missed` | The sweep failed on this member. |
| `MemberSweepOutcome` | What one sweep did to one member, and why. |
| `memberId` | This instance's own name for the member, never the chat service's. |
| `disposition` | What was done. |
| `reason` | Why the member was held or missed. |
| `unknowns` | What the rules wanted and were not given. |
| `heldRoleCount` | How many configured roles were deliberately left alone. |
| `isComplete` | Whether every fact the rules wanted was read. |
| `summary` | One line for a log, naming the member and the reason. |
| `SweepTally` | Per-member outcomes of one sweep, counted, with the reasons kept. |
| `empty` | A tally before any member has been swept. |
| `key` | A stable, short name for one unread fact. |
| `SweepState` | How a recorded sweep ended, as it is read back later. |
| `running` | Started, not finished, and recent enough that it still could be. |
| `abandoned` | Started, never finished, and too long ago to still be running. |
| `failed` | Reached the end, but the sweep itself threw. |
| `finished` | Reached the end cleanly. |
| `SweepRecord` | One sweep of everyone's roles, as it is written down. |
| `runId` | Identifies this sweep in every line it produced. Also builds one from an instant and a suffix. |
| `startedAt` | When the sweep started. |
| `finishedAt` | When it finished, or nil if it never did. |
| `memberCount` | Members the sweep set out to visit. |
| `accountCount` | Accounts the sweep set out to read. |
| `orphansCleared` | Members this bot took managed roles back from. |
| `tally` | Per-member outcomes. |
| `failure` | The error that ended the whole sweep, when one did. |
| `ended` | The same sweep, ended. |
| `elapsed` | Wall-clock time the sweep took, or nil while it has not finished. |
| `state` | How this sweep ended, judged from when it started. |
| `newRunId` | A fresh run id, with a random suffix. |
| `SweepProblem` | Something that went wrong and is worth reading afterwards (SEE-5). |
| `Kind` | What kind of problem this is. |
| `sweepFailed` | The whole sweep threw. |
| `membersSkipped` | Members were held or missed during a sweep. |
| `registryUnread` | The collection catalogue could not be read. |
| `orphanSweepRefused` | The orphan pass refused to run against the records it was given. |
| `orphanSweepFailed` | The orphan pass started and could not finish. |
| `sweepAbandoned` | A sweep started and never finished. |
| `label` | Short heading for a card or a list. |
| `at` | When it happened. |
| `kind` | What kind of problem it is. |
| `detail` | What happened, in one sentence naming something an operator could change. |
| `trimmed` | Most recent problems first, capped by count and never by age. |
| `SweepReport` | What one pass of the sweep did, handed straight back. |
| `ran` | Whether this pass actually ran. |
| `problems` | What went wrong and is worth reading later. |
| `skipped` | A pass that did nothing because another was already running. |
| `SweepLimits` | How hard one sweep is allowed to push the chat service. |
| `memberBatchSize` | How many members are handled at once. |
| `pauseBetweenBatches` | How long to wait between batches. |
| `orphanBatchSize` | How many orphans have their roles taken back at once. |
| `standard` | What a host gets by not choosing. |
| `unthrottled` | No pause at all, for a test. |
| `SweepSchedule` | When the next sweep is due. |
| `defaultInterval` | The interval used when nothing usable was configured. |
| `minimumInterval` | The shortest interval accepted. Anything lower spins the loop. |
| `maximumInterval` | The largest interval that still fits a sleep measured in nanoseconds. |
| `interval` | Whole seconds from a configured value, with the rejected value returned rather than swallowed. |
| `wholeSeconds` | Whole seconds an interval is worth, clamped, with nonsense becoming the default. |
| `secondsUntilDue` | How long before the next sweep, or nil when one is due now. |
| `RoleSweep` | The impure half: the loop, the batching, the run record and the per-member reasons. |
| `jobName` | What this sweep is called when it spends a chain request. |
| `init` | Builds each value from its parts, and a `RoleSweep` from the configuration and the seams it reads and writes through. |
| `isSweeping` | Whether a pass is running right now. |
| `lastCompleted` | The last pass that actually ran, in memory only. |
| `start` | Starts the periodic loop, delayed by whatever is left of the interval. |
| `stop` | Stops the periodic loop and returns without waiting. A pass already in flight runs to its end, because it is not a child of the loop. |
| `run` | Runs one pass over everybody. Never throws. |

## Invariants

- **A read the bot could not complete is never a demotion.** A failed balance
  or asset read reaches the rules as `Gating.Reading.unknown`, the roles that
  fact decides drop out of the managed set, and they are preserved (ROLE-1.a).
  An account absent from the batch entirely is substituted with an explicitly
  unread reading rather than dropped, because a member made of their other
  wallets is a real number and is not that person's number.
- **A short liquidity reading is not a smaller one.** Only a complete reading
  is written back to the store, so one bad minute cannot become the stored
  figure the linking arithmetic adds to next time.
- **The orphan pass records its baseline only after its guard passes.**
  `Gating.RoleRules.orphanSweep` answers with either a run carrying a baseline
  or a refusal carrying none, so there is no count to write on a refusal and
  the previous baseline survives for the next pass (ROLE-5.a).
- **A baseline that will not read is not a missing baseline.** The store
  throws, and the orphan pass refuses, because a corrupt row read as nothing
  falls back to the zero floor alone and disarms the halving check in silence.
- **The record is written before the work and again after it.** A sweep killed
  part way reads as unfinished rather than as the previous one's success
  (SEE-2).
- **Members whose roles did not change are split into held and missed**, each
  with a named reason, and a deliberate reason is never counted as a failure
  (SEE-2.a).
- **Every line of one sweep carries the same run id** (SEE-6). Nothing writes
  a line except through a run log that already holds it.
- **The sweep is the instance's own work.** Its chain reads pass
  `Chain.RequestCaller.system(job:)`, so they are not rationed against one
  member's share of the day.
- **One batched chain read for the whole pass**, deduplicated, in order, so a
  pool's reserves are read once for the run rather than once per member. The
  member's own account list is deduplicated as well: asking once and then
  summing the answer twice would promote somebody on money they do not have,
  which is the worse half of a duplicated row rather than the cheaper one.
- **Nothing is written on a record this pass has not just re-read.** A pass
  is minutes long, so both directions of a record changing under it strip a
  real person: the accounts are read again immediately before the write, so a
  member who unlinked is held rather than handed everything back; and the
  records are read again immediately before the orphan filter, so a member
  who verified during the pass is not taken for somebody the bot has never
  heard of. The second reading of the records is a union with the first,
  because a second reading can only ever protect somebody.
- **A pass already in flight runs to its end.** Each pass runs in a task of
  its own rather than as a child of the loop, so `stop()` cannot reach inside
  one. A cancelled pass would record every member it had not reached as
  missed and blame the chat service for it, which would write a permission
  outage that never happened into the journal on every redeploy (SEE-2).
- **Only `Gating.RoleDecision.managed` is touched.** A badge a moderator hands
  out by hand survives every sweep, including the orphan pass (ROLE-5).
- **A sweep never throws.** The loop has to be running again in half an hour
  either way, so a failure becomes a record, a problem and a report.
- **Two passes never overlap.** The second does nothing at all and writes
  nothing.

## Behavioral Examples

| Situation | What happens |
|-----------|--------------|
| Every wallet read, member sold down | The rungs are revoked and the outcome is `changed`. |
| One wallet of two unreadable | Nothing is written. `held`, reason `facts-unread`. |
| An account missing from the batch entirely | Treated as unread, not absent. `held`. |
| A pool whose reserves did not load | The ladder is held; `liquidity-positions` is named as the unread fact. |
| The collection catalogue refuses | The ladder and the pools still decide; the collection badges are held and a `registry-unread` problem is kept. |
| No catalogue supplied at all | Every collection badge is held, for ever, which is the safe direction. |
| A member's current roles cannot be read | Nothing is written. `missed`, reason `roles-unreadable`. |
| The chat service refuses a write | `missed`, reason `apply-failed`. |
| A member who unlinks their last account mid-pass | `held`, reason `unlinked-mid-sweep`. Nothing is written, so the roles the unlink stripped stay off. |
| A store that will not answer the re-check | The decision is applied. An unread re-check is not evidence that anybody unlinked, and the decision was made from a complete reading. |
| A member who finishes verifying mid-pass | Left alone. The orphan pass reads the records again and finds them, so what their verification granted stays on. |
| The records will not read a second time | The orphan pass refuses with `orphan-sweep-refused`, and no role is taken from anybody. |
| The loop is stopped mid-pass | The pass finishes and records what it really did. Nobody is written down as missed for a shutdown. |
| A member on record with no proved account | `held`, reason `no-accounts`, in the per-member pass. The orphan pass is what takes their managed roles back, because they count as having proved nothing. |
| Nobody on record | The orphan pass refuses, lists nothing, and records no baseline. |
| More than half the members gone since the last pass | The orphan pass refuses and the old baseline survives. |
| A baseline row that will not decode | The orphan pass refuses rather than treating it as a first run. |
| A member holding a managed role with nothing on record | The managed roles are taken back; a hand-granted role is left. |
| No roster supplied | No orphan pass at all, and no complaint about it. |
| A sweep started while one is running | The second does nothing and writes nothing. |
| A chat outage after the chain was read | The reading is still written back, because it has already been paid for out of the day's budget. |
| A restart five seconds after a sweep | The loop waits out the remainder rather than repeating a read of every wallet. |

## Error Cases

| Case | Behaviour |
|------|-----------|
| `SweepDirectory.verifiedMembers` throws | The whole pass ends with a failure on its record and a `sweep-failed` problem. Nothing was taken from anybody. |
| `CollectionRegistry.assetCollections` throws | A `registry-unread` problem; the pass carries on and holds the collection roles. |
| `RoleGateway.currentRoleIds` throws | That member is `missed`; no decision is computed and nothing is written. |
| `RoleGateway.apply` throws | That member is `missed` with `apply-failed`. |
| `SweepDirectory.verifiedMembers` throws on the second read | The orphan pass refuses with `orphan-sweep-refused`; the per-member pass has already finished and stands. |
| `AccountStore.accounts` throws on the re-check before a write | Ignored. An unread re-check is not an unlink, so the decision is applied. |
| `RoleBaselineStore.loadRoleBaseline` throws | The orphan pass refuses with `orphan-sweep-refused`. |
| `RoleBaselineStore.save` throws | Logged; the pass carries on and the next one compares against the previous baseline. |
| `ServerRoster.members` throws | An `orphan-sweep-failed` problem; no role is taken from anybody. |
| `AccountStore.recordBalances` throws | Ignored. The decision was made from the reading itself, not from the store. |
| A journal that cannot write | Nothing. A journal is what describes the sweep, not what makes it correct. |
| `ROLE_SWEEP_INTERVAL` unparseable, zero or under a minute | The default interval, with the rejected value returned so a host can say so. |

## Dependencies

- `Gating`, for the decision, the configuration, `MemberHoldings`, `Reading`
  and the orphan guard. The decision is never re-derived here.
- `Chain`, for `WalletCheck`, `ChainReadGap`, `RequestCaller` and
  `BatchedChainReader`, and for the bridge that turns readings into holdings.
- `Store`, for `MemberRecord`, `AccountRecord`, `AccountStore`,
  `RoleBaselineStore` and `RoleBaselineRecord`. The baseline record already
  existed for exactly this guard and is adopted rather than re-invented.
- No chat client. `RoleGateway` and `ServerRoster` are declared here over
  `String`, and the adapter that knows what a snowflake is depends on this
  target rather than the other way round.
- No `Surface` and no `Runtime`. A host joins them; this target cannot reach
  either, so the loop can never acquire a card or a boot gate.

## Change Log

| Version | Change |
|---------|--------|
| 1 | The first sweep: one batched chain read for the whole pass as the instance's own work, a decision per member through a chat seam declared here, a record written before the work and again after it, held and missed split with named reasons, and an orphan pass behind the guard whose baseline is recorded only when it passes. Corrected before release, each against a test that failed first: a member's own duplicated address is summed once rather than twice, the accounts are re-read immediately before the write so an unlink mid-pass is held rather than undone, the records are re-read immediately before the orphan filter so somebody who verified mid-pass is not stripped, and a pass in flight survives `stop()` so a redeploy does not write a permission outage that never happened. |
