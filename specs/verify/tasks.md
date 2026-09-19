---
spec: verify.spec.md
---

## Tasks

- [x] Mint a challenge of five lines, with the operator's own words first, an
      identity for this instance, the subject third, a six character code and
      a hundred and twenty eight bit nonce.
- [x] Refuse, at the mint and with a named reason, any value that would not
      render as one line, and a label over a hundred UTF-8 bytes, because the
      subject is found by its line index.
- [x] Keep a session with an id that is a bearer credential, an expiry
      measured against a supplied instant, one live session per subject, and
      a prune that leaves nothing behind.
- [x] Record the address a wallet connected once, and refuse a second
      differing one without answering anything about it.
- [x] Pin a session to an address at the mint, and refuse the first differing
      address at the connect rather than after a signature.
- [x] Read a submitted blob tolerantly about spelling and strictly about
      saying two things: both base64 alphabets, three envelope shapes, keys
      in whatever order a wallet sends them, and a refusal for a duplicate
      key at any depth, a trailing byte, a declared length the bytes do not
      carry, a value nested past a limit, and anything over a ceiling
      applied before parsing.
- [x] Return the transaction bytes as a slice of what arrived, with the range
      they came from, so nothing has to be taken on trust that they were not
      rebuilt.
- [x] Accept exactly one proof shape, and refuse `rekey`, `close`, `aclose`,
      `lx` and `grp` each with its own reason whether or not the signature is
      valid, with every wire name taken from the dependency's own encoder.
- [x] Bound the fee at the network minimum, read an absent amount and an
      absent fee as zero, and prove both edges of the bound.
- [x] Produce the fifteen refusals in one order, with the subject read out of
      the submitted note and sitting immediately before the note.
- [x] Carry a non-reversible handle in a refusal and never the session id, the
      blob, the signature or the challenge.
- [x] Check the signature over the prefix and the slice, against the claimed
      address or against an authorising key the caller supplied and nothing
      else, refusing a small-order key before the library is asked.
- [x] Bound submissions per session at three and per subject over a window,
      and report the authorising key retry at most once per session, naming
      which of the two allowances ran out.
- [x] Claim a session for the length of a call, so single use, both
      submission bounds and the one retry hold for calls that arrive
      together and not only for calls in turn.
- [x] Produce a proved account only by consuming a signature and a session,
      with no public initialiser, and give the asserted route a public type of
      its own that both meet at through calls naming their route.
- [x] Prove every absence by reading the target's own sources and the
      manifest, because an absence has no behaviour to assert.
- [ ] The listener, the page and the chat command, with the eight obligations
      REQ-verify-009 and REQ-verify-010 name. Another change owns them, and
      until they land nobody can verify a member from a clone of this
      repository.
- [ ] A durable conformance to `VerificationSessionStore`, which is where the
      per-subject bound stops evaporating on a restart.
- [ ] The chain observed route, where a member sends a real transaction
      carrying the challenge in its note. It needs an indexer, which is a new
      host and a new quota, and it costs the member a fee. The seam is open:
      the checker takes a proof and an expectation and does not care which
      channel delivered it.
- [ ] A manual check against each supported wallet on a real handset, before
      the flow is announced to anybody. No fixture can discover a shape
      nobody has seen, and no test here shows that a real wallet produces
      something this accepts.
