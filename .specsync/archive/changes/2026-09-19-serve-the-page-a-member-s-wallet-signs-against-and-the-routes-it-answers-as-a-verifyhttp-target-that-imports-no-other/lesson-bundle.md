# Lesson bundle — serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Serve the page a member's wallet signs against, and the routes it answers, as a VerifyHTTP target that imports no other target in this package and that nothing links yet
- **Kind**: Feature
- **Specs**: verify-http, verify
- **Paths**: Sources/VerifyHTTP, Tests/VerifyHTTPTests, Package.swift, Package.resolved, .specsync/config.toml, specs/verify-http, specs/verify
- **Acceptance**: A member's wallet can be served the page and its signature accepted over HTTP from the operator's own machine, without the page interpolating any value into its markup, loading any third-party script, or the target reaching any other target in this package. Concretely: the page is a string constant so no missing resource bundle can trap the process; the account name, code and expiry are written as text nodes by the script rather than templated server-side; responses carry a Content-Security-Policy with no third-party origin plus nosniff, X-Frame-Options DENY and frame-ancestors; a rate limiter bounds the routes; TargetShapeTests reads the target's own sources and fails if it ever imports Store, Chain, Gating, Reserve, Games, Surface, SurfaceDiscord, Runtime, DiscordBM or Algorand, or reads an environment variable; and no executable links the target, so the program binds no listener of its and /verify stays unregistered. 1264 tests in 105 suites pass, and specsync check --strict reports 225/225 files.

## Evidence

- Verification commit: `37faffff926ea495e708d31b69d614771e1da844`
- Base commit: `8ea3bf3a95fd9c935675e5ff12457529f43068d3`
- Verified by: `specsync check --spec verify --spec verify-http`

## From the change's context.md

# Context

**The page is a constant and that is a decision, not a convenience.**
`Bundle.module` traps rather than returning nil when the bundle is not beside
the binary. The bot this was ported from shipped a page route that took the
whole process down the first time somebody loaded it, on a deployment that
looked fine. A string cannot be missing.

**No interpolation is a cheaper guarantee than correct escaping.** The obvious
design templates the member's chat account name into the page server-side, and
then the target owns an escaping rule for ever, on the one page where getting
it wrong means script execution in front of somebody about to sign. Fetching
the name and writing it as a text node moves the problem to a browser API that
cannot produce markup. The page being byte-identical for every member is a
second benefit: a suspicious operator can diff the served bytes against this
repository.

**Not vendoring a wallet connector costs usability, on purpose.** Pasting a
signed transaction is genuinely clumsy on a phone. It was still chosen over
bundling third-party browser code, because the repository's answer to "should
I install this" is that you can read what it depends on, and several hundred
kilobytes of minified connector on the signing page is the worst place to make
that answer weaker. The documentation says the paste path is clumsy rather
than describing it as a feature.

**The host is a struct of closures rather than a protocol.** Everything this
target can cause to happen is then visible where the host is built. There is
no closure that writes to a store, which is why a page cannot record a member
even if somebody later wants it to.

**Landing unwired is the same discipline #27 used.** The chat surface was
built, reviewed and merged before anything linked it. Reviewing a signing page
that cannot be reached is easier than reviewing one that is live, and the
wiring change afterwards is about wiring alone.

## Why both deltas say `Modified` rather than `Added`

The target, its tests and its living contract in `specs/verify-http/` were
written before this workspace existed, so by the time the delta was authored
the living tree already held `REQ-verify-http-001` through `-009`. A delta
describes a move **from the living tree**, and the tree it is moving from
already has them, so `## Added` is refused and `## Modified` is correct.

That is worth saying plainly rather than leaving as a curiosity, because it is
the same ordering that stranded the workspace #21 merged without: the
implementation ran ahead of the lifecycle. The cost here was small because the
change was caught before merge. The cost there was a red audit on `main` for
several commits, and it is the reason `finalize` before merge is not optional.

## From the change's design.md

# Design

## The shape

`VerifyHTTP` is a library target with a listener, a router, a page and a rate
limiter. It depends on `Verify` and `Crypto` and on nothing else in this
package.

The host arrives as `VerifyHTTPHost`, a struct of `@Sendable` closures:
`chatAccountName`, `addressAlreadyClaimed`, `authorizingKey`,
`recordPendingProof`. Everything this target can cause to happen is therefore
visible at the one call site that builds it, and a reader does not have to
trace a protocol hierarchy to find out whether a page can write to a database.
It cannot, because there is no closure that would let it.

## Three decisions, and what each one refuses

**The page is a `String` constant.** Not a SwiftPM resource. `Bundle.module`
traps when the bundle is not beside the binary; a string cannot be missing.
This is a direct answer to research item 3.

**No value is interpolated into the HTML.** The account name, the code and the
expiry are fetched by the page's own script and written as text nodes. There
is no template, so there is no escaping rule to get right, and a member whose
name is markup is a member whose name is text. The page is byte-identical for
every member, which also means it can be compared against the repository by
anyone suspicious of the deployment. This answers research item 1.

**No wallet connector is vendored.** Bundling hundreds of kilobytes of
third-party browser code into a repository whose answer to "should I install
this" is that you can read what it depends on would undo the answer. The page
ships two paths instead: an operator supplies their own connector and widens
`script-src`, or a member pastes a signed transaction from a tool they already
use. The second is clumsy on a phone and the documentation says so rather than
pretending otherwise. This answers research item 2.

## What the target may reach, as a test

An absence cannot be demonstrated by using the code, so
`Tests/VerifyHTTPTests/TargetShapeTests.swift` reads the target's own sources
and fails if it ever imports `Store`, `StoreSQLite`, `Chain`, `Gating`,
`Reserve`, `Games`, `Surface`, `SurfaceDiscord`, `Runtime`, `DiscordBM` or
`Algorand`, or reads an environment variable. `Verify` has the same test for
the same reason: a setting that changes how a signature is checked is one
setting away from a setting that skips it.

## From the change's testing.md

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

## Where these lessons go

- `specs/verify-http/context.md`
- `specs/verify/context.md`
