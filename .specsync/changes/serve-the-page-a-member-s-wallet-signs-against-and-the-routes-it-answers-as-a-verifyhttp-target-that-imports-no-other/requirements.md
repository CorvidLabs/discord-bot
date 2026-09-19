---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: requirements
---

# Requirements

The living contract is `specs/verify-http/`, which this change adds:
`REQ-verify-http-001` through `REQ-verify-http-009` state the page, the
routes, the headers, the rate limit, the handoff to `Verify` and the target's
own boundary.

What this artifact records is the boundary those requirements are written
against, because it is the part a future change is most likely to erode:

- The target imports **no** other target in this package, and reads **no**
  environment variable. Both are asserted by a test that reads the target's
  own sources, because neither absence can be demonstrated by using the code.
- The page interpolates **no** value into its markup and loads **no**
  third-party script.
- Nothing links the target, so the program binds no listener of its and
  `/verify` is not registered.

A change that wants to relax any of those is a change to this contract, not an
implementation detail.