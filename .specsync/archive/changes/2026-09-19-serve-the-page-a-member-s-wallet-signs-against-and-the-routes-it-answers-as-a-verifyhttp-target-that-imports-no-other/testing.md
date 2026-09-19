---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: testing
---

# Testing

Every test here is offline: no key, no funded account, no chat server, no
network. The listener is exercised over loopback by `LoopbackClient` in the
test target.

## Requirement evidence

| Requirement | Evidence | What it proves |
|-------------|----------|----------------|
| REQ-verify-http-001 | `Tests/VerifyHTTPTests/PageTests.swift` | The page is served as a constant, is byte-identical for every member, and contains no interpolated value. |
| REQ-verify-http-002 | `Tests/VerifyHTTPTests/PageTests.swift` | The script writes the name, code and expiry as text nodes, so a member's own name cannot become markup. |
| REQ-verify-http-003 | `Tests/VerifyHTTPTests/CardTests.swift` | Every response carries the CSP with no third-party origin, `nosniff`, `X-Frame-Options: DENY` and `frame-ancestors`. |
| REQ-verify-http-004 | `Tests/VerifyHTTPTests/RoutingTests.swift` | Each route answers only its own method and path; anything else is refused rather than falling through. |
| REQ-verify-http-005 | `Tests/VerifyHTTPTests/ConnectTests.swift` | The connect route hands a member a challenge bound to their session. |
| REQ-verify-http-006 | `Tests/VerifyHTTPTests/SubmitTests.swift` | A submitted signature reaches `Verify` unchanged and its refusals are reported without being reordered or softened. |
| REQ-verify-http-007 | `Tests/VerifyHTTPTests/RateLimitTests.swift` | The rate limit bounds the routes, and a shared client address behind a proxy cannot lock the portal out for everybody. |
| REQ-verify-http-008 | `Tests/VerifyHTTPTests/BearerCredentialTests.swift` | A credential is compared without leaking its length or content through timing or through an error body. |
| REQ-verify-http-009 | `Tests/VerifyHTTPTests/TargetShapeTests.swift` | The target imports no other target in this package and reads no environment variable, proved by reading its own sources. |

## The whole suite

1264 tests in 105 suites pass. `specsync check --strict` reports 8/8 specs and
225/225 files.