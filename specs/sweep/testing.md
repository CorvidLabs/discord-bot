---
spec: sweep.spec.md
---

## Automated Testing

`swift test --filter SweepTests` runs this target's suite, all offline: no
token, no network, no server and no chain.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `NeverDemoteTests.swift` | Unit | The one behaviour everything else is arranged around: an unreadable wallet, one wallet of two, an account missing from the batch, a pool whose reserves did not load, a catalogue that refused and no catalogue at all. Includes the opposite case, a clean read that really does demote, so a hold is a decision rather than an inability. |
| `SweepRecordingTests.swift` | Unit | Two journal writes in order, an unfinished record reading as running and then abandoned, a sweep that threw reading as failed, every line carrying the run id, the run id's shape, a clean sweep writing no problem, and an overlapping pass doing nothing. |
| `HeldAndMissedTests.swift` | Unit | The SEE-2.a split: unreadable roles and a refused write as missed, unread facts as held, three members three ways in one pass, one journal entry for the lot, and a member decided partly still counted as incomplete. |
| `OrphanSweepTests.swift` | Unit | The guard and the baseline: an orphan losing managed roles and keeping a hand-granted one, the baseline recorded on a run, refusals on nobody-on-record, on a collapse and on a corrupt row, a small server allowed to shrink, an unlistable server taking nothing, no roster meaning no pass, and a member with no accounts not counting. |
| `CallerAndBalanceTests.swift` | Unit | `RequestCaller.system` on every read, one batch for the whole pass, duplicate addresses asked once **and summed once**, write-back only from complete readings, and a reading surviving a chat outage. |
| `SweepScheduleTests.swift` | Unit | Interval parsing including zero, a fraction, a word and an overflow; the wait after a recent sweep; any doubt sweeping now; clamping; and the delay read from the journal. |
| `SweepValueTests.swift` | Unit | Tally counting and reason keys, stable summaries, round-tripping a tally and a record, problem trimming, clamped limits, the in-memory journal's cap, and an outcome's one-line summary. |
| `SweepLoopTests.swift` | Unit | The loop actually running, the restart delay, starting twice being harmless, every member visited across batches, a pass in flight surviving `stop()` against a gateway that gives up on cancellation, and the verified badge staying decidable when nothing else is. |
| `MidSweepChangeTests.swift` | Unit | Records that change while a pass is running: an unlink mid-pass held rather than undone, a store that will not answer the re-check still writing, a member who verifies mid-pass not stripped as an orphan, and a second reading the records refuse refusing the orphan pass. |
| `SweepFixtures.swift` | Fixture | A server with three rungs, a collection, a pool, a verified role and a hand-granted role nobody configured. |
| `SweepDoubles.swift` | Fixture | A reader that records its caller, a chat service that can refuse either half, a roster that can refuse, a journal that keeps every write in order, an actor log, and a latch for the overlap test. |
| `SweepHarness.swift` | Fixture | One assembled sweep and the spies behind it. Every fixture member is admitted to the store with their accounts, because the pass re-reads the store before it writes and a member who was never admitted would read as somebody who has just unlinked. |

## Manual Testing

- [ ] Point a host at a server with one member, unplug the chain provider, and
      confirm the member keeps every role and the pass reports one held.
- [ ] Point a host at an empty store and confirm the orphan pass refuses, the
      problem names the store, and no role is taken from anybody.
- [ ] Kill the process mid-pass and confirm the record reads as unfinished
      rather than as the previous pass's success.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| A member with no proved account | Held with `no-accounts` in the per-member pass; the orphan pass takes their managed roles back. |
| A member whose every fact is unread | Held, except that the verified badge is still granted: it is this bot's own record. |
| One account of two missing from the batch | The whole member reads as unknown. |
| A pool the member is in whose reserves failed | The ladder is held; other roles still decide. |
| The catalogue refuses | Collection badges held, a problem kept, everything else decided. |
| A corrupt baseline row | The orphan pass refuses; the zero floor is not fallen back to. |
| A baseline of 5 falling to 1 | Allowed: below ten a server is too small for a halving to mean anything. |
| A baseline of 40 falling to 5 | Refused, and 40 stays on record. |
| An orphan holding a role nobody configured | Only the managed roles are taken. |
| A write refused for an orphan | Counted as not cleared, and reported once for the pass. |
| A second pass started mid-pass | Returns `SweepReport.skipped`, writes nothing, runs nothing. |
| An interval of `0`, `soon` or a fraction | The default interval, with the rejected value returned. |
| An interval that is not a number at all | The default, rather than the floor that spins or the ceiling that stops. |
| A last sweep recorded in the future | Sweeps now. Clock skew is doubt, and doubt sweeps. |
| A journal that cannot write | The sweep still runs and still decides correctly. |
| A member whose last account is unlinked between the batch read and the write | Held with `unlinked-mid-sweep`. Nothing is written, so the unlink's own stripping stands. |
| A member who finishes verifying between the opening read and the orphan filter | Not an orphan. The records are read again and the two readings are unioned. |
| The records refusing the second reading | The orphan pass refuses; the per-member pass already finished and stands. |
| The loop stopped while a pass is running | The pass finishes. Nobody is recorded as missed, and nothing accuses the chat service. |
| One member listing the same address twice | Asked of the chain once and summed once. |
