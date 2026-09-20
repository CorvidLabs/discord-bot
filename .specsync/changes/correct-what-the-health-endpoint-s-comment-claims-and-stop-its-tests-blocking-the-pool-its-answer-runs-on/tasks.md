---
change: correct-what-the-health-endpoint-s-comment-claims-and-stop-its-tests-blocking-the-pool-its-answer-runs-on
artifact: tasks
---

# Tasks

- [x] Correct the comment beside the answer so it describes what the code
      does rather than what was hoped for it.
- [x] Move the loopback request helper off its dispatch queue and onto a
      thread of its own.
- [x] Route the two remaining direct blocking calls through the same helper.
- [x] `swift test` on macOS and on Linux with two visible cores.