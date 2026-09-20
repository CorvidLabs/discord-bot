---
change: correct-what-the-health-endpoint-s-comment-claims-and-stop-its-tests-blocking-the-pool-its-answer-runs-on
artifact: testing
---

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