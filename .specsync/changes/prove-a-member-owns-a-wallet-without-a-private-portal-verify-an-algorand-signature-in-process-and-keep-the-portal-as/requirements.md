---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: requirements
---

# Requirements

## User Stories

- As a member, I want to prove a wallet is mine without handing anybody a key,
  and without the flow feeling like a phishing page, so that the first thing I
  do in this server is not the thing I regret (VERIFY-1).
- As a member, I want what I sign to be readable on my phone and to carry
  something I can check against what Discord just showed me, so that I can
  tell a real prompt from a stolen one (VERIFY-1, VERIFY-6).
- As a member, I want the thing I sign to say which member it will be adopted
  for, so that a prompt somebody else started and handed to me is a prompt I
  can see is not mine (VERIFY-1, VERIFY-6).
- As a member, I want the page I am asked to sign on to say whose session it
  is, by the name I already know that account by, and to warn me plainly when
  it is not mine, so that a link a stranger sent me reads as a stranger's
  (VERIFY-1, VERIFY-6).
- As a member, I want to be able to name the wallet I mean before anything is
  signed, so that a proof signed by any other account is refused rather than
  adopted, and so that I find out I connected the wrong one before my wallet
  asks me to sign (VERIFY-1, VERIFY-2).
- As a member, I want to be able to type a name instead of an address, and to
  be asked for the address when the naming service cannot be reached, rather
  than being stuck with a command that will not take what I typed (VERIFY-1).
- As a member, I want a link somebody else got hold of to be no use to them,
  so that a screenshot of my own screen does not hand my wallet to a stranger
  (VERIFY-1, VERIFY-2).
- As a member, I want an address bound to the wrong person to be something an
  operator can release, so that somebody else's mistake or trick does not lock
  me out of my own wallet for good (VERIFY-2).
- As a member, I want to read what this server keeps about me, who runs it and
  which of it other members see, before I sign rather than after
  (VERIFY-6, VERIFY-7.a).
- As a member, I want what I prove here to mean nothing in any other server,
  even one running the same bot (VERIFY-4, HOST-6).
- As somebody running this, I want verification to work from one clone of one
  repository, without standing up a second service and without asking my
  members to trust anybody but me (VERIFY-5, ADOPT-4, HOST-1).
- As somebody running this, I want to know at startup which way of proving a
  wallet is live, and to be told plainly when the live one takes somebody
  else's word for it (ADOPT-9, BUILD-4, LEARN-8.a).
- As somebody running this, I want the part that proves a wallet failing to
  cost me verification and nothing else (SEE-7).
- As somebody running this, I want a naming service I do not run to cost a
  member one retyped address when it is down, and to cost my boot, my
  verification and every other surface nothing at all (SEE-7, SEE-10,
  TRUST-1).
- As somebody running this, I want no setting, anywhere, that turns off the
  signature check (BUILD-3, BUILD-3.a).
- As somebody running this, I want the words a member reads, and the message
  their wallet asks them to sign, to be my community's (ADOPT-1.c, ADOPT-1.f).
- As somebody running this, I want no member, however fast they type, to be
  able to spend the day's budget for reading the chain (RUN-11).
- As somebody deciding whether to install this, I want a new dependency to be
  a diff I can read rather than something that appeared quietly
  (TRUST-1, TRUST-1.b, TRUST-4).
- As a contributor, I want the whole proof path exercised with no network, no
  live wallet and no key anybody had to trust me with
  (BUILD-2, BUILD-2.a, BUILD-2.b).
- As a contributor, I want to tell which half of verification is built and
  which is still only written down (BUILD-4).

## Acceptance Criteria

Requirements REQ-verify-001 to REQ-verify-022, REQ-verify-030 to
REQ-verify-034 and REQ-verify-041 are satisfied and tested by this change.
REQ-verify-023 to REQ-verify-029, REQ-verify-035 to REQ-verify-040 and
REQ-verify-042 to REQ-verify-043 are obligations of the host target that does
not exist yet; they are defined here, in this change, so that the host has
nothing left to invent, and they are verified when it lands. That is
twenty-eight satisfied here and fifteen carried by the host. The split is
stated rather than blurred, because BUILD-4 is that somebody can tell which
parts are built.

The numbering runs in blocks because each block was added after the one before
it had already been cited across the other artifacts, and renumbering would
have silently changed what every citation means. 030 to 040 came from a
security review of this definition and the repair pass after it; `context.md`,
under "What the security review changed" and "What the second review found
still open", says what each of them closes. 041 to 043 came from the five
decisions the owner took after that repair, and `context.md` records those
under "The five decisions the owner took, and what they settle".

**One warning about the numbers, because two sets of them share a prefix.**
The forty-three requirements here are this change's own, and they live in this
workspace. `deltas/verify.md` carries the **canonical** contract for the new
module, and its requirements are numbered `REQ-verify-001` to
`REQ-verify-010`, starting at one because the module is new. Those ten
consolidate these forty-three; they are not the first ten of them. The
canonical text states a guarantee whole rather than citing a workspace that
will be archived, so nothing in the delta points back here. When reading a
`REQ-verify-NNN` elsewhere, the question to ask first is which of the two
documents it came from.

### REQ-verify-001

`Verify` SHALL be a library target depending on Foundation, `Algorand` and
`Crypto` only. It SHALL NOT depend on `Store`, `Chain`, `Gating` or `Reserve`,
SHALL NOT name a chat client, and SHALL take the member as an opaque subject
string it never interprets.

- Covered by `TargetShapeTests.swift` and by the manifest
  (VERIFY-7.b, HOST-2, TRUST-4).

### REQ-verify-002

`Verify` SHALL declare no private key type, no mnemonic, no signing call and
no transaction submission, and SHALL construct no node client. A source shape
test SHALL assert each of these by name, so that the absence is checkable
rather than promised.

- Covered by `TargetShapeTests.swift` (VERIFY-1, TRUST-1).

### REQ-verify-003

A challenge SHALL be five lines of UTF-8: an operator supplied label, an
identity for this instance, the subject this session was minted for, a six
character code, and a nonce of at least one hundred and twenty eight bits drawn
from the system random number generator. The nonce SHALL NOT be derived from
the subject, the address, the clock or any argument. Two challenges minted in
the same process SHALL differ.

The subject line is REQ-verify-030 and is what stops one member's signature
being adopted for another. It is the opaque subject string the caller supplied,
which above this boundary is the instance's own minted member key, so
REQ-verify-004 still holds: nothing that came from a person is in it.

**Five lines is an invariant, not a description of the usual case.** Nothing
here is five lines while the operator's label is an unconstrained string: a
label with a line break in it renders a six line challenge, and REQ-verify-030's
check, which reads the subject out of the submitted note, locates that line by
its index. So every value rendered into a line SHALL be refused if it carries a
line break of any kind (U+000A, U+000D, U+2028 or U+2029), and the operator's
label SHALL additionally be refused if it exceeds one hundred UTF-8 bytes. A
refused label SHALL be refused at the point the challenge would be minted, with
a named reason, rather than rendered and left to fail somewhere further on.
REQ-verify-040 is the other half: the host checks the label at boot and names
the variable, so an operator learns of it before a member does, the way a bad
tier rung already works in this repository.

- Covered by `ChallengeTests.swift`, including a collision probe over at least
  two thousand mints, a label carrying each of the four line break characters,
  and a label one byte over the bound (VERIFY-1, VERIFY-4, ADOPT-1.c).

### REQ-verify-004

No identifier that came from a person SHALL appear in a challenge, a session or
any type `Verify` declares. The subject SHALL be the value the caller supplies
and the caller of record SHALL be the minted member key.

The rule is about what crosses the boundary, not about what a member is
allowed to read. The name a member knows their own chat account by is shown to
them, on the ephemeral reply and on the page, both of which are the host's and
sit above this boundary: REQ-verify-043 is where that lives and why it is
there rather than in the signed bytes. Nothing carries it into a challenge, a
session, a refusal or any type `Verify` declares, and the host renders it from
its own record of the member rather than reading it back out of anything here.

- Covered by `ChallengeTests.swift` and `TargetShapeTests.swift`
  (VERIFY-7.b, HOST-2).

### REQ-verify-005

The instance identity SHALL be inside the signed bytes. A proof whose note
matches a challenge minted by a different instance SHALL be refused even when
every other field is correct and the nonce is identical.

- Covered by `ProofRefusalTests.swift`, with two coordinators differing only in
  instance identity (VERIFY-4, HOST-6, HOST-6.a, HOST-10).

### REQ-verify-006

A session SHALL carry `issuedAt` and `expiresAt`, and expiry SHALL be evaluated
against a `now` the caller supplies. Nothing in `Verify` SHALL read the clock.
A proof presented at or after `expiresAt` SHALL be refused with a reason naming
expiry, whatever else is wrong with it.

- Covered by `SessionTests.swift` (BUILD-2, BUILD-2.a).

### REQ-verify-007

A session SHALL be consumed on the first accepted proof and a consumed session
SHALL refuse every later proof, including a byte identical resubmission of the
one it accepted. A refused proof SHALL NOT consume the session, so that a
member who picked the wrong account in their wallet may try again. That
tolerance is bounded by REQ-verify-032: trying again is not unlimited, because
a session that accepts submissions for as long as somebody keeps sending them
is a way to make the host work on demand.

- Covered by `SessionTests.swift` and `ProofRefusalTests.swift`
  (VERIFY-1, VERIFY-2).

### REQ-verify-008

A proof SHALL be evaluated only against the challenge stored on the session it
was submitted to. A proof minted for one session and submitted to another
SHALL be refused at the note comparison, and the refusal SHALL NOT reveal the
other session's challenge.

- Covered by `ProofRefusalTests.swift` (VERIFY-1, VERIFY-4).

### REQ-verify-009

Exactly one proof shape SHALL be accepted: a transaction whose type is `pay`,
whose sender and receiver are the same address, whose amount is zero, whose
fee is at most one thousand microAlgos, which carries no lease and no group,
and whose note is the session's challenge bytes exactly. A signature over an
arbitrary message, with or without a wallet's data prefix, SHALL be refused,
and `Verify` SHALL offer no entry point that accepts one.

**The fee bound is the network minimum rather than zero, and both halves of
that are deliberate.** The fee is bounded at all because a zero amount self
payment is harmless only while its fee is: a page that builds the proof with
the fee set to the member's whole balance produces something this bot would
otherwise bless as proof of ownership, and the page keeps the blob. That is
the same argument REQ-verify-011 makes for a rekey, and an earlier draft of
this list stopped one field short of it.

It is bounded at the network minimum rather than at zero because nobody has
measured which wallets override a fee they were handed, and that uncertainty
is the reason the bound is not zero rather than a caveat beside it. A checker
that insists on zero locks out every wallet that raises a fee to the minimum
on the member's behalf, for a fee policy the page cannot enforce inside
somebody else's wallet, and the member reads a refusal they have no way to
act on. At the minimum, a blob that leaks costs a member a fraction of a cent
instead of their whole balance, which is the entire property the bound exists
for.

What is given up by not insisting on zero is said here rather than discovered
later, because an earlier draft claimed it as a feature. A zero fee with no
group makes the blob un-submittable outright: the network carries no
transaction that pays nothing, and fee pooling needs a group fixed before
signing. At the network minimum the blob becomes submittable again. Submitting
it moves nothing, from the member to the member, and costs the member one
minimum fee. That is the price of not guessing at wallet behaviour nobody has
tested, and it is smaller than the price of refusing a member whose wallet
will not sign a zero. The manual list measures which wallets force a minimum;
if every supported wallet turns out to honour a zero, tightening the bound is
a later change with a measurement behind it rather than a guess taken now.

- Covered by `ProofRefusalTests.swift`, including a fee one microAlgo over
  the bound refused and a fee at the bound accepted, and by
  `TargetShapeTests.swift` (VERIFY-1).

### REQ-verify-010

An absent `amt` key SHALL be read as an amount of zero and SHALL NOT be a
refusal. A present non-zero `amt` SHALL be refused. An absent `fee` key
SHALL likewise be read as a fee of zero, never as a fee that is unknown or
unbounded, and a present `fee` above the bound REQ-verify-009 fixes SHALL be
refused. A canonical encoder omits both keys when their value is zero, so
requiring either key refuses every correctly formed proof.

Reading an absent fee as zero is the half of this that the widened bound makes
easier to get wrong, so it is stated rather than implied. Under a strict
equality both readings of a missing key, zero and unknown, end in a refusal,
so a reader that treats the key as unknown looks correct. Under a bound they
part company: a missing key read as unknown is an accepted proof whose fee
nobody checked. The rule is that the reader supplies zero for a key that is
not there, and the bound is applied to that value like any other.

- Covered by `SignedTransactionReaderTests.swift` with a blob a real signer
  produced for a zero amount, zero fee payment, which omits both keys, and a
  case proving an absent `fee` reads as zero rather than as unbounded
  (VERIFY-1).

### REQ-verify-011

A transaction carrying `rekey`, `close`, `aclose`, `lx` or `grp` SHALL be
refused, each with its own reason, whether or not the signature is valid.

The wire name for a rekey is **`rekey`**. An earlier draft of this requirement
wrote `rekeyto`, which is the name of the field in the dependency's own
transaction type and is not the name it puts on the wire: its canonical
encoder emits `rekey`, beside `close` and `aclose`, which were right. Coded
literally, `rekeyto` would have matched nothing, the tolerant reader would have
skipped the real key as unknown, and every rekeying proof would have been
accepted with a valid signature. A page could then have had the bot bless a
blob that hands the member's account to somebody else, and the page keeps the
blob.

`lx` is a lease: the same blob can block the member's own transactions for the
validity window. `grp` means the proof was one leg of an atomic group the
member approved wholesale.

- Covered by `ProofRefusalTests.swift`. Every forbidden key name a fixture uses
  SHALL be obtained from, or asserted equal to, the name the dependency's own
  canonical encoder emits for that field, so that the name in the test and the
  name on the wire cannot drift apart and a rename in the dependency turns the
  suite red rather than turning the check off. A hand built fixture would have
  carried the same wrong name as the code and gone green over the hole.

  Four of the five come out of a payment encoder directly: a rekey, a close, a
  lease and a group can all be set on a payment and encoded. `aclose` is
  emitted only by an asset transaction, so its name is asserted against that
  encoder's output and then used in a payment fixture. The asset transaction
  itself is a separate case and is refused at the transaction type step, which
  is earlier; both cases are needed, because the type refusal does not exercise
  the `aclose` refusal (VERIFY-1).

### REQ-verify-012

The signature SHALL be checked over the bytes `TX` followed by the transaction
bytes **sliced out of the submitted blob**. `Verify` SHALL NOT re-encode parsed
fields and check over the result, and SHALL expose no path that does.

- Covered by `SignedTransactionReaderTests.swift`, asserting the returned slice
  is byte identical to the sub-range of the input, and by
  `TargetShapeTests.swift` (VERIFY-1).

### REQ-verify-013

Refusals SHALL be produced in this order, and a later reason SHALL NOT be
returned while an earlier one holds: session state, session expiry, blob
decode, transaction parse, missing fields, transaction type, **pinned
address**, sender, receiver, amount, fee, forbidden fields, **subject**, note,
signature. That is fifteen reasons. A member whose wallet had the wrong
account selected SHALL be told the sender did not match, never that their
signature was bad.

Numbered, because other artifacts cite the positions: 1 session state,
2 session expiry, 3 blob decode, 4 transaction parse, 5 missing fields,
6 transaction type, 7 pinned address, 8 sender, 9 receiver, 10 amount, 11 fee,
12 forbidden fields, 13 subject, 14 note, 15 signature.

Session state covers a consumed session, a session that has run out of
attempts under REQ-verify-032 whether the bound reached was the session's or
the subject's, a session displaced under REQ-verify-019, a session id that
selects nothing, and a second differing connected address under
REQ-verify-019. Transaction parse covers the canonicality refusals in
REQ-verify-014. Forbidden fields covers all five named in REQ-verify-011.

**Pinned address sits before sender**, and fires only on a session pinned to
an address under REQ-verify-041. The two are different sentences to the
member: pinned address says this is not the account you named when you ran
the command, and sender says this is not the account you connected in your
wallet. Whenever both hold the first is the more useful, because the member
chose the pinned address themselves and can compare it against what their
wallet is showing them, so it is the one returned. On an unpinned session the
position is skipped and sender is the first address reason a member can
reach.

**Subject sits immediately before note, and it was unreachable until it did.**
REQ-verify-030 asks for a distinct reason when a proof's challenge names
another subject, and REQ-verify-009 compares the note against the session's
challenge bytes byte for byte. Behind a byte-exact comparison the note reason
fires first on every such proof, so the subject reason could never be returned
and the member could never be told the one thing that distinguishes a relayed
prompt from a mistyped one. The subject check therefore reads the subject line
out of the **submitted** note, at the line index REQ-verify-003 fixes, and
compares it against the session's own subject before the note is compared at
all. It SHALL NOT rebuild the expected challenge from the submitted note, which
would make the note comparison a tautology; it reads one line and compares one
value.

- Covered by `ProofRefusalTests.swift`, one case per reason, fifteen of them,
  each with every later reason also violated (VERIFY-1).

### REQ-verify-014

The reader SHALL accept standard base64 and URL-safe base64, with or without
padding and with surrounding whitespace, and SHALL accept a bare `{sig, txn}`
map, that map wrapped in a one element array, and a map carrying an additional
signer key. It SHALL refuse anything else, at any depth, without trapping and
without allocating in proportion to a length the input declares but does not
carry. It SHALL impose a nesting depth limit and a blob size ceiling, and
SHALL apply the ceiling before parsing begins, so that neither the recursion
depth nor the total work is chosen by whoever posted the blob.

The reader SHALL also refuse a duplicate key at any depth, a transaction map
whose keys do not ascend by their UTF-8 bytes, and any byte remaining after the
end of the envelope. Tolerance of how a blob is spelled is not tolerance of a
blob that says two things. The page supplies the unsigned bytes, so the page
chooses the encoding; a transaction map carrying `amt` twice, zero first and a
large value second, is one document the wallet can display one way and the
checker read the other way, with one signature over both, and REQ-verify-012
guarantees that signature stays valid over whichever reading is carried away.
Refusing costs a set of the keys seen and one comparison per key, and it
removes the class rather than the instance.

- Covered by `SignedTransactionReaderTests.swift`: one canonical blob from a
  generated key, re-encoded into each accepted shape, plus truncation at every
  byte offset of the canonical blob, plus the declared-length, depth-limit and
  ceiling cases, plus one duplicate key case per depth, one descending key
  order case and one trailing byte case (BUILD-2, BUILD-2.a).

### REQ-verify-015

A signature that fails against the account's own key SHALL be refused with a
reason distinguishable from every other reason, so that a caller may look up an
authorising address and ask once more. That reason SHALL say whether the retry
is still available for this session, which REQ-verify-032 defines and bounds at
one. `Verify` SHALL NOT perform that lookup and SHALL hold nothing that could,
and REQ-verify-037 says where the caller may get the key from.

- Covered by `ProofRefusalTests.swift` and `TargetShapeTests.swift`
  (RUN-11, SEE-1.b).

### REQ-verify-016

`Verify` SHALL accept an authorising key supplied by the caller in the proof
expectation, and SHALL accept a proof signed by it, so that a rekeyed account
can still prove ownership. The key SHALL come from nowhere else: `Verify`
SHALL NOT read it from the submitted blob, SHALL NOT surface the signer key
the reader skips, and SHALL NOT derive it from the address.

Whether the account actually names that key is the caller's to establish, and
REQ-verify-037 is the obligation that says how. `Verify` cannot check it and
SHALL NOT read as though it did: without that obligation this requirement
reduces to "if the caller hands you a key, accept a signature by that key for
any address", which is the reference portal's test-mode bypass reached through
a parameter instead of an environment variable. An outcome produced under an
authorising key SHALL record that it was, so that the audit can tell a proof by
the account's own key from a proof by a key the caller vouched for.

- Covered by `ProofRefusalTests.swift`, with two generated keys, and by
  `TargetShapeTests.swift` for the absence of any other path to the key
  (VERIFY-1).

### REQ-verify-017

There SHALL be no input value, environment variable, build configuration or
compilation condition under which a proof is accepted without a valid
signature. A test SHALL submit the literal strings the reference portal accepts
under its test flag, and a range of other fixed strings, and SHALL assert each
is refused.

- Covered by `NoBypassTests.swift` and `TargetShapeTests.swift`, the latter
  asserting no environment read anywhere in the target
  (BUILD-3, BUILD-3.a, BUILD-3.b).

### REQ-verify-018

`Verify` SHALL NOT log, and SHALL NOT return in any refusal, the submitted
blob, the signature, the challenge in full, **or the session id**. A refusal
SHALL carry a reason and a non-reversible handle: either a truncated hash of
the session id or an opaque per-refusal identifier minted for the purpose,
which the host can correlate against its own record and which nobody can turn
back into the credential.

This requirement used to say the refusal carries the reason and the session id,
which REQ-verify-036 forbids from ever reaching a log or an error report, and a
refusal is the thing a host logs. The two could not both hold. REQ-verify-031
settles which gives way: the session id is a bearer credential, so it does not
travel in the one value whose whole purpose is to be written down somewhere a
human reads later. The clause "and nothing else that could be replayed" is
gone rather than kept, because it was defending the session id as unreplayable
and it is not.

- Covered by `ProofRefusalTests.swift`, asserting the refusal's contents
  exhaustively and that the session id is not among them, and by
  `TargetShapeTests.swift` (VERIFY-7, HOST-2).

### REQ-verify-019

This requirement owns session lifecycle: how many live sessions a subject has,
what a session records as it moves through its states, and when a session and
its challenge are discarded.

A consumed or expired session SHALL be discarded along with its challenge. The
session store protocol SHALL offer a prune taking a `now`, and the in-memory
conformer SHALL hold nothing for a session it has pruned.

One exception, stated here so it does not read as a violation: the per-subject
submission count REQ-verify-032 requires is **subject** state, not session
state, and survives the pruning of every session it counted. It holds no
challenge, no address and no session id, and the same prune drops it once the
window it is counted over has passed.

**One live session per subject.** Minting a session for a subject that already
has a live one SHALL displace the first. The displaced session and its
challenge SHALL be discarded immediately rather than left to expire. What
SHALL NOT be discarded with it is the subject's submission count under
REQ-verify-032: a bound that a new session resets is not a bound.

**One reason for every session id that selects nothing.** A session id that
was never issued, or was consumed, or expired and was pruned, or was displaced,
SHALL be refused at the session state step with a single reason that does not
say which of those it was. Distinguishing them tells whoever holds a stolen id
whether it was ever real, and tells an enumerator when a member is mid-flow.

REQ-verify-006 is not weakened by this: a session still held and past
`expiresAt` reports expiry, because the member needs to know a new link is what
fixes it. Once it has been pruned there is nothing left to tell it apart from
an id that never existed, and that is the right answer rather than a gap.

**One live session per subject lived in `tasks.md` and `plan.md` and in no
requirement**, which is the shape the second review kept finding: a property
the implementer builds from, with nothing above it that a test has to satisfy.
So did the rule below.

**The connected address is recorded once.** A session SHALL record the address
it was connected to the first time one is presented, and SHALL refuse a second,
differing address on the same session, without answering anything about that
address. REQ-verify-028 is the reason: the host's "already proved by somebody
else" check is an oracle if a session can ask it about address after address,
and binding the question to the session is what turns it from a lookup service
into one answer about the one address the member actually connected.

**A pinned session records its address at the mint.** Where REQ-verify-041
applies, the session carries the address the member named before anything was
signed, and the first address presented that differs from it SHALL be refused
with the pinned address reason rather than recorded as the connected address.
That is the earlier mismatch the wallet argument buys: a member who names one
wallet and then connects another learns it before their wallet asks them to
sign, instead of after.

- Covered by `SessionTests.swift`: the prune case, the displacement case, the
  one-reason case for a session id that selects nothing, and the second
  differing address (VERIFY-7, VERIFY-3, VERIFY-2).

### REQ-verify-020

Both routes SHALL converge on one downstream value carrying the subject, the
address, when, and which route produced it. Nothing downstream SHALL branch on
the route except the audit line and the operator facing report of it.

The two routes SHALL NOT share a producer. `ProvedAccount` SHALL be produced
only by consuming a signature, and SHALL NOT be constructible from outside the
module. The asserted route SHALL have a distinct public type of its own,
carrying what the other service said, which the host converts into the
downstream value deliberately and in a call that names the route. See
REQ-verify-034, which is where this is stated as a rule rather than as a shape.

- Covered by `OutcomeTests.swift` and `NoBypassTests.swift` (VERIFY-2,
  HOST-8.a).

### REQ-verify-021

The whole target SHALL be exercised with no network, no live wallet and no
supplied key. Every valid proof in the tests SHALL be produced by a real
signer over the real challenge with a key generated in the test, and no test
SHALL assert a path the production code does not take.

- Covered by every suite in `Tests/VerifyTests`, whose signer is built on
  `Account()` and `SignedTransaction.sign(_:with:)`
  (BUILD-2, BUILD-2.a, BUILD-2.b, BUILD-1.b, PLAY-11).

### REQ-verify-022

`swift-crypto` SHALL be declared as a direct dependency of this package at the
version already in `Package.resolved`, and no resolved version SHALL move.
`docs/WHAT-IT-TALKS-TO.md` SHALL be edited in this change to say so, `Verify`
SHALL be listed there as a target that opens no connection, and the change
SHALL be named in `CHANGELOG.md` under `Unreleased`.

The same document SHALL record the naming service REQ-verify-042 introduces,
as a host the bot reaches **when the host target lands** and reaches from
nowhere today, flagged as not yet true in the way that document already flags
what a member's browser will reach. The disclosure belongs in the change that
decides the call rather than in the one that finally makes it, because TRUST-1
is a list somebody reads before they install. The entry SHALL say that the
call is optional, that it happens only when a member types a name rather than
an address, that nothing refuses to start without it, and that `Verify` is not
the target that makes it.

- Covered by `Package.resolved` being unchanged in its pins, and by the
  documentation gate (TRUST-1, TRUST-1.b, TRUST-4).

### REQ-verify-023

*Host obligation.* Exactly one prover route SHALL be named explicitly in
configuration. Naming none, and naming both, SHALL each stop the boot with a
message naming both variables and saying which to set. No route SHALL be
defaulted.

- Verified when the host lands (ADOPT-6, ADOPT-6.a, ADOPT-7.a, ADOPT-8,
  RUN-9.a, ADOPT-2).

### REQ-verify-024

*Host obligation.* Startup SHALL state which route is live. On the asserted
route it SHALL also state, in words an operator reads rather than a status
code, that the proof is the other service's word and the shared secret is the
whole trust boundary.

- Verified when the host lands (ADOPT-9, BUILD-4, LEARN-8.a, TRUST-1).

### REQ-verify-025

*Host obligation.* On the asserted route the startup check SHALL carry the
shared secret, and a secret the other half does not agree with SHALL stop the
boot naming the variable. An operator SHALL NOT learn of a mismatch from a
member whose command refused.

- Verified when the host lands (VERIFY-5.b, VERIFY-5.a).

### REQ-verify-026

*Host obligation.* A prover that fails after boot SHALL disable verification
and nothing else. Role sweeps, games, payouts and every other surface
SHALL carry on, and `/verify` SHALL answer with a refusal written for a
member.

- Verified when the host lands (SEE-7).

### REQ-verify-027

*Host obligation.* The reply to `/verify` SHALL name who runs this server, what
will be kept about the member, and which of it other members can see, **before**
the button. It SHALL be plain text rather than an embed, so it can be copied on
a phone, and SHALL carry the link as text as well as a button. It SHALL carry
the six character code and the expiry, the expiry read from the session's own
`expiresAt` rather than written into a sentence. Nothing in it SHALL name
whoever wrote the bot.

The command's optional wallet argument is REQ-verify-042 and the warning this
reply carries about a link somebody else sent is REQ-verify-043. Both are
stated there rather than here, so that this requirement keeps owning what a
member reads before they decide and neither of the other two has to repeat
it.

- Verified when the host lands (VERIFY-6, VERIFY-7.a, ADOPT-1.c, ADOPT-1.f).

### REQ-verify-028

*Host obligation.* An address another member has already proved SHALL be
refused at the moment the member connects it, before they are asked to sign,
and SHALL be refused again at adoption. The member SHALL be told which of the
two happened in terms they can act on.

**The check SHALL be bound to the session, and answered at most once.** As
first written it answers "does this address already belong to a member of this
guild?" for any address, to anybody holding a session, which is an enumeration
oracle: the holder lists this product publishes are public, so a member can
walk them and learn which addresses belong to members of their own server. So
the session records the address it was connected to the first time, per
REQ-verify-019, and that is the only address the check is ever run for. A
second, differing address presented on the same session SHALL be refused
**without an answer**: the member is told the session is already connected to
an address and offered a new one, and is told nothing about whether the second
address is known here. A member who genuinely connected the wrong wallet runs
the command again, which costs them one interaction and costs an enumerator one
session per address, which is a real cost only because REQ-verify-038 rate
limits the command that mints one.

- Verified when the host lands (VERIFY-2, HOST-6.a, VERIFY-7).

### REQ-verify-029

*Host obligation.* An account proved before a successful chain read SHALL be
stored with `balancesReadAt` nil, never zero, and SHALL NOT cause a role to be
taken away.

On the asserted route the balance the other half supplies SHALL NOT set
`balancesReadAt`, SHALL NOT determine a tier, and SHALL NOT grant, keep or take
away any role. It may be shown to an operator, labelled as the other service's
word and not this bot's reading. No role SHALL follow from it until the bot's
own chain read succeeds.

An earlier draft said the supplied tier was never used while the supplied
balance was used when a chain read failed. That forbids nothing, because a tier
is a pure function of a balance through the ladder: the host computes the same
tier from the same untrusted number and the ban is a formality. The condition
for reaching it, a failed chain read, is also something a stranger could arrange
on demand until REQ-verify-038 landed. An advisory balance that can set a role
is not advisory.

- Verified when the host lands (ROLE-1.a, VERIFY-5).

### REQ-verify-030

The subject SHALL be inside the signed bytes, as the third challenge line, and
a proof whose challenge does not carry the submitted session's own subject
SHALL be refused with a reason of its own, distinct from the note reason.

That reason is the thirteenth of the fifteen REQ-verify-013 orders,
immediately before note, and it is read from the **submitted** note rather than from the
session's stored challenge. Both halves of that sentence are load bearing.
Reading it from the stored challenge compares the session's subject against
itself and always passes. Placing it after note makes it unreachable, because
the note is compared byte for byte and a proof naming another subject differs
in the note. An earlier draft of this requirement asked for the reason and gave
it neither a position nor a source, so it was a refusal no implementation could
ever return. The same draft called the subject "the fifth challenge line",
meaning the fifth line the security review added rather than the fifth line of
the challenge; REQ-verify-003 and `design.md` both put it third, and an
implementer reading the subject out of line five would have read the nonce.

Without it a challenge is a prompt anybody can pass to anybody. An attacker
runs the verification command, gets a session and its link, and sends the link
to a member. That member opens the operator's real page on the real origin,
connects their wallet, signs a prompt that looks exactly as it should, and the
blob is posted to the attacker's session. The bot then proves the member's
address for the attacker, who takes the roles and the payouts that address
earns, and the member is locked out of proving their own wallet by the refusal
in REQ-verify-028. The six character code does not help, because the member
never ran the command and no code would be familiar to them.

The design argued that the subject was already bound because "the note is
compared against the challenge stored on the one session it was issued for, and
that session has one subject". That is true and it is not the property needed:
it stops a proof being moved between sessions, and the attack never moves one.
What was missing is that the bytes the member reads never said who the proof
was for.

The line makes the binding visible in the wallet, and REQ-verify-035 is what
turns visible into checkable for a member who has seen their own subject value
before. It does nothing for a first-time verifier, who has no baseline to
compare against, and that gap is answered on the page rather than in the
bytes: REQ-verify-043 has the operator's own page name the chat account the
session belongs to, in the words a member already knows that account by, with
a warning beside it.

**The subject line stays exactly as it is, and both values are kept.** It is
not person-derived, so it costs REQ-verify-004 nothing, and it is the thing
that stops a proof being moved between sessions, which no page-level display
can do. What REQ-verify-043 adds is a human-readable account name on the page,
beside it rather than instead of it.

- Covered by `ChallengeTests.swift` for the line, and by
  `ProofRefusalTests.swift` for a proof whose subject line names another
  subject (VERIFY-1, VERIFY-4, VERIFY-6).

### REQ-verify-031

A session id SHALL be at least one hundred and twenty eight bits drawn from the
system random number generator, SHALL NOT be derived from the subject, the
address or the clock, SHALL be compared whole, and SHALL be the only thing that
selects a session. `Verify` SHALL treat it as a credential and REQ-verify-036
says how the host SHALL carry it.

It is worth saying out loud because nothing said it: whoever holds a session id
can submit a proof against that session, and the proof binds whatever address
they connect to whatever member the session names. The id is therefore the
whole credential, and a credential nobody has called one ends up in a query
string, a screenshot, an access log, a browser history or a `Referer` header
sent to a third party asset.

- Covered by `SessionTests.swift` for width, source and whole comparison
  (VERIFY-1, VERIFY-2).

### REQ-verify-032

A session SHALL record how many submissions have been made against it, and
SHALL refuse further submissions once a fixed maximum is reached, with a
reason of its own reported at the session state step. A session SHALL also record whether the
authorising key retry has been used, and the signature refusal SHALL report the
retry as available at most once per session.

**The maximum SHALL be at least three.** A floor is as load bearing as the
ceiling, and the requirement had none, so an implementer could satisfy every
test written against it with a maximum of one. Three is what an honest member
on a rekeyed account needs: one submission with the wrong account selected in
their wallet, one with the right account which fails the signature check
because the account is rekeyed, and one more when the host calls the checker
again with the authorising key it read. A maximum below three locks out exactly
the class REQ-verify-016 exists to serve, and every specified test still
passes, because refusing too early looks identical to bounding correctly.

**The bound SHALL also be kept per subject, not only per session.** A session
bound alone is defeated by session churn: REQ-verify-019 has a new session
displace the subject's previous one, so a member who has spent their
allowance runs the command again and gets a fresh one. The session store
SHALL therefore keep, per subject, the total submissions made and the total
authorising key retries offered within a window the caller supplies, SHALL NOT
reset either when a session is displaced, consumed, expired or pruned, and
SHALL refuse a submission that would exceed the per-subject maximum at the
session state step with the same reason. The window SHALL be evaluated against
the same `now` the caller supplies everywhere else, so REQ-verify-006 still
holds and nothing here reads a clock. The per-subject maximum SHALL be
larger than the per-session maximum, so that the ordinary case, a member who
ran the command twice because the first attempt confused them, is not refused
by the defence against a member who ran it two hundred times.

This is the half of the budget story that can be proved offline, and it is
bounded per subject rather than per source because a subject is what `Verify`
can see. A stranger with many subjects is REQ-verify-038's, which rate limits
per member **and per source**, and neither half discharges the story alone.

This is the requirement that carries the offline half of the user story about
no member being able to spend the day's budget for reading the chain, and
REQ-verify-038 carries the rest. It is written as a half rather than as a
closure because the first version of it claimed the whole story and did not
have it: bounded per session and defeated by minting sessions. Before either,
that story had nothing behind it at all: REQ-verify-007 guarantees a refused
proof does not consume
the session, "at most once per session" existed only as prose in `design.md`,
and `plan.md` left rate limiting to "the transport", of which there is none. One
verification command followed by a loop of field correct proofs signed by a
throwaway key would pass every field check, fail the signature, spend a chain
read on the authorising address each time, and leave the session alive for the
next one. One member could exhaust the day's budget and pause role sync, rain,
claim and the reserve for everybody.

The bound belongs here rather than only in the host because it is the half that
can be proved offline. REQ-verify-038 is the other half.

- Covered by `SessionTests.swift` for the per-session bound, the floor of
  three, the per-subject bound surviving a displaced session, and the single
  retry flag; and by `ProofRefusalTests.swift` for the reason ordering
  (RUN-11, VERIFY-1).

### REQ-verify-033

The reader SHALL NOT surface a signer key carried in the envelope, and no value
read out of the submitted blob SHALL be usable as the key a signature is checked
against. The only keys a signature is ever checked against SHALL be the claimed
address and the authorising key in the proof expectation.

- Covered by `SignedTransactionReaderTests.swift` for the skipped signer key,
  `ProofRefusalTests.swift` for a blob naming its own signer, and
  `TargetShapeTests.swift` (VERIFY-1).

### REQ-verify-034

No public interface of `Verify` SHALL return a proved account without consuming
a signature. The value the asserted route produces SHALL be a distinct public
type, named for what it is, with its own public initialiser, and converting it
into the downstream value SHALL be an explicit call that tags the route as
asserted.

An earlier draft said both routes produce one `ProvedAccount`, that the same
value can be constructed for the asserted route, and that the initialiser of
`ProvedAccount` is not public. Those three cannot all hold. The natural way to
resolve them in code is a public factory that mints an unchecked proved account
inside the one target whose whole claim is REQ-verify-017, and the no bypass
suite as written would not have seen it, because it only checks the initialiser.
Two types, one seam, and the unchecked one says asserted in its name.

- Covered by `NoBypassTests.swift`, which SHALL assert over the target's public
  interface rather than over one initialiser, and by `OutcomeTests.swift`
  (BUILD-3, BUILD-4, VERIFY-2).

### REQ-verify-035

*Host obligation.* The ephemeral reply SHALL print the same subject value that
REQ-verify-030 puts in the signed bytes, and the page SHALL display it beside
the six character code, so that a member can compare what their wallet shows
against what their own chat client showed them. The reply SHALL say, in plain
words, that a signing prompt they did not just start is somebody trying to take
their wallet. REQ-verify-043 is the other half of what the page shows: the
chat account the session belongs to, named, with the warning beside it, which
is what a first-time verifier can read without having a subject value to
recognise.

Adoption SHALL require a confirmation by the subject, after the proof has been
checked, offered on the ephemeral interaction that issued the session. A proof
alone SHALL NOT bind an address.

**Where the checked proof waits, because the session is gone by then.** The
session is consumed the moment the proof is accepted (REQ-verify-007) and
discarded with its challenge (REQ-verify-019), so the confirmation cannot hang
off it, and on a phone the chat client may have been killed during the hand off
to the wallet, so it cannot depend on that one interaction still being alive
either. As first written this requirement asked for a confirmation with nowhere
to put the thing being confirmed.

So the host SHALL hold a **pending proof** record, outside the session store,
with these properties:

- It is keyed by the **subject**, never by the session id, so that the member
  can be shown it on the interaction that issued the session and also on a
  fresh interaction they start themselves after their client was killed. One
  pending proof per subject; a second accepted proof replaces the first.
- It carries the address, the route, when the proof was checked, and nothing
  that could be replayed: not the blob, not the signature, not the challenge
  (REQ-verify-018).
- It has **an expiry of its own**, independent of the session's, long enough to
  survive reopening a chat client and short enough that a proof nobody
  confirmed does not sit there for a day. On expiry it is discarded.
- **An unconfirmed pending proof binds nothing.** No `AccountRecord`, no role,
  no audit line beyond the fact that a proof was checked and not confirmed.
  Expiry is silent to everybody but the member, who is offered a new session.
- Confirming SHALL require the subject to match the pending proof's subject.
  Nothing else SHALL be able to confirm it.

What each part closes, stated exactly, because a half measure described as a
closure is worse than none. The confirmation closes adoption by somebody who
merely came into possession of a link: they can sign, and they cannot confirm.
It does not close the relay in REQ-verify-030 on its own, because in that
attack the attacker owns the session and can confirm on their own interaction.
The relay is answered by REQ-verify-043, on the page, where the account the
session belongs to is named in words a member reads without having to
recognise anything first. What this requirement carries is the rest of the
defence around it: the subject value a returning member can check against
their own chat client, and the confirmation that makes a link on its own
worthless to whoever holds it.

- Verified when the host lands (VERIFY-1, VERIFY-6, VERIFY-2).

### REQ-verify-036

*Host obligation.* The session id SHALL be treated as a bearer credential. It
SHALL be delivered only in the ephemeral reply, SHALL travel to the page in the
URL fragment or in a request body and never in a query string, SHALL never be
written to a log, an access log, an error report or a crash report, and the
page SHALL be served with a referrer policy of `no-referrer` so that no third
party asset receives it in a `Referer` header.

The reference portal puts its token in a query string, which is the concrete
version of every one of those leaks at once.

- Verified when the host lands (VERIFY-1, VERIFY-2, VERIFY-7).

### REQ-verify-037

*Host obligation.* An authorising key passed to `Verify` SHALL come only from
the host's own chain read of that exact account's authorising address field.
It SHALL NOT be taken from the submission, from the blob, from configuration or
from a development stub, and the read SHALL be attempted at most once per
session, only on the signature refusal that reports a retry as available.

This is the obligation REQ-verify-016 depends on. Without it, an attacker
submits a well formed zero self payment naming any address as sender, with the
correct note, signed by a key they generated, and passes that key as the
authorising key. Every check passes and any address becomes claimable by anybody
who can type it.

- Verified when the host lands (VERIFY-1, RUN-11, BUILD-3).

### REQ-verify-038

*Host obligation.* The verification command and the submit route SHALL both be
rate limited, per member and per source, and the limits SHALL be part of the
host rather than assumed of something in front of it. No member SHALL be able
to cause an unbounded number of chain reads, and the budget pause SHALL be
reached by the rest of the bot's work rather than by one member's submissions.

Rate limiting SHALL NOT be recorded as belonging to "the transport". `plan.md`
said that while no transport existed, which is how a defence ends up owned by
nobody.

- Verified when the host lands (RUN-11, SEE-7).

### REQ-verify-039

*Host obligation.* An address bound to the wrong member SHALL be releasable by
an operator, with an audit line naming who released it and from whom. The
refusal in REQ-verify-028 SHALL NOT be permanent without that path.

REQ-verify-028 is what makes an address one member's only. It is also what
turns a successful relay or a leaked link into a member who can never prove
their own wallet, and a lock with no key is not a safety property.

- Verified when the host lands (VERIFY-2, HOST-6.a, SEE-7).

### REQ-verify-040

*Host obligation.* The operator's challenge label SHALL be validated at boot:
a label carrying a line break of any kind, or exceeding the bound
REQ-verify-003 fixes, SHALL stop the boot with a message naming the variable to
fix and saying what is wrong with it. An operator SHALL NOT learn of it from a
member whose wallet showed them six lines.

This is the same shape as a bad tier rung, which stops the boot and names the
variable rather than silently dropping a rung (ADOPT-1.a, ADOPT-2). It is a
host obligation because `Verify` reads no environment variable
(REQ-verify-002), so the only place a configured value can be checked before a
member sees it is where the configuration is loaded. REQ-verify-003 is the
offline half: the mint refuses the same label with a named reason, so a host
that forgets this obligation fails a challenge rather than rendering a
malformed one.

- Verified when the host lands (ADOPT-1.c, ADOPT-2, ADOPT-7.a, VERIFY-6).

### REQ-verify-041

A session MAY be pinned to a single address at the mint. Where it is, a proof
whose sender is any other address SHALL be refused with a reason of its own,
saying that the account named when the session was minted is not the account
that signed. That reason is the seventh of the fifteen REQ-verify-013 orders.
The first address presented on a pinned session that differs from the pin
SHALL be refused with the same reason rather than recorded as the connected
address (REQ-verify-019).

The pin SHALL be an address and nothing else. Turning a name into an address
belongs to the host under REQ-verify-042, and `Verify` SHALL NOT hold a name,
SHALL NOT resolve one, and SHALL NOT acquire anything that could. This is the
target that reads nothing, and a naming service is a network read.

**What pinning buys, said honestly, because it is less than it looks.** It
does **not** close the relay. An address is public: an attacker who wants a
particular member's wallet can name that member's own address in their own
session, and every check the bot can run still passes. What it buys is three
smaller things, each of them real. The refusal is better, because a member who
named an account and signed with another is told exactly that rather than
told the sender did not match something they never chose. The mismatch comes
earlier, at the connect rather than after a signature. And the member has
committed to an address before they were asked to sign, which is one more
thing a relayed prompt has to agree with, and one more moment at which the
member is thinking about which wallet this is for.

- Covered by `ProofRefusalTests.swift`, with a pinned session and a proof from
  a second generated key, asserting the pinned address reason and not the
  sender reason; and by `SessionTests.swift` for the connect refusal on a
  pinned session (VERIFY-1, VERIFY-2).

### REQ-verify-042

*Host obligation.* The verification command SHALL take an optional wallet
argument. With no argument it SHALL behave exactly as REQ-verify-027 defines,
unchanged. With one, the host SHALL resolve the argument to a single address,
SHALL mint the session pinned to that address under REQ-verify-041, and
SHALL show the member the resolved address before they are asked to sign, so
that what was pinned is what they meant.

The argument MAY be a name rather than an address. Resolving a name is an
outbound call to a naming service this package does not talk to today, which
makes it a new host in `docs/WHAT-IT-TALKS-TO.md` under REQ-verify-022 and a
new thing that can be down. Three rules follow, and none of them is optional.

- **The boot SHALL NOT depend on it.** No startup check pings the naming
  service, and one that is unreachable, or that an operator never configured,
  SHALL NOT stop the bot starting and SHALL NOT disable verification.
- **A failure SHALL fail soft, and SHALL say so.** When a name cannot be
  resolved, the member SHALL be told that the naming service could not be
  reached and asked for the raw address instead, and the command SHALL stay
  usable with an address. A member who typed a name SHALL NOT be left stuck,
  and SHALL NOT be handed a session pinned to a guess.
- **The resolution SHALL sit above the verifying target.** `Verify`
  SHALL receive an address and never a name, so the target keeps the property
  REQ-verify-001 and REQ-verify-002 give it: it reads nothing.

An unresolved name SHALL NOT be treated as though it were an address, and an
argument that already parses as an address SHALL NOT be sent to the naming
service at all.

- Verified when the host lands (VERIFY-1, VERIFY-2, SEE-7, SEE-10, TRUST-1,
  TRUST-1.b).

### REQ-verify-043

*Host obligation.* The page a member signs on SHALL name the chat account the
session belongs to, in the display name that member's own chat client would
show for it, and SHALL carry a warning beside it in plain words: only continue
if that account is yours, and nobody should ever send you this link. The
ephemeral reply SHALL carry the same warning, so a member reads it before they
leave the chat client and again when they arrive.

**Why the page is where this goes, and why the page is enough for this
attack.** In the relay the victim is on the **operator's real page**, on the
real origin, served by the operator's own process. The attacker's whole
contribution is a link, so nothing about the page can be made to lie about
whose session it is. Page-level display is therefore sufficient against the
relay, and it is sufficient for a first-time verifier, who has no subject
value to recognise and every reason to recognise a name that is not theirs.

Putting the same name in the signed bytes would additionally defend a
**counterfeit** page, one the operator did not serve. That is a different
attack with a different answer and it is not what this closes. It would also
cost the rule in REQ-verify-004, by carrying an identifier that came from a
person below the chat boundary and into the one target whose claim is that it
holds none. The page pays neither price, so the page is where the name goes.

The name SHALL be rendered by the host from its own record of the member, and
SHALL NOT be carried in a challenge, a session, a refusal or any type `Verify`
declares. REQ-verify-030's opaque subject line stays exactly as it is, beside
this and not replaced by it: it is what stops a proof moving between sessions,
which no page can do.

**What is left over, said plainly rather than dismissed or inflated.** This
attack needs a member to take a link from a stranger and sign what it shows
them. The server rules an operator already publishes cover that, and every
wallet warns about it too. It is a real attack and it is largely user error.
The honest residue is a first-time verifier, who has no baseline for what
normal looks like here and no reason yet to read an unexpected link as
unusual: the named account and the warning are the whole of what stands
between them and a relayed prompt, and they have to read them.

- Verified when the host lands (VERIFY-1, VERIFY-6, VERIFY-2, ADOPT-1.c).

## Requirements this change deliberately does not carry

- **Serving the page, binding the socket, and the slash command.** There is no
  executable target, no HTTP server and no gateway in this repository. Until
  the host lands, a stranger who clones this still cannot verify a member, and
  `README.md` and `docs/VERIFICATION.md` must say so in the terms BUILD-4 asks
  for. What this change removes is the need for a *second* service, not the
  need for a first one. The optional wallet argument (REQ-verify-042), the
  call to the naming service behind it and the named account and warning on
  the page (REQ-verify-043) are all part of that surface: defined here,
  built there.
- **Anything that starts before this has been read.** The runtime work and the
  follow-ups approved alongside this are being built. This change and the
  Discord surface it defines wait until the owner has read them, so nothing
  here is a licence to open `Sources/Verify`.
- **The chain observed route.** Proving by sending a zero amount transaction
  with the challenge in its note needs an indexer, which is a new host, a new
  quota and possibly a new secret, and it costs the member a fee. Left as a
  future caller of the same checker.
- **Open sourcing the existing portal.** Option C in
  `docs/decisions/0001-verification-portal.md`, unaffected either way.
