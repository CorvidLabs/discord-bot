---
id: correct-what-the-health-endpoint-s-comment-claims-and-stop-its-tests-blocking-the-pool-its-answer-runs-on
state: archived
type: bug_fix
base_commit: 02c2eee20df6387dd339d3ebd59c93b8dac6baed
---

# Correct what the health endpoint's comment claims, and stop its tests blocking the pool its answer runs on

## Intent

Correct what the health endpoint's comment claims, and stop its tests blocking the pool its answer runs on

## Affected Canonical Specs

- `runtime`

## Acceptance Criteria

- The comment beside the health endpoint's answer says what the code does rather than what was hoped for it: waiting on the connection's own thread gives back the read slot only once the answer is out, and does not make answering independent of the cooperative pool, because the answer reaches an actor and must run there. The endpoint's tests no longer block that pool: the loopback request helper runs on a thread of its own rather than a dispatch queue, and the two direct blocking calls go through the same helper. Verified by the suite passing on Linux with two visible cores, which is the condition under which blocking the pool deadlocks the listener.

## No-spec Rationale

No requirement changes. One change is a comment that claimed more than the code does, and the other is test code, which the canonical contract does not describe. The endpoint's routes, status codes, body and ordering are untouched.
