---
spec: verify.spec.md
---

## Automated Testing

`swift test --filter VerifyTests` runs this target's suite: 130 tests in 8
suites, all offline. The whole package runs 1131 tests in 91 suites, across
`Reserve`, `Gating`, `Games`, `Chain`, `Store`, `StoreSQLite` and `Verify`
(130). The suite is run on Linux as well as on macOS, because Foundation is a
different implementation there and the module has already been caught by the
difference twice.

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `ChallengeTests.swift` | Unit | The five lines with the subject third, the operator's label carried byte for byte, one code in two places, a label refused for each of the four line break scalars and for the two of them paired as a carriage return and line feed, asserted over scalars because `String.contains` is not the same call on both platforms, one byte over the bound, the bound measured in bytes rather than characters, a two thousand mint collision probe, and a whole-bytes comparison. |
| `SessionTests.swift` | Unit | Expiry against a supplied instant and the boundary either side of it, a clock stepped backwards, consumption and a byte identical resubmission, a refusal leaving the session usable, pruning that leaves nothing, the id's width and source, a width of thirty two characters that is ninety six bytes, the floor of three, the per-session and per-subject bounds naming which ran out, the per-subject bound surviving displacement, the window restarting, displacement discarding a challenge, one reason for every id that selects nothing, the connected address recorded once, and a pinned session refusing at the connect. |
| `SignedTransactionReaderTests.swift` | Unit | Five spellings of one blob, ordinary text staying invalid, a leftover group of one character and padding anywhere but the end refused on both platforms, the ceiling firing before parsing, the three accepted shapes, the slice asserted against the input by offset and length, a signer key skipped, an envelope and a transaction map whose keys do not ascend both read, an unknown key not shifting the fields after it, an absent amount and an absent fee reading as zero, duplicate keys at two depths, a trailing byte, truncation at every offset, a declared length and a declared count, the depth limit, and a non-string key. |
| `ProofRefusalTests.swift` | Unit | One case per ordered reason, each constructed so every later reason is also violated; both edges of the fee bound; each forbidden field with a valid signature and a fixture built by the dependency's own encoder; the wire names asserted against that encoder's output; the subject reason returned rather than the note; a proof from another instance; a valid signature over the wrong preimage; every published small-order encoding; two hundred generated keys that are not mistaken for one; the authorising key path, the single retry, and a key of the wrong width reaching the caller without costing an attempt; the two exhaustion bounds not sharing one sentence; and what a refusal carries. |
| `NoBypassTests.swift` | Unit | Twelve fixed strings including the two a reference portal accepts under a flag, refused as ordinary malformed input; a signature over an arbitrary message with and without a wallet's data prefix; one fixed input giving one outcome whatever this was built as; and the one call that yields a proved account taking both a blob and a session. |
| `OutcomeTests.swift` | Unit | Two producers meeting at one value that differs only in its route tag, and an asserted account carrying whose word it was. |
| `ConcurrencyTests.swift` | Unit | Two submissions of one valid proof, two connects with two addresses, and a burst of eight field correct proofs signed by a throwaway key, every one of them in flight at once against one session: one proof accepted, one address bound, the per-session allowance not outspent and the authorising key retry offered at most once. The store holds every reader until the whole burst has read, so the interleaving is the same on every run rather than the one the scheduler happened to pick. |
| `TargetShapeTests.swift` | Source | The manifest's dependency list exactly; no import of another target; no chat client and no chat identifier; no key type, no mnemonic and no signing call; no node client and no request type; nothing read from outside the process; no clock; no logging; no re-encode; no lookup and nothing that could perform one; a public key built in exactly one place; no field a signer could be surfaced in; no force unwrap; no public interface yielding a proved account without a blob and a session; two distinguishable producers; and every exported type `Sendable`. |

Every key in every suite is generated inside the test from the platform's own
randomness, every signature is produced by the dependency's own signing path,
and every blob by its own encoder, so the production path runs unchanged. No
test reads a setting, opens a connection or builds a request. Reading a file
is allowed and required: `TargetShapeTests` is how an absence gets checked at
all, and it finds the repository from `#filePath` so it means the same thing
wherever it is run from.

## What this evidence does not cover

Said here rather than left to be assumed, because BUILD-4 is that somebody can
tell which parts are built.

- **The host obligations in REQ-verify-009 and REQ-verify-010 have no
  evidence here, and no suite claims any.** They are the listener, the page,
  the chat command, the bearer-credential handling, the confirmation and the
  pending proof, the authorising address read, the rate limit, the release
  path for an address bound to the wrong member, the boot-time label check,
  the wallet argument and the naming service behind it, and the named account
  and warning on the page. They are written down here so the change that
  lands them has nothing left to invent, and they are verified then.
- **Two of them have an offline half that is covered**, and only the half. The
  label rule is refused at the mint by `ChallengeTests`; naming the variable
  at boot is the host's. The submission bound is covered per session and per
  subject by `SessionTests`; the rate limit per member and per source is the
  host's, and neither half discharges the story about the day's chain budget
  on its own.
- **No test here shows that a real wallet produces something this accepts.**
  The fixtures emit the canonical shape and re-encode it into the others; a
  fixture cannot discover a shape nobody has seen yet, only a handset can.
  That is the manual check in `tasks.md`, and it is the only part of this
  plan that cannot be automated.
- **The claim is proved for one process and not for two.** `ConcurrencyTests`
  races calls inside one coordinator, which is what the claim covers. A host
  that backs the store with a database several instances share owes the same
  claim at that level, and nothing here can show whether it has one.
- **Nothing here is evidence about a page**, because there is no page.

## Manual Testing

- On a real handset, on both platforms, with each supported wallet: run the
  flow end to end and record whether the blob that comes back is a shape this
  reader accepts. Do it in the chat client's own in-app browser and in an
  external one, because nothing in either implementation read for this
  handles the hand-off between them and its absence is evidence about those
  implementations rather than about phones.
- Send one tester's session link to a second tester and record whether the
  named account on the page reads as somebody else's to a person who was not
  told what to look for.
- Make the naming service unreachable and confirm that the boot, verification
  by address, and every other surface carry on working.
