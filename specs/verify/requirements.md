---
spec: verify.spec.md
---

## User Stories

- As a member, I want to prove a wallet is mine without handing anybody a key,
  and without the flow feeling like a phishing page, so that the first thing I
  do in this server is not the thing I regret (VERIFY-1).
- As a member, I want what I sign to say which member it will be adopted for,
  so that a prompt somebody else started and handed to me is one I can see is
  not mine (VERIFY-1, VERIFY-6).
- As a member, I want to be able to name the wallet I mean before anything is
  signed, so that I find out I connected the wrong one before my wallet asks
  me to sign (VERIFY-1, VERIFY-2).
- As a member, I want to be told the sender did not match when my wallet had
  the wrong account selected, rather than told my signature was bad, because
  one of those is something I can fix (VERIFY-1).
- As a member, I want what I proved in one community to mean nothing in any
  other, even one running the same bot (VERIFY-4, HOST-6).
- As a member, I want nothing about me to be kept here beyond what the proof
  needed, and nothing a log can turn back into a link somebody else could use
  (VERIFY-7, VERIFY-7.b).
- As somebody running this, I want verification without standing up a second
  service and without asking my members to trust anybody but me (VERIFY-5,
  HOST-1).
- As somebody running this, I want no setting, anywhere, that turns off the
  signature check (BUILD-3, BUILD-3.a, BUILD-3.b).
- As somebody running this, I want the words a member reads, and the message
  their wallet asks them to sign, to be my community's (ADOPT-1.c, ADOPT-1.f).
- As somebody running this, I want no member, however fast they type, to be
  able to spend the day's budget for reading the chain (RUN-11).
- As somebody deciding whether to install this, I want a new dependency to be
  a diff I can read rather than something that appeared quietly (TRUST-1,
  TRUST-1.b, TRUST-4).
- As a contributor, I want the whole proof path exercised with no network, no
  live wallet and no key anybody had to trust me with (BUILD-2, BUILD-2.a,
  BUILD-2.b).
- As a contributor, I want to tell which half of verification is built and
  which is still only written down (BUILD-4).

## Requirements

### REQ-verify-001

The module SHALL decide whether an Algorand account is controlled by whoever
presented a proof of it, and SHALL do so reading nothing: no connection, no
node client, no clock, no setting from outside the process, no private key
type, no signing call, no transaction submission, no log. Every instant SHALL
arrive as a `now` the caller supplies. A member SHALL be an opaque subject
string it never interprets, and no identifier that came from a person SHALL
appear in a challenge, a session, a refusal or any type it declares. Its
dependencies SHALL be Foundation, the Algorand address parser and a
cryptography library, and no other target in this package
(VERIFY-7.b, HOST-2, TRUST-4, BUILD-2.a).

### REQ-verify-002

A challenge SHALL be five lines of UTF-8: an operator supplied label, an
identity for this instance, the subject this session was minted for, a six
character code, and a nonce of at least a hundred and twenty eight bits from
the system random number generator, derived from no argument. Five lines
SHALL be an invariant rather than a description, because the subject is
located by its line index when a submitted note is checked: every value
rendered into a line SHALL be refused at the mint, with a named reason, if it
carries U+000A, U+000D, U+2028 or U+2029, and the label SHALL be refused above
a hundred UTF-8 bytes. A challenge SHALL render its own text and read it back,
and SHALL be compared whole, as bytes (VERIFY-1, VERIFY-4, VERIFY-6,
ADOPT-1.c).

### REQ-verify-003

A session SHALL be selected only by an id of at least a hundred and twenty
eight bits from the system generator, derived from nothing and compared
whole, and that id SHALL be treated as a bearer credential. A session SHALL
carry `issuedAt` and `expiresAt` and SHALL refuse a proof at or after
`expiresAt` naming expiry whatever else is wrong with it. It SHALL be consumed
on the first accepted proof and refuse every later one; a refused proof SHALL
NOT consume it. A subject SHALL have at most one live session, a second
displacing the first, which is discarded with its challenge at once. A session
id that selects nothing SHALL be refused with a single reason that does not
say why. A session SHALL record the address it was connected to the first time
one is presented and SHALL refuse a second differing address without answering
anything about it. Every one of these SHALL hold for calls that arrive
together as well as in turn: a session SHALL be claimed for the length of a
call, and a call arriving on a claimed session SHALL be refused with the
reason that does not say why (VERIFY-1, VERIFY-2, VERIFY-7).

### REQ-verify-004

A session SHALL bound how many submissions it accepts, at a maximum of at
least three, and the same bound SHALL be kept per subject over a window the
caller supplies, surviving displacement, consumption, expiry and pruning, at a
maximum larger than the per-session one. The authorising key retry SHALL be
reported as available at most once per session. All three SHALL hold for
submissions in flight at the same time and not only for submissions in turn,
because a rate limit bounds requests per unit of time and not requests in
flight. A refusal for a spent allowance SHALL say which of the two ran out,
because a spent link is fixed by a new one and a spent window is fixed by
nothing but waiting. This is the half of the budget story that can be proved
offline; the rate limit on the command and on the submit route is the host's
(RUN-11).

### REQ-verify-005

Exactly one proof shape SHALL be accepted: type `pay`, sender equal to
receiver, amount zero, fee at most a thousand microAlgos, no `rekey`, no
`close`, no `aclose`, no `lx`, no `grp`, and a note that is the session's
challenge bytes exactly. Each forbidden field SHALL be refused with a reason
of its own whether or not the signature is valid, and the wire name for a
rekey SHALL be the one the dependency's canonical encoder emits. An absent
`amt` SHALL read as zero and an absent `fee` SHALL read as zero rather than as
unknown or unbounded. A signature over an arbitrary message, with or without a
wallet's data prefix, SHALL be refused, and no entry point SHALL accept one
(VERIFY-1).

### REQ-verify-006

The reader SHALL accept both base64 alphabets, padded or not, with surrounding
whitespace. Padded or not SHALL be the whole of that latitude: padding SHALL
be the last one or two characters of the last group of four and nothing else,
and a leftover group of one character SHALL be refused, because six bits are
never a whole byte however they are padded. The reader SHALL decide both
itself rather than leaving them to the platform's Foundation, whose
implementations differ in opposite directions and would otherwise decide which
refusal a member reads by which machine answered. It SHALL accept a bare
signature and transaction map, that map in a one element array, and a map
carrying an additional signer key, which it SHALL skip and SHALL NOT surface.
It SHALL return the transaction bytes as a slice of the submitted blob, and
the signature SHALL be checked over `TX` followed by that slice; no path
SHALL re-encode parsed fields and check over the result. It SHALL refuse a
duplicate key at any depth and any byte after the envelope. It SHALL NOT
require a map's keys to be in any particular order: unique keys say one thing
in whatever order they arrive, and the envelope the reader this was ported
from was patched to accept, after a live flow on a phone was refused, carries
its signer key after its transaction. It
SHALL apply a size ceiling before parsing begins, SHALL impose a nesting depth
limit, and SHALL NOT allocate in proportion to a length the input declares but
does not carry (VERIFY-1, BUILD-2.a).

### REQ-verify-007

Refusals SHALL be produced in this order and a later reason SHALL NOT be
returned while an earlier one holds: session state, session expiry, blob
decode, transaction parse, missing fields, transaction type, pinned address,
sender, receiver, amount, fee, forbidden fields, subject, note, signature.
The subject reason SHALL be read out of the **submitted** note at the line
index the challenge shape fixes and SHALL sit immediately before the note. A
refusal SHALL carry a reason and a non-reversible handle and SHALL NOT carry
the blob, the signature, the challenge or the session id. The signature
refusal SHALL be distinguishable from every other reason and SHALL say whether
the retry is still available (VERIFY-1, VERIFY-7).

### REQ-verify-008

There SHALL be no input value, setting, build configuration or compilation
condition under which a proof is accepted without a valid signature. The only
keys a signature is checked against SHALL be the claimed address and an
authorising key the caller supplied in the proof expectation; no value read
out of a submitted blob SHALL be usable as one. A key that is a small-order
point SHALL be refused before the cryptography library is asked, because an
all-zero key with an all-zero signature verifies every message and the
libraries this builds against return true for it. A proved account SHALL be
produced only by consuming a signature and a session, SHALL NOT be
constructible from outside the module, and the value an asserted route
produces SHALL be a distinct public type named for what it is
(BUILD-3, BUILD-3.a, BUILD-3.b, VERIFY-1).

### REQ-verify-009

The obligations this module states for a host — the page a wallet signs
against and the routes it answers — SHALL remain obligations of a host rather
than of this module, and this module SHALL continue to reach no network, read
no clock, hold no key and read no setting. What changes is that a host now
exists in this package, `verify-http`, which depends on this module while this
module SHALL continue to know nothing about it. The dependency SHALL run in
that direction only, and `specs/verify/testing.md` SHALL record which of the
host obligations that target now evidences and which remain unevidenced,
rather than marking them all satisfied because a host appeared.

Acceptance Criteria
- `Tests/VerifyTests/TargetShapeTests.swift` proves this module still
  constructs no client, names no request type, logs nothing and reads no
  environment variable, unchanged by the arrival of a host.
- `Tests/VerifyHTTPTests/TargetShapeTests.swift` proves the dependency runs
  one way: the host imports this module, and this module imports nothing of
  the host's.
- `specs/verify/testing.md` names the obligations `verify-http` now evidences
  and leaves the chat command, the pending record and the operator's release
  path marked unevidenced.

### REQ-verify-010

*Host obligation.* Before a member is asked to sign, the reply SHALL name who
runs this server, what will be kept about them and which of it other members
can see, as plain text rather than an embed, carrying the link as text as well
as a button, the six character code, and the expiry read from the session's
own `expiresAt`. Nothing in it SHALL name whoever wrote the bot. The page
SHALL name the chat account the session belongs to, in the display name that
member's own client would show, with a warning beside it: only continue if
that account is yours, and nobody should ever send you this link. The reply
SHALL carry the same warning. The name SHALL be rendered by the host from its
own record and SHALL NOT enter any type this module declares. The command
SHALL take an optional wallet argument, resolved to a single address and shown
back before anything is signed; resolving a name is an outbound call that
nothing at boot depends on, and a name that cannot be resolved SHALL be
reported as that with a request for the raw address
(VERIFY-1, VERIFY-6, VERIFY-2, ADOPT-1.c, SEE-7, SEE-10, TRUST-1).
