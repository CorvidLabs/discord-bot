---
spec: verify.spec.md
---

## Key Decisions

- **The proof is checked in this process, and the page is a separate
  problem.** Proving ownership is three moves and only one of them was ever a
  service. Minting something to sign needs nothing a bot does not already
  have. Checking a signature is thirty lines: an Algorand address **is** an
  Ed25519 public key, so parsing it to thirty two bytes and asking whether a
  signature is valid over `TX` plus the transaction bytes is the whole of it.
  The private bot this was ported from already did exactly that, in process,
  with no web application anywhere, to sign administrators in. What genuinely
  needs a browser is move two, the return channel: a wallet will not reply to
  a process it has no session with, and every wallet integration in the two
  implementations read for this is a page running a connect library. So this
  module is moves one and three, and the page is a listener and a route that
  another change owns.

- **A second deployable that checks the proof is declined.** It adds no
  capability. It adds a shared secret, a webhook, a boot order, a health gate
  and a startup check that can disagree with the other half, and every one of
  those is a way for verification to fail in a manner an operator learns about
  from a member. A page served elsewhere that posts to this bot's own route is
  the same proof checked in the same process, which is strictly better than an
  assertion webhook and costs nothing extra.

- **The portal route survives, and says in its own type that it was not
  checked here.** An operator who wants the hosted flow keeps it. What changes
  is what is said about it: on that route the proof is the other service's
  word and the shared secret is the whole trust boundary. The two routes
  therefore do **not** share a producer. `ProvedAccount` is made only by
  consuming a signature and has no public initialiser; `AssertedAccount` is
  public, because a host has to be able to make one, and says in its name that
  nothing here checked it. An earlier shape asked for one type, constructible
  for both routes, whose initialiser is not public. Those three cannot all
  hold, and the way it resolves in code is a public factory that mints an
  unchecked proof inside the one module whose whole claim is that there is no
  such thing.

- **One accepted shape, and a signature over an arbitrary message is not it.**
  The private bot's administrator sign-in accepts a signature over the raw
  message **or** over the same message behind a wallet's data prefix. That is
  a reasonable compatibility hedge for signing somebody in and a bad property
  for proving a wallet: it means one signature is valid over two different
  byte strings, and "they signed exactly this" stops being true. One shape,
  one meaning, and no entry point that takes another.

- **The wire name for a rekey is `rekey`.** This is worth a paragraph because
  the definition this was built from first wrote `rekeyto` and it would have
  shipped. `rekeyTo` is what the field is called on the dependency's
  transaction type; what its canonical encoder puts on the wire is `rekey`.
  Coded literally, the refusal would have matched a key that never arrives,
  the tolerant reader would have skipped the real one as an unknown field, and
  every rekeying proof would have been accepted with a valid signature. The
  fixtures for all five forbidden fields are therefore built by the
  dependency's own encoder, or asserted equal to what it emits, so the name in
  the test and the name on the wire cannot drift apart.

- **The fee is bounded at the network minimum rather than pinned at zero.**
  Bounded at all for the same reason a rekey is refused: a zero amount self
  payment is harmless only while its fee is, and a page that builds the proof
  with the fee set to the member's whole balance produces something this
  module would otherwise bless as proof of ownership, while the page keeps the
  blob. Bounded at the minimum rather than at zero because nobody has measured
  which wallets override a fee they were handed, and a checker pinned at zero
  turns an untested wallet behaviour into a member who cannot verify and
  cannot act on the refusal. The cost is written down rather than discovered:
  a zero fee with no group makes the blob un-submittable outright, and at the
  minimum it becomes submittable again, moving nothing from the member to the
  member at a cost of one minimum fee.

- **An absent `amt` is zero, and so is an absent `fee`.** Algorand's canonical
  encoding omits a field holding its zero value, so requiring either key
  refuses every correctly formed proof. The second half is the one the bound
  made newly dangerous: under an equality with zero, a reader that treats a
  missing key as *unknown* also refuses and therefore looks correct; under a
  bound it is an accepted proof whose fee nobody checked.

- **Tolerant about spelling, strict about a blob that says two things.** The
  reader accepts both base64 alphabets, padded or not, with whitespace, and
  three envelope shapes, because those are the shapes a wallet on a phone
  actually sent. It refuses a duplicate key at any depth and any byte after the
  envelope. The page supplies the unsigned bytes, so it chooses the encoding:
  `amt` twice, zero first and a large value second, is one document a wallet
  can display one way and a reader take the other way, under one signature
  that stays valid over whichever reading is carried off, because the reader
  slices rather than re-encoding. The parser this was ported from is
  last-key-wins with no duplicate detection. It does **not** hold the keys to
  an order: unique keys say one thing in any order, so an ordering rule
  forbids nothing the duplicate rule has not already forbidden, and it
  refuses the envelope that parser was patched to accept after a live flow on
  a phone failed on it.

- **The subject is in the signed bytes, and it is opaque.** Without it the
  bytes never say who the proof will be adopted for: somebody runs the
  command, sends their own link to a member, and that member's genuine
  signature over a genuine looking prompt binds their wallet to the sender.
  Nothing moves between sessions in that attack, which is why "the session
  already binds it" is true and answers the wrong question. What is **not** in
  the bytes is anything that came from a person: the line carries the opaque
  subject the caller supplied.

- **The subject refusal is read out of the submitted note, and sits before the
  note.** Both halves are load bearing and the first draft had neither. Read
  from the session's stored challenge, it compares a value against itself and
  always passes. Placed after the byte exact note comparison it can never fire
  at all, because a proof naming another subject differs in the note too, and
  the member would be told their wallet sent the wrong bytes rather than that
  this prompt was somebody else's.

- **Small-order keys are refused before the cryptography library is asked.**
  An all-zero public key with an all-zero signature satisfies the Ed25519
  verification equation for every message, and the libraries this builds
  against return true for it rather than refusing. An address here **is** a
  public key, so without the check the handful of addresses whose bytes are
  small-order points are claimable by anybody, and whatever somebody has sent
  to one of them decides a role for whoever claims it first. The list is the
  published one, compared with the sign bit masked. Being wrong in the
  direction of too many entries costs nothing, which the suite shows over two
  hundred generated accounts; being wrong in the direction of too few leaves
  the hole open.

- **Submitting takes no address, and that is a shaping decision worth
  naming.** A page connects an address and then posts a blob, so the address
  a proof is held to is the one the session already recorded, and
  ``VerificationCoordinator.submit`` does not take one. The alternative, a
  submit that carries an address and records it if the session has none,
  cannot keep the order the contract fixes: the pinned address reason sits at
  position seven and the session state reasons at position one, so a pinned
  session presented with a differing address at submit time would return a
  position-seven reason before the position-two expiry check. Keeping the two
  entry points apart keeps the order provable. The cost is that a submit
  against a session nothing has connected an address to is refused as
  `sessionUnavailable` rather than with something more specific, which is a
  host's mistake and not a member's, and telling whoever holds a session id
  more about that session is not worth the better message.

- **The session id is a bearer credential and is named as one.** Whoever holds
  it can submit against that session, and an accepted proof binds whatever
  address they connect to whatever member the session names. Nothing said that
  before, and a credential nobody has called one ends up in a query string, an
  access log or a referrer header. The portal this was ported from puts its
  token in a query string, which is the concrete version of all of those at
  once. Here it never reaches a refusal, which is the value a host writes
  down; a refusal carries a truncated digest instead.

- **Sessions live in memory and do not survive a restart.** Fifteen minutes of
  state holding a challenge and a subject. Durability would mean this module
  reaching a database, or a database learning about verification, to save one
  member from running the command again after a deploy. The cost is real and
  is stated rather than discovered: the per-subject submission bound goes with
  them, so a restart hands every member a fresh allowance. That is acceptable
  because a restart is the operator's action and not a member's, and it is why
  the rate limit a host owns is the half of that defence that does not
  evaporate on a deploy.

- **Nothing here reads a clock.** Every instant is a parameter, the same way
  the games take theirs, so every expiry boundary in the suite is pinned by
  the test rather than by when it ran, and a clock stepped backwards cannot
  revive an expired session.

## What changed from the implementation this was ported from

- The challenge gained a line for the instance and a line for the subject, and
  its nonce went from thirty two bits taken from the front of a UUID to a
  hundred and twenty eight from the system generator.
- The ordered checks went from five to fifteen. The five it had were sender,
  receiver, amount, note and signature, in that order, and the order was
  already right and already commented for the right reason.
- The parser gained a duplicate-key rule, a trailing-byte rule, a size
  ceiling and a depth limit, and lost nothing. An ascending-key rule was
  tried and taken out again: it refused the very envelope the parser this
  was ported from carries a regression test for, and refused it at the parse
  step, which is before a rekeyed account can ever be offered the authorising
  key retry.
- The test-mode bypass is gone, with no equivalent at any setting. The
  original accepts two literal strings in place of a signed transaction when a
  variable is set. It is documented and off by default and it is still an
  identity bypass behind a flag: with it on, anybody who can reach the
  endpoint can claim any address they can type.
- The authorising address lookup that made the rekey path work moved **out**
  of the checker and became a value the caller passes in. The original reads
  the chain before it evaluates the fields, so a member with the wrong account
  selected in their wallet spends a request; here the field checks run first
  and the read is the host's, at most once per session, only on the one
  refusal it could explain.

## What was deliberately not ported

- **The listener, the page and the chat command.** There is no executable
  target in this repository, no server and no gateway. After this module, a
  stranger who clones this still cannot verify a member, because there is
  still nothing to run. What changed is that the part deciding whether
  somebody owns an account is here, offline and tested, with no second service
  anywhere in it.
- **The webhook payload decode.** Two of its five fields are a chat server id
  and a chat member id, and no identifier that came from a person may appear
  in any type this module declares. The decode belongs to the host, along with
  the rest of that route.
- **The chain observed route**, where a member sends a real transaction
  carrying the challenge in its note and the sender is the proof. It needs an
  indexer, which is a new host, a new quota and possibly a new secret, and it
  costs the member a fee. The seam is left open: the checker takes a proof and
  an expectation and does not care which channel delivered it, so a future
  route is a new caller rather than a new checker.
