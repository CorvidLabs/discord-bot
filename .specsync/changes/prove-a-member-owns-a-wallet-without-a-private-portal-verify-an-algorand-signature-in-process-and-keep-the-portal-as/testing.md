---
change: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
artifact: testing
---

# Testing

## What is under test

`design.md` settles the shape: one new library target, `Verify`, holding the
challenge, the session, the tolerant reader and the ordered check, with no
network, no clock, no key and no chat client. `requirements.md` splits the
work: REQ-verify-001 to REQ-verify-022, REQ-verify-030 to REQ-verify-034 and
REQ-verify-041 are satisfied and proved by this change, and REQ-verify-023 to
REQ-verify-029, REQ-verify-035 to REQ-verify-040 and REQ-verify-042 to
REQ-verify-043 are obligations of a host target that does not exist yet.
Twenty-eight here, fifteen there.

This document keeps that split visible rather than blurring it, because
`hi/build.md` BUILD-4 is that somebody can tell which parts are built. A
coverage table quietly claiming evidence for the host requirements would be
the exact failure BUILD-4 warns about.

Everything below is evidence that does not exist yet. This is a definition,
written before any of it is built, and nothing here has been run.

## Why every row names what it fails against

A test that cannot fail proves nothing, and a verification path attracts tests
that cannot fail more than most code does: the happy path is easy to assert and
every interesting case is a refusal, which is also what a broken implementation
produces. So each case below carries the wrong implementation it goes red
against. If a row's third column describes something the code could not
plausibly do, the row is decoration and should be cut rather than kept for the
count.

Where a row says "the reference", it means the implementation
`docs/VERIFICATION.md` was read out of, whose departures that document lists.

## How a valid signature is made with no network and no wallet

The suite needs real signatures over real preimages and has to make them from
nothing. It can, using the package already in `Package.swift:57`:

- `Sources/Algorand/Account.swift:54` generates a key pair from the platform's
  randomness. No mnemonic, no file, nothing anybody had to be trusted with,
  which is BUILD-2.b.
- `Sources/Algorand/SignedTransaction.swift:143` signs, through
  `Sources/Algorand/Transaction+Signing.swift:29`, whose doc comment at `:14`
  states that the bytes signed are `"TX"` followed by the canonical encoding
  and are not hashed first. That is the preimage `Verify` checks, stated by the
  code that produces it rather than assumed from a specification.
- `Sources/Algorand/SignedTransaction.swift:187` encodes the envelope, and the
  comment above it at `:180` says the transaction is spliced in already
  encoded, so the bytes under `txn` are exactly the bytes that were signed.
  That is what makes a byte for byte slice assertion possible at all.

So the fixture builds a zero amount, zero fee payment from a generated account
to itself, puts the session's challenge in the note, signs, encodes and hands
over base64. A second fixture builds the same payment with the fee set to the
network minimum, because the checker bounds the fee rather than pinning it at
zero and an accepted edge needs a fixture as much as a refused one. The production path then runs unchanged. This is the **fake
signer** `docs/VERIFICATION.md` names as one of the two honest ways to test
without a wallet, and it is why this change needs no flag: a test that skips
the code under test is not a test of it.

**A fixture that names a wire key names it the way the encoder does.** Every
forbidden key name a fixture uses is obtained from, or asserted equal to, what
the dependency's own canonical encoder emits, never written into bytes by hand.
A rekey, a close, a lease and a group can be set on a payment and encoded, so
those four fixtures are built outright by `PaymentTransaction.encode`. `aclose`
is emitted only by an asset transaction, so its name is asserted against that
encoder's output and then used in a payment fixture, with the asset transaction
covered separately as a transaction type refusal. This is not tidiness. The requirement for the rekey refusal originally said
`rekeyto`, which is the name of the field on the dependency's transaction type
and is not the name it puts on the wire: the canonical encoder writes `rekey`
(`Sources/Algorand/CanonicalTransactionFields.swift:175`). Coded literally, the
refusal would have matched nothing and the tolerant reader would have skipped
the real key as unknown, so every rekeying proof would have been accepted with
a valid signature. A hand written fixture would have carried the same wrong
name as the code and the suite would have gone green over it. Built by the
encoder, the test and the wire cannot disagree, and a future rename in the
dependency turns the suite red instead of turning the check off.

Three limits of that fixture, stated because they bound what the evidence is
worth:

1. **It emits only the canonical shape.** The reader exists for shapes a
   canonical encoder cannot produce. Those fixtures come from re-encoding
   **the canonical blob the generated-key signer just produced** into each
   accepted spelling, plus hand built bytes for the malformed cases, each
   labelled by its shape rather than by a wallet. Not from a recorded wallet
   blob: one of those carries a real address and cannot go into a public
   repository, which `tasks.md` section 5 says too. A shape nobody has seen
   yet is still unhandled; a fixture cannot discover one, only a handset can.
2. **It proves the checker, not the wallet.** No test here shows that a real
   wallet produces something this accepts. That is the manual list, and it is
   the only part of this plan that cannot be automated.
3. **It proves nothing about the page,** because there is no page in this
   change.

## `TargetShapeTests.swift`

The suite that reads the target's own sources and the manifest. It exists
because several of the properties this change sells are absences, and an
absence has no behaviour to assert. This is an established idiom here rather
than a novelty: `Tests/StoreSQLiteTests/TargetShapeTests.swift` already
asserts three such rules by reading `Sources/`, locating the repository from
`#filePath` so the test means the same thing wherever it is run from, and its
own comment gives the reason — "a rule held by attention alone is a rule that
lasts until a busy afternoon". This suite follows that shape, and it is why
`tasks.md` allows a test to open a file while forbidding it a network.

| Case | Asserts | Goes red against |
|---|---|---|
| The target depends on Foundation, `Algorand` and `Crypto`, and on nothing else | the manifest's dependency list for `Verify`, exactly | somebody adding `Store` for convenience, after which the checker can reach a database and the claim that it sits at the bottom of the graph is gone |
| The target names no chat client and no chat identifier type | no such import, no such type | a subject typed as anything but an opaque string, which is how an identifier that came from a person gets below the boundary AGENTS.md draws |
| The target declares no private key type, no mnemonic and no signing call | those names do not occur | a helper that signs "just for the tests", which is a key living in the one target whose whole claim is that it holds none |
| The target constructs no node client and calls nothing that submits | no client type, no submit call | the single import away from a client that `Chain` is also one away from, which is only ever answered by checking rather than by promising |
| The target reads no environment variable and no process argument | no environment read anywhere in the sources | the first flag anybody adds, on the day they add it, rather than in an audit a year later |
| No path re-encodes parsed fields and verifies over the result | no encode call reachable from the check | the mistake `docs/VERIFICATION.md` says you will not find quickly: a re-encoding one byte different fails a perfectly good proof and looks like a cryptography problem |
| `Verify` performs no account lookup and holds nothing that could | no data source, no URL type | doing the rekey retry inside the target, which makes it untestable offline and spends a chain request on every bad signature, which is RUN-11 |
| The target logs nothing | no logging call | a debug line printing a blob or a challenge, which is a replayable value written to wherever logs go |
| **No public interface returns a proved account without consuming a signature** | every public function and initialiser that can yield one takes a blob and a session | a public factory for the asserted route living inside `ProvedAccount`. This is the row that catches the resolution `tasks.md` was heading for when it asked for one type, constructible for both routes, with a non-public initialiser. A test that only checks the initialiser passes against that factory (REQ-verify-034) |
| The asserted value is a type of its own, named asserted, with its own public initialiser | two producers, one seam | one type for both, after which the only value in the target that nothing checked is indistinguishable from the one that was checked |
| No value read out of a submitted blob can become a key a signature is checked against | the reader's output has no signer field, and the only keys the check takes are the address and the expectation's | surfacing `sgnr` "for completeness", which is one convenience away from the blob naming the key that validates it (REQ-verify-033) |

## `ChallengeTests.swift`

| Case | Asserts | Goes red against |
|---|---|---|
| A challenge is five lines: the operator's label, the instance identity, the subject, the code, the nonce | the exact bytes, line breaks included, and the subject on the **third** line | a rendering that varies by platform, which changes what the member's wallet shows and invalidates every stored challenge |
| **A label containing a line break is refused at the mint** | one case per break character: U+000A, U+000D, U+2028, U+2029 | rendering it anyway, which makes a six line challenge. Five lines is what makes the subject findable by index, and REQ-verify-013 reads it back out of the submitted note that way, so a two line label does not merely look untidy: it moves the nonce into the slot the subject check reads (REQ-verify-003) |
| **A label over the bound is refused at the mint** | one byte over one hundred UTF-8 bytes is refused, one byte under is accepted | an unbounded label, which lets an operator put a page of text in front of the member's wallet and pushes everything a member needs to read off the screen. The boot-time half of this rule, which names the variable, is REQ-verify-040 and is the host's |
| **The subject line is the session's own subject** | the line carries the opaque subject the caller supplied and nothing else | leaving the subject out, which is what an earlier draft did on the argument that the session already binds it. It binds the wrong thing: an attacker runs the command, sends their own link to a member, and that member's genuine signature over a genuine looking prompt binds their wallet to the attacker. The bytes have to say who the proof is for (REQ-verify-030) |
| Two thousand mints produce two thousand distinct nonces | a collision probe, not a single comparison | a nonce narrow enough to collide. The reference takes thirty two bits from a UUID prefix; two mints a day apart are fine and a crowd arriving at once is not, and a single inequality assertion would never see it |
| The nonce is not derived from the subject, the address, the clock or any argument | the same arguments twice give different challenges | seeding from the timestamp, which makes two members who run the command together share a challenge and makes the nonce guessable by anyone who knows when it was minted |
| No identifier that came from a person appears in a challenge or a session | the subject line is the supplied opaque value and nothing else is kept | putting the chat account id in the challenge, which is what the contract currently asks for and what this change departs from. The departure is now narrow: the subject is there, as the minted member key |
| The label is the operator's, byte for byte | nothing added, trimmed or defaulted | a built in label, which puts another community's words in front of the member's wallet, and is ADOPT-1.c |
| The code shown to the member is the code inside the signed bytes | one value, two places, never minted twice | rendering the code separately for the reply and for the challenge, which is the anti phishing device silently not working while looking like it works |
| A challenge is compared as bytes, whole | one byte different does not match | a trimmed, case folded or prefix comparison, each of which accepts something the member did not sign |

## `SessionTests.swift`

| Case | Asserts | Goes red against |
|---|---|---|
| Expiry is evaluated against a supplied `now` | every case passes a fixed instant | reading the clock inside the check, which makes the suite depend on the machine it runs on and makes the boundary untestable at all |
| A proof at `expiresAt` is refused and one a moment before is accepted | the boundary is exactly where the requirement puts it | a comparison one either way, the kind of thing nobody notices and nobody gets right by accident |
| **An expired session refuses with expiry named, whatever else is wrong** | a blob that is also malformed and also for the wrong sender still reports expiry | reporting the first structural failure found, which tells a member to fix their wallet when what they need is a new link |
| A clock stepped backwards does not revive an expired session | expiry is an absolute instant compared against a supplied one | a countdown decremented per tick, which a suspended host resets |
| **A replayed proof is refused: the session is consumed on the first acceptance and refuses a byte identical resubmission** | consumed is terminal | a store that reads and never marks, and a store that marks after the account is written, where a crash between the two leaves a live challenge sitting behind a proved account |
| A refused proof does not consume the session | a member who picked the wrong account may try again | consuming on submission, which turns one mis-tap into a new link and a new signature, and makes a hostile submission a denial of somebody else's verification |
| A consumed or expired session is pruned, challenge and all | the in-memory conformer holds nothing for a pruned session | keeping spent sessions, which leaves a challenge and a subject in memory for no reason and is the opposite of VERIFY-7 |
| A session id is at least a hundred and twenty eight bits from the system generator, is not derived from the subject, the address or the clock, and is compared whole | width, source and comparison | a counter or a short token, which lets somebody enumerate live sessions and submit against one they did not open. It is the whole credential: whoever holds it binds whatever address they connect to whatever member the session names (REQ-verify-031) |
| **A session stops accepting submissions at a fixed maximum**, reported at the session state step | the count is on the session and the maximum is enforced | an unbounded session. REQ-verify-007 keeps a refused proof from consuming the session, which is right for a member who mis-tapped and is also a loop: field correct proofs signed by a throwaway key, forever, each one costing the host a chain read for an authorising address. One member exhausts the day's budget and pauses role sync, rain, claim and the reserve for the whole server (REQ-verify-032) |
| **The maximum is not below three** | the constant itself, asserted | a maximum of one or two, which passes every other row on this list and refuses the one member this whole seam exists for: a rekeyed account needs a wrong-account attempt, a right-account attempt that fails the signature check, and the authorising key retry. A ceiling with no floor is half a bound (REQ-verify-032, REQ-verify-016) |
| **Spending a session's allowance and then minting a new session does not buy a new allowance** | the count is kept per subject, over a supplied window, and survives displacement, consumption, expiry and pruning | the bound as first written. REQ-verify-019 has a new session displace the old one, so a per-session cap is refreshed by running the command again: the member mints a fresh session and a fresh allowance whenever they like, and the chain reads the cap exists to limit are spent anyway. This row is the one that fails against the version the second review found (REQ-verify-032) |
| **A second session for the same subject displaces the first, and a proof against the displaced one is refused** | the displaced session and its challenge are gone, and the refusal is at the session state step | two live challenges for one member, which is what this repository's plan and task list assumed away and no requirement said, until REQ-verify-019 |
| **A session id that selects nothing gets one reason, whatever the reason really is** | never issued, consumed, pruned and displaced are indistinguishable in the refusal | telling a holder of a stolen id whether it was ever real, and telling an enumerator when a member is mid-flow. A session still held and past expiry still reports expiry, which is REQ-verify-006 and is a different case (REQ-verify-019) |
| **A session records the connected address once and refuses a second differing one without answering** | the refusal says the session is already connected and says nothing about the second address | an unbound duplicate-address check, which answers "is this address a member of this guild?" for any address to anybody holding a session. The holder lists this product publishes are public, so that is an enumeration oracle over them (REQ-verify-019, REQ-verify-028) |
| **A session pinned at the mint refuses the first differing address at the connect** | the refusal is the pinned address reason, and it happens before anything is signed | recording the address anyway and only noticing at the proof, which throws away the one thing the wallet argument buys: a mismatch the member finds before their wallet asks them to sign (REQ-verify-041, REQ-verify-042) |
| **An unpinned session skips the pinned address position entirely** | the first address reason an unpinned session can reach is sender | a pin defaulted to something, after which a member who named no wallet is refused for not matching an address they never chose. `/verify` bare behaves exactly as it did |
| **The authorising key retry is offered at most once per session** | the second signature refusal for one session reports no retry available | "at most once per session" living only in a design sentence, which is a habit rather than a bound, and which nothing can fail against |

## `SignedTransactionReaderTests.swift`

The reader is hand written binary parsing that will one day be reachable from
the internet, in the process that will later hold a signing key. It gets the
most hostile suite in the change.

| Case | Asserts | Goes red against |
|---|---|---|
| Standard base64, url safe base64, padded, unpadded, and with surrounding whitespace all yield the same bytes | one blob, five spellings, one result | accepting only what the canonical encoder emits, which is the bug that works on a laptop and fails on a phone |
| A short hyphenated word is not a blob | ordinary text stays invalid | translating a hyphen to a plus unconditionally, which turns words into something that decodes and then fails much later with a useless reason |
| A bare signature and transaction map, that map wrapped in a one element array, and a map carrying an extra signer key each yield the same transaction slice | the wrapper is unwrapped and the unknown key skipped | handling only the shape the tests were written against, which is how the reference's codec grew every branch it has |
| An unknown key of any type is skipped without losing position | the following field still reads correctly | a skip that guesses a length, which shifts every field after it and produces a wrong slice rather than an error |
| **The returned transaction bytes are byte identical to a sub-range of the input** | the slice, asserted against the input by offset and length | any implementation that rebuilds the bytes. This is the one mistake that fails a valid proof, and the assertion has to be on identity rather than on equality of parsed fields, or it does not catch it |
| A signature that is not exactly sixty four bytes is refused by the reader | the length is checked before anything uses it | handing a short buffer to the crypto library and trusting whatever comes back |
| **Truncation at every byte offset of a canonical blob is refused, and none of them traps** | a loop over every prefix | an unchecked index, which is a crash the whole process takes, reachable by anybody who can post to the route |
| A declared map count, string length or binary length larger than the bytes that arrived is refused without allocating to match it | bounded memory | sizing a buffer from a number the input chose, which is how a short hostile blob becomes a large allocation |
| A value nested past the depth limit is refused in bounded time | there is a depth limit | unbounded recursion, which is the same crash by a different route |
| A blob longer than the ceiling is refused before parsing begins | the ceiling is first | parsing first and refusing later, which lets a stranger choose how much work the process does per request |
| An absent amount key reads as zero | the fixture is a real signed zero amount payment, which omits the key | requiring the key, which refuses every correctly formed proof. This is the easiest thing in the change to get wrong, and the fixture is chosen so that getting it wrong cannot pass |
| An absent fee key reads as zero | the same fixture, which omits `fee` for the same reason | two things now that the fee is a bound rather than an equality. Requiring the key refuses every correctly formed proof, as with the amount. Reading a missing key as unknown rather than as zero is worse and is newly reachable: under the old equality both readings refused and the mistake hid, and under a bound it is an accepted proof whose fee nobody checked |
| **A duplicate key at any depth is refused** | one case at envelope depth and one inside the transaction map | last key wins, which the reference's parser does (`SignedTransactionCodec.swift:65-83`). The page supplies the unsigned bytes, so it chooses the encoding: `amt` twice, zero first and a large value second, is one document the wallet shows one way and this reader takes the other, under one signature that stays valid over whichever reading leaves the building, because the reader slices rather than re-encodes. A checker that blesses a document meaning two things is not checking one |
| A transaction map whose keys do not ascend by their UTF-8 bytes is refused | the order is checked as the map is read | accepting any order, which is the other half of the same ambiguity and costs one comparison per key to remove |
| Any byte after the end of the envelope is refused | the whole input is consumed | stopping at the first complete value, which lets a blob carry a second document nobody looked at |
| A blob carrying an extra signer key parses and the signer is not surfaced | the reader's output has nowhere to put it | returning it, after which somebody wires it to the authorising key and the blob names the key that validates it (REQ-verify-033) |

## `ProofRefusalTests.swift`

The ordered check, fifteen reasons, one case per reason, each constructed so
that every **later** reason is also violated. That construction is the whole point: it
proves the order rather than asserting it. A suite that violates one rule at a
time passes against an implementation that evaluates them in any order at all.

| Case | Asserts | Goes red against |
|---|---|---|
| A proof against a consumed session reports session state, though it is also expired and malformed | state first | any other order |
| A proof against an expired session reports expiry, though the blob is also rubbish | expiry second | reporting the decode failure, which sends a member to debug their wallet when they need a new link |
| **A malformed blob reports the decode failure, though the transaction inside would also have failed** | decode third | a decode that silently yields empty fields, after which the member is told the sender is wrong when there was no sender |
| Bytes that decode but do not parse report the parse failure | parse fourth | conflating the two, which loses the difference between a wallet that sent the wrong encoding and one that sent the wrong shape, and those are debugged differently |
| A transaction missing a type, a sender, a receiver or a note reports the missing field by name | missing fields fifth | one reason for every failure, which tells the member nothing they can act on |
| A transaction whose type is not `pay` is refused | transaction type sixth, before the sender | reading a transaction's fields without asking what kind of transaction it is, which is how a shape nobody designed for reaches checks written for a payment |
| **A proof on a pinned session signed by a second generated key reports the pinned address, not the sender** | pinned address seventh, before sender, and only on a pinned session | folding the pin into the sender check. The two are different sentences: this is not the account you named, and this is not the account you connected. Whenever both hold the first is the one the member can act on, because they chose it. A row asserting only "refused" passes against an implementation that never returns the pinned reason at all (REQ-verify-041) |
| **A proof signed by a different account reports the sender, not the signature** | sender eighth, before the signature | evaluating the signature first. A member with the wrong account selected must be told that: it is something they can fix and a bad signature is not. The reference gets this right and says why at `SignedTransactionCodec.swift:428` |
| A transaction paying somebody else reports the receiver | receiver ninth | accepting any receiver, which means the member signed a payment instruction rather than a proof |
| A non-zero amount is refused, and an absent amount is not | amount tenth | requiring the key, asserted again here because it is the one that would ship broken |
| **A fee above the network minimum is refused, with a valid signature over it, and a fee at the minimum is accepted** | fee eleventh, its own reason, and both edges of the bound | three things. Asking the page for a zero fee and never checking it, which is what an earlier draft did: a hostile page builds the self payment with the right note and the fee set to the member's whole balance, the bot certifies it as proof of ownership, and the page still holds the blob and submits it. Pinning the check at zero instead of at the minimum, which refuses every wallet that raises a fee on the member's behalf, for a policy the page cannot enforce inside somebody else's wallet, and which nobody has measured. And a bound written one either way, which is why both edges are asserted rather than one (REQ-verify-009) |
| A transaction carrying a rekey, a close, an asset close, a lease or a group is refused, each with its own reason, each with a valid signature so the refusal cannot be the signature's, and **each fixture built by the dependency's own encoder** | forbidden fields twelfth | two things at once. First, checking only the fields the proof needs: this is the shape a hostile page would try to get countersigned. Second, and this one nearly shipped, writing the refusal against `rekeyto`, a name that never appears on the wire, so the tolerant reader skips the real `rekey` as unknown and every rekeying proof passes. A hand built fixture shares the wrong name with the code and goes green; an encoder built one cannot (REQ-verify-011) |
| A lease is refused | its own reason | ignoring `lx`, which lets the same blob block the member's own transactions for the validity window |
| A group is refused | its own reason | ignoring `grp`, which means the proof the bot blessed was one leg of an atomic group the member approved wholesale |
| **A proof whose challenge names another subject is refused, with a reason of its own, and that reason and not the note reason is what comes back** | subject thirteenth, immediately before note, read out of the **submitted** note at the line index the challenge shape fixes | two things. First, building the expected challenge out of the submitted note, which is a tempting simplification and turns the note comparison into a tautology. Second, and this is what the second review found, placing the subject reason **after** the note: the note is compared byte for byte, a proof naming another subject differs in the note as well, so the note reason fires first and the subject reason is unreachable. A row asserting only "refused" passes against that. This row asserts which reason (REQ-verify-030, REQ-verify-013) |
| **A proof minted for another session is refused at the note, and the refusal does not disclose the other challenge** | note fourteenth | comparing against any challenge this instance issued, which makes every open session of every member interchangeable |
| **A proof minted by another instance is refused, with every other field correct and the nonce identical** | the instance identity is inside the signed bytes | leaving the server line out, after which one community's proof is another community's proof and VERIFY-4 and HOST-6 are words rather than properties |
| **A valid signature over the wrong thing is refused** | the preimage is `"TX"` then the sliced bytes | verifying over the bare transaction, over the whole envelope, or over the challenge string alone. Each accepts a signature the member produced for some other purpose |
| **A signature from a key that is not the claimed account is refused** | the check is against the claimed address, never against a signer named in the blob | trusting the blob's own signer field. This is the whole attack: anybody could then claim any address they can type and take what it earns |
| A signature failure is distinguishable from every other reason | one case the host can act on | folding it into a general failure, after which the host cannot tell when a rekey retry is worth a chain read |
| A proof signed by a supplied authorising key is accepted, and the outcome records that it was | the rekey path works, with two generated keys, and the audit can tell the two apart | refusing rekeyed accounts outright, which silently excludes a real and blameless class of member; and accepting one without recording it, after which nothing downstream can tell a proof by the account's own key from a proof by a key somebody vouched for |
| The authorising key is taken only from the expectation | no other parameter, field or blob value reaches the verification | taking it from the submission or from the blob's signer field. Then an attacker submits a well formed zero self payment naming any address as sender, with the right note, signed by a key they generated, passes that key as the authorising key, and every check passes. That is the reference's test mode bypass reached through a parameter instead of an environment variable, and it is why REQ-verify-037 states where the key may come from |
| With no authorising key supplied, a bad signature is a refusal and not a retry | no second chance invented inside the target | retrying against the same address, which is the same check twice dressed up as a fallback |
| A refusal carries a reason and a non-reversible handle, and never the blob, the signature, the challenge in full **or the session id** | the refusal's contents, exhaustively, including that the session id does not appear in any field or in the rendered message (REQ-verify-018) | putting the challenge in an error message, which hands a replayable value to whatever reads errors; and returning the session id, which this requirement used to ask for and REQ-verify-036 forbids from ever reaching a log, which is exactly where a refusal ends up |
| The handle is stable enough to correlate and useless to replay | the same refusal yields the same handle, and the handle does not yield the session id | an abbreviation of the id, which is the id with fewer characters to guess |
| A signature over an arbitrary message, with or without a wallet's data prefix, is refused, and no entry point accepts one | one proof shape only | keeping the older message signing path as a convenience. It is cheaper to check, its support across wallets is patchier, and a second accepted shape is a second thing to get wrong for no gain |
| An all zero signature against an all zero address is refused | the identity and small order edges are not a pass | ignoring the library's result, or reading a thrown error as success |
| A claimed address that fails its checksum is refused | the address parses whole | taking whatever base32 decodes, which accepts a typo as a different account |

## `NoBypassTests.swift`

`hi/build.md` BUILD-3 exists because of the shape `docs/VERIFICATION.md`
describes under "The test mode bypass, said plainly": a setting whose name says
test and whose effect is that anybody may claim anybody's wallet. This suite is
the standing proof that this repository does not have one. It is also the suite
most likely to be deleted one day for looking redundant, which is why it is
written down here with its reason attached.

| Case | Asserts | Goes red against |
|---|---|---|
| The literal strings the reference accepts under its flag are refused | refused as ordinary malformed input, with no special case anywhere | a convenience special case added later by somebody who did not read the contract |
| A range of other fixed strings, the empty one included, are refused | the refusal is a property of having no signature, not a denylist of two literals | a denylist, which is defeated by choosing a third string |
| No build configuration or compilation condition changes the outcome | the same input gives the same outcome in debug and in release | a debug only branch, which is one production build away from being an identity bypass, and is BUILD-3.b |
| A proved account cannot be constructed outside the module | the initialiser is not public | a public initialiser, which lets any caller mint a proof that was never checked and makes every test above decorative |
| **No public API of `Verify` returns a proved account without consuming a signature** | the whole public surface, not one initialiser | a public unchecked factory beside the non-public initialiser, which satisfies the row above and defeats it. That is the shape `tasks.md` was heading for when it asked for one type, constructible for the asserted route, whose initialiser is not public; those three cannot all hold and this is the row that decides which one gives way (REQ-verify-034) |
| The asserted value is a separate public type whose name says asserted, and converting it into the downstream value is an explicit call | the two producers are distinguishable at the call site | one type for both, after which a reviewer reading the host cannot see which values were checked here and which were somebody else's word |

Two of those rows are structural rather than assertions, in the idiom
`AGENTS.md` already uses for the claim written before the payment: the wrong
thing does not compile. They are written down so they are not lost the day
somebody widens the access control for a reason that seems good at the time.
The public surface row is not structural and has to be a real test, because the
thing it catches compiles perfectly well.

## `OutcomeTests.swift`

| Case | Asserts | Goes red against |
|---|---|---|
| Both routes converge on one `VerifiedAccount` carrying subject, address, when, and route, from two different producers | one seam, two producers: a `ProvedAccount` from consuming a signature and an `AssertedAccount` the host constructs, each converting into it, the asserted one through an explicit call (REQ-verify-034) | both routes producing the same `ProvedAccount` with a route tag, which is what `plan.md` and `design.md` said until the second review. It cannot hold beside a non-public initialiser and a no-bypass claim, and the way it resolves in code is a public factory minting an unchecked proof |
| A `VerifiedAccount` built from a `ProvedAccount` and one built from an `AssertedAccount`, for the same subject and address, differ **only** in the route tag | the seam is one shape (REQ-verify-020) | two record shapes, which is how one of them quietly stops enforcing something the other still does |
| The route is in process when the signature was checked here and asserted when it was not | the tag is the truth, and it is on `VerifiedAccount` rather than on the proved value | tagging both the same, which hides from an operator that their bot is taking another service's word for an identity. The asymmetry is real, and the point of the tag is that the software says so rather than the operator working it out |
| Nothing but the audit line branches on the route | a search of the decision code finds no route | a role rule or a payout that reads it, which would make one change into two products |

## Requirement evidence

| Requirement | Evidence |
|---|---|
| REQ-verify-001 | `TargetShapeTests.swift`, the dependency and boundary cases, plus the manifest itself |
| REQ-verify-002 | `TargetShapeTests.swift`, the four absence cases |
| REQ-verify-003 | `ChallengeTests.swift`, the five line shape with the subject third, the two thousand mint collision probe, the derivation cases, and the label cases: each line break character and one byte over the bound |
| REQ-verify-004 | `ChallengeTests.swift` and `TargetShapeTests.swift` |
| REQ-verify-005 | `ProofRefusalTests.swift`, two coordinators differing only in instance identity |
| REQ-verify-006 | `SessionTests.swift`, the supplied `now`, the boundary, and expiry winning over everything else |
| REQ-verify-007 | `SessionTests.swift`, consumption and the byte identical resubmission; `ProofRefusalTests.swift` for a refusal not consuming |
| REQ-verify-008 | `ProofRefusalTests.swift`, the cross session note case, including that the refusal discloses nothing |
| REQ-verify-009 | `ProofRefusalTests.swift`, the single accepted shape including the type and both edges of the fee bound, and the refused message signature; `TargetShapeTests.swift` for the absent entry point |
| REQ-verify-010 | `SignedTransactionReaderTests.swift`, an absent amount and an absent fee from a real zero amount, zero fee signature, with the absent fee asserted to read as zero rather than as unbounded; `ProofRefusalTests.swift` for a present non-zero amount and a present fee over the bound |
| REQ-verify-011 | `ProofRefusalTests.swift`, one case per forbidden field, each with a valid signature so the refusal cannot be the signature's, **each fixture built by the dependency's own encoder** so the wire names in the test cannot drift from the wire names in the encoder |
| REQ-verify-012 | `SignedTransactionReaderTests.swift`, the byte identical slice; `TargetShapeTests.swift`, no reachable re-encode |
| REQ-verify-013 | `ProofRefusalTests.swift`, one case per reason, fifteen of them, each violating every later reason as well, and the subject and pinned address cases each asserting **which** reason rather than only that it refused |
| REQ-verify-014 | `SignedTransactionReaderTests.swift`, the accepted spellings and shapes, truncation at every offset, the declared length and depth cases, and the canonicality cases: a duplicate key at two depths, a descending key order and a trailing byte |
| REQ-verify-015 | `ProofRefusalTests.swift`, the distinguishable signature refusal; `TargetShapeTests.swift`, no lookup and nothing that could perform one |
| REQ-verify-016 | `ProofRefusalTests.swift`, two generated keys, the recorded authorising flag, and the case proving the key comes only from the expectation; `TargetShapeTests.swift` for the absence of any other path to it |
| REQ-verify-017 | `NoBypassTests.swift`, all four cases; `TargetShapeTests.swift`, no environment read |
| REQ-verify-018 | `ProofRefusalTests.swift`, the refusal contents case including that the session id is absent, and the handle case; `TargetShapeTests.swift`, no logging call |
| REQ-verify-019 | `SessionTests.swift`, the prune case, the displacement case, the one-reason case for a session id that selects nothing, and the connected address recorded once |
| REQ-verify-020 | `OutcomeTests.swift`, all four cases, with the two producers converging on one `VerifiedAccount` that differs only in the route tag |
| REQ-verify-021 | Every suite, through the generated key signer, and the standing rule that no test in this package reaches a network |
| REQ-verify-022 | `Package.resolved` unchanged in its pins, checked by the build; the documentation edits listed in `docs.md` |
| REQ-verify-023 | **Not evidenced by this change.** Host obligation, verified when the host lands |
| REQ-verify-024 | **Not evidenced by this change.** Host obligation |
| REQ-verify-025 | **Not evidenced by this change.** Host obligation, and the one that answers VERIFY-5.b |
| REQ-verify-026 | **Not evidenced by this change.** Host obligation |
| REQ-verify-027 | **Not evidenced by this change.** Host obligation |
| REQ-verify-028 | **Not evidenced by this change.** Host obligation. `Sources/Store/BotStore.swift:64` already refuses an address another member proved, per its doc comment at `:62`, and the conformance suite in `Sources/StoreTestKit` already covers that refusal. What is missing is the caller that surfaces it before the member is asked to sign. The half that can be evidenced here is the binding that stops it being an oracle: `SessionTests.swift`, the connected address recorded once and a second differing address refused without an answer |
| REQ-verify-029 | **Not evidenced by this change.** Host obligation. `Sources/Store/AccountRecord.swift:35` already documents that nil is not zero. The requirement was rewritten during the security review: banning the supplied tier while accepting the supplied balance forbade nothing, because a tier is a pure function of a balance through the ladder |
| REQ-verify-030 | `ChallengeTests.swift`, the subject line on the third line; `ProofRefusalTests.swift`, a challenge naming another subject, asserting the subject reason and not the note reason |
| REQ-verify-031 | `SessionTests.swift`, width, source and whole comparison |
| REQ-verify-032 | `SessionTests.swift`, the attempt maximum, the floor of three, the per-subject count surviving a new session, and the single retry; `ProofRefusalTests.swift`, the session state reason |
| REQ-verify-033 | `SignedTransactionReaderTests.swift`, the unsurfaced signer key; `ProofRefusalTests.swift`, a blob naming its own signer; `TargetShapeTests.swift` |
| REQ-verify-034 | `NoBypassTests.swift`, the public surface row and the separate asserted type; `TargetShapeTests.swift` |
| REQ-verify-035 | **Not evidenced by this change.** Host obligation, and the one whose closure is partial: see the note under the table. It also owns the pending proof the confirmation acts on, keyed by the subject rather than by the session id, with an expiry of its own, binding nothing until it is confirmed |
| REQ-verify-036 | **Not evidenced by this change.** Host obligation |
| REQ-verify-037 | **Not evidenced by this change.** Host obligation, and the one REQ-verify-016 depends on to mean anything |
| REQ-verify-038 | **Not evidenced by this change.** Host obligation, the other half of REQ-verify-032, and the only half that bounds a member who mints subjects rather than sessions |
| REQ-verify-039 | **Not evidenced by this change.** Host obligation |
| REQ-verify-040 | **Not evidenced by this change.** Host obligation: the operator's label is checked at boot and a bad one names its variable. The offline half, the mint refusing the same label, is REQ-verify-003 and is evidenced above |
| REQ-verify-041 | `ProofRefusalTests.swift`, a pinned session refusing a proof from a second generated key with the pinned address reason and not the sender reason; `SessionTests.swift`, the connect refusal on a pinned session and an unpinned session skipping the position |
| REQ-verify-042 | **Not evidenced by this change.** Host obligation: the command's optional wallet argument, the naming service behind it and its soft failure. The offline half is REQ-verify-041, the pin itself, and is evidenced above. No suite here can fail against a boot that pings a naming service, because there is no boot |
| REQ-verify-043 | **Not evidenced by this change.** Host obligation: the page and the reply name the chat account the session belongs to and warn that nobody should ever send a member the link. Nothing offline can test whether a person reads a warning, which is why the manual list carries the relay run rather than this table |

Criterion coverage, for the `hi/` ids this change can honestly claim: VERIFY-1
by `ProofRefusalTests.swift` and `NoBypassTests.swift` together, because
proving without surrendering a key means both that no key is asked for and that
no proof is accepted without one. VERIFY-4 and HOST-6 by the instance identity
case. VERIFY-7 and VERIFY-7.b by the prune case and by the challenge holding no
identifier that came from a person. BUILD-2, BUILD-2.a and BUILD-2.b by the
generated key signer. BUILD-3 by `NoBypassTests.swift`. BUILD-4 by this table
naming the **fifteen** requirements it does not evidence: REQ-verify-023 to
REQ-verify-029, REQ-verify-035 to REQ-verify-040 and REQ-verify-042 to
REQ-verify-043. That count used to read seven, which was right when the host
block ended at 029 and stayed on the page after five more host obligations
were added below it, and then thirteen before the owner's decisions added two.
A number in a document whose whole job is saying which parts are built is not
a detail.

**What closes the relay, and what no test here can show.** The confirmation in
REQ-verify-035 closes adoption by somebody who only came into possession of a
link: they can sign and they cannot confirm. It does not close the relay,
because in that attack the attacker owns the session and can confirm on their
own interaction. The relay is answered by REQ-verify-043, on the page: the
chat account the session belongs to is named there, with a warning beside it,
and in a relay the victim is on the operator's real page, which cannot be made
to lie about whose session it is. That is sufficient for this attack and it is
the only form of it a first-time verifier can use, since the subject line asks
them to recognise a value they have never seen.

No suite here can evidence any of that, and this document does not pretend
otherwise. Whether a person reads a name and a warning is not a property of
the checker. The manual list carries the relay run for that reason, and a row
here asserting the relay is closed would be the decoration this document opens
by warning against. What is left after the page is a first-time verifier who
does not read it: the attack needs somebody to take a link from a stranger and
sign what it shows them, which the server rules already cover and every wallet
warns about, so it is real and largely user error, and saying that is not the
same as dismissing it.

VERIFY-5 and ADOPT-4, the two criteria this change exists for, are **not**
claimed here. Not needing a second service is a property of the package graph;
verifying a member from one clone needs the host, and until it lands the honest
statement is the one `requirements.md` makes and `README.md` has to repeat.

## Manual, when the host lands

Nothing in this change can be exercised by hand, because nothing in it can be
run: no page, no route, no command. The list below is what has to be done when
the host lands. It is written now, not then, because the reader's fixtures are
only as good as what these checks find, and because a manual list written
afterwards tends to be a list of what already worked.

- [ ] On a phone, complete a proof with each supported wallet family. Record
      the exact shape each one posted, and add any shape the reader did not
      already accept as a fixture, with a comment naming the device that sent
      it.
- [ ] Try it inside the chat client's own in app browser, on both platforms,
      with the in app browser and with the external-browser setting. **This is
      the first real measurement of a thing nothing read for this change
      answers**, so record what happened rather than confirming an
      expectation; neither implementation read here handles in app browsers or
      records a result. If the hand-off fails, the page needs a way out — open
      in the system browser, or show the connection as a code the wallet's own
      scanner can read. If that fallback is where most members end up, the
      decision record says that is a reason to revisit where the page lives.
- [ ] With the wrong account selected in the wallet, confirm the member is told
      the sender did not match and not that their signature was bad.
- [ ] Read **all five** challenge lines on the phone as a member would, the
      member line included, and confirm the six character code the wallet shows
      is the one the chat reply showed **and** that the member line shows the
      same subject value the reply printed. This item said four lines, written
      before the member line existed and left behind when it was added, so the
      one line standing between a first-time verifier and a relayed prompt was
      never going to be read on a handset. Confirm also that the challenge is
      five lines and not six, which is what an operator label with a line break
      in it would produce (REQ-verify-003, REQ-verify-040).
- [ ] Confirm the wallet signs at all, and record **which wallet, which
      version, which handset**. **(external)** A conforming wallet is
      understood to check the genesis id and hash against its own network, and
      not to require live suggested params; nothing read for this change
      establishes either, and `research.md` section 7 keeps it as the open
      question that decides whether the page can drop its one node read. So
      the page builds the proof against the operator's own network rather than
      a placeholder until a handset says otherwise, and dropping the read is
      an improvement to earn rather than a premise to design on. Confirm also
      that the parameters come from one cached read rather than one read per
      member, or a queue of members is a way to spend the day's chain budget,
      which is RUN-11.
- [ ] Abandon the flow half way and confirm nothing about the member changed:
      no record, no role, no cost. That is the second half of VERIFY-1 and no
      offline test can see it.
- [ ] Submit the same blob twice by hand and confirm the second is refused.
- [ ] Record, for each supported wallet, **what fee it actually signs** when
      the page hands it a zero: zero, the network minimum, or something else.
      The checker accepts anything up to the minimum, so this is no longer a
      pass or fail, it is the measurement the bound was widened because nobody
      had. A wallet that raises the fee above the minimum cannot verify, and
      that is the case to find. If every wallet honours a zero, tightening the
      bound back is a later change with this measurement behind it; until
      then the bound stays where it is rather than being guessed at.
- [ ] Confirm each supported wallet emits the transaction map with ascending
      keys and no duplicates. Any conforming wallet must, or its transactions
      would fail signature verification on chain, but the checker now refuses
      what it used to tolerate and this is where that is measured.
- [ ] Take a session link out of one member's reply, open it as somebody else,
      sign with a different wallet, and confirm nothing is adopted without the
      confirmation in the first member's own chat client.
- [ ] **Kill the chat client during the hand-off to the wallet**, on both
      platforms, then reopen it and confirm the member can still confirm the
      proof they just made. That is what the pending proof being keyed by the
      subject rather than by the session id is for (`REQ-verify-035`), and a
      phone is the only place it can be measured.
- [ ] Leave a checked proof unconfirmed until it expires, and confirm nothing
      was bound: no record, no role, and the address is still free for its real
      owner to prove.
- [ ] On one session, connect one address, then try to present a second,
      different address. Confirm the refusal says the session is already
      connected and says **nothing** about whether that second address belongs
      to anybody here (`REQ-verify-019`, `REQ-verify-028`). Try it with an
      address taken from a public holder list and confirm the answer is the
      same as for an address nobody here holds.
- [ ] Run the relay by hand: one tester starts the flow, sends their link to a
      second tester, and the second tester opens it on their phone **without
      being told what to look for**. Record whether they notice that the page
      names somebody else's chat account, and whether they read the warning
      beside it (`REQ-verify-043`). That reading is the only evidence there
      will ever be for the decision that put the name on the page rather than
      in the signed bytes, and nothing offline can produce it. Record the
      member line in the wallet prompt in the same run, so the two can be
      compared: the subject value is what a returning member can check and the
      name is what a first timer can.
- [ ] Run `/verify wallet:` with an address the tester holds, then sign with a
      **different** account, and confirm the refusal says the account named
      when the command was run is not the account that signed, rather than
      saying the sender did not match (`REQ-verify-041`). Then run it again
      and connect the wrong wallet first, and confirm the mismatch is reported
      at the connect, before anything asks for a signature.
- [ ] Run `/verify wallet:` with a **name** rather than an address, and
      confirm the resolved address is shown before anything is signed. Then
      make the naming service unreachable and run it again: confirm the member
      is told the service could not be reached and asked for the raw address,
      that verification by address still works, and that restarting the bot
      with the service still unreachable starts it (`REQ-verify-042`).
- [ ] Wait out the expiry, then sign, and confirm the refusal names expiry and
      offers a new link.
- [ ] Prove the same wallet against two instances configured with different
      instance identities, and confirm neither proof works on the other.
- [ ] Run the portal route against a conforming portal and confirm the startup
      line says, in words an operator reads, that on this route the proof is
      the other service's word.

## Not covered, and why

- **The page's own JavaScript.** There is no page in this change and no browser
  test runner in this repository. When the page arrives, adding one for a
  connect button and a sign button would be a larger surface than the thing it
  guards. What can regress unseen is the checker, and that is covered here.
- **Real wallet behaviour.** Covered only by the manual list. A shape no
  handset has yet sent is still unhandled and will be until one sends it. The
  reader suite is written so that such a shape fails as a decode refusal with a
  nameable cause rather than as a signature refusal with none, which is the
  most an offline suite can do about a thing it cannot see.
- **The wallet connection libraries.** They change on their own schedule. That
  is the recurring cost this change accepts and cannot test away, and the
  decision record is where it is recorded rather than here.
- **The naming service, and what happens when it is down.** There is no call
  to it in this change, so there is nothing offline to fail against. What can
  be tested here is the half that stays in the target: the pin is an address,
  `Verify` holds no name and nothing that could resolve one, and
  `TargetShapeTests.swift` proves the absence the same way it proves the
  others. The soft failure itself is the host's and is on the manual list.
- **Whether a member reads a warning.** The page naming the chat account the
  session belongs to is what answers the relay, and no offline suite can show
  that a person notices it. That is the manual relay run, and it is the one
  item on that list whose result is an observation about people rather than
  about software.
- **The genesis hash and the validity window.** `Verify` does not check either,
  and that is deliberate rather than an omission. A key is the same key on
  every network, so a proof signed against another network still proves control
  of the account, and the wallet is the thing that refuses a network mismatch
  anyway. What makes the proof unique is the note, and the note is checked.
  Adding a network check would couple an offline target to a network identity
  it has no other reason to know, and it would refuse a member whose wallet
  happened to be pointed elsewhere while proving nothing extra. Recorded here
  because the reference also omits it and somebody will eventually ask whether
  that was an oversight in both.
- **Rate limiting the command and the route.** Owned by the host and tested
  there, as REQ-verify-038, not left to "the transport". What is tested here is
  the half that can be: a session bounds its submissions, the store keeps the
  same bound per subject so a new session does not buy a new allowance, and the
  authorising retry is offered once (REQ-verify-032). So the offline suite can
  fail against an unbounded session and against a bound that session churn
  resets, and it still cannot fail against a missing rate limit on the command
  that mints sessions, or against a member with many subjects. Neither half
  discharges the budget story, and this document does not claim either does.
  `Verify` has a blob ceiling because a parser needs one, not because it is the
  defence.
- **Whether the signed transaction could be submitted.** It is never sent, so
  there is no submission path in this package to test. The suite asserts the
  amount is zero, the receiver is the sender, and the forbidden fields are
  absent, which together are what make submitting it pointless as well as
  harmless.
- **Timing of the comparisons.** The challenge and the session id are compared
  as values inside the process, not presented by a remote caller, so the timing
  channel the shared secret comparison worries about does not apply here. When
  the host binds a route, the secret on the portal path is where that property
  lives and it is tested there.
