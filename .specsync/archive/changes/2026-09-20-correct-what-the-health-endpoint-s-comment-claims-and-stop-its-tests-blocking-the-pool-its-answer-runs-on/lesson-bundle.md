# Lesson bundle — correct-what-the-health-endpoint-s-comment-claims-and-stop-its-tests-blocking-the-pool-its-answer-runs-on

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Correct what the health endpoint's comment claims, and stop its tests blocking the pool its answer runs on
- **Kind**: BugFix
- **Specs**: runtime
- **Paths**: Sources/Runtime/HealthListener.swift, Tests/RuntimeTests/HealthListenerTests.swift
- **Acceptance**: The comment beside the health endpoint's answer says what the code does rather than what was hoped for it: waiting on the connection's own thread gives back the read slot only once the answer is out, and does not make answering independent of the cooperative pool, because the answer reaches an actor and must run there. The endpoint's tests no longer block that pool: the loopback request helper runs on a thread of its own rather than a dispatch queue, and the two direct blocking calls go through the same helper. Verified by the suite passing on Linux with two visible cores, which is the condition under which blocking the pool deadlocks the listener.

## Evidence

- Verification commit: `411797b97538855fa1db2edfe9b42deaac3452a8`
- Base commit: `02c2eee20df6387dd339d3ebd59c93b8dac6baed`
- Verified by: `specsync check --spec runtime`

## From the change's context.md

# Context

**A comment that claims more than the code does is worse than no comment.**
The change before this one moved the endpoint's answer onto the connection's
own thread and said, in the source and in its own pull request, that this
made the endpoint answer "when the process is busy" and independently of the
cooperative pool. That is not true. `Task { }` runs its body on the
cooperative pool whoever waits for it, and the answer reaches an actor, so
the pool is on its path either way. Waiting on the connection's thread buys
one real thing — the read slot is given back only once the answer is out, so
the bound on concurrent reads means what it says — and it buys nothing else.
The comment now says that.

The claim was wrong in a way that would have cost the next reader time: it
describes a property somebody could reasonably rely on, and a future change
that removed the wait would look like it was breaking that property rather
than an accounting detail.

**The tests were the ones breaking the rule.** Blocking a cooperative thread
is the one thing a caller must not do, and a test is a caller. The endpoint's
request helper bridged through a `DispatchQueue`, which is the other bounded
pool, and two call sites blocked directly inside `async` tests. On a
two-core runner that is the whole pool, and the listener's answer is then
never scheduled: the connection is accepted, the request is read, and nobody
is left to reply. The listener was correct throughout.

**How to reproduce a pool-starvation bug, which is the part worth keeping.**
`docker run --cpus=2` does **not** do it: that caps CPU time through the CFS
quota while `nproc` still reports the host's count, and both pools size
themselves from the visible count. Two earlier verifications passed for that
reason and were contradicted by CI. `--cpuset-cpus="0,1"` is the flag that
limits visible cores, and under it the failure reproduces in seconds.

## From the change's testing.md

# Testing

No new test and no changed requirement. The endpoint's existing suite covers
its behaviour; what changed is the harness underneath it.

## How it was verified

`swift test` on macOS, and on Linux in a Swift 6.1 container pinned to two
visible cores with `--cpuset-cpus="0,1"`. The `--cpus` flag does not
reproduce the condition and was the reason two earlier checks reported green
against a red CI.

Run alone under that pin, the affected suites pass in about a second. Run
with the whole tree pinned to the same two cores, two wall-clock assertions
elsewhere overrun their bounds; that is the harness competing with itself
rather than the listener, and CI, which is not pinned that hard, does not
show it.

## Where these lessons go

- `specs/runtime/context.md`
