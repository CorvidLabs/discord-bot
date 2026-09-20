---
change: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
artifact: testing
---

# Testing

No new test, and no changed requirement. The existing `HealthListenerTests`
already cover the endpoint's behaviour; what changed is that they now pass
under a constraint they previously failed.

## How it was verified

`swift test` on macOS, and in a Swift 6.1 Linux container limited to two
CPUs, which is what a hosted runner has and what an earlier full-core
container did not reproduce. Before: connections were accepted and read and
never answered, and every probe waited out its timeout. After: the suite
passes.

The endpoint's own contract is unchanged, which is why this change declares
no spec delta: the routes, the status codes, the body and the ordering are
all exactly as documented. Only the threads that carry them are different.