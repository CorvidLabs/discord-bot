---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
module: verify
---

# Semantic delta: verify

## Added

### REQUIREMENT REQ-verify-001

`Verify` SHALL decide whether an Algorand account is controlled by whoever
presented a proof of it, and SHALL do so reading nothing. It SHALL open no
connection, construct no node client, read no clock, read no environment
variable and no process argument, declare no private key type, no mnemonic,
no signing call and no transaction submission, and log nothing. Every instant
it needs SHALL arrive as a `now` the caller supplies. It SHALL take the
member as an opaque subject string it never interprets, and no identifier
that came from a person SHALL appear in a challenge, a session, a refusal or
any type it declares. Its dependencies SHALL be Foundation, the Algorand
address parser and a cryptography library, and no other target in this
package.

Acceptance Criteria
- `TargetShapeTests` reads the manifest and the target's own sources and
  proves each absence by name: the dependency list exactly, no chat client
  and no chat identifier type, no key type and no signing call, no node
  client and no submit call, no environment read, no logging call, and no
  account lookup and nothing that could perform one.
- `ChallengeTests` proves the subject a challenge carries is the opaque value
  the caller supplied and nothing else.
- Every suite in `Tests/VerifyTests` runs with no network, no live wallet and
  no supplied key, with every key generated inside the test.

### REQUIREMENT REQ-verify-002

A challenge SHALL be five lines of UTF-8, in this order: an operator supplied
label, an identity for this instance, the subject this session was minted
for, a six character code, and a nonce of at least one hundred and twenty
eight bits drawn from the system random number generator. The nonce SHALL NOT
be derived from the subject, the address, the clock or any argument, and two
challenges minted in the same process SHALL differ. The instance identity
inside the signed bytes is what makes a proof worthless in another community.
The subject line inside the signed bytes is what stops one member's signature
being adopted for another, and it is opaque, so nothing person-derived
crosses the boundary REQ-verify-001 draws.

Five lines is an invariant rather than a description of the usual case,
because the subject is located by its line index when a submitted note is
checked. Every value rendered into a line SHALL be refused, at the point the
challenge would be minted and with a named reason, if it carries a line break
of any kind (U+000A, U+000D, U+2028 or U+2029), and the operator's label
SHALL additionally be refused above one hundred UTF-8 bytes. A challenge
SHALL render its own text and read it back, so that the bytes signed and the
bytes compared come from one function, and a challenge SHALL be compared
whole, as bytes.

Acceptance Criteria
- `ChallengeTests` proves the exact five line rendering with the subject
  third, and that the six character code shown to the member is the same
  value that sits inside the signed bytes.
- `ChallengeTests` proves a label carrying each of the four line break
  characters is refused at the mint, and that a label one byte over the bound
  is refused while one byte under is accepted.
- `ChallengeTests` proves two thousand mints yield two thousand distinct
  nonces, and that the same arguments twice give different challenges.
- `ProofRefusalTests` proves a proof minted under one instance identity is
  refused under another, with every other field correct and the nonce
  identical.

### REQUIREMENT REQ-verify-003

A session SHALL be selected only by a session id of at least one hundred and
twenty eight bits drawn from the system random number generator, not derived
from the subject, the address or the clock, and compared whole. That id is a
bearer credential: whoever holds it can submit against the session, and a
submission binds whatever address the submitter connects to whatever member
the session names.

A session SHALL carry `issuedAt` and `expiresAt`, and a proof presented at or
after `expiresAt` SHALL be refused naming expiry whatever else is wrong with
it. A session SHALL be consumed on the first accepted proof and SHALL refuse
every later proof, including a byte identical resubmission of the one it
accepted, while a refused proof SHALL NOT consume it.

A subject SHALL have at most one live session: minting a second one
SHALL displace the first, and the displaced session and its challenge
SHALL be discarded at once rather than left to expire. A consumed or expired session
SHALL be discarded with its challenge by a prune taking a `now`. A session id
that selects nothing, whether it was never issued, consumed, pruned or
displaced, SHALL be refused with a single reason that does not say which of
those it was.

A session SHALL record the address it was connected to the first time one is
presented, and SHALL refuse a second, differing address without answering
anything about that address, so that the host's check for an address another
member already proved cannot be walked. A session SHALL bound how many
submissions it accepts, at a maximum of at least three, and the same bound
SHALL be kept per subject over a window the caller supplies, surviving
displacement, consumption, expiry and pruning, at a maximum larger than the
per-session one. The authorising key retry SHALL be reported as available at
most once per session.

Acceptance Criteria
- `SessionTests` proves expiry is evaluated against a supplied `now`, that
  the boundary is at `expiresAt`, and that an expired session reports expiry
  although the same submission is also malformed and also for the wrong
  sender.
- `SessionTests` proves a byte identical resubmission of an accepted proof is
  refused, and that a refused proof leaves the session usable.
- `SessionTests` proves a displaced session and its challenge are gone, that
  never issued, consumed, pruned and displaced are indistinguishable in the
  refusal, and that a pruned session leaves nothing behind.
- `SessionTests` proves the per-session maximum is not below three, and that
  spending a session's allowance and then minting a new session for the same
  subject does not buy a new allowance.
- `SessionTests` proves a second differing connected address is refused
  without disclosing anything about that address.

### REQUIREMENT REQ-verify-004

Exactly one proof shape SHALL be accepted: a transaction whose type is `pay`,
whose sender and receiver are the same address, whose amount is zero, whose
fee is at most one thousand microAlgos, which carries none of `rekey`,
`close`, `aclose`, `lx` or `grp`, and whose note is the session's challenge
bytes exactly. A signature over an arbitrary message, with or without a
wallet's data prefix, SHALL be refused, and no entry point SHALL accept one.
Each forbidden field SHALL be refused with a reason of its own whether or not
the signature is valid. The wire name for a rekey is `rekey`, which is what
the dependency's canonical encoder emits, and not the name the field carries
on its transaction type.

An absent `amt` key SHALL be read as an amount of zero, and an absent `fee`
key SHALL be read as a fee of zero rather than as a fee that is unknown or
unbounded, because a canonical encoder omits both keys when their value is
zero and requiring either refuses every correctly formed proof.

The fee bound is the network minimum rather than zero, and both halves are
deliberate. It is bounded at all because a zero amount self payment is
harmless only while its fee is: a page that builds the proof with the fee set
to the member's whole balance would otherwise produce something this target
blesses as proof of ownership, and the page keeps the blob. It is bounded at
the minimum rather than at zero because there is no measurement of which
wallets override a fee they were handed, and a checker that insists on zero
refuses every wallet that raises one, for a fee policy the page cannot
enforce inside somebody else's wallet. At the minimum, a leaked blob costs a
member a fraction of a cent instead of their whole balance, which is the
property the bound exists for. What that gives up is that the blob becomes
submittable: submitting it moves nothing, from the member to the member, and
costs that one minimum fee.

Acceptance Criteria
- `ProofRefusalTests` proves a fee one microAlgo above the bound is refused
  at its own step with a valid signature over it, and that a fee at the bound
  is accepted.
- `SignedTransactionReaderTests` proves an absent `amt` and an absent `fee`
  each read as zero, against a blob a real signer produced for a zero amount,
  zero fee payment, which omits both keys.
- `ProofRefusalTests` proves each of `rekey`, `close`, `aclose`, `lx` and
  `grp` is refused with its own reason and a valid signature, with every
  forbidden key name in the fixture obtained from, or asserted equal to, what
  the dependency's own canonical encoder emits.
- `ProofRefusalTests` proves a transaction whose type is not `pay`, one
  paying a different receiver and one with a non-zero amount are each refused
  at their own step, and that a signature over an arbitrary message is
  refused.

### REQUIREMENT REQ-verify-005

The reader SHALL accept standard and URL-safe base64, padded or unpadded and
with surrounding whitespace, and SHALL accept a bare signature and
transaction map, that map wrapped in a one element array, and a map carrying
an additional signer key, which it SHALL skip and SHALL NOT surface. The
reader SHALL return the transaction bytes as a slice of the submitted blob,
and the
signature SHALL be checked over the bytes `TX` followed by that slice. No
path SHALL re-encode parsed fields and check a signature over the result.

Tolerance about how a blob is spelled SHALL NOT be tolerance of a blob that
says two things. A duplicate key at any depth, a transaction map whose keys
do not ascend by their UTF-8 bytes, and any byte after the end of the
envelope SHALL each be refused. Everything else SHALL be refused at any depth
without trapping: the reader SHALL apply a blob size ceiling before parsing
begins, SHALL impose a nesting depth limit, and SHALL NOT allocate in
proportion to a length the input declares but does not carry.

Acceptance Criteria
- `SignedTransactionReaderTests` proves the accepted spellings and the three
  accepted shapes yield one identical transaction slice, asserted against the
  input by offset and length rather than by equality of parsed fields.
- `SignedTransactionReaderTests` proves truncation at every byte offset of a
  canonical blob is refused and none of them traps, that a signature which is
  not exactly sixty four bytes is refused, and that a declared length larger
  than the bytes that arrived is refused without allocating to match it.
- `SignedTransactionReaderTests` proves a value nested past the depth limit
  is refused in bounded time and a blob over the ceiling is refused before
  parsing begins.
- `SignedTransactionReaderTests` proves a duplicate key at envelope depth and
  inside the transaction map, a descending key order and a trailing byte are
  each refused, and that a signer key in the envelope is skipped and has
  nowhere to be surfaced.

### REQUIREMENT REQ-verify-006

Refusals SHALL be produced in this order, and a later reason SHALL NOT be
returned while an earlier one holds: session state, session expiry, blob
decode, transaction parse, missing fields, transaction type, pinned address,
sender, receiver, amount, fee, forbidden fields, subject, note, signature.
That is fifteen reasons. Field failures therefore precede signature failure,
so a member whose wallet had the wrong account selected is told the sender
did not match rather than told their signature was bad.

The subject reason SHALL be read out of the **submitted** note, at the line
index the challenge shape fixes, and compared against the session's own
subject, and it SHALL sit immediately before the note. It SHALL NOT rebuild
the expected challenge out of the submitted note. Placed after a byte exact
note comparison the reason could never be returned at all, and rebuilt from
the submitted note the note comparison becomes a tautology.

A refusal SHALL carry a reason and a non-reversible handle, either a
truncated hash of the session id or an opaque per-refusal identifier, and
SHALL NOT carry the submitted blob, the signature, the challenge in full or
the session id. The signature refusal SHALL be distinguishable from every
other reason, so that a caller may look up an authorising address and ask
once more, and it SHALL say whether that retry is still available for this
session.

Acceptance Criteria
- `ProofRefusalTests` covers one case per reason, fifteen of them, each
  constructed so that every later reason is also violated, so the order is
  proved rather than asserted.
- `ProofRefusalTests` proves the subject case returns the subject reason and
  not the note reason, and that a proof minted for another session is refused
  at the note without disclosing the other session's challenge.
- `ProofRefusalTests` asserts a refusal's contents exhaustively, including
  that the session id appears in no field and in no rendered message, and
  that the same refusal yields the same handle while the handle does not
  yield the session id.

### REQUIREMENT REQ-verify-007

There SHALL be no input value, environment variable, build configuration or
compilation condition under which a proof is accepted without a valid
signature. The only keys a signature is ever checked against SHALL be the
claimed address and an authorising key the caller supplied in the proof
expectation; no value read out of a submitted blob SHALL be usable as one,
and the target SHALL NOT derive a key from anything else.

A proved account SHALL be produced only by consuming a signature, SHALL NOT
be constructible from outside the module, and SHALL NOT be returned by any
public interface that does not take a submitted proof and a session. The
value an asserted route produces SHALL be a distinct public type named for
what it is, and converting it into the one downstream value both routes meet
at SHALL be an explicit call that tags the route as asserted. An outcome
produced under an authorising key SHALL record that it was, so an audit can
tell a proof by the account's own key from a proof by a key the caller
vouched for.

Acceptance Criteria
- `NoBypassTests` proves that the literal strings a reference portal accepts
  under a test flag, and a range of other fixed strings including the empty
  one, are each refused as ordinary malformed input with no special case.
- `NoBypassTests` proves the same input gives the same outcome in a debug and
  a release build, and asserts over the whole public surface that nothing
  returns a proved account without consuming a signature.
- `OutcomeTests` proves a downstream value built from a proved account and
  one built from an asserted account, for the same subject and address,
  differ only in the route tag.
- `ProofRefusalTests` proves a signature from a key that is not the claimed
  account is refused, that a blob naming its own signer does not have that
  signer used, and that a proof signed by a supplied authorising key is
  accepted and recorded as such.

### REQUIREMENT REQ-verify-008

A session MAY be pinned to a single address at the mint. Where it is, a proof
whose sender is any other address SHALL be refused with a reason of its own,
saying that the account named when the session was minted is not the account
that signed, and the first address presented on that session that differs
from the pin SHALL be refused with the same reason rather than recorded as
the connected address. The pin SHALL be an address: the target SHALL NOT hold
a name, SHALL NOT resolve one, and SHALL NOT acquire anything that could.

Pinning does not close a relayed prompt and the contract does not claim it
does. An address is public, so an attacker may name the address they want in
their own session and every check still passes. What pinning buys is a
refusal that names what the member chose, a mismatch found before the member
is asked to sign, and a member who has committed to an address first.

Acceptance Criteria
- `ProofRefusalTests` proves a pinned session refuses a proof from a second
  generated key with the pinned address reason and not the sender reason.
- `SessionTests` proves a pinned session refuses the first differing address
  at the connect, and that an unpinned session skips the position entirely.

### REQUIREMENT REQ-verify-009

A host embedding this module SHALL carry the obligations the module cannot.
Exactly one prover route SHALL be named explicitly in configuration, with
naming none and naming both each stopping the boot and naming both variables;
no route SHALL be defaulted. Startup SHALL state which route is live and, on
an asserted route, SHALL say in words an operator reads that the proof is the
other service's word and the shared secret is the whole trust boundary. A
prover that fails after boot SHALL disable verification and nothing else.

The session id SHALL be treated as a bearer credential: delivered only in the
ephemeral reply, carried to the page in a URL fragment or a request body and
never in a query string, never written to a log, an access log, an error
report or a crash report, with the page served under a referrer policy of
`no-referrer`. Adoption SHALL require a confirmation by the subject after the
proof has been checked, and the checked proof SHALL wait in a pending record
keyed by the subject rather than by the session id, with an expiry of its
own, binding nothing at all until it is confirmed.

An authorising key passed to the module SHALL come only from the host's own
chain read of that exact account's authorising address field, attempted at
most once per session and only on the signature refusal that reports a retry
as available. The verification command and the submit route SHALL both be
rate limited, per member and per source. An address another member has
already proved SHALL be refused when it is connected and again at adoption,
and SHALL be releasable by an operator with an audit line naming who released
it and from whom. The operator's challenge label SHALL be validated at boot,
stopping the boot and naming the variable to fix. A balance another service
supplied SHALL set no read timestamp, determine no tier, and grant, keep or
remove no role.

Acceptance Criteria
- Verified when the host target lands. No suite in `Tests/VerifyTests` claims
  evidence for any part of it, and `specs/verify/testing.md` records it as
  unevidenced so that a reader can tell which half is built.
- The half of the rate limit that can be proved offline is the session and
  subject bound in REQ-verify-003, and this requirement does not claim it.
- The half of the label rule that can be proved offline is the refusal at the
  mint in REQ-verify-002, and this requirement does not claim it either.

### REQUIREMENT REQ-verify-010

Before a member is asked to sign, the reply SHALL name who runs this server,
what will be kept about them and which of it other members can see, as plain
text rather than an embed so it can be copied on a phone, carrying the link
as text as well as a button, the six character code, and the expiry read from
the session's own `expiresAt`. Nothing in it SHALL name whoever wrote the
bot.

The page SHALL name the chat account the session belongs to, in the display
name that member's own chat client would show for it, and SHALL carry a
warning beside it in plain words: only continue if that account is yours, and
nobody should ever send you this link. The reply SHALL carry the same
warning. In a relayed prompt the member is on the operator's real page, on
the real origin, so the page cannot be made to lie about whose session it is,
and naming the account there is what a first-time verifier can read without
having a value to recognise. Carrying the same name in the signed bytes would
additionally defend a counterfeit page, which is a different attack, and it
would cost the rule in REQ-verify-001, so the name SHALL be rendered by the
host from its own record of the member and SHALL NOT enter a challenge, a
session, a refusal or any type the module declares.

The verification command SHALL take an optional wallet argument. With none it
behaves as above. With one, the host SHALL resolve it to a single address,
SHALL mint the session pinned to that address under REQ-verify-008, and
SHALL show the member the resolved address before they are asked to sign. The
argument MAY be a name rather than an address, and resolving a name is an
outbound call to a naming service: the boot SHALL NOT depend on that service,
a name that cannot be resolved SHALL be reported as such with a request for
the raw address instead so that a member who typed a name is never stuck, and
the module SHALL receive an address and never a name.

Acceptance Criteria
- Verified when the host target lands, along with the rest of the chat
  surface, and recorded as unevidenced in `specs/verify/testing.md`.
- The manual list run when the host lands has one tester send their own
  session link to a second tester and records whether the named account reads
  as somebody else's to a person who was not told what to look for.
- The manual list also confirms that a naming service made unreachable leaves
  the boot, verification by address, and every other surface working.
