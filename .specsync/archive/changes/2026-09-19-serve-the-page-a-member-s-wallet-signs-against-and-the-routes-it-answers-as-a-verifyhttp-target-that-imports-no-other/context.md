---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
artifact: context
---

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
