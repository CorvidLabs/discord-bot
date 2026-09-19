---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
module: verify
---

# Semantic delta: verify

## Modified

### REQUIREMENT REQ-verify-009

The obligations this module states for a host — the page a wallet signs
against and the routes it answers — SHALL remain obligations of a host rather
than of this module, and this module SHALL continue to reach no network, read
no clock, hold no key and read no setting. What changes is that a host now
exists in this package, `verify-http`, which depends on this module while this
module SHALL continue to know nothing about it. The dependency SHALL run in
that direction only, and `specs/verify/testing.md` SHALL record which of the
host obligations that target now evidences and which remain unevidenced,
rather than marking them all satisfied because a host appeared.

Acceptance Criteria
- `Tests/VerifyTests/TargetShapeTests.swift` proves this module still
  constructs no client, names no request type, logs nothing and reads no
  environment variable, unchanged by the arrival of a host.
- `Tests/VerifyHTTPTests/TargetShapeTests.swift` proves the dependency runs
  one way: the host imports this module, and this module imports nothing of
  the host's.
- `specs/verify/testing.md` names the obligations `verify-http` now evidences
  and leaves the chat command, the pending record and the operator's release
  path marked unevidenced.
