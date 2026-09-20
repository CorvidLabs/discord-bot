---
change: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
artifact: research
---

# Research

The endpoint was written against a rule this package already had: nothing
that blocks runs on the cooperative pool. It followed half of it. The accept
loop and the connection reads were moved off the cooperative pool and onto
libdispatch queues, which is not the same thing as off a shared pool.

Two pools are involved and the distinction is the whole bug.

- **libdispatch's pool** runs blocks put on a `DispatchQueue`. It is bounded,
  roughly by the machine's cores. A block that never returns holds a worker
  for ever.
- **The cooperative pool** runs `Task` bodies. It is bounded by cores too,
  and a synchronous blocking call made from an `async` function holds one of
  its threads for as long as it blocks.

The endpoint used the first for its loop and its reads, and the second for
its answer. Both are shared, and both are small.

It survived on a developer machine because a pool sized to eight or ten cores
absorbs a handful of blocked threads. It failed on a two-core runner, where
the same code has two.