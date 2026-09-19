---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: plan
---

# Plan

## The question, answered

**Can a member prove ownership of an Algorand account to a Discord bot with no
second web service, using only what wallets in that ecosystem already do?**

**Yes.** No second service is needed. A browser page still is, and those are
not the same thing, which is the confusion the whole decision has been resting
on.

Two halves, and only one of them is a service.

**The checking half needs nothing.** An Algorand address *is* an Ed25519 public
key with a checksum on it, so verifying a signature is a public key
construction and one call. The implementation this contract was read out of
already does exactly that in process, with no web application anywhere, to sign
administrators in: it parses the address, hands the raw bytes to
`Curve25519.Signing.PublicKey(rawRepresentation:)` and calls
`isValidSignature` (`WalletAuth.swift:11-31`). Nineteen lines of body. The
pieces it needs are already in this repository's resolved graph:
`swift-algorand` 0.4.0 gives `Address` with checksum parsing
(`Sources/Algorand/Address.swift:14-95`, `init(string:)` at `:37`), and it
depends on apple/swift-crypto (its `Package.swift:20` and `:27`), which
`Package.resolved` already pins at 3.15.1.

**The wallet half needs a browser.** Every wallet integration in either code
base read for this connects to a page, not to a bot. The reference front end
configures three wallets and they are all of that shape (`main.tsx:15-21`,
through `use-wallet`), and its dependency graph is a browser graph:
`@perawallet/connect`, `@blockshake/defly-connect`, `lute-connect`, `algosdk`
and WalletConnect under them (its `package.json`, its lockfile). The ported
bot's admin page vendors one wallet's browser build and reaches it the same
way.

**(external)** Two claims below come from the ecosystem's documents rather
than from either code base, and neither is something a reader here can
re-run. They are the ones to check first if this plan is ever wrong. The
`algorand://` family (ARC-0026 and its relatives) is understood to open a
*send* sheet: it composes a payment the member then broadcasts, taking no
callback and returning no signature; no URI scheme is known that asks a wallet
to sign something and hand the signature back. And arbitrary data signing —
which is what the reference's legacy path verifies with its `MX` prefix
(`VerificationController.swift:1085-1108`, and the same prefix in
`WalletAuth.swift:21-29`) — is understood to be a JavaScript API reached after
a page has connected to a wallet, not a link you can put in a chat message.
What the code does establish is narrower: the ported bot's page calls a
wallet's `signData` from a browser (`AdminUIScript.swift:965`) and its
verifier accepts the result over the raw bytes **or** over `MX` plus the bytes
(`WalletAuth.swift:24-30`), which means the code does not settle which of the
two that wallet actually signs.

**So: a page is unavoidable, and a page is not a service.** A static document
and a submit endpoint can be served by the bot's own process on the port it
will bind anyway. Everything the split costs goes away with it: the shared
secret, `X-API-Key` in both directions, the webhook, the single fixed size
read, the `201` that must not be `200`, and a boot order that takes the bot
down when the other half is down. Read `docs/VERIFICATION.md` and count how
much of it is about the seam rather than about proving anything:
authentication, the transport constraint, the retry rules, three of the five
security properties, four of the eight departures and six of the nine failure
modes.

**The conclusion that matters for this plan is narrower than "build D1".** The
part that must live in the bot is the **verifier**, because that is the only
place a proof can be judged. The **page** is a courier and its location is
configuration. A page cannot forge a verification: the only thing the bot will
accept is a valid signature over a challenge the bot itself issued, to a
session the bot itself opened, once. So where the page is served from is an
availability and a phishing question, not an integrity question, and it should
not be settled in the same breath as the verifier. This change builds the
verifier. Where the page is served from is decided next, with the executable,
and the bot serving it is the default that `ADOPT-4` wants.

## How it works, end to end, on a phone

**Owned by `design.md`**, "The flow, end to end, in process", which is the
artifact that fixes the shape. This plan had its own copy of those steps
and the two diverged: the copy here described the reference's transaction
build with the wrong line range and described the member's account as bound
in a round trip the design settles differently. One statement, one owner, so
the copy is gone rather than kept in step.

What the plan needs from that flow is only the two things it must not pretend
away, because they size the work that comes after this change.

**What Discord's in-app browser does to the hand-off is not known here.** A
link tapped inside Discord on a phone opens in Discord's own webview. Whether
a wallet deep link can leave that webview and come back with a live session is
**not answered by anything read for this change**, and it is not a thing a
document can settle: it needs real handsets on both platforms, with the
in-app browser and with the external-browser setting. It is recorded as open
question 5 in `tasks.md`. It does not block this change, deliberately: the
checker does not care which browser the signature came through. It must be
answered before the flow is announced to members, and if it turns out to break
for most members rather than some, that is the "What would change this plan"
entry below.

**Discord puts only `http` and `https` on a link.** So an https hop is
compulsory whatever else is true: there is no way to hand a member a wallet
scheme URI as a button. That is the same constraint the decision record
already names under "What would change this": whoever serves the page needs a
hostname and a certificate. An operator who has neither points at a page
hosted somewhere that does, and the verifier stays where it is — which is
exactly why this plan does not settle where the page lives.

## Two shapes that were considered and are not this

**The bot as the WalletConnect client, with no page at all.** In principle the
bot could hold the WalletConnect session itself, post a `wc:` URI, and take the
signed blob back over the relay. This is genuinely no page. It is not being
done, for three reasons and any one would be enough. Nothing in either code
base read for this is such a client, and **(external)** no maintained Swift
one was found, so it looks like a protocol implementation rather than an
integration — that one is worth re-checking rather than trusting, because it
is the only reason of the three that a search could overturn. Discord cannot
render the URI as a link (above), so the member has to copy a long string and
paste it into their wallet by hand. And it does not remove a dependency, it
moves one: instead of a page an operator serves, verification would depend on
a relay somebody else runs, which is the wrong direction for `HOST-5` and for
`TRUST-1`.

**Proving it on chain, with no browser.** This is D2 in
`docs/decisions/0001-verification-portal.md:153-172`: the bot gives the member
a code, the member sends a zero amount transaction with the code in the note
from any wallet, and the bot finds it. Everything the decision record says
about it holds, and reading the pinned dependency sharpens it. It needs an
indexer, because a node cannot search by note, and `swift-algorand`'s
`IndexerClient.searchTransactions`
(`Sources/Algorand/IndexerClient.swift:178`) takes an address and a round
range and has no note prefix parameter at all, so a caller filters locally
and it is a new host, a new quota and an upstream addition. It costs a real fee,
which means **an account holding no ALGO cannot use it**, and a member who
holds the gated token and no ALGO is an ordinary case rather than an exotic
one. And it is slow by a round plus whatever the indexer lags. It stays what
the decision record already made it: a later fallback for a member whose wallet
will not connect, not the main road, and not in this change.

## The order of work

**None of it starts yet.** The runtime work and the follow-ups approved
alongside this are being built; this change and the Discord surface it defines
wait until the owner has read them. The order below is what happens after
that, not a queue somebody may join early.

1. **Settle the decision before building against it.** `AGENTS.md` says a
   record marked proposed is not licence to build it, and
   `docs/decisions/0001-verification-portal.md:3` still says proposed. Amend
   the record with what reading the code settled: that the proof is checked in
   the bot's own process, so B and C are declined; that the page's location is
   configuration and is a stated scope exclusion of the record rather than
   part of its decision; and that D2 and the relay shape are named and
   declined. Move it to accepted, by somebody who is not the author, which is
   the same rule as change approval.

2. **Write the contract first.** `specs/verify/` with the sections
   `.specsync/config.toml` requires, and `Sources/Verify` added to its
   `source_dirs`. Adding the directory without the spec turns the gate red,
   which is the point.

3. **The target, shaped so it can never grow a connection.** A new `Verify`
   library product depending on `Algorand` and `Crypto` and on nothing else in
   this package: not `Store`, not `Chain`, not `Gating`, not `Reserve`.
   `REQ-verify-001` names all four and this step used to name three. The member is a plain
   `String` subject here and becomes a member key at the boundary above, the
   same way a role is a plain string in `Gating` and becomes a snowflake at the
   Discord boundary (the `Gating` comment in `Package.swift`). This also means
   `Package.swift` gains apple/swift-crypto as a **direct** dependency, since
   `swift-algorand` links `Crypto` without re exporting it. No new artifact
   enters the build, because `Package.resolved` already pins 3.15.1, but it is
   a new edge and `docs/WHAT-IT-TALKS-TO.md` records it in the same pull
   request.

4. **The challenge.** **Five** lines, as `REQ-verify-003` fixes them, in this
   order: an operator supplied label, an identity for this instance, **the
   subject this session was minted for**, a six character code, and a nonce of
   at least 128 bits. An earlier draft of this step said four lines and left
   the subject out; the security review found that the sentence justifying the
   omission answered a different attack, and `REQ-verify-030` is the correction.
   The subject is the third line, and `REQ-verify-013` has the checker read it
   back out of the submitted note at that index, so the count and the order are
   part of the contract rather than a rendering detail.

   Which makes the label's shape part of the contract too. Five lines is only
   an invariant while nothing rendered into a line can contain a line break: a
   two line operator label makes every challenge six lines and moves the nonce
   into the slot the subject check reads. So the mint refuses a label carrying
   a line break or over one hundred UTF-8 bytes (`REQ-verify-003`), and the
   host refuses it at boot naming the variable (`REQ-verify-040`), which is how
   this repository already handles a bad tier rung.

   That is **two departures** from the contract at
   `docs/VERIFICATION.md:476-490`, which asks for four lines: a fixed label,
   the member's chat account id, a unix timestamp and a random nonce. The
   subject stays, as the instance's own minted member key rather than the chat
   account id, because `REQ-verify-004` forbids an identifier that came from a
   person anywhere in the target. And the nonce widens from the reference's
   thirty two bits. Those are the two the other artifacts count and the two
   `docs/VERIFICATION.md` records as departures.

   The rest of the difference between four lines and five is not a departure
   taken here but a requirement of its own, and the document records each:
   the label is the operator's rather than fixed (`ADOPT-1.c`), the instance
   line is what `REQ-verify-005` requires and the contract's challenge has no
   equivalent of, the six character code is the anti-phishing device
   `REQ-verify-003` names, and there is no timestamp line because expiry is
   the session's `expiresAt` rather than a number inside the signed bytes
   (`REQ-verify-006`). Counting them as two departures plus four named
   requirements rather than as six differences is a presentational choice, and
   it is written down here so that nobody reconciling the count later concludes
   the artifacts disagree.

   The challenge is a value type that renders and re reads its own text, so
   the bytes that were signed and the bytes that are compared come from one
   place. Four properties it must have, and the reference has
   only some of them:
   - *Not replayable*: consumed once, and the session is marked before the
     outcome is adopted; a **refused** proof does not consume it.
   - *Not adoptable for another member, and detectable when somebody tries*:
     the subject is **in** the signed bytes, and the checker compares the
     subject line of the submitted note against the session's own subject
     before it compares the note. What that buys, exactly: a proof cannot be
     moved from the session it was minted for to another member's session, and
     a member who knows their own subject value can see that a prompt somebody
     handed them is not theirs. What it does not buy: a refusal in the relay
     itself. There the attacker owns the session, so the challenge legitimately
     names the attacker's subject and the bytes are correct in every way the
     checker can test; the only reader who could tell is the member, and a
     first time verifier has never seen their own subject value. The session
     binding alone never covered this, which is what the earlier draft's
     sentence, "the subject is deliberately not in the signed bytes because the
     session has one subject", got wrong: it stops a proof moving between
     sessions and the relay moves nothing. **The relay is answered on the
     page**, by `REQ-verify-043`: the page names the chat account the session
     belongs to and warns that nobody should ever send a member this link. In
     a relay the victim is on the operator's real page, which therefore cannot
     be made to lie about whose session it is, so a name displayed there is
     enough for this attack and is the only form of it a first time verifier
     can use. Naming the member inside the signed bytes would defend a
     counterfeit page instead, which is a different attack, and would cost
     `REQ-verify-004`. Both values are kept: the opaque subject in the bytes
     and the readable name on the page.
   - *Not usable for another server*: an instance value is in the signed bytes.
     The reference's challenge is a label, the member's chat account id, a
     timestamp and eight characters of a UUID
     (`VerificationController.swift:520-523`), and it carries **no** server
     identifier at all. Server binding there comes from the session row, not
     from what was signed, which is thinner than the acceptance criterion asks
     for.
   - *Expires*: fifteen minutes, because that is the number the reply already
     tells the member.

5. **The reader for what a wallet posts.** This is the large piece and the
   honest estimate is that it is most of the work. `swift-algorand` ships a
   MessagePack **writer** and no reader — `MessagePackWriter` is `internal`
   and its own doc comment says "It has no decoder"
   (`Sources/Algorand/MessagePackWriter.swift:8-14`) — so the decoder is new.
   It has to be as tolerant as the reference's, which is 460 lines. Its
   header comment attributes the tolerance to one named wallet on one named
   mobile browser and names three shapes: standard or URL safe base64, with
   or without padding (`SignedTransactionCodec.swift:22-44`); a bare signed
   transaction map, that map wrapped in a one element array, or a map
   carrying an extra signer field (`:47-52` and `:90-120`). It is one
   attribution covering three shapes, not a shape per handset, and the
   remaining branches of that file are a generic skipper rather than recorded
   wallet behaviour. It must slice the transaction bytes out of the blob
   exactly as they arrived (`:104-112`) and never re encode, because a re
   encoding that differs by one byte fails a perfectly good signature.

   It is also the one piece here that will one day be reachable from the
   internet, so `REQ-verify-014` puts three bounds on it that the reference has
   no equivalent of: a blob size ceiling applied **before** parsing begins, a
   nesting depth limit, and a refusal to allocate in proportion to a length the
   input declares but does not carry. Each is how a short hostile blob becomes
   a large allocation, an unbounded recursion or an unbounded parse. The
   canonicality rules, a duplicate key at any depth, a transaction map whose
   keys do not ascend and any byte after the envelope, are in the same
   requirement and are about a blob that says two things rather than about
   work.

6. **The ownership decision, in the order `REQ-verify-013` fixes.** Session
   state, session expiry, blob decode, transaction parse, missing fields,
   **transaction type**, **pinned address**, sender, receiver, amount,
   **fee**, **forbidden fields**, **subject**, note, signature. Fifteen, not
   the eleven this plan first listed: the type and the fee were added by the
   security review, because a zero amount self payment is harmless only if its
   fee is bounded; the subject took a position of its own in the repair pass
   after it, because a reason sitting behind the byte-exact note comparison
   can never be returned; and the pinned address arrived with the wallet
   argument, sitting before sender because "this is not the account you named"
   is a better sentence than "this is not the account you connected" whenever
   both are true. Subject is read out of the **submitted** note and compared
   against the session's subject, which is the only reading of it that can
   fail. The
   reference has the field-before-signature shape and says why at
   `SignedTransactionCodec.swift:428` — a member with the wrong account
   selected can fix that, and a member told their signature is bad cannot —
   but its `evaluate` (`:429-457`) checks only sender, receiver, amount, note
   and signature. The five forbidden fields, `rekey`, `close`, `aclose`, `lx`
   and `grp`, are added here and are not a port. The wire name is `rekey`:
   `rekeyto` is what the dependency calls the field on its transaction type and
   never appears on the wire (`CanonicalTransactionFields.swift:175`), and an
   earlier draft of this plan and of `REQ-verify-011` printed the wrong one.
   Amount is zero *or absent*, and fee is **at most one thousand microAlgos**
   or absent: canonical encoding drops a zero-valued integer field in
   `CanonicalTransactionFields.set(_:uint:)`
   (`Sources/Algorand/CanonicalTransactionFields.swift:55-58`), reached from
   `PaymentTransaction.encode` at `Sources/Algorand/PaymentTransaction.swift:140`.

   **The fee is bounded at the network minimum rather than pinned at zero**
   (`REQ-verify-009`). Bounding it at all is the security review's finding: a
   zero amount self payment is harmless only while its fee is. Bounding it at
   the minimum rather than at zero is about evidence rather than generosity.
   Nobody has measured which wallets override a fee they were handed, and a
   checker pinned at zero turns that untested behaviour into a member who
   cannot verify and cannot act on the refusal, for a fee policy the page has
   no way to enforce inside somebody else's wallet. At the minimum a leaked
   blob costs a member a fraction of a cent instead of their balance, which is
   the whole point. What is given up is that the blob stops being
   un-submittable: submitting it moves nothing and costs one minimum fee. The
   manual list measures which wallets force a minimum, and tightening the
   bound afterwards is a change with evidence behind it. Note the trap the
   widened bound opens: an **absent** fee key still reads as zero, never as
   unknown, or a proof whose fee nobody checked is accepted.

7. **The rekey retry, as a value the caller passes rather than a call the
   target makes.** An account may be rekeyed, in which case the address bytes
   are not the key that signed and the authorising address is. The reference
   handles this (`VerificationController.swift:1052-1062`); the in process
   check that exists today does not (`WalletAuth.swift:11-31` verifies against
   the address and stops). `Verify` takes an **optional authorising key on
   `ProofExpectation`** (`REQ-verify-016`) and declares no source protocol and
   holds nothing that could perform a lookup (`REQ-verify-015`), so the module
   keeps the property `Chain` has and `docs/WHAT-IT-TALKS-TO.md` can keep
   saying which targets contain a call site. An earlier draft of this step
   had `Verify` declaring a one method `AuthorizingAddressSource`; that
   contradicted `REQ-verify-015` and the `TargetShapeTests` row asserting no
   data source and no URL type, and the requirement won. **Fix the ordering
   while porting**: the reference does the chain read on any failed signature,
   *before* it looks at the fields (`:1052-1062` runs before `:1063`), so a
   member who simply picked the wrong account in their wallet spends a
   request. Here the fields are checked first, the signature refusal is
   distinguishable, and the host — the only place that can rate limit a chain
   read (`RUN-11`) — decides whether to look up an authorising address and
   call the checker again with it.

8. **The session, and single use.** A `VerificationSession` value and a store
   protocol for it, declared in `Verify` with an in memory conformance, so this
   change needs no table and no canonical spec of a merged module changes.
   One live session per **subject**, which is `REQ-verify-019`: opening a
   second displaces the first and discards it with its challenge, so a member
   who runs the command twice does not leave two live challenges behind them,
   and a proof against the displaced one is refused at the session state step.
   Subject rather than member, deliberately: this target never learns what a
   member is, and the two words stop being interchangeable the moment somebody
   implements the lookup.

   **And one reason for every session id that selects nothing.** Never issued,
   consumed, pruned, displaced: one refusal that does not say which
   (`REQ-verify-019`). Telling them apart tells whoever holds a stolen id
   whether it was ever real and tells an enumerator when a member is mid-flow.
   A session still held and past its expiry still reports expiry, which is
   `REQ-verify-006` and is a different case.

   **What displacement must not reset is the submission count.** The session
   bounds submissions (`REQ-verify-032`) and the point of that bound is that
   one member cannot make the host spend the day's chain budget. A bound held
   only on the session is defeated by the line above: mint a new session, get a
   new allowance. So the store also keeps a per-subject count, over a window
   the caller supplies, evaluated against the same supplied `now` as
   everything else here, and surviving displacement, consumption, expiry and
   pruning. The per-session maximum is at least three, because a member on a
   rekeyed account legitimately needs a wrong-account attempt, a correct one
   that fails the signature check, and the authorising key retry. The
   per-subject maximum is larger than the per-session one, or the defence
   against a member who submits two hundred times refuses the member who ran
   the command twice. The rate
   limit on the command itself, which is what stops an enumerator minting
   sessions all day, is the host's and is `REQ-verify-038`.

   **And a session may be pinned to one address at the mint.** That is the
   wallet argument (`REQ-verify-041`, `REQ-verify-042`): the member names the
   account they mean before anything is signed, the first address presented
   that is not the pin is refused with a reason of its own, and a proof signed
   by any other address is refused at the pinned address step. A name is
   resolved by the host and shown back to the member as an address before
   anything is signed, and a name that cannot be resolved is reported as that
   with a request for the raw address. It does not close the relay, because an
   address is public and an attacker can name the victim's. It buys a refusal that names what the member chose, a mismatch
   found at the connect rather than after a signature, and a member who has
   committed to an address first. The pin reaching `Verify` is an address: a
   member may type a name, and the host resolves it, because a naming service
   is a network read and this target makes none.

   **And the session records one connected address.** The first address
   presented is kept; a second, differing one is refused, and refused without
   saying anything about it (`REQ-verify-019`). That is what keeps
   `REQ-verify-028`, which refuses an address another member has already
   proved, from answering "is this address a member here?" about any address
   somebody feels like typing, which against the public holder lists this
   product publishes is an enumeration oracle over them. The durable
   conformance arrives with the executable, and it is where the per-subject
   count stops evaporating on a restart.

9. **Two producers, one seam.** `REQ-verify-034` fixes the shape and this step
   used to contradict it. A `ProvedAccount` is produced **only** by consuming a
   signature and has no public initialiser. The asserted route produces an
   `AssertedAccount`, a distinct public type with a public initialiser, named
   for what it is: the one value in this target that nothing here checked.
   Both convert into `VerifiedAccount`, the single downstream seam carrying the
   subject, the address, when, and the route tag, and the asserted conversion
   is an explicit call the host has to write. The route tag lives on
   `VerifiedAccount`, not on the proved value.

   An earlier draft of this step said both routes produce the same
   `ProvedAccount` with a route tag, which cannot hold beside "no public
   interface returns a proved account without consuming a signature": the
   natural resolution in code is a public factory minting an unchecked proof
   inside the one target whose whole claim is that there is no such thing.
   **Decoding the callback itself is the host's**, not this change's: two of
   its five fields are a chat server id and a chat member id, and
   `REQ-verify-004` forbids an identifier that came from a person in any type
   `Verify` declares. The host above then has exactly one path from
   `VerifiedAccount` to `AccountRecord` and `AccountStore.prove`
   (`Sources/Store/BotStore.swift:64`), which is what "the bot half is the same
   either way" has to mean in practice. The convergence is only *checked* once
   a host exists, and this change says so rather than implying otherwise.

10. **Tests, all offline, with generated keys.** The fixture generator already
    exists in the pinned dependency, and every line below was read at the
    resolved revision of swift-algorand 0.4.0: `Account()` mints a keypair
    (`Sources/Algorand/Account.swift:54`, throwing),
    `SignedTransaction.sign` (`Sources/Algorand/SignedTransaction.swift:143`)
    signs through `Transaction.bytesToSign`
    (`Sources/Algorand/Transaction+Signing.swift:29`), whose doc comment at
    `:14` states that the bytes are `"TX"` followed by the canonical encoding
    and are not hashed first, and `SignedTransaction.encode()`
    (`:187`) writes the `sig` and `txn` envelope with the transaction spliced
    in already encoded, per the comment at `:180`. A zero amount payment
    reproduces the absent amount trap by construction, because
    `CanonicalTransactionFields.set(_:uint:)`
    (`Sources/Algorand/CanonicalTransactionFields.swift:55-58`) drops a
    zero-valued field. The awkward shapes that the tolerant decoder exists
    for have to be assembled as bytes by hand, because a recorded real blob
    would carry a real address into a public repository.

11. **Documents, in the same pull request.** `docs/VERIFICATION.md` gains a
    section saying that the bot can be both halves and which parts of the
    contract then do not apply, and records the two challenge departures;
    `docs/CONFIGURATION.md` gains **no new variable**, only the library count,
    because nothing in this change reads one (`REQ-verify-002`,
    `REQ-verify-017`); `docs/WHAT-IT-TALKS-TO.md` gains the direct crypto
    dependency, states that `Verify` contains no call site that opens a
    connection, and records the naming service behind the wallet argument as
    a host the bot will reach when the host lands and reaches from nowhere
    today, flagged the way that document already flags what a member's browser
    will reach (`REQ-verify-022`, `REQ-verify-042`); `README.md` stops saying that nothing signs a challenge, in
    exactly the measure that stops being true; `CHANGELOG.md` under
    `Unreleased`.

## The portal stays supported, and this is what it costs

**It stays.** An operator who already runs the hosted flow keeps it, against
the contract in `docs/VERIFICATION.md`, and a bot built from this repository
keeps working with a portal built to that document. What changes is that it is
**one option and no longer the only one**.

**And neither option is the default.** `REQ-verify-023` is that exactly one
prover route is named explicitly in configuration, and that naming none, like
naming both, stops the boot with a message naming both variables and saying
which to set. An earlier draft of this paragraph said the portal was "off
unless configured" and that with no portal URL set `/verify` quietly uses the
built in path, which is a defaulted route and is what the requirement forbids:
an operator who meant to run the portal and mistyped the variable would get a
bot that verified members by another method without ever saying so. Once the
in-process route **is** named, the consequences that paragraph was reaching
for do follow: no startup health gate, no webhook route bound and no shared
secret required. That is `ADOPT-6` applied to a whole feature rather than to a
value, and `ADOPT-7.a` is why the unset case stops the boot rather than
guessing.

The costs, stated rather than buried.

**The bot is taking somebody's word for it.** This is the real one. On the
portal route the portal checks the signature and the bot records a claim it
cannot verify. The bot cannot tell a correctly verified member from a portal
that decided to say so. That is not hypothetical: the reference portal has a
mode in which the literal string `test-transaction`, or a matching literal on
the legacy path, is accepted as proof of ownership
(`VerificationController.swift:284`), behind an environment flag, off by
default and documented in its example environment file. It is an identity
bypass, it is the shape `BUILD-3` exists because of, and nothing on the bot's
side of that webhook could ever detect it. So the two routes are not equally
trustworthy and the software must not present them as though they were. When a
portal is configured the bot says so at startup, in the line `ADOPT-9` already
asks for: this instance does not check signatures itself.

**A secret that can drift.** The shared secret stays the whole trust boundary,
with the constant time comparison and the `VERIFY-5.b` failure it brings, and
the bot needs an authenticated inbound route with a rate limit on it. Paid only
by operators who choose the portal, which is the improvement.

**A document in the gate, forever.** `docs/VERIFICATION.md` has to stay true as
the bot's side changes. One file, and the cheapest line on this list.

**Two paths through one adoption step.** Step 9 above exists to stop that
becoming two code paths that drift. It is a design cost paid once.

**No bypass is ported.** Not the flag, not a quieter version of it, not a
development shortcut that reads as one. Testing without a wallet is a fake
signer in the suite producing a real signature over the real challenge with a
generated key, so the code under test actually runs.

## Deliberately out of scope

What is left out matters as much as what is in, so each of these says why.

- **The HTTP listener.** There is no executable in this repository
  (`README.md:67`) and no listener anywhere, so a socket has nothing to hang
  off. It also carries a real architecture decision that deserves its own
  change: a hand written socket server, which is what produced the single 8192
  byte read that `docs/VERIFICATION.md` spends a whole section warning about,
  or the first dependency in this package with a graph behind it.
- **The page and its JavaScript.** This is the recurring cost the decision
  record names, and it is the one that does not go away: the wallet connection
  libraries change on their own schedule and a break in one of them is a break
  in verification. It does **not** need a bundler in the Swift build: the
  ported bot vendors a single prebuilt browser ESM file as a package resource
  with its regeneration command in a comment at the top of it, and its build
  stays `swift build`. This plan said the opposite in an earlier draft and
  `research.md` corrects it against the code. What remains true is that the
  page cannot be tested the way the rest of this can, and shipping it beside a
  verifier that can be tested would lower the standard of the whole change.
  Whether a checked-in prebuilt bundle is acceptable here, or a build step is
  wanted, is a live decision (`research.md`, section 7).
- **Where the page is served from.** Decided with the executable. The verifier
  does not care, and this plan deliberately does not settle it in order to
  avoid betting the product on every operator having a hostname and a
  certificate.
- **The Discord surface.** No `/verify` command, no reply, no button, and
  therefore none of the three things the host owes the member: the optional
  wallet argument (`REQ-verify-042`), the call to a naming service behind it,
  and the named chat account and warning on the page and in the reply
  (`REQ-verify-043`). There is no gateway (`README.md:52`). All three are
  defined here so the host has nothing to invent; the half of them that can be
  proved offline, the pin and its refusal, is built here as
  `REQ-verify-041`.
- **The durable session table and the adoption step.** They need a host. The
  seams are declared here so that the host has nothing to invent.
- **The on chain note fallback and an indexer.** Argued above. Later, with a
  reason, or not at all.
- ~~**Rate limiting the verifier.** It belongs with the transport, and there is
  no transport.~~ **Cut by the security review.** A defence assigned to a thing
  that does not exist is a defence nobody owns, and this one had a user story
  above it: no member, however fast they type, can spend the day's budget for
  reading the chain. What is in scope here is the half that can be proved
  offline, `REQ-verify-032`: a session records its submissions and refuses more
  than a fixed maximum of at least three, the store keeps the same count per
  subject so that minting a fresh session does not mint a fresh allowance, and
  the authorising key retry is offered at most once per session. The other
  half, a rate limit on the command and on the submit route, per member **and
  per source**, is `REQ-verify-038`, an obligation of the host, written down
  here so the host cannot inherit it as an assumption. Neither half discharges
  the story on its own and this plan no longer claims either does.
- **Opening the reference portal's repository.** Option C in the decision
  record. Nothing here depends on it and it is a standing obligation taken on
  for code most operators do not want.

**What this change therefore does not achieve.** Two things, and both are in
the acceptance criteria rather than hidden from them.

The criterion says somebody who clones this repository can run verification
without standing up a second service. That cannot be true of any change while
there is no binary to run. This change makes it *buildable* by leaving only the
transport and the page, both named, and the criterion is answered in the change
that adds the executable. Saying so here is `docs/README.md` rule 7 applied to
a plan.

And the criterion used to say that what a member signs "cannot be used for a
different member". It has been amended, because that was false of the bytes
alone. A proof cannot be **moved** to another member's session, and the
subject line makes a relayed prompt detectable by a member who has seen their
own subject value. A relay is still not **refused** by anything the checker
can test: the attacker owns the session, so the challenge legitimately names
the attacker's own subject and every check passes.

What answers it is the page, not the bytes (`REQ-verify-043`): the operator's
own page names the chat account the session belongs to and warns that nobody
should ever send a member this link. In a relay the victim is on that real
page, which cannot be made to lie about whose session it is, so the display is
enough for this attack, and unlike the subject line it works for a first time
verifier. Putting a member-recognisable name in the signed bytes would defend
a counterfeit page instead, which is a different attack, and would cost
`REQ-verify-004`. The residue after that is a first timer who does not read
the warning: the attack needs somebody to take a link from a stranger and sign
what it shows them, which the server rules already cover and every wallet
warns about, so it is real and it is largely user error. `context.md` sets out
the decision and the residue under "The five decisions the owner took, and
what they settle".

## What would change this plan

- **If a wallet ships a way to return a signature without a browser.** Then the
  page stops being compulsory and this plan loses its largest remaining cost.
  Nothing suggests it is coming.
- **If Discord's in app browser turns out to break the flow for most members
  rather than some.** Then the page is not the answer for phones and the on
  chain note path stops being a fallback and becomes the main road for mobile,
  with the indexer and the fee that come with it.
- **If most operators turn out to have no hostname.** Then the page lives
  somewhere else for most people, the bot serving it becomes the exception, and
  the only thing that changes is which default the executable ships with. The
  verifier does not move.
