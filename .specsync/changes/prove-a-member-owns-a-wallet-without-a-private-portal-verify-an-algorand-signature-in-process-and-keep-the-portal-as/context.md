---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: context
---

# Context

## The problem

The thing this product exists for is that holding something on chain means
something in a server, and the first step of that is a member proving an
account is theirs without handing anybody a key. Everything else is downstream
of that one moment: `Gating` decides nothing until a member has a proved
account, `Reserve` pays nobody, and the six libraries add up to something that
cannot do its job.

In the implementation this repository is being ported from, that proof happens
in a **separate web application in a separate private repository**. The bot
hands the member off to it and hears back over a webhook, and it refuses to
start if that application is not answering. So a stranger who clones this
repository and follows the README cannot verify a single member. The feature
the product exists for returns an error. That is
[ADOPT-4](../../../hi/adopt.md) failing, getting from a clean machine to a
running bot by following the README alone, and
[VERIFY-5](../../../hi/verify.md) failing, offering verification in your own
server without asking your members to trust anybody but you.

## How it was noticed

By writing the contract down. [`docs/VERIFICATION.md`](../../../docs/VERIFICATION.md)
was read out of the working implementation's source so that somebody could
build the other half from it, and the act of writing it made two things
obvious. The first is how much of the document is not about proving anything:
the shared secret, the header, the callback, the single fixed size read, the
status code that has to be `201`, the boot order. All of that is the cost of
the split. The second is that the expensive half, the Ed25519 check, is about
forty lines, and the bot already does it in process to sign administrators in.

That was recorded as
[`docs/decisions/0001-verification-portal.md`](../../../docs/decisions/0001-verification-portal.md),
which lists four options and is marked **proposed**. A record marked proposed
is not licence to build it, so this change exists to answer the open question
with evidence rather than to assume either answer.

## What the research settled

[`research.md`](research.md) has the detail and the citations. The short
version, because everything downstream rests on it:

**A member can prove an account to a Discord bot with no second service.** Not
as a design: the bot this repository is being ported from already serves a
browser page from its own process, serves the wallet library itself as a
vendored static asset with no bundler in the build, issues a single use
challenge, takes the signature back on its own endpoint and verifies it in
process. It does that today for administrators. Member verification is the
same shape with a different audience and a different record at the end.

**A member cannot prove an account with no page at all**, as far as the code
read for this shows. Every wallet integration in either implementation read
here is driven from a browser: the reference portal configures three wallets
through a browser connect library and the ported bot vendors one wallet's
browser package. No path by which a server asks a wallet for a signature and
gets one back with nothing in front of the member appears anywhere in that
code. That is a statement about what was read, not a survey of every wallet
that exists, and `research.md` marks the wider claims **(external)** because
they are not grounded in anything a reader here can re-run.

Those two are one sentence apart and they have been running together in every
discussion of this: **a page is not a service.** The page has to exist under
every option. What is optional is whether a second deployable process serves
it.

## What was settled while these artifacts were reconciled

These eight artifacts were written in parallel by people who could not see each
other's work, and on two questions they came back disagreeing. Both are
settled here, once, because a definition that answers its own central question
two ways is worth nothing to whoever executes it.

**Is the proof checked in process, or by a portal?** *In process.* This was
never really two answers: every artifact reaches it. What made it worth
writing down is that the evidence is stronger than any of them claimed
individually, and it is checkable rather than argued. The bot this repository
is being ported from does the whole shape today, in one process, for
administrators: it binds its own HTTP listener, serves a vendored browser
build of a wallet's connect package as a package resource with its
regeneration command in a comment, serves the page's script from Swift source,
issues a single-use nonce it consumes rather than reads, and verifies the
Ed25519 signature in about nineteen lines with no web application anywhere in
the flow. `research.md` cites every one of those line by line. The portal is
therefore a supported route and not a requirement, and `Verify` is what this
change builds.

**Does this change decide where the page is served from?** *No, and two
artifacts said it did.* `plan.md` and `tasks.md` held that the verifier
belongs in the bot whatever happens to the page, and that the page's location
is configuration settled with the executable. `design.md` and `docs.md` held
that the decision record moves to accepted as "D1, the bot serves the page".
Settled toward `plan.md`, because that is what the evidence in `research.md`
actually supports and the other reading goes past it: research establishes
that the checking needs no second service, and it establishes that B and C
cost strictly more than D1 for no capability, but on the page's location it
says the opposite of settled — that a hostname with TLS "is identical under B,
C and D1, so it does not choose between them; it is the cost of a page" — and
it leaves the wallet list and the vendored-bundle question open as page
decisions that are "not this artifact's to make". `design.md`'s own three-route
table already makes page location configuration: a page served elsewhere that
posts to the bot's submit route is the same proof in the same process. So the
record is accepted on the narrower proposition, which is the one the evidence
carries.

Two consequences follow, and both were applied:

- The decision record moves to accepted on "the proof is checked in the bot's
  own process; a second deployable service that does the checking is declined,
  and so is publishing the existing portal". Where the page lives is a stated
  **scope exclusion** of the record rather than part of its decision.
- Sentences asserting that the bot in *this* repository already binds a
  listener were corrected. It does not. `docs/VERIFICATION.md:13` says so, and
  the listener is new work under every option.

A third disagreement, smaller and settled the same way: `design.md` listed four
new variables for `docs/CONFIGURATION.md` and `docs.md` argued for none.
`requirements.md` decides it, because `REQ-verify-002` and `REQ-verify-017`
leave nothing in this change that reads a variable. None, and the section
arrives with the host.

## The five decisions the owner took, and what they settle

**Read this before approving.** After the security repair was written, the
repository owner took five decisions in an interview. One of them closes the
only security finding that was still open, three add surface, and the fifth
says when any of it may start. They are settled: this section records the
reasoning so that nobody relitigates them, and so that the next person reading
these artifacts can tell a decision from a preference.

### 1. The relay warning goes on the page, not into the signed bytes

**The attack.** Somebody runs the verification command in the server, gets a
session and its link, and sends the link to a member. The member opens the
operator's real page, on the real origin, connects their wallet, and signs a
prompt with nothing wrong with it. The blob is posted to the sender's session,
and the member's address is proved for them, while the member is locked out of
proving their own wallet by the one-address-one-member refusal.

**The decision.** The page shows which chat account the session belongs to, by
name, with a warning along the lines of "only continue if that account is
yours, and nobody should ever send you this link". The reply carries the same
warning. That is `REQ-verify-043`.

**Why the page is enough here, exactly.** In the relay the victim is on the
**operator's real page**. The attacker's whole contribution is a link, so the
page cannot be made to lie about whose session it is: whatever it displays is
the operator's own software telling the truth. Page-level display is therefore
sufficient against this attack. It is also the only form of the defence that
helps a first-time verifier, who has never seen their own subject value and
has nothing to compare one against, but who can read a name that is not
theirs.

Putting the same name **in the signed bytes** would buy something different:
a defence against a **counterfeit** page, one the operator never served. That
is a different attack with a different answer, and it is not what this closes.
It would also cost the rule against a person-derived identifier below the chat
boundary, inside the one target whose whole claim is that it holds none.

**Both values are kept, and this is the part to get right.** The opaque
subject already in the challenge **stays**. It is not person-derived, so it
costs `REQ-verify-004` nothing, and it is what stops a proof being moved
between sessions, which no page-level display can do. What is added is a
human-readable account name **on the page**. Both, not one instead of the
other.

**What is left over, in the owner's own framing.** This attack needs a member
to take a link from a stranger and sign what it shows them. The server rules
an operator already publishes cover that, and every wallet warns about it too.
It is a real attack and it is largely user error. The honest residue is a
first-time verifier, who has no baseline for what normal looks like here and
no reason yet to read an unexpected link as unusual. Saying that plainly is
neither dismissing the attack nor overstating it, and these artifacts say it
in those terms rather than claiming a closure they do not have.

### 2. `/verify` gains an optional wallet argument

`/verify` bare behaves exactly as it does today. `/verify wallet:` pins the
session to that one address, and a proof signed by any other address is
refused with a reason of its own that says so. That is `REQ-verify-041` in the
target and `REQ-verify-042` in the host.

**It does not close the relay, and nothing here says it does.** An address is
public: an attacker who wants a particular member's wallet can name that
member's own address in their own session, and every check still passes. Its
value is three smaller things. The refusal is better, because a member who
named an account and signed with another is told exactly that rather than told
the sender did not match something they never chose. The mismatch comes
earlier, at the connect rather than after a signature. And the member has
committed to an address before anybody asked them to sign one.

### 3. A wallet argument may be a name, and resolving it fails soft

A member may type a name rather than an address. Resolving one is an outbound
call to a naming service this bot does not currently talk to, which makes it a
new host in `docs/WHAT-IT-TALKS-TO.md` and a new thing that can be down. Three
rules follow, and `REQ-verify-042` carries all three.

When the naming service cannot be reached, the member is told so and asked for
the raw address instead: somebody who typed a name is never stuck. The boot
never depends on the service being up, so nothing pings it at startup and an
unreachable one costs the bot nothing it is doing. And the resolution belongs
to the **host**, not to the verifying target, which must keep reading nothing:
`Verify` receives an address and never a name.

### 4. The fee bound is the network minimum, not zero

The strict `fee == 0` becomes `fee <= 1000` microAlgos. `REQ-verify-009` and
`REQ-verify-010` carry it.

The reasoning matters more than the number. A leaked blob then costs a member
a fraction of a cent instead of their whole balance, which is what bounding
the fee was for. And no wallet is locked out by a fee policy the page cannot
override inside somebody else's application: nobody has tested which wallets
force a minimum, and **that uncertainty is exactly why the bound is not
zero**, rather than a caveat beside it.

What is given up is stated rather than buried. A zero fee with no group made
the blob un-submittable outright; at the minimum it becomes submittable again,
and submitting it moves nothing and costs one minimum fee. And the widened
bound makes one old mistake newly reachable: an **absent** fee key must still
read as zero, never as unknown, or a proof whose fee nobody checked is
accepted. Under the old equality both readings refused and the mistake hid.

### 5. Scope

The runtime work and the follow-ups are approved and are being built. **This
change and the Discord surface it defines wait until the owner has read them.**
Nothing in these artifacts is a licence to open `Sources/Verify`, and the
approval is still somebody else's to record.

## What the security review changed

After the artifacts were reconciled, the definition was read by a security
reviewer and cross-checked against a second reading. Nine ways were found for
somebody to claim an account that was not theirs, or for one member to stop the
whole server. All nine were real. Eight are closed in `requirements.md`,
`plan.md`, `design.md`, `tasks.md` and `testing.md` together; the ninth, the
relay in finding 1, was closed only in part here, and the rest of it is
decision 1 above. The reasoning is here because the next person simplifying this
will meet each one as a line that looks like belt and braces.

Two of them were in the definition only because a correct sentence was applied
to the wrong question, which is worth saying because it is the failure mode to
expect again.

**1. The signed bytes named no member, so a challenge could be relayed.** The
challenge was four lines and the subject was deliberately absent, on the
argument that "the note is compared against the challenge stored on the one
session it was issued for, and that session has one subject". True, and about a
different attack. It stops a proof being moved between sessions. It does nothing
when nothing moves: an attacker runs the command, gets a session and its link,
sends the link to a member, and that member opens the operator's real page on
the real origin, connects their wallet and signs a prompt with nothing wrong
with it. The blob is posted to the attacker's session and the bot proves the
member's address for the attacker, who takes the roles and payouts it earns,
while the member is locked out of proving their own wallet by the refusal that
keeps one address to one member. The six character code does not help: the
member never ran the command, so no code would look familiar. The reference
portal is better here, because its challenge carries the chat account id
(`VerificationController.swift:519-523`), and a relayed prompt shows an id that
is not yours. Closed by `REQ-verify-030`, a fifth challenge line carrying the
subject as the minted member key, which is not person-derived so
`REQ-verify-004` survives; `REQ-verify-035`, which echoes the same value in the
reply and on the page and requires a confirmation in the chat client before
adoption; and `REQ-verify-039`, so the lock is not permanent. **The closure is
partial and is written as partial**: the confirmation stops somebody who only
holds a link, not the relay, because in the relay the attacker owns the session
and can confirm. What is left is a member who signs a prompt naming a subject
value they have never seen, which is every first timer. That last part is
answered by `REQ-verify-043`, on the page rather than in the bytes, and it is
decision 1 above rather than a fix made here.

**2. `rekeyto` is not the wire key, so the refusal refused nothing.** The
forbidden field list said `rekeyto`. The dependency's canonical encoder writes
`rekey` (`Sources/Algorand/CanonicalTransactionFields.swift:175`); `rekeyto` is
the field's name on the transaction type and never reaches the wire. `close`
and `aclose` were right. Coded literally, the refusal would have matched a key
that never arrives, the tolerant reader would have skipped the real one as
unknown, and every rekeying proof would have passed with a valid signature: a
hostile page sets `rekey` to its own address, the bot blesses the blob, the page
submits it and the account is somebody else's. The tests would have passed,
because their fixtures would have carried the same wrong name. Closed by writing
`rekey`, and by requiring every fixture for a refused field to be built by the
dependency's own encoder rather than assembled by hand, so the name in the test
and the name on the wire cannot drift.

**3. The session id was the whole credential and nothing said so.** Anybody who
came by a member's session link, from a screenshot, a proxy log, browser
history or a `Referer` sent by a third party asset, could open it, connect their
own wallet, sign, submit, and have the member's chat account bound to their
address. With the reserve paying per verified member per epoch, that pays once
per leaked link. The reference makes it concrete by putting its token in a query
string (`VerificationController.swift:551`). Closed by `REQ-verify-031`, which
names it a credential and fixes its width and comparison, `REQ-verify-036`,
which says how it travels and where it must never be written, and the
confirmation step in `REQ-verify-035`.

**4. The authorising key was an unauthenticated key override.** One requirement
accepted a caller-supplied key "for an account that names it" while another
forbade `Verify` from doing the lookup that would establish it. What is left is
"if the caller hands you key K, accept a signature by K for address W", with
nothing said about where K comes from. Populate it from the request body, or
from the signer key in the blob, or from a development stub, and any address
becomes claimable by anybody who can type it: the reference's test mode bypass,
reached through a parameter instead of an environment variable. Closed by
`REQ-verify-037`, which says the key comes only from the host's own chain read
of that exact account's authorising address, never from the submission, at most
once per session; by `REQ-verify-033`, which keeps the reader from surfacing a
signer key that could become one; and by recording on the outcome that an
authorising key was used.

**5. A user story no requirement discharged.** "No member, however fast they
type, can spend the day's budget for reading the chain" had nothing behind it.
A refused proof deliberately does not consume the session, "at most once per
session" existed only as a sentence in `design.md`, and `plan.md` assigned rate
limiting to "the transport", of which there is none. One command, then a loop of
field correct proofs signed by a throwaway key: fields pass, signature fails,
the host spends a chain read on the authorising address, the session survives.
One member pauses role sync, rain, claim and the reserve for everybody. Closed
by `REQ-verify-032`, which puts the submission count and the single retry on the
session where an offline test can fail against them, and `REQ-verify-038`, which
makes the rate limit the host's obligation rather than a transport's. The
`plan.md` bullet is struck through rather than deleted, so the reasoning that
lost is still readable.

**6. The asserted proof was the bypass in a new shape, and `tasks.md`
contradicted itself.** One requirement forbade accepting a proof without a valid
signature, another required both routes to produce one `ProvedAccount`, and
`tasks.md` said both that the asserted value can be constructed and that the
initialiser is not public. Those cannot all hold, and the natural resolution in
code is a public unchecked-proof factory inside the one target whose entire
claim is that there is no such thing, which the no bypass suite would not have
seen because it only checked the initialiser. Closed by `REQ-verify-034`: two
public types, one seam, the unchecked one named `AssertedAccount`, and a no
bypass test that asserts over the public interface.

**7. The accepted shape pinned neither the type nor the fee.** The page was
asked for a zero fee and the bot never checked it. A hostile page builds the
self payment with the right note and the fee set to the member's whole balance;
the bot certifies it as proof of ownership; the page keeps the blob and submits
it. A lease lets the same blob block the member's own transactions for the
validity window, and a group means the proof was one leg of an atomic group
approved wholesale. The design's own reason for refusing a rekey, that the bot
never holds a signed instrument that could empty an account if it leaked,
applies to the fee word for word, and the list stopped one field short. Closed
by adding the type, the fee and the two fields to the accepted shape and to the
ordered refusals, which go from eleven to thirteen, to fourteen when the
second review gave the subject reason a position of its own, and to fifteen
when the owner's wallet argument added the pinned address. This finding was
closed with `fee == 0`, which also made the blob un-submittable outright and
was written up here as better than harmless. Decision 4 has since widened it
to `fee <= 1000`: the finding stands, the bound moved, and the
un-submittability went with it. See "The five decisions the owner took" for
why that trade was taken.

**8. Tolerance was required and canonicality was not.** The reader had to
tolerate every spelling of a blob and nothing said it must refuse a blob that
says two things. The page supplies the unsigned bytes, so it chooses the
encoding: a transaction map carrying `amt` twice is one document the wallet can
display one way and the reader take the other way, under one signature, and the
slice-not-re-encode rule keeps that signature valid over whichever reading is
carried off. The reference's parser is last key wins with no duplicate detection
(`SignedTransactionCodec.swift:65-83`). Closed by `REQ-verify-014`: a duplicate
key at any depth, a non-ascending transaction map and a trailing byte are all
refused, which costs a set.

One qualification, recorded so nobody rediscovers it as a contradiction. The
attack's last step, the page submitting the blob so that the executed meaning
differs from the displayed one, is weaker than it sounds: a node re-encodes a
transaction canonically before checking its signature, so a non-canonical blob
is not submittable at all. What stands without that step is enough on its own.
The checker was making an ownership decision on a document that means two
things, and which of the two it read was the encoder's choice rather than the
member's. Two further notes for whoever implements it: ascending order must be
compared as UTF-8 bytes, not by a locale-aware string comparison, and any
conforming wallet already emits ascending keys, because otherwise its
transactions would fail on chain. The manual list measures that on real
handsets before the flow is announced.

**9. Banning the supplied tier while keeping the supplied balance forbade
nothing.** A tier is a pure function of a balance through the ladder, so a host
that may use the supplied balance can compute the supplied tier itself, and the
condition for reaching that path, a failed chain read, was reachable on demand
through finding 5. Closed by rewriting `REQ-verify-029`: on the asserted route
the supplied balance sets no read timestamp, determines no tier and grants,
keeps or removes no role. It may be shown to an operator, labelled as the other
service's word. No role follows from it until the bot's own read succeeds. The
consequence, said plainly: a member verified through a portal gets no roles
until the bot reads the chain, which is the correct behaviour and is slower than
it used to be described as being.

**Nothing was rejected.** All nine were checked against the definition and,
where they cited it, against the pinned dependency at `swift-algorand` 0.4.0
rather than against the quote. Two narrative details were found overstated and
are corrected above rather than used to dismiss the finding they came from: the
on-chain leg of finding 8, and the claim in finding 1 that a confirmation step
closes the relay.

## What the second review found still open

Two reviewers then re-ran every one of those nine attacks against the repaired
text. Their verdict was not that a fix had failed. It was that the repair had
edited `requirements.md`, `testing.md` and `tasks.md` thoroughly and `plan.md`
and `design.md` only in places, so **four of the nine were still standing in
the two artifacts an implementer actually builds from**: `plan.md` still
specified a four line challenge and still carried the sentence "the subject is
deliberately not in the signed bytes", which is the critical finding's own
sentence; both still said one `ProvedAccount` with a route tag; and
`design.md`'s rekey retry still fired on "step 10", which the inserted type and
fee checks had turned into the forbidden fields step, so a genuinely rekeyed
member would have been refused with no retry ever attempted.

That failure, the executable artifact quietly keeping the losing side of a
settled question, has now happened three times in this repository. It is
recorded here rather than in a commit message because it is the thing to check
for first the next time any of these artifacts is amended: **when
`requirements.md` changes, `plan.md` and `design.md` are where the old answer
survives.**

Six things were also found open or miscounted, and all six are closed:

1. **The subject refusal was unreachable and unnumbered.** `REQ-verify-030`
   asked for a distinct reason; `REQ-verify-013` did not list it; and behind
   the byte-exact note comparison the note reason fired first on every proof it
   was meant to catch. It was made the twelfth of fourteen, immediately
   before note, reading the subject out of the **submitted** note; it is the
   thirteenth of fifteen now that the pinned address sits above it.
2. **`REQ-verify-018` falsified itself.** It had a refusal carry the session
   id; `REQ-verify-036` forbids the session id from ever reaching a log or an
   error report; a refusal is the thing that gets logged. It now carries a
   non-reversible handle, and `design.md`'s "the session id and the outcome are
   logged" is corrected with it.
3. **Session churn defeated the submission cap.** `REQ-verify-032` bounded
   submissions per session while `tasks.md` and `plan.md` had a new session
   delete the member's previous one, so a member minted a fresh session and a
   fresh allowance whenever they liked. The count is now kept per subject as
   well, over a supplied window, surviving displacement.
4. **The cap had no floor**, so an implementer could set it to one, pass every
   specified test, and lock out every member on a rekeyed account: that member
   legitimately needs a wrong-account attempt, a right-account attempt that
   fails the signature check, and the authorising key retry. The floor is three.
5. **Two rules lived only in `tasks.md` and `plan.md`**, which is the same
   shape as the finding above: one live session per member, and the session
   recording its connected address once. Both are now in `REQ-verify-019`, with
   tests. The second is what keeps `REQ-verify-028` from answering "does this
   address belong to a member here?" for any address anybody with a session
   cares to type, which, against the public holder lists this product
   publishes, is an enumeration oracle over them.
6. **The confirmation had nowhere to live**, and **"five lines" was not an
   invariant**. `REQ-verify-035` required a confirmation on the ephemeral
   interaction that issued the session, but the session is consumed when the
   proof is accepted and a phone may have killed the chat client during the
   hand off; there is now a pending proof keyed by the subject, with an expiry
   of its own, binding nothing until confirmed. And an unconstrained operator
   label could render a six line challenge and move the line the subject check
   reads by index, so the label may carry no line break and is bounded, refused
   at the mint (`REQ-verify-003`) and at boot naming the variable
   (`REQ-verify-040`), the way a bad tier rung already works here.

Counts that had drifted are fixed with them: the ordered refusals were
fourteen at that point, the host obligations thirteen rather than the seven
`testing.md` still claimed, `docs.md` said "four obligations" above a list of
five, and the manual list told a tester to read four challenge lines, which
meant the member line, the only thing between a first-time verifier and a
relayed prompt, would never have been read on a handset. The owner's
decisions have since moved two of those: the ordered refusals are fifteen and
the host obligations fifteen.

**What the second review could not close, and nor could any wording.** The
relay in finding 1. It needed a decision rather than a repair, the owner has
taken it, and it is decision 1 under "The five decisions the owner took, and
what they settle", above.

## What is ruled out, and why

- **Pasting a signature into a Discord modal.** A normal holder has no way to
  produce one without a command line or a page that asks them to do something
  indistinguishable from phishing. [VERIFY](../../../hi/verify.md) says that if
  it feels like a phishing flow we have lost them and we should have.
- **Proving it with an on-chain transaction instead of a page.** It needs an
  indexer, which is a new host, a new quota and a new provider to depend on; it
  costs the member a fee and requires them to hold ALGO, which breaks the
  promise that walking away costs nothing; and it is slow. Worth keeping later
  as a documented fallback for a member whose wallet will not connect, which is
  a real and recurring support case. Not the road, and not this change.
- **Publishing the existing web application.** It is an identity provider that
  also does verification: authorization codes, a published key set, refresh
  tokens, email verification, password reset. Publishing it takes on a standing
  security reporting obligation for code most operators do not want, in order
  to ship forty lines of signature checking.
- **A second executable in this repository, as distinct from the bot serving
  the page.** If the page is being written anyway, putting it behind a second
  process, a shared secret and a webhook adds no capability and adds most of
  the contract document.
- **The test mode bypass, under any name.** The reference has a mode in which a
  literal string is accepted in place of a signed transaction. It is off by
  default and documented and it is still an identity bypass behind a flag.
  [BUILD-3](../../../hi/build.md) exists because of that exact shape. Testing
  without a wallet is done with a generated key that produces a real signature
  over the real challenge, so the verification path runs unchanged.
- **Two variables for one secret, and any fallback to a built-in default.**
  Both are already recorded as departures in the contract, and
  [ADOPT-6](../../../hi/adopt.md) is that an unset thing is empty rather than
  somebody else's.

## What a session picking this up mid-flight needs to know

**This is a definition.** Nothing under `Sources/` or `Tests/` is written until
the change is approved, and approval is somebody else's to record
([`AGENTS.md`](../../../AGENTS.md)). Deciding the open question in
`research.md` is not the same as moving
[`docs/decisions/0001-verification-portal.md`](../../../docs/decisions/0001-verification-portal.md)
from proposed to accepted. Somebody has to do that deliberately, and this
change's documentation artifact should say so.

**The portal stays supported.** The acceptance criteria are explicit: an
operator who wants the hosted flow keeps it, against the contract in
[`docs/VERIFICATION.md`](../../../docs/VERIFICATION.md), and **the bot half is
the same either way**. That is a design constraint, not a nicety. It means the
verifier, the challenge and the session are one thing and the transport is a
seam over them, so that "the page is served here" and "the page is served
elsewhere and calls back" are two callers of one module rather than two
implementations that can disagree.

**There is no HTTP anything in this repository yet.** No listener, no client,
no executable. The listener is new work under every option, and when a gateway
eventually exists the contract's ordering rule applies: bind the local ports
before identifying to Discord, because binding is how a process learns another
copy is already running.

**swift-crypto is already in the resolved graph**, pinned, reached through
`swift-algorand`. Declaring it directly adds no new pin. `Package.resolved` is
gated by the change workspace, so a lockfile move is part of this change rather
than a tidy-up beside it.

**What does not exist in the dependency**: there is no msgpack reader
(`MessagePackWriter` is internal and its own doc comment says it has no
decoder) and no way to verify a signature against a bare public key
(`Account.verify` is a method on a type that holds a private key). Both have
to be written here. The tolerant decoder in the reference is 460 lines. Its
header comment attributes the tolerance to one named wallet on one named
mobile browser, and names the three shapes that wallet sent; it does not
attribute every branch to a handset, and neither should we. So the decoder is
ported deliberately and re-tested, not copied and trusted, and the shapes it
accepts beyond those three are a judgement rather than a recording.

**The gate's paperwork.** A new module needs `specs/<module>/` and an entry in
`.specsync/config.toml` before the gate passes. A new variable edits
[`docs/CONFIGURATION.md`](../../../docs/CONFIGURATION.md) in the same pull
request. A new outbound call, host, dependency or secret edits
[`docs/WHAT-IT-TALKS-TO.md`](../../../docs/WHAT-IT-TALKS-TO.md) in the same
pull request. Serving a page to a member's browser is a new inbound surface and
belongs in the second of those whether or not it counts as a call.

**The naming service behind the wallet argument is such a host**, and it is
written into that document by this change even though the call arrives with
the host target, flagged as not yet true in the way that document already
flags what a member's browser will reach. TRUST-1 is a list somebody reads
before they install, so the disclosure belongs in the change that decides the
call rather than in the one that finally makes it.

**The tests run offline, with generated keys** ([BUILD-2](../../../hi/build.md)),
which is also an acceptance criterion here. A fake signer producing real
signatures is the whole mechanism, and it is cheap: the dependency can already
sign.

**This repository is public.** No real address, asset id, chat identifier,
hostname or personal path in code, tests, specs, documents or commit messages,
and no naming of the private project any of this was ported from. Two private
repositories were read for the research and neither is named or path-quoted in
it.

## Still open when this was written

- Whether current releases of every wallet will sign a transaction built with
  fabricated parameters, which is what would let the page drop its one node
  read. The standard says they should and one wallet's own tutorial did exactly
  that, and one of them has had a major rewrite since. It is an afternoon with
  three phones, and it should be settled before the page is written rather than
  assumed in the design.
- Which wallets to offer, which is an [ADOPT](../../../hi/adopt.md) question as
  much as a technical one and changes how much vendored JavaScript this
  repository carries.
- Whether a checked-in prebuilt wallet bundle is acceptable here, or whether a
  build step is wanted. The ported implementation vendors one file with its
  regeneration command in a comment and keeps the build as `swift build`. There
  is a real argument each way and it is a decision, not a detail.
- Whether the account being proved is bound at connect time, as the reference
  does, or named in the challenge itself. That changes where one account, one
  member produces a message the member actually reads, and it belongs in
  [`design.md`](design.md). Note that the *member* is now named in the
  challenge, which is a different question and is settled: see
  `REQ-verify-030`.
- ~~How far a member has to be protected from a signing prompt they did not
  start.~~ **Answered.** It is decision 1 above: the page names the chat
  account the session belongs to and warns beside it, the opaque subject line
  stays in the signed bytes, and the residue is a first-time verifier who does
  not read the warning. Kept here, struck through rather than deleted, because
  it was the largest open question in these artifacts and a reader coming back
  to this list should be able to see where it went.
- Which fee each supported wallet actually signs when the page hands it a
  zero. The choice this used to pose has been made: decision 4 bounds the fee
  at the network minimum rather than requiring zero, so a wallet that raises
  it to the minimum verifies. What is still unmeasured is the list itself, and
  a wallet that sets a fee **above** the minimum still cannot verify. It is on
  the manual list, and if every wallet turns out to honour a zero, tightening
  the bound back is a later change with that measurement behind it.
