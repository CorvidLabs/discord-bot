---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: design
---

# Design

## The question this change had to answer before anything could be shaped

`docs/decisions/0001-verification-portal.md` is marked proposed and lists four
options. The fourth, "no portal at all", is the one this change exists to test,
and the test is a single question:

> Can a member prove ownership of an Algorand account to a Discord bot with no
> second web service, using only what wallets in that ecosystem already do?

The answer is **yes**, and the reason it is yes is narrower than it first
looks, so it is worth setting out exactly. Proving ownership is three moves,
not one, and only one of the three was ever a service.

**Move one: the bot produces something to sign.** Five lines: the operator's
label, an identity for this instance, the subject the session was minted for, a
six character code and a random nonce, held against a session record. That list
is REQ-verify-003 and it is written out at "The bot mints a session and a
challenge" below; this paragraph used to say "a label, an identity, a timestamp
and a random nonce", which was the pre-security-review challenge and had
neither the subject nor the code in it. No network, no page, no second process.
The reference portal builds its own challenge, which is a different and
shorter list, in about five lines of code (`VerificationController.swift`
lines 519 to 523); what it contains is set out under the departures below.
Either way, minting something to sign needs nothing a Discord bot does not
already have.

**Move three: the bot checks the signature.** This is the part everybody
assumes is hard and is not. The address **is** the public key: parse the
address to thirty two bytes, build a `Curve25519.Signing.PublicKey` from them,
and ask whether the signature is valid over `TX` plus the transaction bytes.
The reference portal does it in six lines (`VerificationController.swift`
lines 1077 to 1082), and the private original of this bot **already does the
same thing in process, with no web application anywhere**, to sign
administrators in (`WalletAuth.swift` lines 11 to 31).
Nothing about it needs a service. It needs `swift-crypto`, which is already in
this package's resolved graph.

**Move two is the whole problem, and it is a return channel, not a service.**
A wallet will not accept a request from, or reply to, a process it has no
session with. Every wallet integration in the code read for this is a browser
page running a connect library: the reference portal's front end declares
`@txnlab/use-wallet-react`, `@perawallet/connect`, `@blockshake/defly-connect`
and `lute-connect` (`frontend/package.json` lines 13 to 18) and the ported bot
vendors one wallet's browser build. Two other channels are described in the
ecosystem's own documents rather than in either code base, and `research.md`
marks them **(external)**: a WalletConnect session with a relay in the middle,
and an ARC-26 `algorand:` URI, which is understood to prefill a payment the
wallet then submits, so what comes back would be a transaction on chain rather
than a signature in hand. Nothing read here establishes a shape in which a
wallet hands bytes back to a slash command, and nothing read here rules one
out either; what can be said is that no such shape appears in two working
implementations.

So the honest finding, stated in both directions:

- **A second web service is not needed.** Nothing in the three moves requires a
  second deployable. `docs/VERIFICATION.md`, "What the bot exposes", already
  specifies the listener the bot will bind for the webhook and `/health`, and
  when that listener exists a page served on it is one more route: one
  process, one port, one clone. **This repository binds nothing today**
  (`docs/VERIFICATION.md:13`), so the listener is new work under every option
  and this design must not be read as saying it already exists.
- **A browser page is needed, on the main route.** Not because the
  cryptography needs one, but because the signature has to travel back and a
  page is the only return channel evidenced here that costs the member
  nothing, needs no third party, and reached every wallet the reference
  offered through one call. Saying otherwise would be wishful.

That distinction is the whole design. **This change moves the proof into the
bot and leaves the page where it has to be, and once the bot can serve the
page the page stops being a second service.** Where the page is actually
served from is not settled by this change: see "Decisions, and which way they
went". The portal contract survives as one of three ways the same proof can
reach the same checker.

### The two browser-free routes, and why neither is the main road

Both were taken seriously rather than dismissed, because the recommendation in
the decision record depends on it.

**WalletConnect with the bot as the client.** **(external)** — none of this
shape appears in either code base, so the account of it below comes from the
protocol's own documents and is not evidence a reader here can re-run. In
principle it is genuinely no page: the bot mints a pairing URI, posts it as a
tappable link, the wallet opens, the member approves a session, the bot asks
for `algo_signTxn` and gets the blob straight back. What is expected to kill
it as the main road is not difficulty, it is disclosure: the protocol is
understood to need a relay host the operator does not run and a project
credential from a third party, which would be a new host and a new secret in
`docs/WHAT-IT-TALKS-TO.md` and a direct hit on TRUST-1 for something the page
route needs none of. It would also rest on a wallet's own universal link
behaving on a phone, which means the bot naming particular wallet vendors. It
buys independence from browser libraries and pays in a relay and a credential.
Worth revisiting only if the connect libraries become the recurring cost the
decision record fears, and worth re-checking against current documents first,
because nothing here has been verified.

**ARC-26 deep link plus chain observation.** Also genuinely no page, and
genuinely no relay: the bot posts an `algorand:` URI for a zero amount payment
carrying the challenge in the note, the member taps it, their wallet opens
prefilled, they confirm, and the sender of the resulting transaction is the
proof. This is option D2 in the decision record and the analysis there holds up
against the code. `Chain` reads an algod node and only an algod node
(`docs/WHAT-IT-TALKS-TO.md`, "Outbound calls, the complete list": two call
sites, both `GET /v2/accounts/...` or `GET /v2/assets/...`), and algod cannot
look up a past transaction by note or by id. Finding it means an indexer, which
is a new host, possibly a new secret, and a new draw on
`CHAIN_DAILY_REQUEST_BUDGET`. It also costs the member a fee and requires them
to hold ALGO, and it is slow by a round plus whatever the indexer lags.

Neither is built here. Both stay reachable: the checker this change defines
takes a proof and an expectation, and does not care which channel delivered it,
so a future route is a new caller rather than a new checker.

## What is being built

A new library target, `Verify`, that holds the whole of moves one and three and
none of move two. It is pure in the sense the other targets are pure: no
network, no clock, no Discord, no database, no key.

Around it, three routes may deliver a proof, and all three converge on one
downstream value, `VerifiedAccount`, reached from two different producers:

```
  in process    member -> page the bot serves -> POST to the bot -> Verify
  hosted page   member -> page elsewhere      -> POST to the bot -> Verify
  portal        member -> portal              -> webhook to the bot -> (asserted)
```

The first two are **proved**: the bot holds the signature and checks it. The
third is **asserted**: the portal checked the signature and the bot believes it
because it presented the shared secret. That asymmetry is real, it does not go
away, and the software says which one is running rather than leaving an
operator to work it out (ADOPT-9, BUILD-4).

## The target and the boundary

| | |
|---|---|
| Target | `Verify`, a library product |
| Depends on | Foundation, `Algorand` (address parsing only), `Crypto` |
| Depends on, deliberately not | `Store`, `Chain`, `Gating`, `Reserve` |
| Contract | `specs/verify/`, a new module spec, added to `.specsync/config.toml` |

`Verify` sits at the bottom of the graph beside `Gating` and `Games`, not
above `Store`. It takes a subject as an opaque string and never learns what a
member is, so it cannot acquire a chat type and cannot acquire a database.

It depends on `Algorand` for one thing: turning an address string into the
thirty two bytes that are its public key, checksum included
(`Address.init(string:)`). Writing a second base32 decoder with an Algorand
checksum in this package would be the exact duplication AGENTS.md calls a
defect, so it borrows the one that exists. The cost is that `Verify` is one
import away from `AlgodClient`, which is the same position `Chain` is in, and
it is answered the same way: a source shape test asserts `Verify` constructs no
client and calls nothing that submits.

It depends on `Crypto` for public key verification. `swift-algorand` has no
verify that takes a public key on its own: `verify(signature:for:)` is a
method on `Account` (`Sources/Algorand/Account.swift:136`), and an `Account`
is a type that holds a private key, which is precisely the thing this target
must never hold. So `swift-crypto` becomes a **direct** dependency of this
package. It is already in `Package.resolved` at 3.15.1, arriving through
`swift-algorand`, so this adds no pin and changes no resolved version. It does
change the dependency table in `docs/WHAT-IT-TALKS-TO.md` from "arrives with
`swift-algorand`" to "declared here", and TRUST-1.b says that is a diff
somebody reads rather than something that appears quietly.

## The flow, end to end, in process

### 1. The member asks

`/verify`, in Discord. The reply is ephemeral and, **before** the button, says
who runs this server, what will be kept about them, and which of it other
members can see (VERIFY-6). That text is the operator's, from configuration,
and nothing in it names whoever wrote the bot (ADOPT-1.c). The reference
portal's page fails this outright: its footer carries the originating project's
name and an invite to that project's own chat server
(`Resources/Views/verify.leaf` line 88 and `frontend/src/App.tsx` line 456).

The reply also carries a six character code and the expiry as a Discord
timestamp, which renders in the member's own clock.

**And it prints the subject value that will be inside the signed bytes**, which
the page displays beside the same six character code, so a member can compare
what their wallet shows against what their own chat client showed them
(REQ-verify-035). It says, in plain words, that a signing prompt they did not
just start is somebody trying to take their wallet. The echo is not
decoration: REQ-verify-030 puts the subject in the bytes, and the echo is what
lets a member who has verified before check what their wallet is showing
against what their own chat client showed them. It does nothing for a member
verifying for the first time, which is what the next paragraph is for.

**And both the reply and the page name the chat account this session belongs
to, by the name the member's own client shows for it, with the warning beside
it: only continue if that account is yours, and nobody should ever send you
this link (REQ-verify-043).** That is the answer to the relay, and it is
deliberately on the page rather than in the signed bytes. In a relay the
victim is on the operator's **real** page, on the real origin: the attacker's
whole contribution is a link, so the page cannot be made to lie about whose
session it is, and a name on it is something a first-time verifier can read
without having any value to recognise. Carrying the same name in the signed
bytes would additionally defend a **counterfeit** page, which is a different
attack with a different answer, and would put an identifier that came from a
person below the chat boundary, which REQ-verify-004 forbids. The opaque
subject line stays exactly where it is, beside the name rather than replaced
by it: it is what stops a proof moving between sessions, and no page can do
that.

**The command takes an optional wallet argument (REQ-verify-042).** Bare, it
is what it always was. With an address, or with a name the host resolves and
then **shows back to the member as an address before anything is signed**, the
session is pinned to that one address and a proof signed by any other is
refused with a reason of its own (REQ-verify-041). A name the naming service
cannot resolve is reported as that, with a request for the raw address: a
member who typed a name is never stuck, nothing at boot depends on the
service, and `Verify` never sees a name at all. That does not close the
relay either, and nothing here pretends it does: an address is public, so an
attacker can name the address they are after. It buys a refusal that names
what the member chose, a mismatch found at the connect rather than after a
signature, and a member who has said which wallet they mean before anybody
asks them to sign one.

### 2. The bot mints a session and a challenge

One `VerificationSession`: a session id of at least a hundred and twenty eight
bits from the system generator, a subject (the minted member key, never a chat
identifier), the challenge, `issuedAt`, `expiresAt`, a state, and, when the
member named a wallet, the one address this session is pinned to
(REQ-verify-041).

The challenge is five lines of UTF-8, and the member will read them in their
wallet:

```
<the operator's label>
Server: <the instance's own identity>
Member: <the subject this session was minted for>
Code: <six characters, the same six shown in Discord>
<a hundred and twenty eight bit nonce>
```

Every line earns its place. The label is the operator's so the member sees
their own community's words. The server line is what makes a proof
untransferable to another community (VERIFY-4, HOST-6). The member line is what
stops a proof being adopted for another member, and it is the line a security
review of this design found missing: without it the bytes never say who the
proof will be adopted for, so a link handed to somebody else produces a genuine
looking prompt whose signature binds their wallet to the sender of the link
(REQ-verify-030). What it does **not** do is refuse that relay: that is
answered on the page by REQ-verify-043, and the residue after it is set out
under "The account is adopted".
The code is the anti-phishing device: the member can see with their own eyes
that the wallet is showing the request Discord just made, on a phone, without
reading a nonce. The nonce is what they cannot choose.

**Five lines is a property somebody has to enforce.** The member line is the
third, and the checker reads it back out of the submitted note by that index,
so the count cannot be left to the goodwill of the operator's label. A label
containing a line break renders a six line challenge and moves every line below
it. So no value rendered into a line may carry a line break of any kind, the
label is bounded at one hundred UTF-8 bytes, the mint refuses a label that
breaks either rule with a named reason (REQ-verify-003), and the host refuses
it at boot naming the variable (REQ-verify-040), the way a bad tier rung
already stops a boot in this repository rather than silently dropping a rung.

Two departures from `docs/VERIFICATION.md`, both deliberate and both to be
written into that document as part of this change. The contract asks for four
lines and this is five; the other differences are not departures decided here
but requirements with names, and `plan.md`'s challenge step accounts for them
so that the count does not read as a disagreement: the operator's label is
ADOPT-1.c, the instance line is REQ-verify-005, the code is REQ-verify-003, and
the missing timestamp is REQ-verify-006 putting expiry on the session instead.

- **The subject is in the challenge, but as the minted member key rather than
  the chat account id.** The contract asks for the chat account id. An earlier
  draft of this design left the subject out altogether, on the argument that
  "the binding it provides is already provided by the session: the note is
  compared against the challenge stored on the one session it was issued for,
  and that session has one subject". That argument is true about the thing it
  describes and it answers the wrong question. It stops a proof being moved
  from one session to another. It does nothing about a member being handed
  somebody else's link and signing it, because in that attack nothing moves:
  the signature is produced for the session it is submitted to, and the subject
  of that session is the attacker. So the subject is in the bytes. What is not
  in them is anything that came from a person: the line carries the opaque
  subject the caller supplied, which above this boundary is the instance's own
  minted member key, so the rule in AGENTS.md still holds. The code line stays,
  and does the work it always did.
- **The nonce is a hundred and twenty eight bits, not thirty two.** The
  reference takes the first eight hexadecimal characters of a UUID
  (`VerificationController.swift` line 520), which is thirty two bits. Nothing
  rests on it there, because the note is compared against the stored challenge
  rather than looked up by nonce, but a full width nonce costs one line and
  removes the question.

### 3. The member opens the page

The button points at the bot's own listener. There is no shared secret in this
direction, no `X-API-Key`, no `201` that has to be exactly `201`, and no second
process that can disagree with the first, because there is no second process.
Roughly half of `docs/VERIFICATION.md` is about that seam, and on this route
none of it exists.

**On a phone this is the fragile step, and the design says so rather than
hoping.** Discord opens links in its own in-app browser. Whether a wallet deep
link can leave that browser and come back with a session is **not answered by
anything read for this change**: neither implementation handles it, and a grep
of the reference portal's front end and its views for user agent sniffing,
in-app browser detection or an "open in browser" affordance comes back empty.
That absence is evidence about the reference, not evidence about phones. So it
is an open operational question (`tasks.md`, open question 5), it is the first
thing the host target must test on real handsets, and no part of this change
depends on the answer, because the checker does not care.

The only thing this design fixes about it is the part that lives in the
change's own scope: the reply carries the plain URL as text as well as a
button, because Discord's mobile app cannot copy text out of an embed, which
is why the reply is plain text rather than an embed, the same reason `/time`
is. What the page does about it is the page's design and is not decided here.

### 4. The member connects a wallet and signs

The page lists the wallets the **operator** configured, not a list the project
picked. The connect library opens the wallet, the member approves, and the page
tells the bot which address was connected.

**The session records that address once.** A second, differing address on the
same session is refused at the session state step, and refused without saying
anything about it (REQ-verify-019, REQ-verify-013). The reason is the check in REQ-verify-028: refusing an
address another member has already proved is the right behaviour and, asked
freely, it answers "is this address a member of this guild?" for any address
anybody cares to type. The holder lists this product publishes are public, so
that is an afternoon's walk from a list of addresses to a list of which of them
belong to members here. Bound to the session, the question is asked once, about
the address the member actually connected. A member who connected the wrong
wallet runs the command again.

**And if the member named a wallet when they ran the command, the session was
pinned to it at the mint** (REQ-verify-041, REQ-verify-042). Then the first
address presented that is not the pin is refused there and then, with a reason
that names what the member themselves chose, rather than being recorded and
contradicted a signature later. The pin is an address by the time it reaches
`Verify`: a member may type a name, and the host resolves it, because
resolving a name is a network read and this target does not make one.

Then the page builds one transaction:

- type `pay`, sender and receiver both the connected address
- amount zero
- fee zero, flat, and never above the network minimum
- note: the challenge bytes, exactly
- no `rekey`, no `close`, no `aclose`, no `lx`, no `grp`

That is what the reference builds too (`frontend/src/App.tsx` lines 158 to
176), and the fee override matters for the member's nerve: a wallet showing a
fee on something described as free is a member who cancels.

**Every one of those is also checked, not merely asked for.** An earlier draft
asked the page for a zero fee and never checked it, which left the bot willing
to certify as proof of ownership a self payment whose fee is the member's entire
balance, while the page keeps the signed blob and can submit it. The fee is in
the accepted shape for the same reason the rekey is: the bot must never hold or
bless a signed instrument that could empty an account if it leaked.

**What the checker enforces is a bound of one thousand microAlgos, the network
minimum, rather than equality with zero.** The page still asks for zero, for
the reason above, and the checker accepts a wallet that raises it to the
minimum on the member's behalf. Nobody has measured which wallets do that, and
that
uncertainty is exactly why the bound is not zero: a checker pinned at zero
turns an untested wallet behaviour into a member who cannot verify and cannot
act on the refusal, and the page has no way to enforce a fee policy inside
somebody else's wallet. At the minimum, a blob that leaks costs a member a
fraction of a cent rather than their balance, which is the whole point of
bounding it.

The cost of that is said here rather than found later. A **zero** fee with no
group makes the blob un-submittable outright, which is stronger than harmless:
the network carries no transaction that pays nothing, and fee pooling needs a
group fixed before signing. At the minimum the blob becomes submittable again.
Submitting it moves nothing, from the member to the member, and costs one
minimum fee. That is the price of not guessing at wallet behaviour, and the
manual list is where the guess gets replaced by a measurement; if every
supported wallet turns out to honour a zero, tightening the bound is a later
change with evidence behind it.

**The transaction is never submitted.** It costs nothing, leaves no trace and
exists only as a signature to check.

### 5. The signature comes back

The page posts the signed blob, base64, to the bot's submit route with the
session id. One read, one body, and the outcome comes back in the response
rather than over a webhook, because there is nowhere else for it to go.

**The session id is the whole credential, and the design now says so rather
than leaving it implied.** Whoever holds it can submit against that session,
and a submission binds whatever address the submitter connects to whatever
member the session names. So it reaches the page in the URL fragment or in the
request body and never in a query string, it is never written to a log or an
error report, the page is served with a referrer policy of `no-referrer` so no
third party asset receives it, and adoption needs a confirmation back in the
chat client that somebody holding only the link cannot give
(REQ-verify-031, REQ-verify-036, REQ-verify-035). The reference portal puts its
token in a query string (`VerificationController.swift` line 551), which is the
concrete version of every one of those leaks at once.

### 6. The bot checks it

All of this is `Verify`, offline, with a `now` the caller supplies:

1. The session exists, is not consumed, has not been displaced by a newer one
   for the same subject, has submissions left against both its own maximum and
   its subject's, and `now` is before `expiresAt`. A session id that selects
   nothing gets one reason that does not say why (REQ-verify-019,
   REQ-verify-032).
2. The blob decodes. Standard or URL-safe base64, padded or not, and only
   after a size ceiling has been applied, so a stranger does not choose how
   much work the process does per request (REQ-verify-014).
3. The msgpack parses into a sixty four byte signature and the transaction
   bytes, **sliced out of the blob exactly as they arrived**. It may be a bare
   `{sig, txn}` map, that map wrapped in a one element array, or a map carrying
   an extra `sgnr`, which is skipped and never surfaced: no value read out of
   the blob is ever used as a key to check a signature against
   (REQ-verify-033). Those three shapes are the ones the reference's own codec
   attributes, at the top of the file (`SignedTransactionCodec.swift` lines 5
   to 7), to one named wallet on one named mobile browser. That is one
   attribution covering three shapes, not three handsets, and it is the whole
   of what the code establishes about what a wallet sends.

   **Tolerant about spelling, strict about saying two things.** A duplicate key
   at any depth, a transaction map whose keys do not ascend, and any byte after
   the envelope are all refused. The page chooses the encoding, so a
   transaction map carrying `amt` twice is a document the wallet can display one
   way and this reader take the other way, under one signature that stays valid
   over whichever reading is carried off, because **the reader slices rather
   than re-encodes**. Named rather than cited as a step number, for the same
   reason the retry condition below is named: a step inserted above it
   renumbers the reference and nothing goes red. The reference's parser is last
   key wins with no duplicate
   detection (`SignedTransactionCodec.swift` lines 65 to 83). Refusing costs a
   set of the keys seen.

   **And bounded, because this is the part that will face the internet.** There
   is a nesting depth limit, a declared map count or string or binary length
   larger than the bytes that actually arrived is refused without allocating to
   match it, and the size ceiling above is applied before parsing begins. None
   of the three is a tidiness rule: each is how a short hostile blob becomes a
   large allocation, an unbounded recursion or an unbounded parse
   (REQ-verify-014).
4. The transaction has a type, a sender, a receiver and a note.
5. The type is `pay`.
6. If the session was **pinned** to an address when it was minted, the sender
   is that address. This is its own reason, before the sender check, because
   the two say different things to a member: this is not the account you
   named, and this is not the account you connected. On an unpinned session
   the step is skipped (REQ-verify-041).
7. Sender equals the connected address.
8. Receiver equals the same address.
9. Amount is zero, **and an absent amount is zero**. Algorand's canonical
   encoding omits zero valued fields, so refusing a transaction with no `amt`
   key refuses every correctly formed proof. The reference gets this right
   (`SignedTransactionCodec.swift` line 449, an optional binding rather than a
   required one) and it is the single easiest thing to get wrong.
10. Fee is at most one thousand microAlgos, the network minimum, **and an
    absent fee is zero**, by the same encoding rule as the amount. An absent
    key read as anything but zero is an accepted proof whose fee nobody
    checked, which is a mistake a bound makes reachable and equality with zero
    used to hide.
11. No `rekey`, `close`, `aclose`, `lx` or `grp`. The wire name is `rekey`; see
    the decision below.
12. The **subject line of the submitted note** is this session's own subject.
    It is read out of the note that arrived, at the line index the challenge
    shape fixes, and compared against the subject the session was minted for.
    It is not rebuilt from the session's challenge, which would compare a value
    against itself, and it is checked **before** the note rather than after,
    because the note comparison below is byte exact: a proof naming another
    subject differs in the note too, so a subject reason placed after it could
    never be returned and the member would be told their wallet sent the wrong
    bytes rather than that this prompt was somebody else's (REQ-verify-030,
    REQ-verify-013).
13. The note equals the session's stored challenge bytes exactly.
14. The Ed25519 signature is valid over `TX` plus the transaction bytes, against
    the public key that is the address, or against the authorising key the
    caller supplied in the expectation and nowhere else.

Field failures are reported before signature failure, so a member with the
wrong account selected in their wallet is told that rather than told their
signature is bad. One is something they can fix. The reference has this
ordering and a comment explaining it (`SignedTransactionCodec.swift` line 428);
it is worth carrying over because the reason is good.

These fourteen steps are the fifteen ordered reasons of REQ-verify-013 with
session state and session expiry merged into the first. That requirement is the
one that fixes the order; this list is the walk through it, and where anything
here or elsewhere needs to point at a check it names the check rather than its
number.

**If and only if the signature check fails on its own**, the host may read the
account's authorising address once and ask again, so a rekeyed account can
still prove ownership. The condition is named rather than numbered on purpose:
it used to read "if and only if step 10 fails", written when the signature was
the tenth check, and the security review then inserted the type check and the
fee check above it, which moved the signature check without moving the
sentence. The subject check was inserted above it after that, and the pinned
address check after that again, either of which would have moved it once
more. A
genuinely rekeyed member's proof would have failed with no retry ever
attempted, which is precisely the class REQ-verify-016 exists to serve, and the
next step inserted into this list would have broken it again. `Verify` does not
do that lookup: it returns a distinguishable refusal and the host decides,
because the host is the only place that can rate limit a chain read (RUN-11).

### 7. The account is adopted

The session is marked consumed, and `Verify` returns a `ProvedAccount`, which
the host converts into a `VerifiedAccount` tagged `inProcess`. The host does
not adopt it yet: adoption waits for a confirmation by the subject, offered on
the ephemeral interaction that issued the session (REQ-verify-035). A proof is
evidence that somebody controls an address; the confirmation is the member
saying that the proof is theirs, and it is what makes a link somebody else
merely got hold of useless to them. Confirming requires the subject to match
the pending proof's subject, and nothing else can confirm it.

**What the confirmation does not close, and what does.** The confirmation does
not close the relay. In that attack the attacker owns the session, so they
confirm on their own interaction, exactly as the real member would. It closes
the narrower case: a link that somebody came into possession of, whose holder
can sign and cannot confirm.

The relay is closed, as far as it can be, **on the page**: the named chat
account and the warning beside it (REQ-verify-043), which is what a first-time
verifier can read without a value to recognise, backed by the subject line for
a returning member and by the confirmation for a stolen link. The reasoning
for putting it there rather than in the signed bytes is in section 1 and in
`context.md` under "The five decisions the owner took, and what they settle".

What remains after that is stated plainly rather than dismissed or inflated.
The attack needs a member to take a link from a stranger and sign what it
shows them, which the server rules an operator already publishes cover and
every wallet warns about. It is real, and it is largely user error. The honest
residue is a first-time verifier who has no baseline for what normal looks
like here: the named account and the warning are the whole of what stands
between them and a relayed prompt, and they have to read them.

**The confirmation needs somewhere for the proof to wait, and the session is
not it.** By the time there is anything to confirm the session is consumed and
discarded with its challenge, and on a phone the chat client may have been
killed during the hand off to the wallet, so the interaction that issued the
session may be gone too. An earlier draft of this section asked for a
confirmation and named no home for the thing being confirmed. So the host
holds a **pending proof**, outside the session store, keyed by the **subject**
rather than by the session id: that is what lets the member confirm on the
original interaction if it is still alive and on a fresh one if it is not.
It carries the address, the route and when the proof was checked, and nothing
replayable. It has an expiry of its own, independent of the session's. One per
subject, replaced by a later accepted proof. And an unconfirmed pending proof
**binds nothing**: no record, no role, no lock on the address, and it is
discarded when it expires.

From there the path is the one that already exists: the bot reads the account
from the chain itself, works out the tier from its own ladder, assigns the roles
in one call, and writes the audit. `AccountStore.prove` refuses an address
another member already proved (`Sources/Store/BotStore.swift` lines 56 to 64).
That refusal needs a way out, which it does not have today: it is also what a
successful relay or a leaked link turns into a member permanently unable to
prove their own wallet, so REQ-verify-039 makes an operator able to release
one, with an audit line.

On this route there is no advisory balance at all. The webhook's `balance`
field exists because a portal already read the chain and the bot might not be
able to; in process there is nothing to advise with, so an account proved
before a successful read is stored with `balancesReadAt` nil, which
`AccountRecord` already documents as meaning unknown rather than zero
(`Sources/Store/AccountRecord.swift` lines 33 to 38).

## The flow, end to end, portal

Unchanged, against `docs/VERIFICATION.md` exactly as written. The bot creates
the session on the portal, hands the member the portal's URL, and the portal
calls the webhook with five fields. The bot validates the payload with the four
named reasons before answering `200`, then constructs an **`AssertedAccount`**
and, in an explicit call that names the route, converts it into a
`VerifiedAccount` tagged `asserted`.

It does **not** produce a `ProvedAccount`. This section used to say both routes
produce the same `ProvedAccount` with a route tag, which is the shape
REQ-verify-034 rules out: one type constructible on both routes, whose
initialiser is not public, resolves in code as a public factory minting an
unchecked proof inside the one target whose whole claim is REQ-verify-017. Two
producers, one seam, and the unchecked one says asserted in its name. The route
tag lives on `VerifiedAccount`, which is the value everything downstream reads.

What changes about this route is only what is said about it. It is no longer
the only way, it is no longer what the boot gate exists for by default, and the
startup line says, in words, that on this route the proof is the portal's word
and the shared secret is the whole trust boundary.

The third route falls out for free and is worth naming because it answers the
one thing the decision record says would change its mind. An operator whose bot
has no public hostname can serve the page anywhere they like and have it post
the blob to the bot's submit route. The page moves; the proof stays in process.
That is strictly better than the assertion webhook and costs nothing extra,
because it is the same endpoint.

## The types

Names are indicative; the module spec in `specs/verify/` is what fixes them.

| Type | What it is |
|------|------------|
| `VerificationChallenge` | The five lines and the bytes they encode to. Built from an operator label, an instance identity, the subject, a code and a nonce. Renders its own text and re-reads it, so the bytes signed and the bytes compared come from one function. Value type, `Equatable`, no clock. |
| `VerificationSession` | Session id, subject, challenge, `issuedAt`, `expiresAt`, state, an optional address the session was pinned to at the mint (REQ-verify-041), the connected address once there is one and never a second differing one (REQ-verify-019), the count of submissions made against it, and whether the one authorising key retry has been used. |
| `VerificationSessionState` | `issued`, `connected`, `consumed`. Terminal is terminal. A session id that selects nothing live, because it was never issued, or was consumed, or expired and was pruned, or was displaced by a newer session for the same subject, refuses at the session state step with **one** reason that does not say which, so a refusal discloses nothing about what else exists. |
| `SignedTransactionReader` | Base64 tolerance plus the msgpack subset. Returns the signature and the transaction bytes as a slice of what arrived. Ported from the reference's codec. |
| `SignedTransactionFields` | Type, sender, receiver, amount, fee, note, and the five fields whose presence is a refusal (`rekey`, `close`, `aclose`, `lx`, `grp`). All optional, because absent is a real answer, and for `amt` and `fee` the real answer is zero. |
| `ProofExpectation` | What the proof must match: the address, the challenge bytes, optionally the pinned address the session was minted for, and optionally an authorising key for the rekey retry. An address in both places, never a name: resolving a name is the host's (REQ-verify-042). |
| `ProofRefusal` | An enumeration, one case per ordered check, each carrying a member readable sentence the operator can override **and a non-reversible handle** the host can correlate: a truncated hash of the session id or an opaque per-refusal identifier. Never the session id itself, never the blob, the signature or the challenge (REQ-verify-018). |
| `VerificationOutcome` | `proved(ProvedAccount)` or `refused(ProofRefusal)`. |
| `ProvedAccount` | Subject, address, when, and whether an authorising key was used. Produced only by consuming a signature; no public initialiser. |
| `AssertedAccount` | Subject, address, when, and what the other service said. Public initialiser, because the host has to be able to make one. Named for what it is, so that the one value in this target that was never checked cannot be mistaken for the one that was. |
| `VerifiedAccount` | The single seam both routes meet at: subject, address, when, and `ProofRoute`. Made from a `ProvedAccount` or, by an explicit call, from an `AssertedAccount`. |
| `ProofRoute` | `inProcess` or `asserted`. Carried into the audit so an operator can tell them apart afterwards. |
| `VerificationSessionStore` | A protocol the host implements: put, get, consume, prune, and the two things REQ-verify-019 and REQ-verify-032 need of a store rather than of a session. Putting a session for a subject that already has one displaces and discards the first. And it keeps, per subject and over a window the caller supplies, the submissions made and the retries offered, which survive displacement, consumption, expiry and pruning: the count is what a new session must not reset. The prune drops a subject's counts once its window has passed, and the per-subject maximum is larger than the per-session one so the bound against a member who submits two hundred times does not refuse the member who ran the command twice. One conformer in the target, in memory, for tests. |
| `VerificationCoordinator` | An actor over the store: mint a session, record a connection, accept a blob, produce an outcome. No clock: `now` is a parameter. |

`VerificationCoordinator` is the deliberate scope decision. It would have been
smaller to ship only a signature checker and let the host own sessions,
expiry, single use and ordering. That is also how every one of those properties
gets quietly reimplemented and quietly got wrong. Putting them in the target
means the eventual host's whole job is: bind a route, read a body, call one
method, render one page.

## Decisions, and which way they went

**A second executable that does the checking is declined; where the page is
served from is not decided here.** Option B in the decision record was the
same page behind a second executable, a shared secret, a webhook and a boot
order. It adds no capability. It adds most of `docs/VERIFICATION.md`, which is
why that document is as long as it is. Chosen against, as the record
recommends.

That is as far as the evidence reaches. An earlier draft of this section said
"the page is served by the bot, not by a second process" as a decision this
change makes, and `plan.md` and `tasks.md` said the opposite: that the page's
location is configuration, decided with the executable. `research.md` supports
`plan.md` — it finds that a hostname with TLS is required identically under B,
C and D1 and therefore "does not choose between them", and it leaves the
wallet list and the vendored bundle open as page decisions. The three-route
table above is the same point in another form: a page served elsewhere that
posts to the bot's submit route is the same proof checked in the same process.
So the bot serving the page is the **intended default**, argued for and not
yet chosen, and the decision record is accepted on the narrower proposition.
`context.md` records the reconciliation.

**The existing portal is not open sourced as part of this.** Option C is an
audit, not a feature, and it publishes an identity provider, with password
reset and email delivery and a standing TRUST-3 obligation, in order to ship
forty lines of signature checking. Nothing here forecloses it.

**One accepted shape: a zero amount self payment.** A signed arbitrary message,
with a wallet's `MX` prefix, is simpler to check and would work in some
wallets. It is refused, for a reason visible in the private original:
`WalletAuth.isValidSignature` accepts a signature over the raw message **or**
over the prefixed message (`WalletAuth.swift` lines 24 to 30). That is a
sensible compatibility hedge for administrator sign in and a bad property for
member verification, because it means one signature is valid over two different
byte strings and "they signed exactly this" stops being true. One shape, one
meaning. An operator who wants the message form can run the portal route.

**The subject is the minted member key, not the chat account id.** Argued
above. A person may reasonably disagree: the contract asks for the chat id, and
a member reading a wallet prompt that names them by a Discord handle is
arguably reassured by it. The counter is that they cannot read a snowflake
either, and that the code line does the reassuring better with nothing
person derived crossing the boundary.

**The relay is answered on the page, not in the signed bytes, and the reason
is exact.** The page names the chat account the session belongs to and warns
that nobody should ever send a member this link (REQ-verify-043). In the relay
the victim is standing on the **operator's real page**, on the real origin,
because the attacker's contribution is a link and nothing else: the page
therefore cannot be made to lie about whose session it is, and page-level
display is sufficient for this attack. It is also the only form of it that
helps a first-time verifier, who has no subject value to recognise and every
chance of recognising a name that is not theirs.

Putting the name in the signed bytes would buy something different: a defence
against a **counterfeit** page, one the operator never served. That is a
different attack, it has a different answer, and it would cost the rule
against a person-derived identifier below the chat boundary, inside the one
target whose claim is that it holds none. The page pays neither price. Both
values are kept: the opaque subject line in the bytes, which stops a proof
moving between sessions, and the readable name on the page, which is the part
a person checks.

What is left over after that is a first-time verifier who does not read the
warning. The attack needs somebody to take a link from a stranger and sign
what it shows them, which the server rules an operator already publishes cover
and which every wallet warns about. It is real and it is largely user error,
and saying so is not the same as dismissing it: the residue is a member with
no baseline for what normal looks like here, and the words on the page are the
whole of their defence.

**The command takes an optional wallet argument, and it does not close the
relay either.** `/verify` bare is unchanged; `/verify wallet:` pins the session
to one address and refuses a proof signed by any other with a reason of its
own (REQ-verify-041, REQ-verify-042). It is worth having for three smaller
reasons and it is worth being honest that they are smaller: an address is
public, so an attacker can name the address they are after and every check
still passes. What it buys is a better refusal, an earlier mismatch, and a
member who has committed to an address before anything asked them to sign.

**A wallet argument may be a name, and resolving one fails soft.** A naming
service is a host this package does not talk to today, so it is a new row in
`docs/WHAT-IT-TALKS-TO.md` and a new thing that can be down. Three
consequences, all of them decided here rather than left to the host to invent:
nothing at boot pings it, so a service that is down or was never configured
costs the bot nothing at startup; a name that cannot be resolved is reported
as that, with a request for the raw address, so a member who typed a name is
never stuck; and the resolution happens above the verifying target, which
receives an address and never a name, because `Verify` is the target that
reads nothing and a naming service is a read.

**Sessions live in memory and do not survive a restart.** Fifteen minutes of
state, holding a challenge and a subject. Making it durable means `Verify`
reaching the store, or the store learning about verification, for the sake of a
member who was mid-signature during a deploy and can run the command again. The
cost is real and small: a restart during a verification means one member starts
over, and they are told that rather than shown a dead link.

The per-subject submission count (REQ-verify-032) goes with them, and that is
worth saying rather than discovering: a restart hands every member a fresh
allowance. It is acceptable here because a restart is the operator's action
and not a member's, and it is the reason REQ-verify-038, which the host owns
along with whatever durability it gives its own rate limiter, is the half of
that defence that does not evaporate on a deploy. The host's durable
conformance is where this stops being true, and it should.

**Expiry is checked against a `now` the caller supplies, and nothing in
`Verify` reads the clock.** The same reason `Games` takes its clock through
`GameContext` and `TimeParser` takes `now` as a parameter: every reading is
pinned by a test rather than dependent on when the test ran.

**The expiry the member is told is read from the session.** The reference tells
the member fifteen minutes in plain text without reading `expiresAt`, which
`docs/VERIFICATION.md` calls a wart out loud. One value, read once, formatted
for Discord. It cannot drift because there is nothing to drift from.

**The rekey retry costs a chain read, and `Verify` does not make it.** The
alternative is for the checker to hold a reader and retry itself, which is
tidier and puts an unmetered chain read behind a public endpoint. RUN-11 says
no one member can spend the day's budget however fast they type, so the read
lives with the host that owns the budget, happens at most once per session, and
only on the one refusal that could be explained by a rekey.

"At most once per session" used to be a sentence here and nowhere else, which
is not a bound. It is now REQ-verify-032: the session records that the retry
has been used and the signature refusal stops reporting one as available, so
the limit is a property the offline suite can fail against rather than a habit
the host is trusted to keep. The session also bounds how many submissions it
will take at all, because a session that accepts them forever is a way for one
member to make the host work on demand, and REQ-verify-038 puts a rate limit on
the command and the route rather than leaving it to a transport that does not
exist.

Two things that bound had to gain before it was one. **It is kept per subject
as well as per session**, because REQ-verify-019 has a new session displace the
old one: a bound a member can refresh by running the command again is a
formality, and the store keeps the count across sessions for that reason.
**And it has a floor of three**, because a maximum of one or two satisfies
every test written against a ceiling and locks out the rekeyed member this
very decision exists to serve: one wrong account, one right account that fails
the signature check, one retry with the authorising key.

**Where the authorising key comes from is the host's obligation, and saying so
was load bearing.** `Verify` takes the key as a value in the expectation and
cannot check that the account names it, because checking would be the lookup
REQ-verify-015 forbids it. Written without a constraint on the caller, that
reduces to "if the caller hands you a key, accept a signature by that key for
any address", which is the reference's test mode bypass reached through a
parameter instead of an environment variable. REQ-verify-037 says the key comes
only from the host's own read of that exact account's authorising address, never
from the submission and never from the blob, and REQ-verify-033 keeps the reader
from surfacing a signer key that could become one.

**A proof carrying `rekey`, `close`, `aclose`, `lx` or `grp` is refused, and a
fee above the network minimum with it.** The reference skips every key it does not recognise
(`SignedTransactionCodec.swift` lines 80 to 82), which is correct for parsing
and incomplete for safety. The bot never submits, so it cannot be the attacker,
but refusing means the bot never holds or blesses a signed instrument that could
empty or reassign a member's account if it leaked. It costs a handful of
comparisons.

**The wire name is `rekey`, not `rekeyto`.** This is worth a paragraph because
an earlier draft of the requirement wrote `rekeyto` and it would have shipped.
`rekeyto` is what the field is called in the dependency's transaction type; what
the dependency's canonical encoder puts on the wire is `rekey`
(`Sources/Algorand/CanonicalTransactionFields.swift:175`, alongside `lx` at
`:173` and `grp` at `:172`, with `close` and `aclose` on the transaction types
themselves). Coded literally, the refusal would have matched a key that never
arrives, the tolerant reader would have skipped the real one as unknown, and
every rekeying proof would have passed with a valid signature. The fixtures for
these fields are therefore built by the dependency's own encoder rather than by
hand, so that the name in the test cannot drift from the name in the encoder;
a hand built fixture would have carried the same wrong name as the code and the
suite would have gone green over the hole.

**The fee is bounded at the network minimum rather than pinned at zero.** The
page asks for zero and the checker accepts anything up to one thousand
microAlgos. Bounding it at all is the same argument as the rekey: the bot must
never bless a signed instrument that could empty an account if it leaked, and
a self payment whose fee is the member's balance is exactly that. Bounding it
at the minimum rather than at zero is a decision about evidence. Nobody has
measured which wallets override a fee they were handed, and a checker pinned
at zero turns an untested wallet behaviour into a member who cannot verify and
cannot act on the refusal, for a policy the page has no way to enforce inside
somebody else's wallet. At the minimum a leaked blob costs a member a fraction
of a cent instead of their balance, which is what the bound is for.

The cost is real and is written down rather than discovered: a zero fee with
no group makes the blob un-submittable outright, and at the minimum it becomes
submittable again. Submitting it moves nothing, from the member to the member,
and costs one minimum fee. That is cheaper than refusing a member whose wallet
insists on a minimum, and the manual list is where the guess becomes a
measurement. If every supported wallet honours a zero, tightening the bound
later is a change with evidence behind it rather than a guess taken now.

**No test mode, no bypass, no flag.** The reference accepts the literal string
`test-transaction` in place of a signed transaction when an environment
variable is set (`VerificationController.swift` lines 281 and 284), and a second
literal does the same for the message path. It is documented and off by
default, and it is still an identity bypass behind a flag: with it on, anyone
who can reach the endpoint can claim any address they can type and take
whatever that address earns. BUILD-3 exists because of this exact shape. There
is no equivalent here, at any setting. Testing without a wallet is done the way
`docs/VERIFICATION.md` prescribes: a real signer with a throwaway key, so the
verification path runs unchanged.

**And the asserted route does not become one by the back door.** Both routes
still meet at one downstream value, but they do not share a producer. A
`ProvedAccount` is made only by consuming a signature and has no public
initialiser; the asserted route makes an `AssertedAccount`, which is public
because the host must be able to make one, and says in its own name that
nothing here checked it. An earlier draft asked for one type, constructible for
the asserted route, with a non-public initialiser, which cannot all be true at
once; the natural way to resolve it in code is a public factory that mints an
unchecked proof inside the one target whose whole claim is that there is no
such thing (REQ-verify-034). The no bypass suite now asserts over the public
interface rather than over one initialiser, which is what would have caught it.

**The blob is never stored and never logged, and neither is the session id.**
The outcome is logged, with a non-reversible handle beside it: a truncated hash
of the session id, or an opaque per-refusal identifier, which is enough for an
operator to match a member's report to a line and useless to anybody who reads
the line. This paragraph used to say the session id was logged, and
REQ-verify-031 and REQ-verify-036 had meanwhile made it a bearer credential
that must never reach a log or an error report, so REQ-verify-018 was
contradicting them from inside the same definition. A signature in a log is a
signature somebody else can replay against any checker that does not bind to a
session; a session id in a log is worse, because it binds.

**`swift-crypto` becomes a direct dependency.** The alternative was to reach it
transitively, which builds today and is a dependency this package has not
declared and cannot pin. It is already resolved at 3.15.1, so the change is a
line in the manifest, a row in the dependency table and a changelog entry, and
no resolved version moves.

## What this change does not build, and what that costs

**It does not build the listener, the page or the slash command.** There is no
executable target in this repository, no HTTP server and no Discord gateway.
Taking an HTTP server is a dependency decision with a real graph behind it, and
the decision record names it as the largest single piece of work in the option
it recommends. Bundling it into this change would make the change
unreviewable and would put a JavaScript build step into a Swift package in the
same commit as the cryptography.

The consequence must be said plainly rather than buried, because it is the
honest gap between this change and its own acceptance criterion: **after this
change, a stranger who clones this repository still cannot verify a member,
because there is still nothing to run.** What changes is that the part that
decides whether somebody owns an account is here, offline, tested, with no
second service anywhere in it, and the part that remains is a page and a socket
rather than a product. `README.md` and `docs/VERIFICATION.md` must both say
that, in the terms BUILD-4 asks for: which parts are built and which are only
written down.

**It does not build the chain observed route.** No indexer, no new host, no new
secret. The seam is left open.

**It does not build the wallet argument, the naming service call or the page's
named account and warning.** All three are the host's, defined here so it has
nothing to invent: REQ-verify-042 and REQ-verify-043. What this change builds
of them is the half that can be proved offline, which is the pin itself and
the refusal that names it (REQ-verify-041).

**It does not decide where the page's JavaScript is built.** That arrives with
the host target and is a release process question, not a proof question.

## Where it touches the documents

| Document | What changes |
|----------|--------------|
| `docs/decisions/0001-verification-portal.md` | Status moves from proposed to accepted on the narrower proposition: the proof is checked in the bot's own process, B and C are declined, the portal is a supported alternative, and the chain observed route is deferred with its cost. Where the page is served from is a stated scope exclusion of the record, not part of its decision. |
| `docs/VERIFICATION.md` | Gains the in-process route as the first route and keeps the portal contract intact as the second. The two challenge departures are recorded. The framing changes from "the bot cannot do this" to "this is the seam you take on if you want the page elsewhere". |
| `docs/WHAT-IT-TALKS-TO.md` | `swift-crypto` moves to a declared dependency. `Verify` is listed as a target that opens no connection. **One new host, recorded now and reached later:** the naming service behind the wallet argument (REQ-verify-042), written in the way that document already flags what a member's browser will reach, as optional, reached only when a member types a name, needed by nothing at boot, and not called by `Verify`. No new secret. |
| `docs/CONFIGURATION.md` | **No new variable.** This design originally listed the route variable, the operator's label, the wallet list and the session lifetime here; `REQ-verify-002` and `REQ-verify-017` leave nothing in this change that reads one, and the route variable is `REQ-verify-023`, a host obligation. Only the library count on line 18 changes. Those four arrive with the host, and this document will own their meanings then. |
| `specs/verify/` | The new module contract, and `Sources/Verify` added to `.specsync/config.toml`. |
| `README.md`, `CHANGELOG.md` | What exists and what is still missing, and the dependency line under `Unreleased`. |
