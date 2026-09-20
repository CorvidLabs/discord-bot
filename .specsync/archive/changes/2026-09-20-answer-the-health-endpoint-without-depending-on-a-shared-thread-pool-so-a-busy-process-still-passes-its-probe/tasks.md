---
change: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
artifact: tasks
---

# Tasks

- [x] Accept loop on `Thread.detachNewThread`.
- [x] Each connection read on a thread of its own.
- [x] The answer written on that thread rather than in a `Task`.
- [x] Both dispatch queues removed.
- [x] `swift test` on macOS.
- [x] `swift test` on Linux under a two-core cap.