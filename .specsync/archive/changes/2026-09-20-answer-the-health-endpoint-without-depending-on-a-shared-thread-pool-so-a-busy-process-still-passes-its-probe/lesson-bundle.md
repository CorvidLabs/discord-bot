# Lesson bundle — answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Answer the health endpoint without depending on a shared thread pool, so a busy process still passes its probe
- **Kind**: BugFix
- **Specs**: runtime
- **Paths**: Sources/Runtime/HealthListener.swift
- **Acceptance**: The health endpoint answers when the process's shared thread pools are saturated. Its accept loop and each connection read run on threads of their own rather than on libdispatch queues, because both block and that pool is bounded by the machine's cores. The answer is written on the thread the connection already owns rather than handed to a Task on the cooperative pool, so a probe is answered even when every cooperative thread is busy, which is exactly the moment an orchestrator is deciding whether to kill the process. Proved by the existing HealthListenerTests passing on a two-core Linux container, where they previously timed out with the connection accepted and read.

## Evidence

- Verification commit: `e6125e48afe23b6ef36be7516a7c206560e14a35`
- Base commit: `129c7f231b624f250703de257979072b64661d18`
- Verified by: `specsync check --spec runtime`

## From the change's context.md

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

## From the change's design.md

# Design

Three changes, all of the same shape: stop borrowing a shared pool for work
that blocks.

1. **The accept loop gets a thread.** It runs until the listener stops, so on
   a queue it holds a libdispatch worker for the listener's whole life.
2. **Each connection read gets a thread.** It blocks for up to the client's
   whole budget. The bound on how many happen at once is unchanged and is
   what stops a flood starting an unbounded number of them.
3. **The answer is written on the thread that read the request**, waiting for
   the async work through a semaphore rather than handing the socket to
   `Task { }`.

The third is the one worth arguing about, because waiting on a semaphore for
async work is ordinarily a smell. It is right here: the thread is one this
connection already owns and nothing else can use, and the alternative makes
answering depend on a pool the rest of the program is competing for. A health
endpoint that stops answering when the process is busy has inverted its own
purpose — that is the moment its answer matters most, because an orchestrator
is deciding whether to kill the process.

`SocketHTTPListener` in `SurfaceDiscord` already worked this way. This brings
the health endpoint in line with it rather than inventing anything.

## From the change's testing.md

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

## Where these lessons go

- `specs/runtime/context.md`
