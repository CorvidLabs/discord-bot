---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: tasks
---

# Tasks

Each item is meant to be obviously done or obviously not done. Where an item
would otherwise be a judgement call, it names the check that settles it.

Every item here is checked against `requirements.md`. Where the two disagreed
while this was being written, `requirements.md` won and this file was changed,
because this is the artifact somebody executes and a task list that quietly
drops a requirement is how a criterion gets lost. The reconciliation is
recorded in `context.md` under "What was settled while these artifacts were
reconciled".

A security review of this definition then found nine ways it let somebody claim
an account that was not theirs, or let one member stop the whole server. Eight
are closed, in `requirements.md` and here together, and `context.md` records
them under "What the security review changed" so that the next person
simplifying this list knows which items are load bearing. The ninth, the
relay, is answered by a decision the owner has since taken: it is closed on
the **page**, by `REQ-verify-043`, rather than in the signed bytes, and the
residue is written down rather than claimed away. See "The five decisions the
owner took" below and the section of the same name in `context.md`.

Two reviewers then re-ran every attack against the repaired text and found
four of the nine still standing in `plan.md` and `design.md`, plus six things
the repair had left open or miscounted. Those are recorded under "What the
second review found still open".

## 1. Decide, before building against it

- [ ] Amend `docs/decisions/0001-verification-portal.md` with what reading the
      code settled: the proof is checked in the bot's own process, so a second
      deployable service that does the checking is not needed (B and C are
      declined); the page's location is configuration and is decided with the
      executable; the relay shape (the bot as a wallet-connection client) and
      D2 (the on chain note) are named and declined, with the reasons in
      `plan.md`.
- [ ] Change its `Status:` line from proposed to accepted, with a date.
- [ ] The acceptance is recorded by somebody who is not the author, the same
      rule `AGENTS.md` states for change approval.
- [ ] `README.md` and `docs/VERIFICATION.md` no longer describe the question as
      open, because they both currently point at the record as undecided.

## 2. The contract, before the code

- [ ] `specs/verify/verify.spec.md` exists with every section
      `.specsync/config.toml` lists in `required_sections`.
- [ ] `specs/verify/context.md`, `requirements.md`, `tasks.md` and `testing.md`
      exist, matching the shape of `specs/chain/` and `specs/store/`.
- [ ] `Sources/Verify` is added to `source_dirs` in `.specsync/config.toml`.
- [ ] `specsync check --strict` passes with the new module in the list.
- [ ] Every requirement in the module spec cites the criterion id it serves
      (`VERIFY-1`, `VERIFY-4`, `BUILD-2`, `BUILD-3`). Not `VERIFY-5`:
      `testing.md` states that this change does not claim it, because
      verifying a member from one clone needs the host, and a spec citing a
      criterion the change cannot evidence is the BUILD-4 failure in
      miniature.

## 3. The target

- [ ] `Package.swift` declares a `Verify` library product and target.
- [ ] `Verify` depends on `Algorand` and `Crypto` and on no other target in
      this package. A `grep` of `Sources/Verify` for `import Store`,
      `import Chain`, `import Gating` or `import Reserve` returns nothing.
      `REQ-verify-001` names all four; this item and `plan.md` named three.
- [ ] `Package.swift` declares apple/swift-crypto as a direct dependency,
      because `swift-algorand` links `Crypto` without re exporting it (its
      `Package.swift:20` and `:27`).
- [ ] `Package.resolved` is unchanged in the versions it pins. swift-crypto is
      already at 3.15.1, so a changed version here means something else moved
      and needs explaining.
- [ ] Nothing in `Sources/Verify` constructs a `URLSession`, a `URL` request or
      a socket. The `docs/WHAT-IT-TALKS-TO.md` grep for outbound call sites
      still finds them only in `Sources/Chain`.

## 4. The challenge

- [ ] A `VerificationChallenge` value renders its own text and re reads it, so
      the bytes signed and the bytes compared are produced by one function.
- [ ] Its text is **five lines of UTF-8** and contains exactly these, in this
      order (REQ-verify-003): an operator supplied label, an identity for this
      instance, **the subject, which is the third line**, a six character code,
      and the nonce. Not a timestamp: the expiry is the session's `expiresAt`
      rather than a number inside the signed bytes (REQ-verify-006).
- [ ] **Five lines is enforced, not assumed.** No value rendered into a line
      may contain a line break (U+000A, U+000D, U+2028, U+2029), and the
      operator's label is refused over one hundred UTF-8 bytes
      (REQ-verify-003). A two line label makes a six line challenge and moves
      the nonce into the slot the subject check reads by index, so this is a
      correctness property and not tidiness.
- [ ] A test mints with a label containing each of the four line break
      characters and with a label one byte over the bound, and proves each is
      refused with a named reason rather than rendered.
- [ ] The host's half of the same rule is written into the module contract as
      REQ-verify-040: a bad label stops the boot and names the variable, the
      way a bad tier rung already does. `Verify` reads no variable, so the
      target cannot be the place that check happens.
- [ ] The subject line is the opaque subject the caller supplied and nothing
      else (REQ-verify-030). An earlier draft of this list left the subject out
      on the grounds that the session already binds it. It does not bind the
      case that matters: somebody who runs the command and hands their own link
      to another member gets that member's wallet bound to themselves, because
      the signature is produced for the session it is submitted to. The line is
      what makes the bytes say who the proof is for.
- [ ] A test proves a proof whose challenge names another subject is refused,
      with a reason of its own that is not the note reason, so that an
      implementation which rebuilds the expected challenge out of the submitted
      note goes red rather than green (REQ-verify-030).
- [ ] **That reason is reachable**, which it was not as first written. The
      check reads the subject out of the **submitted** note, at the line index
      above, and runs at position thirteen of the fifteen, immediately before
      note (REQ-verify-013). Behind the byte-exact note comparison it can never
      fire, because a proof naming another subject differs in the note as well.
      A test that only asserts "refused" passes against an implementation that
      returns the note reason, so the test asserts **which** reason.
- [ ] The nonce is at least 128 bits from the system random number generator,
      and is not derived from the subject, the address, the clock or any
      argument. The reference uses eight characters of a UUID string
      (`VerificationController.swift:519-523`), which is thirty two bits.
- [ ] A collision probe over at least two thousand mints finds two thousand
      distinct nonces. A single inequality assertion would not see a nonce
      narrow enough to collide under a crowd (REQ-verify-003).
- [ ] The six character code shown in the reply and the six characters inside
      the signed bytes are one value, minted once. This is the anti phishing
      device and it is worthless if the two can ever differ.
- [ ] A test proves a challenge minted by one instance value does not verify
      against another, with every other field correct and the nonce identical,
      which is the part the reference challenge does not carry at all
      (REQ-verify-005).
- [ ] A test proves a challenge past its expiry is refused, with `now` passed
      in as a parameter rather than read from the clock, and that expiry is
      named as the reason whatever else is wrong with the proof
      (REQ-verify-006).
- [ ] The default lifetime is fifteen minutes, matching the number
      `docs/VERIFICATION.md` says the member is told. What the member is shown
      is read from the session's `expiresAt`, never written into a sentence.
- [ ] No identifier that came from a person appears in the challenge, the
      session, or any type `Verify` declares (REQ-verify-004). The subject is
      the opaque string the caller supplies, which above this boundary is the
      instance's own minted member key, per the `AGENTS.md` rule that nothing
      below the chat boundary holds an identifier that came from a person.
      This is a **departure from `docs/VERIFICATION.md:478-479`**, which asks
      for the member's chat account id in the challenge; the departure is
      written into that document by section 12 rather than left for a reader
      to notice.

## 5. The reader

- [ ] Base64 decoding accepts standard and URL safe alphabets, with and without
      padding, and with whitespace, and refuses anything else
      (`SignedTransactionCodec.swift:22-44` is the behaviour to match).
- [ ] The msgpack reader parses a bare signed transaction map, the same map
      wrapped in a one element array, and a map carrying an extra signer field,
      and returns the 64 byte signature and the transaction bytes.
- [ ] The transaction bytes are **sliced out of the input** and never re
      encoded. A test signs a transaction, mutates one byte of the blob outside
      the signature, and proves the verification fails rather than silently
      re encoding around it.
- [ ] A truncated blob, an empty blob and a blob whose signature field is not
      64 bytes each return a named failure rather than crashing or returning
      `nil` with no reason. Truncation is tested at **every byte offset** of a
      canonical blob and none of them traps (REQ-verify-014).
- [ ] A declared map count, string length or binary length larger than the
      bytes that arrived is refused **without allocating to match it**, a
      value nested past a depth limit is refused in bounded time, and a blob
      over a size ceiling is refused before parsing begins (REQ-verify-014).
      These are the three ways a short hostile blob becomes a large
      allocation or a crash, and the reader is the one thing here that will
      one day be reachable from the internet.
- [ ] **A duplicate key at any depth is refused**, a transaction map whose keys
      do not ascend by their UTF-8 bytes is refused, and any byte after the end
      of the envelope is refused (REQ-verify-014). Tolerance about how a blob is
      spelled is not tolerance of a blob that says two things: the page supplies
      the unsigned bytes, so a transaction map carrying `amt` twice is one
      document the wallet displays one way and this reader takes the other way,
      under one signature that stays valid over whichever reading is carried
      off, because the reader slices rather than re-encodes. The reference's
      parser is last key wins with no duplicate detection
      (`SignedTransactionCodec.swift:65-83`). The fix is a set of the keys seen.
- [ ] A test per case: the duplicate at envelope depth, the duplicate inside the
      transaction map, the descending key order, and the trailing byte. Each one
      goes red against a reader that takes the last value it saw.
- [ ] The extra signer key is **skipped and never surfaced** (REQ-verify-033).
      No value read out of the blob is reachable as a key to check a signature
      against. A test asserts the reader's output has no field that could carry
      one.
- [ ] No force unwrap, no `try!`, no `as!` anywhere in the reader, which is the
      file most likely to acquire one.
- [ ] Every branch of the tolerant decoder has a test. Where a real wallet's
      shape cannot be recorded (it would carry a real address into a public
      repository) the bytes are assembled by hand and the test is named for
      **the shape**, not for a wallet, which is the rule `testing.md` states
      and the same rule section 13 applies to vendor names generally.

## 6. The ownership decision

- [ ] Failures are checked in the **fifteen** step order `REQ-verify-013`
      fixes, each with its own case: session state, session expiry, blob decode,
      transaction parse, missing fields, transaction type, **pinned address**,
      sender, receiver, amount, fee, forbidden fields, **subject**, note,
      signature. A later reason is never returned while an earlier one holds.
      It was eleven before the security review; transaction type and fee are
      the two that review added, subject took a position of its own in the
      repair pass after it, and pinned address arrived with the wallet
      argument. All four are in the order rather than bolted on at the end,
      because a member reads the first reason they are given, and because a
      reason placed after a byte-exact comparison of the same bytes is a
      reason nothing can ever return.
- [ ] Each case in the suite violates **every later reason as well**, so the
      order is proved rather than asserted. A suite that violates one rule at
      a time passes against an implementation that evaluates them in any order.
- [ ] `rekey`, `close`, `aclose`, `lx` and `grp` are each refused with their
      own reason, whether or not the signature is valid (`REQ-verify-011`). The
      reference has no such check: `SignedTransactionOwnership.evaluate`
      (`SignedTransactionCodec.swift:429-457`) tests sender, receiver, amount,
      note and signature and nothing else, and the parser skips every key it
      does not recognise. Refusing means the bot never holds or blesses a signed
      instrument that could empty or reassign an account if it leaked.
- [ ] **The key is `rekey`, not `rekeyto`.** `rekeyto` is the name of the field
      on the dependency's transaction type; the name its canonical encoder puts
      on the wire is `rekey`
      (`CanonicalTransactionFields.swift:175`, with `grp` at `:172` and `lx` at
      `:173`). An earlier draft of `REQ-verify-011` said `rekeyto`, which never
      arrives, so the refusal would have matched nothing, the tolerant reader
      would have skipped the real key as unknown, and every rekeying proof would
      have been accepted with a valid signature.
- [ ] **Every forbidden key name in a fixture comes from the dependency's own
      encoder**, not from a hand written string. A rekey, a close, a lease and
      a group can be set on a payment and encoded, so those four fixtures are
      encoder built outright. `aclose` is emitted only by an asset transaction:
      assert its name against that encoder's output, then use that name in a
      payment fixture, and cover the asset transaction separately as a
      transaction type refusal. A hand built fixture carries the same wrong
      name as the code and goes green over the hole, which is exactly how this
      one survived review of the requirement text.
- [ ] **The transaction type is `pay`** and anything else is refused, at its own
      step (`REQ-verify-009`). A canonical encoder always writes `type`, so
      requiring it present costs nothing.
- [ ] **The fee is at most one thousand microAlgos, and an absent fee is
      zero** (`REQ-verify-009`, `REQ-verify-010`). The page is asked for a
      zero fee and the bot checks a bound, because a zero amount self payment
      is harmless only if its fee is bounded: otherwise the bot certifies as
      proof of ownership a transaction whose fee is the member's whole
      balance, and the page keeps the blob and can submit it. A test builds
      exactly that and proves it is refused at the fee step, with a valid
      signature, so the refusal cannot be the signature's.
- [ ] **The bound is the network minimum and not zero, and the constant says
      why beside itself.** Nobody has measured which wallets override a fee
      they were handed, and that is the reason for the bound rather than a
      footnote to it: a checker pinned at zero refuses every wallet that
      raises one, for a policy the page cannot enforce inside somebody else's
      wallet. At the minimum a leaked blob costs a member a fraction of a cent
      instead of their balance. A test proves a fee at the bound is accepted
      and one microAlgo over is refused, so neither edge can move unnoticed.
- [ ] **An absent fee still reads as zero, and a test says so on its own.**
      Under the old equality both readings of a missing key refused, so a
      reader treating it as unknown looked correct; under a bound it is an
      accepted proof whose fee nobody checked (`REQ-verify-010`).
- [ ] **An absent amount is zero.** A test builds the proof with
      `PaymentTransaction` and proves it is accepted. The omission is not in
      `PaymentTransaction` itself: its `encode` calls
      `fields.set("amt", uint:)` (`PaymentTransaction.swift:140`) and the
      omission is in `CanonicalTransactionFields.set(_:uint:)`
      (`CanonicalTransactionFields.swift:55-58`), which returns early on zero.
      So the fixture reproduces the trap by construction rather than by a hand
      written blob.
- [ ] A test proves a transaction signed by the right key but sent to a
      different receiver is refused as a receiver mismatch and not as a bad
      signature.
- [ ] Every failure carries a message a member can act on. A test asserts the
      message for a wrong selected account says which thing to change.
- [ ] No failure message contains the signature, the blob, the challenge
      nonce **or the session id** (`REQ-verify-018`). A refusal carries the
      reason and a non-reversible handle, a truncated hash of the session id or
      an opaque per-refusal identifier, which an operator can correlate and
      nobody can replay. The requirement used to ask for the session id itself,
      which `REQ-verify-036` forbids from reaching a log or an error report,
      and a refusal is the thing that gets logged.

## 7. The rekey seam

**`Verify` declares no source protocol and performs no lookup.** An earlier
draft of this list had it declaring a one method `AuthorizingAddressSource`
and calling it. That contradicts `REQ-verify-015` ("`Verify` SHALL NOT perform
that lookup and SHALL hold nothing that could") and the `TargetShapeTests` row
in `testing.md` that asserts no data source and no URL type in the target. The
requirement wins: the seam is a **value the caller passes in**, not a
protocol the target calls out through.

- [ ] `ProofExpectation` optionally carries an authorising key supplied by the
      caller, and a proof signed by it is accepted (`REQ-verify-016`). Tested
      with two generated keys.
- [ ] **The key comes from the expectation and from nowhere else.** `Verify`
      does not read it from the blob, does not surface a signer key that could
      become one (`REQ-verify-033`), and does not derive it from the address.
      Written without that, and without `REQ-verify-037` constraining the
      caller, the requirement reduces to "if the caller hands you key K, accept
      a signature by K for address W", which is the reference's test mode
      bypass reached through a parameter instead of an environment variable.
- [ ] The outcome records that the proof was accepted under an authorising key
      rather than the account's own, so the audit can tell them apart
      (`REQ-verify-016`).
- [ ] `docs/VERIFICATION.md` and the module contract both state
      `REQ-verify-037`: the host reads the authorising address from the chain,
      for that exact account, at most once per session, and never takes the key
      from the submission.
- [ ] With no authorising key supplied, a bad signature is a refusal. `Verify`
      invents no second chance inside the target.
- [ ] The signature refusal is distinguishable from every other reason, so the
      host can tell when a chain read for an authorising address is worth
      making, and can then call the checker a second time with the key it
      found (`REQ-verify-015`).
- [ ] **The refusal says whether the retry is still available, and says it at
      most once per session** (`REQ-verify-032`). The session records that the
      retry has been used. Before the security review this bound was one
      sentence of prose in `design.md` and nothing enforced it, while
      `REQ-verify-007` guaranteed a refused proof leaves the session alive: one
      command followed by a loop of field correct proofs signed by a throwaway
      key would have spent a chain read every time and exhausted the day's
      budget for the whole server. A test drives the loop and proves the second
      refusal reports no retry.
- [ ] **The retry fires only when the signature check fails on its own**, and
      the condition is written in the source that way rather than as a step
      number. `design.md` carried "if and only if step 10 fails" from before
      the type check and the fee check were inserted above it, by which time
      the signature check was step 12 and a genuinely rekeyed member would
      have been refused with no retry ever attempted. Name the step.
- [ ] The field checks run **before** the signature check, so a member who
      picked the wrong account is told the sender did not match and the host
      never reaches for an authorising address on their behalf. The reference
      does the opposite: its chain read at
      `VerificationController.swift:1052-1062` runs before the field
      evaluation at `:1063`, so a wrong selected account spends a request.
      That is the ordering `RUN-11` is about and the reason the read lives
      with the host that owns the budget.

## 8. The session

- [ ] A `VerificationSession` value holds the subject, the challenge, the
      connected address once known, the expiry, the count of submissions made
      against it, and whether the one authorising key retry has been used.
- [ ] The session id is at least 128 bits from the system random number
      generator, is not derived from the subject, the address or the clock, and
      is compared whole (`REQ-verify-031`). It is the whole credential: whoever
      holds it can submit against that session, and a submission binds whatever
      address the submitter connects to whatever member the session names. The
      module contract says so in those words, because nothing said it before and
      an unnamed credential ends up in a query string.
- [ ] **A session stops accepting submissions after a fixed maximum**, reported
      at the session state step with a reason of its own (`REQ-verify-032`). The
      maximum is small, named once in the source, and quoted in the module
      contract rather than retyped.
- [ ] **That maximum is at least three**, with the reason beside the constant:
      a member on a rekeyed account legitimately needs a wrong-account attempt,
      a correct attempt that fails the signature check, and the one authorising
      key retry (`REQ-verify-032`, `REQ-verify-016`). A test asserts the
      constant is not below three. Without the floor, a maximum of one passes
      every other test in this list and locks out the whole class the rekey
      seam exists for.
- [ ] **The same bound is kept per subject, over a window the caller supplies,
      and a new session does not reset it** (`REQ-verify-032`). The item below
      has a second session displace the first, so a per-session bound alone is
      spent and refreshed at will: a member mints a new session and a new
      allowance whenever they like, and the chain reads the bound exists to
      limit go on being spent. A test spends a session's allowance, mints a
      new session for the same subject, and proves the next submission is
      still refused at the session state step.
- [ ] The per-subject maximum is larger than the per-session one, so a member
      who ran the command twice because the first attempt confused them is not
      refused by the defence against a member who ran it two hundred times.
- [ ] Neither bound is claimed to discharge the budget story on its own. The
      rate limit on the command and on the submit route, per member and per
      source, is `REQ-verify-038` and is the host's; a member with many
      subjects is only that limit's to stop.
- [ ] A session store protocol is declared in `Verify`, with an in memory
      conformance in `Verify`. No table is added and no merged module's
      canonical spec changes, which is what the change's no spec rationale
      claims and what `Sources/Store/StoreTable.swift` confirms is still true:
      its six table names gain none. The durable conformance arrives with the
      host.
- [ ] The store protocol offers a prune taking a `now`, and the in memory
      conformer holds nothing for a session it has pruned, challenge included
      (`REQ-verify-019`).
- [ ] **Opening a session for a member who already has one displaces the
      first**, and the displaced session is discarded with its challenge
      (`REQ-verify-019`). This lived here and in `plan.md` and in no
      requirement until the second review; it is in `REQ-verify-019` now,
      which is the requirement that owns session lifecycle, and a test proves
      a proof against the displaced session is refused.
- [ ] **A session id that selects nothing gets one reason**, whether it was
      never issued, consumed, pruned or displaced (`REQ-verify-019`). A test
      asserts the four cases are indistinguishable in the refusal. A session
      still held and past its expiry still reports expiry, which is
      `REQ-verify-006` and is not weakened by this.
- [ ] **A session can be pinned to one address at the mint, and a proof
      signed by any other address is refused with a reason of its own**
      (`REQ-verify-041`). That reason is the seventh of the fifteen, before
      sender, because "this is not the account you named" is the better
      sentence whenever both hold. A test pins a session, submits a proof from
      a second generated key, and asserts the **pinned address** reason rather
      than the sender reason, so an implementation that folds the two together
      goes red.
- [ ] **On a pinned session the first differing address is refused at the
      connect**, with the same reason, rather than recorded as the connected
      address (`REQ-verify-041`, `REQ-verify-019`). That is the earlier
      mismatch the argument buys, and a test proves it happens before anything
      is signed.
- [ ] **The pin is an address and never a name.** `Verify` holds no name,
      resolves none, and acquires nothing that could: resolving a name is a
      network read and this is the target that makes none. The resolution is
      the host's, `REQ-verify-042`, and a `grep` of `Sources/Verify` finds no
      naming-service type and no URL.
- [ ] Nothing in this list claims the pin closes the relay. An address is
      public, so an attacker can name the address they are after. What it buys
      is a better refusal, an earlier mismatch, and a member who committed to
      an address before they were asked to sign one.
- [ ] **The session records the connected address once, and refuses a second
      differing address without answering anything about it**
      (`REQ-verify-019`, `REQ-verify-028`). Unbound, the "already proved by
      another member" check answers that question for any address anybody with
      a session cares to type, and the holder lists this product publishes are
      public, so it is a walk from those lists to which addresses belong to
      members here. A test presents a second address on a connected session and
      proves the refusal says nothing about whether that address is known.
- [ ] A session is consumed before its outcome is adopted, not after. A test
      submits the same valid blob twice and proves the second is refused,
      including a byte identical resubmission of the one it accepted.
- [ ] **A refused proof does not consume the session** (`REQ-verify-007`), so
      a member who picked the wrong account in their wallet may try again and
      a hostile submission is not a denial of somebody else's verification.
      Bounded by the attempt maximum above: trying again is finite.
- [ ] A test proves a blob signed against session A is refused when presented
      to session B for the same member, at the note comparison, and that the
      refusal does not reveal session A's challenge (`REQ-verify-008`).

## 9. One outcome, two inputs

**Two producers, one seam, and the unchecked one says so in its name.** An
earlier draft of this list asked for all three of: one `ProvedAccount` from
both routes, the same value constructible for the asserted route, and a
`ProvedAccount` whose initialiser is not public. Those cannot all hold. The
natural way to resolve them in code is a public factory that mints an unchecked
proved account inside the one target whose whole claim is `REQ-verify-017`, and
`NoBypassTests` as written would not have seen it, because it only checked the
initialiser. `REQ-verify-034` settles it.

- [ ] `ProvedAccount` (subject, address, when proved, and whether an authorising
      key was used) is produced **only** by consuming a signature, and has no
      public initialiser (`REQ-verify-034`).
- [ ] `AssertedAccount` is a distinct public type with a public initialiser,
      carrying what the other service said. Its name is the point: it is the one
      value in this target that nothing here checked.
- [ ] `VerifiedAccount` is the single downstream seam (subject, address, when,
      route). A `ProvedAccount` converts into it tagged `inProcess`; an
      `AssertedAccount` converts into it tagged `asserted`, through an explicit
      call the host has to write. A test builds one of each for the same subject
      and address and asserts they differ only in the route tag
      (`REQ-verify-020`).
- [ ] **Decoding the portal's callback payload is not in this change.** An
      earlier draft of this list had `Verify` decoding the five webhook fields
      and running the four validations `docs/VERIFICATION.md` names. Two of
      those fields are a chat server id and a chat member id, and
      `REQ-verify-004` forbids any identifier that came from a person in any
      type `Verify` declares. The decode belongs to the host, which is where
      `REQ-verify-023` to `REQ-verify-029` already put the rest of the route.
- [ ] Nothing downstream branches on the route except the audit line and the
      operator facing report of it.
- [ ] Nothing in `Verify` writes an `AccountRecord` or calls
      `AccountStore.prove` (`Sources/Store/BotStore.swift:64`). That is the
      host's, and is out of scope here.
- [ ] `ProvedAccount` cannot be constructed from outside the module: the
      initialiser is not public. Otherwise any caller can mint a proof that
      was never checked and every test in section 10 is decorative.
- [ ] **No public interface of `Verify` returns a `ProvedAccount` without
      consuming a signature** (`REQ-verify-034`). This is the item the previous
      one was mistaken for. An unchecked factory would satisfy the previous item
      and defeat this one, so the test asserts over the target's public surface
      and not over one initialiser.

## 10. No bypass

- [ ] No environment variable, build flag or literal string anywhere in
      `Sources/Verify` can cause a signature check to be skipped. A `grep` of
      the target for `Environment`, `ProcessInfo` and `getenv` returns nothing.
- [ ] The test suite's fake signer produces a **real** signature over the
      **real** challenge with a generated key, so the verification path runs
      unchanged.
- [ ] A test asserts that a blob which is not a signature, including the
      literals the reference accepts in its test mode
      (`VerificationController.swift:281` and `:284`), is refused **as
      ordinary malformed input**, with no special case anywhere. A range of
      other fixed strings, the empty one included, is refused too, so the
      refusal is a property of having no signature rather than a denylist of
      two literals.
- [ ] The same input gives the same outcome in a debug build and a release
      build. No build configuration and no compilation condition changes it
      (`REQ-verify-017`, `BUILD-3.b`).
- [ ] `specs/verify/verify.spec.md` states under Error Cases that there is no
      mode in which a fixed string is accepted, citing `BUILD-3`, and that
      there is no caller supplied value that stands in for a signature either,
      citing `REQ-verify-016`, `REQ-verify-033`, `REQ-verify-034` and
      `REQ-verify-037`. A bypass through a parameter is the same bypass as one
      through an environment variable.

## 11. Offline, everywhere

- [ ] `swift test` passes with the machine's network off.
- [ ] No test reads an environment variable, and no test opens a network
      connection or constructs a request URL. **Reading files is allowed and
      required**: `TargetShapeTests` asserts this target's properties by
      reading its own sources and the manifest, which is how an absence gets
      checked at all, and it is the idiom
      `Tests/StoreSQLiteTests/TargetShapeTests.swift` already established —
      it finds the repository from `#filePath` so the test means the same
      thing wherever it runs from. An earlier draft of this item forbade
      opening a file, which would have deleted the suite that `testing.md`
      leans on hardest.
- [ ] Every key in every test is generated by `Account()`
      (`Sources/Algorand/Account.swift:54`, which throws). No address, asset
      id or chat identifier in the repository belongs to anybody.
- [ ] The test count in `README.md` is updated from what `swift test` printed,
      not from arithmetic.

## 12. Documents, same pull request

- [ ] `docs/VERIFICATION.md` gains a section stating that the bot can be both
      halves, and which parts of the contract do not apply when it is.
- [ ] `docs/VERIFICATION.md` keeps the portal contract intact for operators who
      use it, and says plainly that on that route the bot cannot check the
      proof itself.
- [ ] `docs/VERIFICATION.md` records the **two challenge departures** that
      section 4 refers back to here: the subject is in the challenge as the
      minted member key rather than as the chat account id, with a six
      character code beside it, and the nonce is a hundred and twenty eight bits
      rather than the thirty two the reference takes from a UUID prefix. Its
      "Where the reference departs from this contract" table gains a row for the
      narrow nonce and a row for the challenge that names no instance.
- [ ] `docs/VERIFICATION.md` gains the five forbidden fields (`rekey`, `close`,
      `aclose`, `lx`, `grp`) alongside its ordered checks, each refused whether
      or not the signature is good, plus the transaction type and the fee
      bound, because those are new here and not a port. The ordered list it
      carries becomes **fifteen**, the pinned address sitting before sender
      and the subject immediately before the note and read out of the
      submitted note.
- [ ] `docs/VERIFICATION.md` says the fee is bounded at the **network
      minimum** and not at zero, and says why in the document rather than
      only in this list: the page still asks for zero, the checker accepts a
      wallet that raises it, nobody has measured which wallets do, and a
      leaked blob then costs a member a fraction of a cent rather than their
      balance. Somebody writing their own page has to know both the number
      and the reason, or the next page pins it at zero again.
- [ ] `docs/VERIFICATION.md` states the **eight** host obligations, because
      they are contract and not implementation detail: the session id is a
      bearer credential and how it travels (`REQ-verify-036`), adoption needs
      a confirmation in the chat client and the checked proof waits in a
      pending record keyed by the subject, with an expiry of its own, binding
      nothing until it is confirmed (`REQ-verify-035`), the authorising key
      comes only from the host's own chain read (`REQ-verify-037`), the
      command and the submit route are rate limited by the host rather than by
      something assumed in front of it (`REQ-verify-038`), an address bound to
      the wrong member is releasable (`REQ-verify-039`), the operator's label
      is checked at boot so a bad one names its variable rather than producing
      a six line challenge (`REQ-verify-040`), the command takes an optional
      wallet argument whose name resolution fails soft and never touches the
      boot (`REQ-verify-042`), and the page and the reply name the chat
      account the session belongs to and warn that nobody should ever send a
      member this link (`REQ-verify-043`). Five came from the security review,
      the label check from the repair pass after it, and the last two from the
      owner's decisions.
- [ ] `docs/VERIFICATION.md` writes down **why** the named account is on the
      page rather than in the signed bytes, not only that it is. In a relay
      the victim is on the operator's real page, which cannot be made to lie
      about whose session it is, so page-level display is sufficient for that
      attack and is the only form of it a first-time verifier can use. Naming
      the member inside the bytes would defend a counterfeit page instead,
      which is a different attack, and would cost the rule against a
      person-derived identifier below the chat boundary. Somebody writing
      their own page needs the reasoning, or they will drop the warning as
      decoration.
- [ ] `docs/VERIFICATION.md` says the duplicate-address check is bound to the
      session: asked once, about the address the member connected, and a
      second differing address on the same session is refused without an
      answer (`REQ-verify-028`). Somebody writing their own page has to know
      it, because the page is what presents the address.
- [ ] `docs/CONFIGURATION.md` gains **no new variable**, because this change
      adds none that anything reads: `REQ-verify-002` and `REQ-verify-017`
      say `Verify` reads no environment variable at all, and the route
      variable lives in `REQ-verify-023`, a host obligation. Its line 18, "This
      package is six libraries", becomes seven; the sentence about there being
      no executable stays, because it stays true. `Verify` joins the targets
      named there as reading no environment variable, stated positively
      because for this target it is a security property rather than a
      happenstance. `design.md` originally listed four variables as edits
      here; that was reconciled toward `requirements.md` and the section
      arrives with the host.
- [ ] Naming the in-process route means no portal: no health gate, no webhook,
      no secret required. Recorded in `docs/VERIFICATION.md`, not in
      `docs/CONFIGURATION.md`, because it is a statement about the contract
      rather than a variable an operator can set at this commit. It is the
      line that makes the portal optional.
- [ ] **Naming no route is not the same as naming the in-process one**
      (`REQ-verify-023`). An earlier version of the item above said "unset
      portal configuration means no portal", which reads as a default and is
      what the requirement forbids: naming none, like naming both, stops the
      boot with a message naming both variables and saying which to set. An
      operator who meant to run the portal and mistyped the variable must not
      get a bot that quietly verifies members another way. `docs/VERIFICATION.md`
      says which of the two is a choice and which is a boot failure.
- [ ] `docs/WHAT-IT-TALKS-TO.md` records the direct swift-crypto edge and
      states that `Verify` holds no call site that opens a connection.
- [ ] `docs/WHAT-IT-TALKS-TO.md` records the **naming service** behind the
      wallet argument as a host the bot reaches when the host target lands and
      reaches from nowhere today (`REQ-verify-022`, `REQ-verify-042`), flagged
      as not yet true the way that document already flags what a member's
      browser will reach. The row says it is optional, that it is reached only
      when a member types a name rather than an address, that nothing refuses
      to start without it, and that `Verify` is not the target that calls it.
      TRUST-1 is a list somebody reads before they install, so the disclosure
      belongs in the change that decides the call.
- [ ] `README.md`'s "No wallet verification" entry is corrected to exactly what
      became true, and still says the listener and the page are missing.
- [ ] `CHANGELOG.md` has an entry under `Unreleased`.
- [ ] `docs/README.md`'s table gains a row for `specs/verify/` if the map does
      not already cover module specs generically, and rows for
      `docs/VERIFICATION.md` and `docs/decisions/`, which it lists neither of
      although `AGENTS.md` lists both. That is pre existing drift in the one
      file whose job is preventing it, and this is the change that makes both
      load bearing.

## 13. Gate

- [ ] `fledge lanes run verify` green on macOS and on Linux.
- [ ] `specsync check --strict` clean.
- [ ] `specsync change audit` clean, with no uncovered path.
- [ ] No real address, asset id, chat snowflake, personal path or URL belonging
      to a project in any file this change touches, and no naming of the
      implementation any of it was ported from.

## Settled while these artifacts were reconciled

Three questions this list carried as open are answered by `requirements.md`,
and carrying them as open was itself a contradiction: an item cannot be
obviously done while the thing it asks for is undecided.

1. **The challenge names the member key and not the chat account id.**
   `REQ-verify-003` fixes five lines and the third is the subject.
   `REQ-verify-004` forbids any identifier that came from a person anywhere in
   the target, and a minted member key is not one, so both hold.

   This item used to say the opposite: that the challenge names neither, on the
   argument that the binding the reference gets from putting the chat id in the
   challenge (`VerificationController.swift:519-523`) is already provided by
   the session the note is compared against. The security review found that
   argument answers the wrong question. It stops a proof being moved between
   sessions; it does nothing about a member being handed somebody else's link
   and signing it, because then nothing moves. The acceptance criterion in
   `change.md` used to say what a member signs "cannot be used for a different
   member", and without the subject line it plainly could be. `REQ-verify-030`
   is the fix, and it is a partial one on its own, so the criterion has since
   been amended to say what the definition actually delivers: a proof cannot
   be moved to another member's session, and a relayed prompt is detectable
   rather than refused by anything the checker can test. The rest of the relay
   is answered on the page by `REQ-verify-043`, which is decision 1 above.
   `context.md` records the reasoning. This is still a departure from
   `docs/VERIFICATION.md:478-479`, a narrower one, and section 12 writes it in.

2. **The session store protocol lives in `Verify`.** `REQ-verify-019` puts the
   protocol and its prune in the target, and the no spec rationale in
   `change.md` depends on no merged module's canonical spec changing.
   `Sources/Store/StoreTable.swift` names six tables and gains none here.
   Putting it in `Store` beside `AccountStore` would read more naturally and
   would make `change.md`'s rationale false, which is a bigger cost than the
   reading.

3. **`docs/CONFIGURATION.md` gains no variable in this change.** `design.md`
   said it should and `docs.md` said it should not; `requirements.md` settles
   it, because `REQ-verify-002` and `REQ-verify-017` leave nothing in this
   change that reads one.

## What the security review changed in this list

Nine findings, all real, all closed here and in `requirements.md` together.
Written down because every one of them is the kind of item that looks like
belt and braces to somebody tidying up.

1. **The signed bytes name the member** (`REQ-verify-030`, section 4). Without
   it a link handed to somebody else binds their wallet to whoever sent it.
   The bytes now say who the proof is for, which makes a relayed prompt
   detectable by a member who has seen their own subject value, and refuses
   nothing. **The rest of it is answered on the page** by `REQ-verify-043`,
   which is the owner's decision below rather than a wording fix here.
2. **`rekey`, not `rekeyto`** (`REQ-verify-011`, section 6), with the fixtures
   built by the encoder so the names cannot drift.
3. **The session id is a credential and is named as one** (`REQ-verify-031`,
   `REQ-verify-036`, section 8).
4. **The authorising key has a stated provenance** (`REQ-verify-033`,
   `REQ-verify-037`, section 7). Otherwise it is a key override anybody can use.
5. **The retry and the submissions are bounded on the session**
   (`REQ-verify-032`, sections 7 and 8), so one member cannot spend the day's
   chain budget. `plan.md` no longer leaves this to "the transport".
6. **Two types, one seam** (`REQ-verify-034`, section 9), and the no bypass test
   now asserts over the public interface.
7. **The accepted shape pins the type and the fee and refuses a lease and a
   group** (`REQ-verify-009`, `REQ-verify-011`, section 6).
8. **Canonicality, not just tolerance** (`REQ-verify-014`, section 5).
9. **The asserted balance grants nothing until the bot's own read succeeds**
   (`REQ-verify-029`), which is the host's and is out of scope for this list
   beyond writing it into the contract in section 12.

## What the second review found still open

Two reviewers re-ran every attack against the repaired text. Their finding was
not that a closure had failed but that `requirements.md`, `testing.md` and this
list had been repaired thoroughly while `plan.md` and `design.md` were repaired
in places, so four of the nine survived in the artifacts an implementer
actually builds from. That failure mode, the executable artifact taking the
losing side, has happened three times in this repository, and it is the reason
the items below are written here rather than only in `requirements.md`.

1. **The subject refusal was unreachable and unnumbered** (`REQ-verify-013`,
   `REQ-verify-030`, section 4 and section 6). It had no position in the
   ordered reasons and the byte-exact note comparison fired first on every
   proof it was meant to catch. It is now thirteenth of fifteen, the pinned
   address having since been inserted above it, and it reads the subject out
   of the submitted note.
2. **`REQ-verify-018` contradicted `REQ-verify-036`** (section 6). A refusal
   carried the session id; the session id may never reach a log. It now
   carries a non-reversible handle.
3. **Session churn defeated the submission cap** (`REQ-verify-032`, section 8).
   A new session displaced the old one and reset the allowance with it. The
   count is now kept per subject as well, and the cap has a floor of three so
   that a rekeyed member is not locked out by an implementer who reads only
   the ceiling.
4. **One live session per member was in this list and in no requirement**
   (`REQ-verify-019`, section 8). So was the rule that a session records its
   connected address once, which is what keeps `REQ-verify-028` from answering
   "is this address a member here?" for any address anybody types.
5. **The confirmation had nowhere to live** (`REQ-verify-035`, host). The
   session is consumed by the time there is anything to confirm. There is now
   a pending proof keyed by the subject, with an expiry of its own, binding
   nothing until it is confirmed.
6. **"Five lines" was not an invariant** (`REQ-verify-003`, `REQ-verify-040`,
   section 4). An unconstrained operator label could make it six.
7. **Counts had drifted**: the ordered list, the host obligations, and the
   manual instruction to read four challenge lines, which meant the member
   line, the only thing standing between a first-time verifier and a relayed
   prompt, was never read on a handset.

**What they could not close, and nor could this list.** The relay in finding 1
of the security review. It was a decision rather than an oversight, it has
since been taken by the owner, and the next section is what it says.

## The five decisions the owner took

Taken in an interview after the security repair was written, and settled. They
are recorded here because four of them change items in this list and the fifth
says when any of it may start.

1. **The relay warning goes on the page, not into the signed bytes**
   (`REQ-verify-043`, sections 8 and 12). The page and the reply name the chat
   account the session belongs to and warn that only that member should ever
   open the link. In a relay the victim is on the operator's **real** page, so
   the page cannot be made to lie about whose session it is: page-level
   display is therefore sufficient for this attack, and it is the only form of
   it a first-time verifier can use. Naming the member inside the signed bytes
   would defend a counterfeit page instead, which is a different attack with a
   different answer, and it would cost the rule against a person-derived
   identifier below the chat boundary. **The opaque subject value in the
   challenge stays**: it is not person-derived, and it is what stops a proof
   moving between sessions. Both, not one instead of the other. What is left
   over is a first-time verifier who does not read the warning, and this list
   says so rather than claiming the attack closed.
2. **`/verify` gains an optional wallet argument** (`REQ-verify-041`,
   `REQ-verify-042`, section 8). Bare, it behaves as before. With an address,
   the session is pinned and a proof signed by any other address is refused
   with a reason of its own. It does **not** close the relay: an address is
   public and an attacker can name the victim's. It buys a better refusal, an
   earlier mismatch, and a member who committed to an address before they
   signed.
3. **A wallet argument may be a name, and resolving one fails soft**
   (`REQ-verify-042`, section 12). A naming service is a host this package
   does not talk to today, so it is a new row in `docs/WHAT-IT-TALKS-TO.md`.
   Nothing at boot depends on it; a name that cannot be resolved is reported
   as that, with a request for the raw address, so a member is never stuck;
   and the resolution stays above the verifying target, which receives an
   address and never a name.
4. **The fee bound is the network minimum, not zero** (`REQ-verify-009`,
   `REQ-verify-010`, section 6). At most one thousand microAlgos. A leaked
   blob then costs a member a fraction of a cent rather than their balance,
   and no wallet is locked out by a fee policy the page cannot enforce inside
   it. Nobody has tested which wallets force a minimum, and that uncertainty
   is the reason for the bound rather than a caveat beside it. An absent fee
   still reads as zero, never as unbounded.
5. **Scope.** The runtime work and the follow-ups are approved and are being
   built. This change and the Discord surface it defines wait until the owner
   has read them, so no item in this list may be started yet.

## Open questions

Recorded rather than smoothed over. None of them blocks starting, and each
should be answered before the item it sits under is called done. Question 10
used to sit here and is gone: it was the relay, it was a choice rather than an
oversight, and the owner has taken it. It is decision 1 in the section above,
and `change.md`'s acceptance criterion has been amended to say what the
definition now delivers and what is left over.

4. **What is the instance value in the challenge?** The plan wants one so that
   a signature cannot be replayed at another server, which the acceptance
   criterion asks for and the reference challenge does not carry. A minted
   random value stored once, in the same spirit as `MemberKey`
   (`Sources/Store/MemberKey.swift:5-31`), needs somewhere to persist it, and
   `Verify` deliberately does not depend on `Store`. The chat server id is
   already to hand and is not a person's identifier, but it is public and
   guessable, and `HOST-10` means one instance serves one server anyway.
   Unresolved.

5. **Does the flow actually survive Discord's in app browser?** Nothing in
   either repository answers this, and it decides whether the page is usable on
   a phone at all. It needs a real phone, both platforms, and both the default
   in app browser and the external browser setting. It does not block this
   change, because the verifier does not care, and it must be answered before
   the flow is announced to members.

6. **Will operators have a hostname and a certificate?** If most do not, the
   page cannot be served by the bot for most people and the default flips.
   This is the first bullet of "What would change this" in the decision record
   and it is still unanswered. It does not block this change, deliberately,
   which is why the verifier is separated from the page.

7. **Can the tolerant decoder be trusted without real wallet blobs?** Every
   branch can be covered by bytes assembled in a test, and no synthetic fixture
   proves that a particular wallet on a particular phone sends that shape. A
   recorded real blob carries a real address and cannot go in this repository.
   The mitigation is a manual check against each supported wallet before the
   flow is announced; what is missing is who does it and where the result is
   written down.

8. **Which wallets are supported on day one?** The reference configures three
   (`frontend/src/main.tsx:15-21`). That is a page decision rather than a verifier decision,
   so it is out of scope here, and it is worth deciding early because it sizes
   the page and it is what the tolerant decoder is tolerant *of*.

9. **How is a member told which route their server uses?** The plan says the
   bot states at startup that a configured portal means it does not check
   signatures itself, which serves the operator (`ADOPT-9`). Whether the member
   should also be told, before they sign, is a `VERIFY-6` question and has not
   been asked of `hi/verify.md` yet.
