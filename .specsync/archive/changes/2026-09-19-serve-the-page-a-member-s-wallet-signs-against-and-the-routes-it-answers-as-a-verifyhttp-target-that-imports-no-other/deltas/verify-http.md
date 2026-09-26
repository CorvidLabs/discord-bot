---
change: serve-the-page-a-member-s-wallet-signs-against-and-the-routes-it-answers-as-a-verifyhttp-target-that-imports-no-other
module: verify-http
---

# Semantic delta: verify-http

## Modified

### REQUIREMENT REQ-verify-http-001

The target SHALL serve a page a member's wallet signs against and SHALL
accept the signed blob on a route of its own, handing both to
`VerificationCoordinator` and adding no check of its own. It SHALL link
`Verify` and a cryptography library and no other target in this package, so
that serving a page can neither record a member nor spend a chain request.
Every instant SHALL arrive as a parameter, except one read of the wall clock
per request in the listener (VERIFY-5, HOST-1, BUILD-2).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-002

The session id SHALL be treated as a bearer credential. It SHALL reach the
page in the fragment of the link and SHALL NOT appear in a query string, a
request line, a response body, a response header or a log line. Every route
that carries one SHALL be a `POST`. Any request carrying a query string SHALL
be refused rather than served. Every answer, including every refusal, SHALL
carry `Referrer-Policy: no-referrer`, and the page SHALL remove the fragment
from the address bar before it does anything else (VERIFY-7, REQ-verify-003,
REQ-verify-009).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-003

Before a member is asked to sign, the page SHALL name the chat account the
session belongs to, in the display name that member's own client would show,
with a warning beside it: only continue if that account is yours, and nobody
should ever send you this link. The name SHALL be rendered by the host from
its own record, SHALL NOT enter any type `Verify` declares, and SHALL be
written into the page as a text node rather than as markup. A live session
whose account cannot be named SHALL be refused rather than served without the
name (REQ-verify-010, VERIFY-6).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-004

Every route SHALL be rate limited per source, and every route carrying a
session id SHALL be rate limited per session as well, against a
non-reversible handle rather than against the id. A request this surface
will not serve whatever budget is left SHALL be counted against nobody:
a path it does not serve, and a request carrying a query string. The limits
SHALL be configuration with a stated default, and a count or window of
nothing SHALL be refused at construction naming the one to fix. A
forwarded-for header SHALL NOT be honoured, because a header a client sends
is a value a client chooses; the default per-source budgets SHALL therefore
be sized for a whole instance rather than for one member, and SHALL say so
where an operator changing them will read it
(REQ-verify-004, REQ-verify-009, RUN-11).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-005

A refusal SHALL carry a sentence written for a member, a non-reversible
handle, and whether trying again from the same page could help. It SHALL NOT
carry the session id, the blob, the signature or the challenge. The handle
SHALL be built the way `Verify`'s own refusal handle is built, so the two can
be lined up, and a test SHALL pin them against each other
(REQ-verify-007, VERIFY-7).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-006

An address SHALL be bound to the session before the host is asked whether it
belongs to another member, so that question is only ever asked about an
address the member actually connected. It SHALL be asked again before a
checked proof is handed to the host, because the connect and the submission
are separate requests and a caller is free to ignore the first refusal. A
host that cannot answer SHALL be able to say so, and an unanswerable
question SHALL refuse the flow rather than read as "nobody holds it". The
authorising key SHALL be asked for at most once per session, only on the
signature refusal that reports the retry as available, and only from the
host's own read of that exact account's authorising address field; with no
reader configured, the refusal SHALL stand
(REQ-verify-008, REQ-verify-009).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-007

A checked proof SHALL be handed to the host and SHALL bind nothing here. The
member SHALL be told to confirm where they ran the command. A proof the host
could not hold SHALL be reported as that rather than shown as a success
(REQ-verify-009, ADOPT-9).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-008

The page SHALL be a static asset this target serves, with no build step, no
bundler and no resource bundle that can be missing at runtime. No value SHALL
be interpolated into it. It SHALL carry no inline script and no inline style,
and the content security policy SHALL name no origin but its own. Where a
third party wallet connector would be needed, the target SHALL name one
extension point and SHALL say plainly what an operator still has to add
(TRUST-1, BUILD-4).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.

### REQUIREMENT REQ-verify-http-009

The listener SHALL bound one peer's whole request rather than one read of
it, and SHALL bound how many connections are being read at once, refusing
the ones over that bound at accept. Neither is the rate limit's to do: the
limiters are asked once a whole request has been read, so a peer that sends
one byte at a time, or none at all, is invisible to them. A request that
cannot become a request SHALL be answered when that is known rather than
when the budget runs out. A message whose framing cannot be trusted SHALL
NOT be read (RFC 9112 6.3), and a header value that would end the header
block early SHALL NOT be written into one. The process serving these routes
SHALL ignore SIGPIPE; this target is a library and cannot (RT-001).

Acceptance Criteria
- Covered by the suites named in this change's `testing.md`.
