---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: design
---

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