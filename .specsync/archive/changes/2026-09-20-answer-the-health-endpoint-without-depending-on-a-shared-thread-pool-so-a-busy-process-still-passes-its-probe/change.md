---
id: answer-the-health-endpoint-without-depending-on-a-shared-thread-pool-so-a-busy-process-still-passes-its-probe
state: archived
type: bug_fix
base_commit: 129c7f231b624f250703de257979072b64661d18
---

# Answer the health endpoint without depending on a shared thread pool, so a busy process still passes its probe

## Intent

Answer the health endpoint without depending on a shared thread pool, so a busy process still passes its probe

## Affected Canonical Specs

- `runtime`

## Acceptance Criteria

- The health endpoint answers when the process's shared thread pools are saturated. Its accept loop and each connection read run on threads of their own rather than on libdispatch queues, because both block and that pool is bounded by the machine's cores. The answer is written on the thread the connection already owns rather than handed to a Task on the cooperative pool, so a probe is answered even when every cooperative thread is busy, which is exactly the moment an orchestrator is deciding whether to kill the process. Proved by the existing HealthListenerTests passing on a two-core Linux container, where they previously timed out with the connection accepted and read.

## No-spec Rationale

The endpoint's contract is unchanged: the same routes, the same status codes, the same body, the same ordering guarantees. What changes is which threads do the work, so that the documented behaviour holds when the process's shared pools are saturated instead of only when they are idle. A requirement that already says the endpoint answers does not need rewording because it now answers under load; it needed the implementation to stop borrowing a pool it was competing for.
