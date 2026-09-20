---
change: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
artifact: context
---

# Context

**Two pools, and moving work from one to the other is not a fix.** The
endpoint moved its blocking work off the cooperative pool and onto
libdispatch, which is also shared and also bounded by cores. The rule worth
writing down is not "not the cooperative pool" but "not a shared pool":
anything that blocks for an unbounded time owns a thread, and the only
question is whose.

**Why it passed locally and failed on CI.** Both pools are sized from the
core count. A developer machine has eight or more and absorbs a few blocked
threads; a hosted runner has two. The first attempt at this fix was verified
in a Linux container with every core available, which reproduced the
operating system and not the constraint, and it reported green while CI
stayed red. The condition to reproduce is `--cpus=2`, not merely Linux.

**Waiting on a semaphore for async work is usually wrong and is right here.**
The thread doing the waiting belongs to this connection and to nothing else,
so nothing shared is held. What it buys is that the answer no longer needs
the cooperative pool, and the endpoint therefore answers when the process is
saturated. That is when its answer decides whether the process is killed.

**This was found through a test suite and is not a test-only problem.** The
same starvation in production means `/health` stops answering under load and
an orchestrator restarts a process that was working.