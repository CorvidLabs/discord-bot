---
change: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
artifact: plan
---

# Plan

1. Replace the accept queue with a detached thread.
2. Replace the connection queue with a detached thread per connection.
3. Write the answer on that thread, waiting for the async work.
4. Delete both queues rather than leaving them unused.
5. Verify on Linux under a two-core cap, which is the condition that
   reproduces the failure. A full-core container does not.