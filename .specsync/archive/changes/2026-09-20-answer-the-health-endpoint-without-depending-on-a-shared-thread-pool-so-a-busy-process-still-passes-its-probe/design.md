---
change: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
artifact: design
---

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