---
module: verify
version: 1
status: active
files:
  - Sources/Verify/AssertedAccount.swift
  - Sources/Verify/InMemoryVerificationSessionStore.swift
  - Sources/Verify/ProofChecker.swift
  - Sources/Verify/ProofExpectation.swift
  - Sources/Verify/ProofRefusal.swift
  - Sources/Verify/ProofShape.swift
  - Sources/Verify/ProvedAccount.swift
  - Sources/Verify/ReadSignedTransaction.swift
  - Sources/Verify/SignedTransactionFields.swift
  - Sources/Verify/SignedTransactionReadError.swift
  - Sources/Verify/SignedTransactionReader.swift
  - Sources/Verify/VerificationChallenge.swift
  - Sources/Verify/VerificationCoordinator.swift
  - Sources/Verify/VerificationLimits.swift
  - Sources/Verify/VerificationOutcome.swift
  - Sources/Verify/VerificationSession.swift
  - Sources/Verify/VerificationSessionIdentifier.swift
  - Sources/Verify/VerificationSessionStore.swift
  - Sources/Verify/VerifiedAccount.swift
  - Sources/Verify/VerifyError.swift
db_tables: []
depends_on: []
---

# Verify

## Purpose

Decide whether an Algorand account is controlled by whoever presented a proof
of it, and do it reading nothing.

The module mints the five lines a member's wallet asks them to sign, keeps the
session those lines belong to, reads the signed transaction that comes back,
and applies fifteen ordered checks to it. It opens no connection, constructs
no node client, reads no clock, reads nothing from outside the process,
declares no private key type and no signing call, and logs nothing. Every
instant it needs arrives as a `now` the caller supplies.

A member is an opaque subject string it never interprets, so nothing that came
from a person crosses this boundary: not into a challenge, not into a session,
not into a refusal, not into any type the module declares.

**What it deliberately is not.** There is no listener, no page and no chat
command here, and without them nobody can verify a member from a clone of this
repository yet. What this module removes is the need for a *second service* to
check the proof, not the need for something to serve the page. The obligations
that go with the page and the command are written down in REQ-verify-009 and
REQ-verify-010 so the host that lands them has nothing left to invent, and
`specs/verify/testing.md` records them as unevidenced rather than claiming
them.

## Public API

Every exported symbol of the `Verify` library target, in source order, one row
per name. Where several types share a name, the row is merged and says which
type each sense belongs to.

| Export | Description |
|--------|-------------|
| `AssertedAccount` | An account another service says somebody controls. Public to construct, and named for what it is, so the one value here that nothing checked cannot be mistaken for the one that was. |
| `subject` | Who a value is for, as an opaque string: on `AssertedAccount`, `ProvedAccount`, `VerifiedAccount`, `VerificationSession` and `VerificationChallenge`. |
| `address` | The account: on `AssertedAccount`, `ProvedAccount`, `VerifiedAccount` and `ProofExpectation`, where it is the account that was connected. |
| `assertedAt` | When the other service said so. |
| `assertedBy` | What the other service calls itself, so an audit line can say whose word it was. |
| `init` | Memberwise, except where it validates or where it is deliberately absent. `AssertedAccount`, `SubjectTally`, `SignedTransactionFields`, `ReadSignedTransaction` and `InMemoryVerificationSessionStore` take a plain one. `VerificationChallenge.init` and `ProofExpectation.init` refuse a value that would not render as one line, a label over the bound, an address that is not canonical and a key that is not thirty two bytes. `VerificationLimits.init` refuses an interval of nothing. `VerificationSessionIdentifier.init` refuses anything but thirty two lowercase hexadecimal characters. `VerificationCoordinator.init` refuses a label or an instance identity a challenge could not carry. `VerifiedAccount` has two, one per route, each naming its route. `ProvedAccount` has none that is public, which is the point of it. `ForbiddenTransactionField.init(wireName:)` is failable and answers nil for a name that is not one of the five. |
| `InMemoryVerificationSessionStore` | Sessions kept in memory, which is where this module expects them. Rows do not survive the process, and that is the decision rather than a gap. |
| `store` | Stores a newly minted session, displacing and discarding whatever the subject already had. |
| `session` | The session an id selects, or nil when it selects nothing. |
| `update` | Writes back a session whose state or counts have moved on. |
| `prune` | Drops consumed and expired sessions with their challenges, and subject counts whose window has passed: the store method, and the coordinator method that calls it with its own window. |
| `tally` | What a subject has spent in the current window, starting a new window when the last one has passed. |
| `countSubmission` | Counts one submission against a subject. |
| `countRetryOffered` | Counts one authorising key retry offered to a subject. |
| `heldSessionCount` | How many sessions the in-memory store holds, for a suite proving a prune left nothing behind. |
| `ProofChecker` | The ordered check, from the blob onwards. Separate from sessions on purpose: a future route that delivers a proof some other way is a new caller of this, not a new checker. |
| `check` | Checks one submitted blob against one expectation, and answers accepted or the first reason in the order that held. |
| `ProofCheckOutcome` | What came of that. |
| `accepted` | The signature checked out over exactly the right bytes, and whether it did so under an authorising key. |
| `refused` | It did not: `ProofCheckOutcome.refused` carries the reason, `VerificationOutcome.refused` and `ConnectionOutcome.refused` carry the whole refusal. |
| `ProofExpectation` | What a proof has to match: the connected address, the challenge, the pinned address where there is one, and an authorising key the caller vouched for. |
| `challenge` | The exact bytes the member was asked to sign: the field on `ProofExpectation` and the one on `VerificationSession`. |
| `pinnedAddress` | The account the member named before anything was signed, if they named one: on `ProofExpectation` and on `VerificationSession`. An address, never a name. |
| `authorizingKey` | A key the caller vouched for, so a rekeyed account can still prove ownership. It comes from the expectation and from nowhere else. |
| `ProofRefusalReason` | Why a proof was not accepted, one case per ordered reason plus the three that share the session state step. |
| `sessionUnavailable` | The session id selects nothing live: never issued, consumed, pruned, displaced, never connected to an address, or claimed by a call that is still being decided. One reason for all of them. |
| `submissionsExhausted` | The session, or the subject, has made as many submissions as it may, carrying which of the two it was: a spent link is fixed by a new one and a spent window is fixed by nothing but waiting. |
| `SubmissionBound` | Which allowance a submission ran out of: `session` or `subject`. Two remedies that are opposites, so they are not one sentence. |
| `addressAlreadyConnected` | The session is already connected to a different address, answered without saying anything about the second one. |
| `sessionExpired` | The session had run out before the proof arrived. |
| `blobUnreadable` | The submission was not base64, was empty, or was over the ceiling. |
| `transactionUnparsable` | The bytes decoded and are not a signed transaction. |
| `missingField` | The transaction is missing something a proof has to carry, named. |
| `notAPayment` | The transaction is not a payment. |
| `pinnedAddressMismatch` | The account that signed is not the account the member named. |
| `senderMismatch` | The account that signed is not the account that was connected. |
| `receiverMismatch` | The payment is not to the same account it came from. |
| `amountNotZero` | The payment moves something. |
| `feeAboveBound` | The fee is above what a proof may carry. |
| `forbiddenField` | The transaction carries a field a proof may never carry, named. |
| `subjectMismatch` | The prompt that was signed was minted for a different member. |
| `noteMismatch` | What was signed is not this session's challenge. |
| `signatureInvalid` | The signature does not check out, and whether the authorising key retry is still available. |
| `step` | Which of the fifteen positions a reason is produced at. Three reasons share position one. |
| `message` | A sentence a member can act on: the computed property on `ProofRefusalReason` and the one on `ProofRefusal` that reads it. |
| `RefusalHandle` | Something a host can correlate a refusal against and nobody can replay: a truncated digest of the session id, never the id. |
| `characterCount` | Characters in a value of fixed width: on `RefusalHandle` and on `VerificationSessionIdentifier`. |
| `value` | The string a fixed-width value is: on `RefusalHandle` and on `VerificationSessionIdentifier`. |
| `description` | The value itself, for a type that renders as one string: `RefusalHandle`, `VerificationSessionIdentifier`, `VerifyError`, `SignedTransactionReadError`. |
| `ProofRefusal` | A refusal as a host receives it: a reason and a handle, and exhaustively nothing else. |
| `reason` | Why the proof was not accepted. |
| `handle` | Something to correlate it against, which nobody can replay. |
| `ProofShape` | The one shape of proof this module accepts. |
| `transactionType` | The transaction type tag a proof must carry. |
| `signingPrefix` | The two bytes the signature covers before the transaction bytes, not hashed first. |
| `maximumFeeMicroAlgos` | The largest fee a proof may carry: the network minimum, bounded at all so a leaked blob cannot empty an account, and bounded there rather than at zero so no wallet that raises a fee is locked out. |
| `ProvedAccount` | An account somebody proved they control, by a signature this module checked. Produced only by consuming a signature and a session. |
| `provedAt` | When the proof was checked, from the instant the caller supplied. |
| `usedAuthorizingKey` | Whether the signature checked out against a key the caller vouched for rather than against the account's own, recorded so an audit can tell them apart. |
| `ReadSignedTransaction` | What came out of a submitted blob. There is deliberately no field for a signer named in the envelope. |
| `signature` | The sixty four byte Ed25519 signature. |
| `transactionBytes` | The transaction bytes, exactly as they arrived. |
| `transactionByteRange` | Where in the decoded blob those bytes came from, so a caller can prove the slice was not rebuilt. |
| `fields` | What the transaction turned out to say. |
| `RequiredTransactionField` | A field a proof must carry, named so a member is told which one is missing: `type`, `sender`, `receiver`, `note`. |
| `type` | The transaction type tag: the case on `RequiredTransactionField` and the field on `SignedTransactionFields`. |
| `sender` | Who is paying: the case and the field. |
| `receiver` | Who is being paid: the case and the field. |
| `note` | Where the challenge travels: the case and the field. |
| `wireName` | The name a field goes by on the wire: on `RequiredTransactionField` and on `ForbiddenTransactionField`, where `rekey` is what the encoder emits and `rekeyto` is not. |
| `ForbiddenTransactionField` | A field whose presence is a refusal whether or not the signature is good: `rekey`, `close`, `assetClose`, `lease`, `group`. |
| `rekey` | Hands the account's spending authority to another key. |
| `close` | Empties the account into somebody else on the way past. |
| `assetClose` | Empties an asset holding into somebody else on the way past. |
| `lease` | Blocks the member's own transactions for the validity window. |
| `group` | Says the proof was one leg of an atomic group approved wholesale. |
| `SignedTransactionFields` | What a submitted transaction turned out to say. Everything is optional because absent is a real answer. |
| `amount` | The amount, or nil when the key was absent. |
| `fee` | The fee, or nil when the key was absent. |
| `forbiddenFields` | Which forbidden fields were present, in wire order. |
| `amountOrZero` | The amount, reading an absent key as zero, because a canonical encoder omits a field holding its zero value. |
| `feeOrZero` | The fee, reading an absent key as zero: never as unknown, which under a bound is an accepted proof whose fee nobody checked. |
| `SignedTransactionReadError` | Why a submitted blob was not something this module would read. The first three come from decoding and the rest from parsing, and which group a case is in decides which refusal a member reads. |
| `blobOverCeiling` | Longer than the ceiling, refused before any parsing began. |
| `blobEmpty` | Nothing but whitespace arrived. |
| `blobNotBase64` | Not base64 in either alphabet: an alphabet character it does not carry, padding anywhere but the last one or two characters of the last group, or a leftover group of one character, which is six bits and never a whole byte. |
| `truncated` | The bytes ran out in the middle of a value. |
| `notAMap` | A map was expected and the header said something else. |
| `notAString` | A string was expected and the header said something else. Keys are strings at every depth. |
| `notAnUnsignedInteger` | An unsigned integer was expected and the header said something else. |
| `notBinary` | Binary was expected and the header said something else. |
| `unsupportedValue` | A MessagePack type this reader does not carry. |
| `declaredLengthExceedsInput` | A length or a count the input declared but did not carry, refused without allocating to match it. |
| `nestedTooDeep` | A value nested past the depth limit. |
| `duplicateKey` | The same key twice in one map, at some depth. |
| `trailingBytes` | A byte after the end of the envelope, which is a second document nobody looked at. |
| `signatureWrongLength` | A signature field that is not exactly sixty four bytes. |
| `signatureMissing` | No signature in the envelope. |
| `transactionMissing` | No transaction in the envelope. |
| `SignedTransactionReader` | Turns what a page posted into a signature and the exact bytes it covers: tolerant about how a blob is spelled, strict about a blob that says two things. |
| `blobCeilingByteCount` | The largest submission this reader will look at, applied to what arrived before anything is parsed and again to what it decoded to. |
| `nestingDepthLimit` | How deeply a value may nest before it is refused. |
| `signatureByteCount` | Bytes in an Ed25519 signature. |
| `decode` | Base64 in either alphabet, padded or not, with whitespace around it. Padded or not is the whole of the latitude: the padding rule and the leftover group are judged here rather than by Foundation, whose two implementations disagree about them in opposite directions. |
| `read` | The signature, the transaction bytes as a slice, and what they say: from decoded bytes, or from a base64 string in one call. |
| `VerificationChallenge` | The five lines a member reads in their wallet, and the bytes they sign. Renders its own text and reads it back, so the bytes signed and the bytes compared come from one function. |
| `lineCount` | Lines in a challenge. Fixed, because the subject is found by index. |
| `subjectLineIndex` | Which line carries the subject, counting from zero. |
| `maximumLabelByteCount` | The largest an operator's label may be, in UTF-8 bytes. |
| `codeCharacterCount` | Characters in the code a member compares against their chat client. |
| `nonceCharacterCount` | Characters in the nonce: a hundred and twenty eight bits as hexadecimal. |
| `instanceLinePrefix` | What the second line says before the instance identity. |
| `subjectLinePrefix` | What the third line says before the subject. |
| `codeLinePrefix` | What the fourth line says before the code. |
| `label` | The operator's own words, the first thing a member reads in the wallet. |
| `instanceIdentity` | What an instance calls itself: the challenge line that makes a proof worthless in another community, and the coordinator property it comes from. |
| `code` | The six characters shown to the member and carried in the signed bytes: one value, minted once. |
| `nonce` | A hundred and twenty eight bits the member cannot choose. |
| `text` | The five lines as the member's wallet will show them. |
| `bytes` | The bytes a wallet signs and a submitted note is compared against. |
| `mint` | A fresh value from the system's own random number generator, derived from no argument: the challenge, the session id, and the coordinator method that makes a session out of both. |
| `==` | Two challenges are the same challenge when their bytes are the same bytes: whole, with nothing trimmed, folded or compared by prefix. |
| `VerificationCoordinator` | Mint a session, record a connection, take a blob, produce an outcome. An actor, because sessions are shared mutable state. |
| `challengeLabel` | The operator's own words, as the coordinator holds them. |
| `limits` | How long a session lives and how long a subject's counts are kept. |
| `connect` | Records the address a wallet connected, once, refusing a second differing one without answering anything about it and refusing the first that is not a session's pin. |
| `submit` | Takes a submitted blob and decides whether it proves the account the session is connected to. |
| `VerificationLimits` | How long a session lives and how long a subject's counts are kept. The two maximums are not settings. |
| `maximumSubmissionsPerSession` | How many submissions one session will take. Three, and not fewer: a rekeyed member legitimately needs a wrong-account attempt, a right-account attempt that fails the signature check, and the retry. |
| `maximumSubmissionsPerSubject` | How many submissions one subject gets across every session in a window, larger than the per-session maximum. |
| `sessionLifetime` | How long a session is usable for. |
| `subjectWindow` | How long a subject's counts are kept before the window restarts. |
| `standard` | Fifteen minutes to sign, an hour of counting. |
| `VerificationOutcome` | What a submission came to. |
| `proved` | A signature was checked and the session was spent. |
| `ConnectionOutcome` | What connecting an address to a session came to. Its own type because connecting happens before the member's wallet asks them to sign. |
| `connected` | The address is the one this session is held to from now on: the outcome case, and the session state. |
| `VerificationSessionState` | Where a session has got to: `issued`, `connected`, `consumed`. Terminal is terminal. |
| `issued` | Minted, and nothing has connected an address to it yet. |
| `consumed` | A proof was accepted. Nothing else will be. |
| `VerificationSession` | One member's attempt to prove one wallet, for fifteen minutes. |
| `id` | The one thing that selects a session, and a bearer credential. |
| `issuedAt` | When the session was minted. |
| `expiresAt` | When it stops being usable. |
| `VerificationSessionIdentifier` | A hundred and twenty eight bits from the system generator, derived from nothing, compared whole, and treated as a bearer credential. |
| `SubjectTally` | What one subject has spent across every session they have had, over a window the caller supplies. |
| `submissions` | Submissions made in this window. |
| `retriesOffered` | Authorising key retries offered in this window. |
| `windowStartedAt` | When the window started. |
| `VerificationSessionStore` | Where sessions and the counts that bound them are kept. A protocol a host implements, carrying three obligations: one live session per subject, counts that are the subject's rather than a session's, and a prune that leaves nothing. |
| `VerifiedAccount` | The one value both routes meet at, from two producers that do not share one. |
| `verifiedAt` | When it was proved or asserted. |
| `route` | Which of the two it was. |
| `ProofRoute` | How a bot came to believe an account belongs to a member: `inProcess` or `asserted`. |
| `inProcess` | A signature this module checked. |
| `asserted` | Another service's word, believed because it presented a shared secret. |
| `VerifyError` | What this module refuses before there is anything to check. Nothing here carries a value that could be replayed or that names a person. |
| `challengeValueCarriesLineBreak` | A value rendered into a challenge line carried a line break. |
| `challengeLabelTooLong` | The operator's label was longer than a challenge line may be. |
| `malformedSessionIdentifier` | A session id was not the width and alphabet a minted one has. |
| `addressNotCanonical` | An address was not the canonical rendering every Algorand tool accepts. |
| `authorizingKeyWrongLength` | An authorising key was not thirty two bytes of Ed25519 public key. |
| `intervalNotPositive` | A configured interval was zero or negative. |

Four members of `VerificationSession` are public to read and private to write,
which the export extractor does not currently see, so they are named here
rather than in the table above. They are written only by the coordinator, and
a host that holds a session can read them and cannot move one on:

- `connectedAddress`: the address that was connected, recorded once.
- `state`: where the session has got to.
- `submissionCount`: how many submissions have been made against it.
- `authorizingKeyRetryUsed`: whether the one authorising key retry has already
  been offered.

`ProofChecker`'s small-order point list and the cursor inside
`SignedTransactionReader` are private and are not part of the exported
surface. Both are named in the invariants below, because what they refuse is
contract even though how they refuse it is not.

## Invariants

1. **The module reads nothing.** No connection, no node client, no clock, no
   setting from outside the process, no key, no log. Every instant is a
   parameter. `TargetShapeTests` reads the sources and the manifest and
   proves each absence by name, because an absence has no behaviour to
   assert.
2. **A member is an opaque subject string.** Nothing that came from a person
   appears in a challenge, a session, a refusal or any type declared here.
   The name a member reads is the host's, rendered from the host's own record
   and never carried below this boundary.
3. **A challenge is exactly five lines**, with the subject third. Every value
   rendered into a line is refused if it carries U+000A, U+000D, U+2028 or
   U+2029, and the label is refused above one hundred UTF-8 bytes, because
   the subject is located by its line index when a submitted note is checked.
   The check is on Unicode scalars: a carriage return followed by a line feed
   is one Swift `Character`, so a search for a line feed inside it finds
   nothing.
4. **The instance identity is inside the signed bytes**, so a proof minted
   here is refused anywhere else with every other field correct and the nonce
   identical.
5. **The subject is inside the signed bytes**, so the prompt says who the
   proof will be adopted for. It does not refuse a relayed prompt; it makes
   one detectable by a member who has seen their own subject value before,
   and the rest is the host's, on the page.
6. **Exactly one proof shape is accepted**: type `pay`, sender equal to
   receiver, amount zero, fee at most `ProofShape.maximumFeeMicroAlgos`, no
   lease and no group, and a note that is the session's challenge bytes
   exactly. A signature over an arbitrary message is refused and no entry
   point accepts one.
7. **An absent `amt` is zero and an absent `fee` is zero**, never unknown and
   never unbounded. A canonical encoder omits both keys when their value is
   zero, so requiring either refuses every correctly formed proof, and
   reading a missing fee as unknown under a bound is an accepted proof whose
   fee nobody checked.
8. **`rekey`, `close`, `aclose`, `lx` and `grp` are each refused with their
   own reason**, whether or not the signature is valid. The wire name for a
   rekey is `rekey`; `rekeyTo` is what the field is called on the
   dependency's transaction type and is not what its encoder emits.
9. **The signature is checked over `TX` followed by the transaction bytes
   sliced out of the submitted blob.** No path re-encodes parsed fields and
   checks over the result.
10. **Tolerance about spelling is not tolerance of a blob that says two
    things.** A duplicate key at any depth and any byte after the envelope
    are each refused. A size ceiling is applied before parsing begins, a
    depth limit bounds recursion, and no length the input declares is
    believed before the bytes are there. The **order** of a map's keys is
    not one of those rules: unique keys say one thing in any order, and the
    shape the reader this was ported from was patched to accept, after a
    live flow on a phone was refused, puts a signer key after the
    transaction. A signer key means a rekeyed account, and a refusal at the
    parse step is a refusal before the authorising key retry exists.
11. **Refusals are produced in one order and a later reason is never returned
    while an earlier one holds**: session state, session expiry, blob decode,
    transaction parse, missing fields, transaction type, pinned address,
    sender, receiver, amount, fee, forbidden fields, subject, note,
    signature. Fifteen. `ProofRefusalReason.step` is what says which.
12. **The subject reason is read out of the submitted note** at the line index
    the challenge shape fixes, and sits immediately before the note. Rebuilt
    from the submitted note the note comparison becomes a tautology; placed
    after a byte exact note comparison the reason can never be returned at
    all.
13. **A refusal carries a reason and a non-reversible handle, and nothing
    else.** Not the blob, not the signature, not the challenge, and not the
    session id, which is a bearer credential and a refusal is the thing a
    host writes down.
14. **A session is consumed on the first accepted proof** and refuses every
    later one, including a byte identical resubmission. A refused proof does
    not consume it but does spend an attempt.
15. **One live session per subject.** A second displaces the first, which is
    discarded with its challenge at once. A session id that selects nothing,
    for any of those reasons, gets one refusal that does not say which.
16. **The submission bound is kept per subject as well as per session**, over
    a window the caller supplies, and survives displacement, consumption,
    expiry and pruning. A bound a new session resets is not a bound.
17. **The connected address is recorded once.** A second differing address is
    refused without answering anything about it, so a host's check for an
    address another member already proved is asked once, about the address
    the member actually connected, rather than for any address a session id
    holder cares to type.
18. **An authorising key comes from the proof expectation and from nowhere
    else.** Not from the submission, not from a signer named in the blob, not
    derived from the address. An outcome produced under one records that it
    was.
19. **A key that is a small-order point is refused before the library is
    asked.** An all-zero key with an all-zero signature satisfies the Ed25519
    verification equation for every message and the libraries this builds
    against return true for it, so without the check the addresses whose
    bytes are those points are claimable by anybody.
20. **A proved account is produced only by consuming a signature and a
    session**, has no public initialiser, and is a different type from the
    value an asserted route produces. Both meet at one downstream value
    through calls that name their route.
21. **There is no input value, setting, build configuration or compilation
    condition under which a proof is accepted without a valid signature.**
22. **One call at a time per session, and every bound above holds for calls
    that arrive together.** The coordinator is an actor, which bounds one
    uninterrupted run and not one method: the store is a separate actor, so
    every hop into it releases the coordinator and a second call on the same
    session runs between a bound being read and the counter being written.
    A session is therefore claimed for the length of a call, and a second
    call on a claimed session is refused with `sessionUnavailable`, which is
    also the reason that discloses nothing about a member being part way
    through. Without the claim, single use, both submission bounds and the
    one authorising key retry are advisory, and an HTTP route hands a host
    the concurrency to walk past all four with no tooling at all.

## Behavioral Examples

### Scenario: a member proves a wallet

- **Given** a coordinator with an operator's label and an instance identity
- **And** a session minted for an opaque subject at a supplied instant
- **And** an account connected to that session
- **When** the member's wallet signs a zero amount payment from that account
  to itself carrying the challenge bytes as its note
- **Then** the outcome is a proved account carrying the subject, the address,
  the instant supplied, and that no authorising key was used
- **And** the session is consumed, so the same blob submitted again is refused
  at the session state step

### Scenario: the wrong account was selected in the wallet

- **Given** a session connected to one account
- **When** a proof arrives signed by another, over a correct challenge
- **Then** the refusal is the sender, not the signature, because one is
  something the member can fix and the other is not

### Scenario: the member named a wallet before signing

- **Given** a session minted pinned to an address
- **When** a different address is connected
- **Then** the connection is refused with the pinned address reason, before
  anything is signed
- **And** a proof from a different account on that session is refused with the
  pinned address reason rather than the sender reason, because the member
  chose the pinned address themselves

### Scenario: a page tries to get something dangerous countersigned

- **Given** a session connected to an account
- **When** a proof arrives with a correct note, a valid signature, and a rekey
  to somebody else
- **Then** it is refused at the forbidden field step, naming the rekey
- **And** the same holds for a close, an asset close, a lease and a group, and
  for a fee one microAlgo above the network minimum, and a fee at the minimum
  is accepted

### Scenario: a prompt somebody else started

- **Given** a session for one subject
- **When** a proof arrives whose note is a well formed challenge naming
  another subject
- **Then** the refusal is the subject, not the note, so the member is told the
  prompt was somebody else's rather than that their wallet sent the wrong
  bytes

### Scenario: one member cannot spend the day's chain budget

- **Given** a session whose submissions are refused at the signature
- **Then** the first refusal reports the authorising key retry as available
  and the second does not
- **And** the session stops accepting submissions at three
- **And** minting a fresh session for the same subject does not buy a fresh
  allowance until the subject's window has passed

## Error Cases

| Condition | Result |
|-----------|--------|
| A challenge value carrying a line break, in any of the four forms | `VerifyError.challengeValueCarriesLineBreak`, at the mint, naming the value |
| An operator's label over one hundred UTF-8 bytes | `VerifyError.challengeLabelTooLong`, at the mint and at the coordinator's own construction |
| An address that is not the canonical rendering | `VerifyError.addressNotCanonical`, thrown rather than refused, because it is a page's mistake and not a member's |
| An authorising key that is not thirty two bytes | `VerifyError.authorizingKeyWrongLength`, thrown from the submission as well as from the expectation, because it is the caller's mistake: reported as a refusal it reads to the member as a dead link, and the new link they are told to fetch reproduces it |
| A session lifetime or window of zero or less | `VerifyError.intervalNotPositive` |
| A session id that is not thirty two lowercase hexadecimal characters | `VerifyError.malformedSessionIdentifier` |
| A submission that is not base64, is empty, or is over the ceiling | `ProofRefusalReason.blobUnreadable` |
| Bytes that decode and are not a signed transaction, for any of the reasons in `SignedTransactionReadError` | `ProofRefusalReason.transactionUnparsable` |
| Every other way a proof can be wrong | One of the fifteen ordered reasons, the earliest that holds |
| **A fixed string standing in for a signature** | Refused as ordinary malformed input. **There is no mode, setting, flag or build configuration in which a fixed string is accepted** (BUILD-3). |
| **A caller-supplied value standing in for a signature** | There is none. An authorising key is accepted only from the proof expectation, is never read out of a blob, and the caller carries the obligation of having read it from that exact account's authorising address field. A bypass through a parameter is the same bypass as one through a setting. |

## Dependencies

- Foundation.
- `Algorand`, for one thing: turning an address string into the thirty two
  bytes that are its public key, checksum included. Writing a second base32
  decoder with an Algorand checksum in this package would be a duplicate of
  the one that already exists, so it borrows it. The cost is that the module
  is one import away from a node client, which is the position the chain
  reader is also in and is answered the same way: a suite reads the sources
  and proves no client is constructed.
- `Crypto`, declared as a direct dependency of this package rather than
  reached through `Algorand`, which links it without re-exporting it. The
  only signature check that package offers takes a method on a type holding a
  private key, which is precisely what this module must never hold.
- No other target in this package. Not `Store`, not `Chain`, not `Gating`,
  not `Reserve`, and the manifest is what enforces it.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-09-19 | maintainers | Spec written with the `Verify` library target: the challenge, the session, the tolerant reader, the fifteen ordered refusals and the signature check, ported from a working private bot and its verification portal. |
| 2026-09-19 | maintainers | Small-order public keys are refused before the cryptography library is asked, because an all-zero key with an all-zero signature verifies anything and the libraries this builds against return true for it. |
| 2026-09-19 | maintainers | A session is claimed for the length of a call. Actor reentrancy left single use, both submission bounds and the one authorising key retry readable before a store hop and writable after it, so calls arriving together walked past all four. |
| 2026-09-19 | maintainers | The reader no longer requires a map's keys to ascend. It was a rule the reader this was ported from never had, it refuses the shape that reader was patched to accept after a live outage, and unique keys already say one thing in any order. |
