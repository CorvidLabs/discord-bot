---
id: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
state: archived
type: feature
base_commit: 8ea3bf3a95fd9c935675e5ff12457529f43068d3
---

# Serve the page a member's wallet signs against, and the routes it answers, as a VerifyHTTP target that imports no other target in this package and that nothing links yet

## Intent

Serve the page a member's wallet signs against, and the routes it answers, as a VerifyHTTP target that imports no other target in this package and that nothing links yet

## Affected Canonical Specs

- `verify-http`
- `verify`

## Acceptance Criteria

- A member's wallet can be served the page and its signature accepted over HTTP from the operator's own machine, without the page interpolating any value into its markup, loading any third-party script, or the target reaching any other target in this package. Concretely: the page is a string constant so no missing resource bundle can trap the process; the account name, code and expiry are written as text nodes by the script rather than templated server-side; responses carry a Content-Security-Policy with no third-party origin plus nosniff, X-Frame-Options DENY and frame-ancestors; a rate limiter bounds the routes; TargetShapeTests reads the target's own sources and fails if it ever imports Store, Chain, Gating, Reserve, Games, Surface, SurfaceDiscord, Runtime, DiscordBM or Algorand, or reads an environment variable; and no executable links the target, so the program binds no listener of its and /verify stays unregistered. 1264 tests in 105 suites pass, and specsync check --strict reports 225/225 files.

## No-spec Rationale

Not applicable
