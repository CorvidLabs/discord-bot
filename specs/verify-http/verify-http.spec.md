---
module: verify-http
version: 2
status: active
files:
  - Sources/VerifyHTTP/VerifyHTTPHost.swift
  - Sources/VerifyHTTP/VerifyHTTPLimits.swift
  - Sources/VerifyHTTP/VerifyHTTPListener.swift
  - Sources/VerifyHTTP/VerifyHTTPReporting.swift
  - Sources/VerifyHTTP/VerifyHTTPRequest.swift
  - Sources/VerifyHTTP/VerifyHTTPResponse.swift
  - Sources/VerifyHTTP/VerifyHTTPRoute.swift
  - Sources/VerifyHTTP/VerifyHTTPService.swift
  - Sources/VerifyHTTP/VerifyLink.swift
  - Sources/VerifyHTTP/VerifyPage.swift
  - Sources/VerifyHTTP/VerifyPageScript.swift
  - Sources/VerifyHTTP/VerifyRateLimiter.swift
  - Sources/VerifyHTTP/VerifySessionHandle.swift
db_tables: []
depends_on: ["verify"]
---

# VerifyHTTP

## Purpose

Give verification a surface a member can reach.

`Verify` decides whether a proof is a proof and reads nothing to do it: no
clock, no network, no store, no setting. That is what makes it testable and it
is also why, on its own, nobody can verify anything with it. A wallet talks to
a browser, and a browser needs a page to load and a route to post to. This
target is that page and those routes, and nothing else.

It carries the five obligations `Verify` names and cannot hold up itself.

1. **A page a wallet signs against, and a route that takes the signed blob.**
2. **The session id is a bearer credential**: delivered once in the reply only
   the member can see, carried to the page in a fragment, never in a query
   string, never in a log, and the page served under `Referrer-Policy:
   no-referrer`.
3. **The page names the chat account the session belongs to**, with a warning
   beside it in plain words: only continue if that account is yours, and
   nobody should ever send you this link.
4. **A rate limit on every route**, because the module below deliberately has
   none and the story about one member spending the day's chain budget
   depends on it.
5. **A refusal carries a reason and a non-reversible handle**, and never the
   session id.

**Why the named account is on the page rather than in the signed bytes.** The
attack it answers is a relayed prompt: somebody runs the command themselves
and sends the link to a member. The victim is then standing on the operator's
**real** page, on the real origin, and the attacker's whole contribution is a
link, so the page cannot be made to lie about whose session it is. A name on
it is the only form of this defence a first-time verifier can use, because
they have no value to recognise yet. Carrying the same name inside the signed
bytes would additionally defend a **counterfeit** page, which is a different
attack with a different answer, and it would put an identifier that came from
a person below the chat boundary. What is left over is a member who does not
read the warning, which is real, is largely user error, and is said here
rather than left to be discovered.

**What it deliberately does not link.** `Verify` and `Crypto`, and nothing
else in this package. Not `Store`, so serving a page cannot record a member.
Not `Chain`, so serving a page cannot spend a chain request. Not `Surface`,
which would reach all three through one import. The four reads it cannot make
for itself arrive as closures in `VerifyHTTPHost`, which is also what lets the
whole surface be exercised with no token, no node and no database.

**What an operator still has to add.** There is no wallet connector here.
Bundling one would mean vendoring a third party browser library of some
hundreds of kilobytes into a repository whose answer to "should I install
this" is that you can read what it depends on. So the page ships two paths: an
operator drops their own connector in and sets `verifyWalletAdapter` on
`window`, or the member pastes a signed transaction produced by whatever tool
they already use. The second works today and is clumsy on a phone; the first
is what a public community needs, and it is an operator's own asset plus a
widened `script-src`, not a change in here.

## Public API

Every exported symbol of the `VerifyHTTP` library target, one row per name.
Where several types share a name the row is merged and says which type each
sense belongs to.

| Export | Description |
|--------|-------------|
| `VerifyHTTPRequest` | One HTTP request, parsed, with no socket near it, so every rule this surface applies is a unit test. |
| `maximumRequestBytes` | The most bytes one request may be, headers and body together, so a peer cannot make this process hold memory by declaring a body it never sends. |
| `contentLengthHeader` | The header the read loop's framing is decided by, which is why it is the one header this parser is strict about. |
| `method` | `GET` or `POST` as it arrived on `VerifyHTTPRequest`; on `VerifyRouting`, the one method a route is reached with. |
| `target` | The request target, query string included, exactly as it arrived. |
| `headers` | Header names lowercased, values trimmed. |
| `body` | Everything after the first empty line on `VerifyHTTPRequest`; the answer's body on `VerifyHTTPResponse`. |
| `path` | The target with any query string taken off on `VerifyHTTPRequest`; on `VerifyRouting`, the path a route is served at. |
| `carriesQuery` | Whether the target carries a query string at all. Asked, and never read: a session id may never be in one, and a surface that serves a request carrying one has already taught somebody the wrong shape. |
| `declaredBodyByteCount` | What the sender said the body is, in bytes, or nil. |
| `isComplete` | Whether the whole declared body has arrived, which is what the read loop asks after every read. |
| `parse` | One request out of what has arrived so far, answering nil until the header block has been terminated, and nil for a message whose framing cannot be trusted: a `Content-Length` that is not a count, or two of them that disagree (RFC 9112 6.3). Taking the last of two would let the sender pick which bytes this surface reads as the body. |
| `VerifyHTTPResponse` | One HTTP answer as a value, so what a route decides can be asserted without a socket. |
| `securityHeaders` | The headers every answer carries, including `Referrer-Policy: no-referrer` and `Cache-Control: no-store`. On the value rather than added by whatever writes the socket, because a header that protects a bearer credential is not something to leave to a second place. |
| `contentSecurityPolicy` | What the page may reach: this origin and nothing else, and no inline script, which is why the script and the stylesheet are routes of their own. |
| `status` | The status code. |
| `contentType` | What the body is. |
| `asset` | An answer carrying one of this target's own static assets. |
| `json` | An answer carrying JSON. |
| `wireBytes` | The whole answer as bytes, headers and all, built here so the headers a test asserts are the bytes a browser receives. The content type is the one value in it a caller chose, so a newline in it is replaced rather than written: this is a library other programs serve the same flow with, and a header value carrying one ends the header block early. |
| `fallbackContentType` | What a content type that could not be written into a header block safely is replaced by. A type rather than nothing, because a browser handed none sniffs one and `nosniff` then leaves it with a body it will not render. |
| `isSafeHeaderValue` | Whether a value can be written into a header block as it stands. |
| `reason` | The word beside a status code. |
| `VerifyHTTPRoute` | The six things this surface answers: two that are the obligation and four that are what the obligation costs. |
| `page` | The page a member's wallet signs against. |
| `script` | The page's script: the route, and the string `VerifyPage` serves at it. |
| `stylesheet` | The page's stylesheet: the route, and the string `VerifyPage` serves at it. |
| `card` | Who this session belongs to, its code and its expiry. The page cannot be rendered with the name in it, because the id reaches the page in a fragment and a browser never sends a fragment to a server. |
| `connect` | The address a wallet connected, recorded once. |
| `submit` | The signed blob. |
| `VerifyRouteMatch` | What to do about one request, before anything reads a body. |
| `matched` | It is one of this surface's routes. |
| `methodNotAllowed` | The path is one of this surface's routes and the method is not. |
| `unknown` | Nothing here serves that. |
| `VerifyRouting` | Where each route lives and which method reaches it. |
| `pagePath` | Where the page is served. |
| `scriptPath` | Where the page's script is served. |
| `stylesheetPath` | Where the page's stylesheet is served. |
| `cardPath` | Where the card is asked for. |
| `connectPath` | Where an address is connected. |
| `submitPath` | Where a signed blob is posted. |
| `carriesSessionIdentifier` | Whether a route carries a session id in its body. Every route that does is a `POST`, because a bearer credential in a `GET` is a bearer credential in the request line, and the request line is what every log on the path writes down. |
| `match` | What to do about one request, by method and path. |
| `VerifySessionHandle` | Something this surface can write down about a session, which nobody can replay. Built exactly the way `Verify`'s own refusal handle is built, so an operator can line the two up; a suite pins them against each other because the construction is repeated rather than borrowed. |
| `characterCount` | Characters in a handle. |
| `value` | The handle itself, lowercase hexadecimal. |
| `description` | The value itself, for a type that renders as one string: `VerifySessionHandle`, `VerifyHTTPLimitsError`, `VerifyLinkError`, `VerifyHTTPListenerError`. |
| `VerifyRateLimiter` | How many requests one key may make in one window, as a sliding window whose every instant arrives as a parameter. |
| `maximumTrackedKeys` | How many distinct keys are tracked, after which keys are dropped, so a table that only grows cannot exhaust this process's memory. A real ceiling: dropping the stale ones is free and is tried first, and when every key in the table is live, which is what a flood of distinct sources produces, the least recently seen go too. |
| `keysEvictedAtOnce` | How far below the ceiling an eviction goes, so a flood does not sort the table again for every newcomer. |
| `limit` | How many requests one key may make in one window. |
| `window` | How long a window is: on `VerifyRateLimiter` and on `VerifyHTTPLimits`. |
| `isLimited` | Records one request and says whether it is over the limit. Asking is recording, because a caller that asks first and records after has a window in which everything in flight is under the limit. |
| `forget` | Drops every key whose requests are all outside the window. |
| `trackedKeyCount` | How many keys are being tracked, for a suite proving the table does not grow for ever. |
| `VerifyHTTPLimitsError` | Why a set of limits was refused, naming the one to fix. |
| `countNotPositive` | A count was zero or less, which would refuse every request. |
| `windowNotPositive` | A window was zero or less, so nothing would ever be counted. |
| `VerifyHTTPLimits` | What this surface will take, and from whom. |
| `assetRequestsPerSource` | Page, script and stylesheet requests one source may make in a window. A page load is three of them, and behind a reverse proxy the source is the proxy, so this is the whole instance's allowance rather than one member's. |
| `apiRequestsPerSource` | Card, connect and submit requests one source may make in a window. Behind a reverse proxy one source is every member at once, so this is a flood stop sized for an instance and not a member's allowance. |
| `apiRequestsPerSession` | Card, connect and submit requests one session may make in a window. The bound that actually holds, because it counts against a value only the member's own link produces. |
| `maximumBodyBytes` | The most bytes a request body may be. |
| `standard` | Six hundred assets and two hundred and forty calls a minute for the whole instance, and twelve calls a minute for one session. The first two are sized for everybody behind the proxy; the third is the one that bounds a member. |
| `ProofHandoff` | What happened to a proof this surface handed back to the program. |
| `awaitingConfirmation` | It is held, and the member finishes by confirming where they started. Nothing is bound until they do. |
| `unavailable` | The program could not hold it, so nothing was recorded anywhere, and the member is told so rather than shown a success page. |
| `VerifyHTTPHost` | The four things this surface cannot do for itself, each a read of something this target deliberately cannot reach. |
| `chatAccountName` | The display name the member's own chat client would show, from the program's own record. Answering nil stops the flow: a page rendered without the name is the relayed-prompt mitigation switched off with nothing saying so. |
| `addressAlreadyClaimed` | Whether an address is already bound to somebody who is not this subject, or nil when the program could not tell. Asked after the coordinator has bound the address to the session, never before, so it cannot be asked freely for any address anybody cares to type, and asked again before a checked proof is handed over, because the connect and the submission are two requests. Nil refuses the flow: a lock that reports itself open because the key could not be found is a lock that is open. |
| `authorizingKey` | The key at that exact account's authorising address field, read by the program from a chain, or nil when there is no chain reader. Asked at most once per session and only on the signature refusal that reports the retry as available. |
| `recordPendingProof` | Holds a checked proof until the member confirms it where they started. |
| `VerifyLinkError` | Why a link could not be built. |
| `baseMissing` | The base was empty. |
| `baseCarriesQueryOrFragment` | The base already carried a query string or a fragment, so an id appended to it would not arrive. |
| `baseNotSecure` | The base was not an `https` origin, and was not plain HTTP to loopback, which is allowed so the flow can be run locally. Refused rather than upgraded: a wallet connector will not run on a page served in the clear, and neither should a session id travel that way. The loopback host is compared whole, because a prefix test accepts somebody else's machine with a reassuring name. |
| `VerifyLink` | The one link a member is given, and the one place the id is allowed to be. |
| `link` | The link, with the id after the `#`. A fragment is the one part of an address a browser never sends to a server, so it is not in an access log, not in a proxy's, and not in a referrer header. |
| `VerifyPage` | The page, its stylesheet and its script, as strings compiled into this target: a static asset with no build step and no bundler. Held in a constant rather than a resource bundle because `Bundle.module` traps when the bundle is not beside the binary, which is a page route that takes the process down the first time somebody loads it. |
| `html` | The page. No value is ever interpolated into it: the name, the code and the expiry are written as text nodes in the browser, so there is no template and no escaping rule to get wrong. |
| `VerifyPageScript` | The page's script, vendored as text, depending on nothing. |
| `adapterGlobalName` | What an operator's own wallet connector is called on `window`: the whole extension point, written down so the name in the script and the name in the documentation cannot drift. |
| `source` | The script itself. |
| `VerifyHTTPService` | Every rule this surface applies to one request, with no socket in sight. A value rather than an actor, because what changes lives in the three rate limiters and in the session store. |
| `limits` | What this surface will take, and from whom. |
| `respond` | What to answer one request with, taking the peer's address and the instant as parameters. |
| `VerifyHTTPBound` | Proof that a listener exists, carrying the port it actually got. |
| `address` | What the listener bound. |
| `port` | The port it holds, which is not the configured one when that was zero. |
| `VerifyHTTPListenerError` | Why the page could not be served. |
| `addressUnusable` | The address is not one this machine can bind. |
| `addressInUse` | Something is already listening there, which is how a second copy of this bot finds out. |
| `refused` | The operating system refused, naming the step and the errno. |
| `VerifyHTTPListenerDeath` | Why the accept loop stopped without being asked to. |
| `pollFailed` | Waiting on the socket failed for a reason that is not an interruption. |
| `listeningSocketBroken` | The listening socket has nothing left to accept and never will. |
| `acceptRefused` | `accept` refused with something that cannot come right on its own. |
| `acceptKeptFailing` | `accept` failed this many times in a row, which is a dead listener rather than a busy one. |
| `sentence` | What happened, in one sentence for whoever reads the log. |
| `VerifyHTTPListener` | The socket the page is served on: a hand written listener over the platform's own sockets, the same shape as the health endpoint in this package and for the same reason. |
| `peerTimeoutSeconds` | How long a peer has to send its whole request and take its answer. The whole request, not one read of it: the socket option underneath bounds a single `recv`, which a peer dripping one byte at a time restarts for ever. |
| `maximumConcurrentReads` | How many connections may be being read at once. Reads block, so this is the difference between a slow page and a process holding descriptors it will never answer on; the rate limiters cannot help, because they are asked once a whole request has been read. |
| `maximumConsecutiveAcceptFailures` | How many `accept` failures in a row mean the listener is dead rather than busy. |
| `isServing` | Whether a bind is live and its loop has not finished, so a program can make its health answer reflect a page that has died. Not an exit: a library that calls `exit` takes a decision belonging to the composition root. |
| `death` | Why the loop stopped, when it stopped on its own. |
| `bind` | Binds, listens and starts answering, answering with the port obtained. |
| `stop` | Stops answering and gives the port back, waiting for the loop that owns the socket to close it. |
| `init` | Memberwise, except where it validates. `VerifyHTTPLimits.init` refuses a count or a window of nothing, naming it. `VerifyHTTPService.init` takes the coordinator, the same store it was built over, the host's four reads, the limits and a log. `VerifyHTTPListener.init` takes the service, the two bounds a flood is answered by, and a log, clamping each bound to at least one because a bound of nothing refuses every request. `VerifySessionHandle.init` takes a session id and keeps none of it. |

## Invariants

1. **No session id leaves this process.** Not in a response body, not in a
   header, not in a log line, not in a refusal. A suite drives a whole flow
   and asserts the id appears in none of the bytes written and none of the
   lines logged.
2. **No session id arrives in a query string.** Every route that takes one is
   a `POST`, and any request carrying a query string at all is refused,
   including on the page.
3. **Every answer carries `Referrer-Policy: no-referrer`**, on every route,
   including refusals.
4. **The page is named or it is not served.** A live session whose chat
   account cannot be named is refused rather than rendered without the name.
5. **Every route is rate limited**, per source; the three that carry a
   session id are limited per session as well. A request this surface will
   not serve whatever budget is left is counted against nobody: a path it
   does not serve, and a request carrying a query string. So a scanner
   cannot spend the budget a member's own page needs, and behind a proxy
   that budget is the whole community's.
6. **Nothing here reads a clock** except the listener, once per request, at
   the top. Every rule below takes `now` as a parameter.
7. **Nothing is interpolated into the page.** The HTML is the same bytes for
   every member.
8. **The authorising key is asked for at most once per session**, only on the
   signature refusal that reports a retry as available, and only from the
   program's own read of that exact account's authorising address field.
9. **No peer holds this process by not talking to it.** One peer's budget
   is its whole request rather than one read of it, how many connections
   may be being read at once is bounded, and the ones over that bound are
   closed at accept. The rate limiters are asked once a request has been
   read, so none of this is theirs to do.

## Behavioral Examples

### Scenario: a member proves a wallet

- **Given** a session minted for a subject the program can name
- **When** the member opens the link, whose id is after the `#`
- **Then** the page is served with no session id in the request at all
- **And** the page asks for the card with the id in a request body, and is
  told the chat account, the six character code and the expiry read from the
  session's own `expiresAt`
- **And** the connect binds one address to the session
- **And** the submit is answered `200` with `awaiting-confirmation`, the
  proof is handed to the program, and nothing is linked until the member
  confirms where they started

### Scenario: somebody sends a member the link

- **Given** a session minted for one member and a link relayed to another
- **Then** the page names the first member's chat account, beside a warning
  that nobody should ever send this link
- **And** the same page is served, because the page cannot be made to lie
  about whose session it is

### Scenario: a session id is put in a query string

- **When** any route is asked for with a query string, including the page
- **Then** it is refused `400` and the request is not served, because a
  surface that serves one has already taught somebody a shape in which a
  bearer credential lands in an access log

### Scenario: an account another member already proved

- **Given** a session and an address the program says belongs to somebody
  else
- **Then** the connect is refused `409` after the address has been bound to
  the session, so the question is about the address the member actually
  connected rather than any address a session id holder types
- **And** a caller that ignores that refusal and posts a signed blob anyway
  is refused `409` as well, with nothing handed to the program: the page
  honouring the first refusal is the page's manners, and these routes are a
  JSON API anybody can reach
- **And** a program that could not answer at all refuses the flow rather
  than reading as "nobody holds it"

### Scenario: a peer that connects and says nothing, or one byte at a time

- **Given** more such peers than there are connections this listener will
  read at once
- **Then** each is answered or closed within the peer budget, which is the
  whole request's rather than one read's, and the ones over the bound are
  closed at accept
- **And** the page is still served, because none of this reaches the rate
  limiters: they are asked once a whole request has been read

### Scenario: a rekeyed account

- **Given** a submission whose signature is by the account's authorising key
- **Then** the first check refuses at the signature and reports the retry as
  available
- **And** the program's authorising address read is asked once, the
  submission is checked again against that key, and the proved account
  records that the key was used
- **And** with no chain reader configured nothing is asked and the refusal
  stands

### Scenario: a member with a session id posts as fast as a socket allows

- **Then** the per-session budget refuses with `429` and a handle
- **And** a second session from the same source runs into the per-source
  budget, which is answered before a body is read and therefore carries no
  handle

## Error Cases

| Condition | Result |
|-----------|--------|
| A path this surface does not serve | `404`, counted against nobody |
| A served path with the wrong method | `405` |
| Any request carrying a query string | `400`, naming what to do about it |
| A body over `maximumBodyBytes` | `413`, before anything parses it |
| A body that is not JSON, or with no session id in it | `400`, with no handle |
| A session id that is not thirty two lowercase hexadecimal characters | `400`, with no handle: a handle is a digest of a session, and this is a digest of whatever somebody typed |
| Over the per-source budget | `429`, with no handle, because the body has not been read |
| Over the per-session budget | `429`, with the handle |
| A session id that selects nothing live | `404` carrying `sessionUnavailable`'s own sentence |
| A session past its expiry | `410`, because a member needs to know a new link is what fixes it |
| A live session the program cannot name | `503`, and the page is not served without the name |
| An address no Algorand tool would accept | `400`: a page's mistake or a typo, not a proof that failed |
| A second, differing address on one session | `409`, saying nothing at all about either address |
| An address bound to another member | `409`, at the connect and again before a checked proof is handed over |
| An address the program could not read about | `503`, because a lock that reports itself open when the key cannot be found is open |
| Every way a proof can be wrong | `422` carrying the module's own sentence for that reason, except the session and allowance reasons, which are `404`, `410` and `429` |
| A checked proof the program could not hold | `503`, said plainly, because the alternative is a member who saw a success page and has no role |
| An authorising key the program read at the wrong width | `500`, which is this side's mistake and is reported as ours |

## Dependencies

- Foundation, and Dispatch for the two queues the listener's blocking reads
  run on, the bound on how many of those may be in flight, and the
  monotonic clock the peer budget is measured on.
- **The host process must ignore SIGPIPE.** Writing to a peer that has gone
  raises it, and the socket option Darwin offers is set too late on a
  connection the peer has already reset. This is a library with no
  executable of its own, so the program serving these routes owes what this
  package's own executable does before anything else it does (RT-001).
- `Verify`, for everything it decides. This target adds no check of its own
  to a proof and has no way to accept one the module would refuse.
- `Crypto`, for one thing: the truncated digest that stands in for a session
  id in a log line and a rate limiter's key. Already resolved for `Verify`,
  so it moves no version.
- No other target in this package, and the manifest is what enforces it.
  Notably not `Surface`, whose `HTTPRequestHead` this target's request parser
  deliberately duplicates: sharing it would pull `Store`, `Chain` and
  `Gating` in behind it, and the two parsers answer different questions
  anyway. The callback listener takes whatever one read produced, which is
  right for one cooperating service; this one honours `Content-Length`,
  because a browser is free to put the headers in one segment and the body in
  the next.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-09-19 | maintainers | Review fixes: a query string refused for free, per-source budgets sized for an instance and said to be, an unreadable claim answerable and refused, the claim asked again before a proof is handed over, the peer budget made the whole request's, connections in flight bounded, a real ceiling on the limiter's table, framing a sender cannot choose, and a content type that cannot end a header block. |
| 2026-09-19 | maintainers | Spec written with the `VerifyHTTP` library target: the page, the three calls it makes, the socket underneath them, the rate limit on all four, and the link whose session id lives in a fragment. It discharges the host obligations `specs/verify` records as unevidenced, except the chat command, the pending record and the operator's release path, which belong to the program. |
| 2026-09-19 | SpecSync | serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other: Serve the page a member's wallet signs against, and the routes it answers, as a VerifyHTTP target that imports no other target in this package and that nothing links yet |
