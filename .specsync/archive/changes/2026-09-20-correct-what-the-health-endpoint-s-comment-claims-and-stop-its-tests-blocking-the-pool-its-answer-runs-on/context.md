---
change: correct-what-the-health-endpoint-s-comment-claims-and-stop-its-tests-blocking-the-pool-its-answer-runs-on
artifact: context
---

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