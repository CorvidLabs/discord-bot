---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: research
---

# Research

## What was read, and how it is cited

Three code bases were read. This one, at `feature/def-verify`. **The reference
portal**, the web application [`docs/VERIFICATION.md`](../../../docs/VERIFICATION.md)
was written out of. **The ported bot**, the Discord bot this repository is
being ported from. Neither of the other two is named here and neither is
quoted by a filesystem path: their files are cited relative to their own source
target, as `Controllers/VerificationController.swift:280`, so a reader with
access can find the line and a reader without one learns nothing about where it
lives. The dependency, `swift-algorand`, is public and is cited normally.

Where a claim comes from outside a code base it is marked **(external)** and
names what it came from, because the repository rule is that a claim is
grounded in something a reader can re-run and none of those are.

## The question this change turns on, answered first

**Can a member prove ownership of an Algorand account to a Discord bot with no
second web service, using only what wallets in that ecosystem already do?**

**Yes.** Not as a design on paper: the ported bot already does the whole of it,
in one process, today, for administrators. It serves the page, it serves the
wallet library as a static asset it holds itself, it issues a single-use
challenge, it takes the signature back on its own endpoint and it checks the
Ed25519 signature in process with no web application and no second service
anywhere in the flow. The member-facing half is the same shape with a different
audience and a different record to write at the end.

**Can they do it with no browser page at all? Not by any route evidenced
here.** Every wallet integration in either code base is driven from a browser:
the reference portal configures three wallets through a browser connect
library and the ported bot vendors one wallet's browser build. No path by
which a server, holding no key, asks a wallet for a signature and gets one
back without a page in front of the member appears anywhere in that code.
Whether such a path exists somewhere outside it is **(external)** and is
addressed in section 3; what is established here is that two working
implementations both needed a page. It is worth stating precisely because the
two questions have been run together: **a page is not a service.** The page
has to exist. What is optional is whether a second deployable process serves
it.

So the decision in
[`docs/decisions/0001-verification-portal.md`](../../../docs/decisions/0001-verification-portal.md)
is between D1 and B, and everything below is the evidence for which.

## 1. How the reference portal actually proves ownership

Six steps, and only one of them is cryptography.

**It issues a challenge.** `Controllers/VerificationController.swift:519-523`
builds a session token from a UUID with the hyphens stripped, a nonce from the
first eight characters of another UUID, a unix timestamp, and a four-line
challenge string: a fixed label, the member's chat account id, the timestamp
and the nonce. The session expires fifteen minutes later
(`:539`), any earlier pending session for that member is deleted first
(`:526-530`), and the answer is `201` carrying the token, the page URL and the
expiry (`:546-554`).

**Two things the challenge does not contain, and both matter here.** It does
not name the server, although the session row holds a `context_id`
(`Models/PendingVerification.swift:21`) and the bot checks it again on the
callback. And it does not name the community or the instance. So what the
wallet displays to the member says which bot is asking only by way of a fixed
label that every deployment of that software shares. This change's acceptance
criteria ask for a proof that "cannot be used for a different server", and the
reference's signed bytes do not carry one.

**It binds an address at connect time, before any signature.**
`:198-250`. The address is parsed (`:207`), the session is found and its expiry
checked (`:211-216`), an address another member already proved in the same
context is refused with `409` (`:219-232`), and only then is the address
written onto the session and the challenge returned to the page (`:235-247`).
The `409` is the only place one account, one member produces a message the
member actually reads.

**It takes a signed transaction, not a signed message.** `:253-310`. The
submitted blob is base64. The page that produces it
(`frontend/src/App.tsx:158-181`) reads suggested params from a node, forces the
fee to zero and `flatFee` on, builds a zero amount self payment carrying the
challenge as the note, encodes it unsigned and calls `signTransactions`. The
transaction is never submitted.

**It verifies.** `:1029-1075`. The blob is decoded, the signed envelope is
parsed, the bytes `TX` are prepended to the transaction bytes exactly as they
arrived (`:1049-1051`), and the signature is checked against the 32 bytes that
**are** the address (`:1077-1083`). If that fails, and only then, the account is
looked up on chain and the check is retried against its authorising address
(`:1058-1068`, `:1119-1132`), so a rekeyed account can still prove ownership at
the cost of one chain read on a failed signature. Then the transaction's fields
are evaluated: sender, receiver, amount, note
(`Services/SignedTransactionCodec.swift:429-459`). Field failures are reported
before signature failure (`:428`), because a member with the wrong account
selected can fix that and a member with a bad signature cannot. An **absent**
amount is zero (`:449-451`), which is not a nicety: Algorand's canonical
encoding omits zero valued fields, so a verifier that requires an `amt` key
rejects every correctly formed proof.

**It notifies, then saves.** `:335-352`. The webhook goes first and the
database write only happens after it returns. That ordering is right and the
contract keeps it.

### The hard part is the decoder, and it is smaller than it looks

`Services/SignedTransactionCodec.swift` is 460 lines including the ownership
enum at the end. Its own header comment (`:3-7`) says why: one named mobile
wallet, on one named mobile browser, does not always send a bare `{sig, txn}`
map. **That is one attribution covering three named shapes** — the payload may
be standard or URL safe base64, with or without padding (`:22-44`), it may be
wrapped in a one element msgpack array, possibly twice (`:47-52`, `:123-149`),
and the envelope may carry an extra signer field that has to be skipped rather
than rejected (`:113-115`). It is not a shape per handset, and nothing in that
file records which wallet sent which shape or on what device, so a claim that
every branch exists because a real wallet sent it goes further than the code
does. Roughly 250 of those lines are a generic msgpack skipper (`:278-409`)
whose only job is to walk over fields nobody reads so the transaction bytes
can be sliced out verbatim (`:105-112`).

**Sliced out verbatim is the load-bearing part.** The signature is checked over
the bytes as they arrived, never over a re-encoding of the parsed fields. A
re-encoding that differs by a single byte fails a perfectly good signature.

### One thing in it must not be ported

At `:281-287` the submit handler reads an environment variable named for
testing, and when it is set to true and the posted signed transaction is one
fixed literal, or the posted signature is a second fixed literal, it sets its
validity flag to true and never reaches the check. The code is not quoted
here: what matters for a definition is the shape, and a verbatim copy of
another repository's source in a public artifact is a leak that buys nothing.

With that environment variable set, the literal string the handler looks for,
posted in place of a signed transaction, proves that the member owns whatever
address they connected. There is no weakened check here. There is no check.
Anyone who can reach the endpoint takes the roles that address earns and is
paid whatever a holder of it is owed. It is off by default and it is
documented, and it is still an authentication switch wearing the word "test",
which is the exact shape [BUILD-3](../../../hi/build.md) exists to forbid and
[BUILD-3.b](../../../hi/build.md) answers: a build that cannot be trusted with
an identity is a different artifact, not a variable.

The honest replacement is already named in
[`docs/VERIFICATION.md`](../../../docs/VERIFICATION.md): a fake signer in the
test suite that produces a real signature over the real challenge with a
generated key, so the verification path runs unchanged. That is also what this
change's acceptance criteria ask for, and it costs nothing: the ported bot's
dependency can already sign (`Account.sign(_:)` in swift-algorand,
`Sources/Algorand/Account.swift:120`).

### Three other departures found while reading, beyond those already listed

- `:1003-1020` compares the shared secret with `==`. The contract already
  records this; what reading it adds is that the comparison is on the side
  facing the public internet.
- `:1163-1175` returns early when no callback URL is configured, and the caller
  then saves the verification anyway (`:335-352` runs the save after
  `notifyBot` returns normally). A member is verified on the portal and unknown
  to the bot.
- `:566` and `:597` default a missing `guildId` to the empty string rather than
  refusing it, and `:1139` falls back to a hard coded asset id when the
  operator has not set one. The second is the shape
  [ADOPT-6](../../../hi/adopt.md) forbids: an unset thing became somebody
  else's value rather than empty.

## 2. What the ported bot already does in process, which decides this

This is the finding that answers the question, and it is not the forty lines of
signature checking the decision record already credits.

**The ported bot serves a wallet-connected browser page from the bot process.**
`Services/AdminServer.swift` binds an HTTP listener on its own port and:

- serves the wallet library itself, as a static asset, from a route of its own
  (`:144-150`) backed by a file under `Resources/` that its
  `Package.swift:43-45` copies into the build. That file is a vendored,
  minified, single file browser ESM build of one wallet's connect package,
  about one megabyte, with the exact regeneration command in a comment at the
  top of it. **There is no bundler in the Swift build, no npm at build time,
  and no third party CDN at runtime.**
- serves the page's own script from Swift source (`AdminUIScript.swift`, about
  1,200 lines of hand written vanilla JavaScript, no framework), which imports
  the vendored module at `:66-75`.
- issues a challenge at `GET /api/auth/challenge` (`:160-166`): a random nonce,
  a two line message naming what it is for, rate limited per source address to
  20 in 60 seconds (`:762-772`).
- takes the answer at `POST /api/auth/verify` (`:168-183`) and verifies it in
  `:677-690`: the nonce is **consumed** rather than read (`take` at `:758-760`
  removes it), it must be under 120 seconds old, the signature must check out,
  and the address must be on the allowlist.
- sets security headers on every response, including a
  Content-Security-Policy with `default-src 'self'` and
  `frame-ancestors 'none'` (`:17-18`, `:118`, `:775-788`).

**The page asks the wallet to sign arbitrary data, not a transaction.**
`AdminUIScript.swift:957-972`: connect, fetch the challenge, `TextEncoder`,
`wallet.signData([{ data, message }], address)`, base64, post it back. No
transaction is built, no suggested params are read, no node is contacted
anywhere in the flow.

**And the verifier is forty lines.** `Utilities/WalletAuth.swift:11-31`: parse
the address, take its bytes as an Ed25519 public key, require 64 bytes of
signature, check. That is the whole of it.

So the claim in the decision record that "the implementation this was read out
of already does it in process" understates its own evidence. The in-process
part is not only the cryptography. It is the page, the asset serving, the
challenge lifecycle, the single-use nonce, the rate limit and the headers. All
of it already exists in one process, in Swift, with a wallet on the other end.

### What `WalletAuth` does not cover

Named plainly, because these are the gaps this change has to fill rather than
inherit.

- **No transaction understanding at all.** It verifies a signature over a UTF-8
  string. It has no msgpack decoder, no notion of sender, receiver, amount or
  note, and no `TX` prefix. A wallet that can only sign a transaction cannot be
  verified by it.
- **No domain separation, by construction.** `:24-29` accepts the signature
  over the raw message **or** over the message prefixed with `MX`, returning
  true on either. The `MX` prefix exists so that a signature over arbitrary
  data can never be mistaken for a signature over something else; accepting
  the unprefixed form throws half of that away. Whatever this change builds
  should require exactly one form and reject the other.
- **No session.** The nonce lives in an actor in memory (`:750-773`), so every
  restart invalidates every in-flight login. Tolerable for a rare admin sign
  in, wrong for members: a restart during a sweep would refuse everybody
  mid-verification.
- **No binding beyond the nonce.** The challenge message is a label and a
  nonce. No member, no server, no instance.
- **The nonce is not drawn from a named CSPRNG.** `:38-48` fills 32 bytes from
  `UInt8.random(in:)`, one byte at a time. **(external)** Swift's default
  generator is documented as suitable for cryptographic use on the platforms
  in question, so this is very likely fine; that is a claim about a language's
  documentation rather than about anything read here, and "very likely fine"
  is the wrong standard for the value that stops a replay. swift-algorand has `SecureRandom` (`Sources/Algorand/SecureRandom.swift:16`)
  and it is `internal`, so it cannot be used from here; swift-crypto's
  `SymmetricKey(size: .bits256)` is what the reference portal uses for the same
  job (`Controllers/VerificationController.swift:996-1001`).
- **No rekey handling.** An account rekeyed to another key cannot sign in.
- **Nothing writes a record.** Admin sign-in writes a session cookie. Member
  verification has to write an account against a member, which is
  `AccountStore.prove` here (`Sources/Store/BotStore.swift:56-64`).

## 3. What a wallet can be asked to sign, and how a verifier checks it

Three schemes exist, and they are not interchangeable. The first column is what
the key actually signs, which is the only thing a verifier can check.

| Scheme | Bytes signed | What binds it |
|--------|--------------|---------------|
| Transaction (`algo_signTxn`) | `TX` followed by the canonical msgpack transaction | The genesis id and hash in the transaction pin it to a network |
| Legacy arbitrary data | `MX` followed by the bytes you passed | Nothing but the bytes themselves |
| ARC-60 (`algo_signData`) | A digest over the data together with a digest over authenticator data | A scope and the page's own origin |

**What is evidenced in the code read for this, stated no wider than the code
goes.** The reference portal offers three wallets
(`frontend/src/main.tsx:15-21`) and builds one transaction for all of them
through one `signTransactions` call (`App.tsx:180`), so its **author**
evidently expected the transaction path to work across all three; that a
deployment exists is not the same as a test, and no code read here records a
per-wallet result. The arbitrary-data path is in production for **one** of
them: the ported bot's admin sign-in calls that wallet's `signData` from a
browser (`AdminUIScript.swift:965`). Note what that does **not** settle —
its verifier accepts the signature over the raw bytes **or** over `MX` plus
the bytes (`Utilities/WalletAuth.swift:24-30`), returning true on either, so
the code does not establish which of the two byte strings that wallet
actually signs. Anything built here must require exactly one form, and
finding out which one is a handset question rather than a reading question.
The reference portal still carries a verifier for the arbitrary-data path
(`Controllers/VerificationController.swift:1085-1108`) that its current page
no longer uses, which is the archaeology of having moved to transactions for
uniformity.

**(external)** None of the four bullets below is evidenced by either code base
or by anything else a reader here can re-run. They came from a second agent
with web access reporting on the wallets' own SDK sources and the ARC texts,
they are recorded because the design would change if they were wrong, and they
must be re-checked before anybody builds on them. This block is the most
dangerous thing in this artifact and is marked accordingly:

- Arbitrary-data signing is **not uniform**. One of the three wallets exposes
  the legacy raw-bytes call and a newer ARC-60 call; one exposes ARC-60 only,
  in a shape that changed between recent versions; one exposes **no**
  data-signing method at all and speaks only `algo_signTxn`.
- The cross-wallet React library the reference portal's page is built on does
  expose a `signData`, and in the major version that page pins it is
  implemented by **one** of the three wallets; the others throw. A later major
  version adds a second.
- ARC-60 is still a draft, and its AUTH scope requires the wallet to check the
  page's origin against the payload. That is a real benefit for a self-hosted
  page, because it binds the signature to the operator's own hostname and
  therefore to their community, and it is not something to depend on while one
  of the three wallets cannot do it at all.

**Conclusion for the design: the transaction is the main road and arbitrary
data is not a second road this change takes.** Not because the transaction is
better, but because it is the only one the code read here shows reaching every
wallet the reference offered, through a single call. Which means this
repository has to port a tolerant decoder.

The data path is **declined**, and `design.md` decides it on a ground that
does not depend on the external bullets above: accepting a signature over an
arbitrary message would mean accepting two byte strings for one signature, as
`WalletAuth.swift:24-30` does, and "they signed exactly this" would stop being
true. `REQ-verify-009` fixes one accepted shape. An earlier draft of this
section recommended supporting the data path as well; that would have been a
second thing to get wrong for no gain this change needs, and it is left as a
future caller of the same checker rather than as work here.

### Verifying without a node

The verifier needs nothing from the network. Address bytes are the public key,
the signature is Ed25519, the message is a prefix and some bytes. The only
chain read anywhere in the reference's verification is the rekey retry on a
**failed** signature (`:1058-1068`), which is optional and rate-limitable.

**The page, though, reads a node today, and does not have to.**
`frontend/src/App.tsx:158` calls `getTransactionParams` purely to fill in
fields of a transaction that is never submitted, and then overrides the fee it
just fetched. **(external)** ARC-1 requires a conforming wallet to check the
genesis id and hash against its own network and explicitly does **not** require
live suggested params; a fabricated first and last round and a zero fee are at
most a warning, and an official tutorial for one of these wallets built exactly
this pattern with hard coded rounds. Whether the current release of each wallet
app still signs it is not something a document can settle: it is one afternoon
with three phones, and it should be settled before the page is written.

If it holds, the genesis pair for the configured network is the only thing the
page needs, and it never changes: one read at boot, cached for the life of the
process, or an operator setting. This repository has no network setting today,
only `CHAIN_NODE_URL` (`docs/CONFIGURATION.md:202`), which is also the gap
[ADOPT-12.b](../../../hi/adopt.md) names.

## 4. What this repository already has, and what it is missing

**Has:**

- `Address(string:)` in swift-algorand parses and checksums an address and
  exposes its 32 bytes (`Sources/Algorand/Address.swift:14-95`).
- swift-crypto is already in the resolved graph, pinned, through
  swift-algorand (`Package.resolved`, and swift-algorand's own
  `Package.swift:19-28`). Declaring it directly adds **no new pin**, which
  matters for [TRUST-4](../../../hi/trust.md) and for the manifest's own note
  about ranges and locks (`Package.swift:46-58`).
- The record end of it: `AccountStore.prove` refuses an account another member
  proved (`Sources/Store/BotStore.swift:56-64`), and `forget` exists for the
  other direction (`:44`).
- `Gating.AdminAllowlist` (`Sources/Gating/AdminAllowlist.swift:15-45`), the
  list of accounts that may administer **by signing**, with nothing behind it
  yet. Whatever verifier this change builds is the thing that allowlist has
  been waiting for. One verifier, two audiences.

**Missing:**

- **Any HTTP surface.** There is no listener, no client, no executable
  (`README.md:67-69`). The webhook the contract describes does not exist here
  either, so "the bot already binds a listener anyway" is true of the ported
  bot and not yet true of this one. A listener is new work under every option.
- **A msgpack reader.** swift-algorand can write msgpack
  (`MessagePackWriter.swift`) and encode a signed transaction
  (`SignedTransaction.swift:187`), and `MessagePackValue` is `internal`
  (`:154`). There is no decoder, and nothing that parses a signed transaction
  that arrived from outside. The tolerant decoder has to be ported or written.
- **A public-key-only verify.** `Account.verify(signature:for:)` exists
  (`Sources/Algorand/Account.swift:136`) and an `Account` holds a private key,
  so it is the wrong entry point. Verification goes through swift-crypto
  directly, as both code bases read for this already do
  (`VerificationController.swift:1078-1081` and `WalletAuth.swift:14`, both
  `Curve25519.Signing.PublicKey(rawRepresentation:)` then
  `isValidSignature`).
- **Anywhere to keep a session.** Six tables
  (`Sources/Store/StoreTable.swift`), none of them a pending challenge.
- **A CSPRNG.** See above.

## 5. What each of the four options really costs

Corrected against what was read. The decision record's costing is broadly right
and wrong in two specific places.

**A, publish the contract only.** Done. Nothing to add, and it does not compete:
every other option needs the document. Leaves
[ADOPT-4](../../../hi/adopt.md) failing.

**B, a second executable here.** Needs everything D1 needs, plus the whole seam:
a shared secret, `X-API-Key` on both sides in constant time, the callback, the
single fixed-size read, the `201`, the boot-order dependency and the two
process deployment. Read
[`docs/VERIFICATION.md`](../../../docs/VERIFICATION.md) and count: the
authentication section, the transport constraint, the retry rules, three of the
five security properties, four of the eight departures and six of the nine
failure modes are all the seam. Every one is paid by every operator, forever,
to keep two processes agreeing about a string.

**C, publish the existing portal.** The reference portal's route table
(`Controllers/VerificationController.swift:7-53`) is an identity provider that
also does verification: a published JWKS, authorization codes, refresh tokens,
a `/me` endpoint, a redirect allowlist, and separately email verification and
password reset (`Migrations/` holds tables for all of it). Verification is the
minority of it. Publishing it means an audit, a scrub, removing the test mode
bypass, and a standing security-reporting obligation
([TRUST-3](../../../hi/trust.md)) on code most operators will not want.

**D1, the bot serves the page.** The two costs the decision record puts on this
are **smaller than stated**, and that is the substantive correction:

- "A JavaScript bundler in a Swift repository and a release process with two
  artifacts in two languages" is not required. The ported bot vendors a single
  prebuilt browser ESM file with its regeneration command in a comment, copies
  it as a package resource, and serves it. The build stays `swift build`.
  Keeping a vendored bundle honest is a real commitment and a much smaller one
  than a second toolchain, and it has an answer this repository already uses
  elsewhere: the file is checked in, so what is served is what the repository
  says.
- "Browser JavaScript is a larger attack surface, and the page is on the same
  process that holds a signing key" is answered the way the ported bot answers
  it: a separate port, a strict Content-Security-Policy, security headers on
  every response and a reverse proxy in front. The verification page needs
  **no** authenticated surface at all, which is a weaker requirement than the
  admin page that already runs this way.

What is not smaller: the wallet libraries are a standing commitment at their
cadence and not ours, and that cost is **identical** under B, C and D1. It is
the cost of a page existing, not of where it is served.

**D2, prove it on chain with no browser.** Still needs an indexer, but the
client cost is zero: swift-algorand ships `IndexerClient`
(`Sources/Algorand/IndexerClient.swift`). Two caveats found on reading it. Its
`searchTransactions` (`:178-210`) takes an address and a round range and has no
note-prefix parameter, so a caller filters locally. And doing it against algod
alone, by scanning blocks over a fifteen minute window, is roughly two hundred
block reads per verification against a budget this repository counts in whole
days (`CHAIN_DAILY_REQUEST_BUDGET`, `docs/CONFIGURATION.md:206`), which is not
a serious option. D2 also costs the member a fee and requires them to hold
ALGO, which breaks the promise that walking away costs nothing
([VERIFY-1](../../../hi/verify.md)).

**D3, paste a signature into a modal.** Rejected, and reading the wallets
confirms why: a normal holder has no way to produce one without a command line
or a page that asks them to do something indistinguishable from phishing.
**(external)** The wallet URL schemes that exist open a send or an opt-in
screen and return no signature, so there is no deep link that closes this loop.

## 6. The flow, end to end, if the bot serves the page

What the member does, on a phone, which is where most of them are.

1. `/verify` in Discord. The bot creates a session and a challenge, with an
   expiry fifteen minutes out. It replies, ephemerally, with a button. **What
   the challenge contains is fixed by `REQ-verify-003` and not by this
   sketch**: five lines, being the operator's label, an identity for this
   instance, the subject, a six character code and a nonce. The subject is the
   instance's own minted member key, never the chat account id and never a
   time, which is what `REQ-verify-004` forbids and what `design.md` departs
   from the contract over. An earlier draft of this step named the member and
   the time; a later one named neither, which the security review closed as
   `REQ-verify-030`.
2. The member taps it. Discord opens the operator's own hostname in a browser.
   The page is served by the bot.
3. The page offers the wallets it was built with. The member taps theirs. The
   wallet app opens by deep link, they approve the connection, and they come
   back to the page.
4. The page asks for a signature. Where the wallet can sign arbitrary data, it
   is the challenge text and nothing else. Where it cannot, it is a zero amount
   self payment carrying the challenge in its note, which the wallet displays
   as a payment to themselves of nothing. The member approves in the wallet and
   comes back.
5. The page posts the result to the bot's own endpoint. The bot verifies in
   the order `REQ-verify-013` fixes: **session state and expiry first**, then
   the decode and the parse, then the fields, then the note, and the signature
   last. An earlier draft of this step put the session checks after the
   signature, which would tell a member with a dead link to go and debug their
   wallet. It marks the session used, writes the account with
   `AccountStore.prove`, and reads the balance.
6. The page says it worked. Roles follow in Discord.

**What is honestly awkward about that on a phone.** Steps 3 and 4 each leave
the browser for the wallet app and come back, and Discord's in-app browser is
where that is most likely to go wrong. The reference portal's flow is the same
shape and is in use, so it evidently works often enough; that is not the same
as it working for everybody, and no repository read for this contains evidence
about the failure rate. A member whose wallet will not connect is a real and
recurring support case, which is the argument for keeping D2 as a documented
fallback rather than as the road.

**What the operator has to have:** a hostname with TLS pointing at the bot.
Wallet connection wants a secure context, and the member's phone is not the
bot's localhost. That requirement is identical under B, C and D1, so it does
not choose between them; it is the cost of a page. The ported bot already runs
its admin page this way, behind a proxy, reading `X-Forwarded-Proto` to decide
cookie security (`Services/AdminServer.swift:692-694`).

## 7. What this research could not settle

- **Whether current releases of all three wallet apps sign a transaction built
  from fabricated suggested params.** ARC-1 says they should, and one wallet's
  own tutorial did exactly this, and one of the three has had a major rewrite
  since. Three phones, one afternoon. Until then the page should keep the one
  node read and treat dropping it as an improvement, not a premise.
- **Which wallets to ship.** The reference portal picked three. That is an
  [ADOPT](../../../hi/adopt.md) question as much as a technical one, and the
  answer changes how much vendored JavaScript this repository carries.
- **Whether the vendored bundle is acceptable to this repository's own
  standards** for what a build is made of. A checked-in megabyte of minified
  third-party JavaScript is auditable in the sense that it does not change
  under you and is not auditable in the sense that anybody will read it. There
  is a real argument for a build step and a real argument against. It is a
  decision, and it is not this artifact's to make.
- **Whether the challenge should name the account.** The reference binds the
  address at connect time and checks the sender against it. Binding it into the
  challenge instead would remove a state transition and change where the
  `409` for one account, one member is raised. That belongs in `design.md`.
