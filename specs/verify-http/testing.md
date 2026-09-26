---
spec: verify-http.spec.md
---

## Automated Testing

`swift test --filter VerifyHTTPTests` runs this target's suite: 72 tests in 9
suites, all offline. The whole package runs 1203 tests in 100 suites. The
suite is run on Linux as well as on macOS, because Foundation is a different
implementation there and this target is the one that touches sockets.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `RoutingTests.swift` | Unit | Every route reachable by its own path and method and nothing else; every route carrying a session id being a `POST`; the right path with the wrong method as `405` and an unknown path as `404`; a query string refused on the page as well as on a call; a body that is not JSON and one whose session id is not an id, both refused with no handle; a body over the ceiling refused before anything parses it; a request that is not a request until its header block has been terminated; a declared body that has not all arrived; and a message with two content lengths that disagree, or one that is not a count, refused rather than framed by whichever the sender put last. |
| `PageTests.swift` | Unit | A content type carrying a newline replaced rather than written, so it cannot add a header of its own; the warning being in the static page rather than arriving with the card; the code explained; no inline script and no inline style; a policy naming no origin but this one and no `unsafe-inline`; the script removing the fragment from the address bar and writing the name as a text node; every element the script reaches for present on the page; one extension point with the name the documentation gives; `Referrer-Policy: no-referrer` and `Cache-Control: no-store` on the page and on a `404` alike; and the script and stylesheet served as themselves. |
| `CardTests.swift` | Unit | The account, the code, the challenge and the expiry read from the session's own `expiresAt`; a session before and after an address is connected; a pinned session; a live session with no name refused rather than rendered; an id that selects nothing and an id that has expired told apart; and a spent session answered with the reason that says nothing. |
| `ConnectTests.swift` | Unit | One address recorded and answered back; a second differing address refused without naming either; a pinned session refusing before a wallet asks anybody to sign; an address another member holds refused and asked about exactly once on this path; an address the program could not read about refused `503` rather than treated as free; an address no Algorand tool would accept as the page's mistake rather than a failed proof; and a connect with no address costing the session nothing. |
| `SubmitTests.swift` | Unit | A real signature, produced by the dependency's own signing path, checked and handed over as awaiting confirmation; a proof for an account another member holds refused `409` with nothing handed over, although the connect had already been refused once; a proof the program cannot answer the claim question for held back with the same `503`; a proof the host could not hold reported as that; an unreadable blob as `422` carrying the module's own sentence; a submission against a session nothing was connected to saying nothing about it; the session's three attempts ending in a `429` whose sentence is not the rate limit's; a prompt minted for somebody else as a hard stop; the one authorising key retry taken, with the read counted; and the same submission refused with nothing asked when no chain reader is configured. |
| `BearerCredentialTests.swift` | Unit | A whole flow across five answers with the session id in none of the bytes written; the id in none of the lines logged, with the handle in them instead; the handle equal to `Verify`'s own for the same session; the handle not being an abbreviation of the id; the link carrying the id after the `#` and nothing before it; and a base that could not carry a fragment, or is not `https`, refused naming the variable. |
| `RateLimitTests.swift` | Unit | A sliding window where asking is recording; a key table that does not grow for ever, including a table of ten thousand keys every one of which is live, where the least recently seen are dropped and the one spending right now keeps its history; the page limited per source with another source unaffected; the submit route limited per source and per session, the session refusal carrying a handle and the source refusal carrying none; a wrong path and a query string each counted against nobody; the standard budgets serving thirty page loads and thirty cards from one source, which is what "sized for an instance" means; and a limit or a window of nothing refused at construction. |
| `TargetShapeTests.swift` | Source | No import of another target in this package and a manifest that says the same thing; a clock read in the listener and nowhere else, exactly once; no force unwrap, forced try or forced cast; no lock and no `@unchecked Sendable`; and the page, the stylesheet and the script held in raw literals, which is where "nothing is interpolated into the page" is actually checkable. |
| `ListenerTests.swift` | Integration | The page served over a real loopback socket with its headers; a body that arrives in a second segment read rather than answered as empty; rubbish answered with the status it actually earns and the connection closed; a request that can never parse answered when that is known rather than when the budget runs out; a peer dripping a byte every four tenths of a second answered on the budget rather than on its own schedule; connections in flight bounded, the ones over it closed at accept in milliseconds rather than held, and the slots coming back; port zero accepted and `isServing` following the bind and the stop; an address this machine cannot bind refused; a second bind of the same port refused, which is how a second copy of the bot finds out; and stopping giving the port back so the next bind succeeds. |

Every key in the suite is generated inside the test from the platform's own
randomness, every signature is produced by the dependency's own signing path,
and every blob by its own encoder, so the production path runs unchanged. The
only socket any test opens is a loopback bind on port zero.

## What this evidence does not cover

- **No test here drives a browser.** The page and the script are asserted as
  text: that the warning is in the static HTML, that the script removes the
  fragment and writes a text node, that nothing is inline. Whether the page
  is usable on a phone, and whether a real wallet round trip works through
  the adapter, is the manual check below and cannot be automated here.
- **No wallet connector is exercised, because none is bundled.** The suite
  proves the fallback path: an address typed in and a blob pasted. An
  operator's own adapter is their asset and their test.
- **The chat command, the pending record and the confirmation are not
  here.** They are the program's, and `specs/verify/testing.md` still
  records them as unevidenced.
- **The rate limit is proved per source and per session, in one process.** A
  host running two instances behind one address owes the same bound at a
  level nothing here can see.
- **The listener's two bounds are proved at a scale a suite can run.** Two
  connections in flight and a one second peer budget, not the hundreds a
  real flood arrives as. What the tests pin is that the bound exists, that
  it is taken before a connection is queued, and that the budget is the
  request's; how a machine behaves with ten thousand sockets open is not
  something this suite can say.
- **Nothing here proves an operator configured TLS**, and the listener
  cannot tell.

## Manual Testing

- On a real handset, in the chat client's own in-app browser and in an
  external one: open a link, read the page, and record whether the named
  account reads as somebody else's to a person who was not told what to look
  for.
- Send one tester's link to a second tester and record what they do.
- With an operator's own wallet adapter loaded, run the flow end to end with
  each supported wallet and record whether the blob that comes back is a
  shape the reader accepts.
- Put the listener behind the operator's own terminator and confirm the page
  loads over `https`, since a wallet connector will not run otherwise.
