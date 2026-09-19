---
change: re-read-what-every-member-holds-and-move-their-roles-to-match-as-a-sweep-module-with-the-loop-the-batching-the-run
artifact: testing
---

# Testing

Every test is offline. The chat gateway is a double over `String`, the chain
reader is a double, and the clock arrives as a parameter, so a sweep replays
exactly.

## Requirement evidence

| Requirement | Evidence | What it proves |
|-------------|----------|----------------|
| REQ-sweep-001, REQ-sweep-024 | `Tests/SweepTests/SweepLoopTests.swift` | Every member on record is visited and the decision applied; one address listed twice for a member is one balance. |
| REQ-sweep-002, REQ-sweep-003, REQ-sweep-004, REQ-sweep-005 | `Tests/SweepTests/NeverDemoteTests.swift` | An unread fact holds at every level: a partial batch, a short liquidity reading and a collection catalogue that did not answer each hold rather than demote. |
| REQ-sweep-006 | `Tests/SweepTests/OrphanSweepTests.swift` | Only configured roles are touched; everything else survives, including through the orphan pass. |
| REQ-sweep-007, REQ-sweep-008, REQ-sweep-009 | `Tests/SweepTests/OrphanSweepTests.swift` | The guard refuses on an empty directory and on a halved one; a refusal leaves the previous baseline; an unreadable baseline refuses rather than reading as a first run. |
| REQ-sweep-010, REQ-sweep-011, REQ-sweep-012 | `Tests/SweepTests/SweepRecordingTests.swift` | The record is written before and after, so an unfinished sweep never reads as finished; a sweep that threw reads as finished with a reason; unchanged members split into held and missed with named reasons. |
| REQ-sweep-013, REQ-sweep-014, REQ-sweep-015 | `Tests/SweepTests/SweepRecordingTests.swift` | Every line carries the run id; problems survive a restart, newest first and capped by count; each names something an operator could change. |
| REQ-sweep-016 | `Tests/SweepTests/CallerAndBalanceTests.swift` | Sweep reads are the instance's own work and carry no member share. |
| REQ-sweep-017, REQ-sweep-018, REQ-sweep-019, REQ-sweep-023 | `Tests/SweepTests/SweepScheduleTests.swift`, `Tests/SweepTests/SweepLoopTests.swift` | One deduplicated batch per pass; a restart inside the interval waits out the remainder; two passes never overlap; stopping leaves a pass in flight to finish. |
| REQ-sweep-020, REQ-sweep-021, REQ-sweep-022 | `Tests/SweepTests/MidSweepChangeTests.swift` | Only a complete reading is written back; accounts are re-read before the write and a list that emptied holds it; the orphan pass re-reads and treats anybody in either reading as known. |
| REQ-surface-019 | `Tests/SurfaceDiscordTests/RoleListTests.swift` | The list sent is the managed half of the target plus unmanaged roles the member holds; `held` is never granted; a hand-granted badge survives. Five assertions that fail against the previous behaviour. |

## The whole suite

1269 tests in 106 suites pass. `specsync check --strict` reports 8/8 specs and
226/226 files.