---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: tasks
---

# Tasks

- [x] Request, response, route and limits as pure values.
- [x] The page as a string constant, with no interpolation anywhere in it.
- [x] The page script, fetching the name, code and expiry and writing them as
      text nodes.
- [x] Security headers on every response: CSP with no third-party origin,
      `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
      `frame-ancestors`.
- [x] The rate limiter, and a test that a shared client address does not lock
      everybody out.
- [x] The service and its routing, handing off to `Verify`.
- [x] The listener, with blocking work kept off the cooperative pool.
- [x] `TargetShapeTests`, proving no other target in this package is imported
      and no environment variable is read.
- [x] The living contract in `specs/verify-http/`.
- [x] Update `specs/verify/` where this target changes what that one can
      assume.
- [x] Update `README.md`, `docs/VERIFICATION.md` and
      `docs/WHAT-IT-TALKS-TO.md`: fourteen targets, four that open or accept a
      connection, three files calling `socket(`, and a page this package now
      does serve.
- [x] `swift test`, `specsync check --strict`, `hi check`, verify lane.