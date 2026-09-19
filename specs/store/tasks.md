---
spec: store.spec.md
---

## Tasks

- [x] Records, protocols and refusals, with a member named by a key this
      instance draws rather than by anything that came from them.
- [x] A store in memory that is a real implementation, keeping rows as encoded
      text so the rule that an unreadable row throws is exercised.
- [x] A conformance suite any backend can be run against, with probes a backend
      may decline and a skip that states the reason.
- [x] The platform's SQLite behind a statement type that only accepts literals
      and a value type with no floating point case.
- [x] One connection, every durability setting read back, and a write scope
      whose synchronous body makes claim-after-pay a compile error.
- [x] An exclusive lease, taken before the handle, so two instances cannot pay
      the same week.
- [x] Migrations with checksums, a refusal for a file written by something
      newer, a copy taken before anything changes, and a reverse for every step.
- [x] Claims as their own rows, written as an append, so a payout does not
      rewrite a growing value once per recipient.
- [x] Boot reconciliation of recorded spend, upward only, through the four
      methods the reserve seam already has.
- [ ] Propose the fifth seam method that writes the epoch row and the state in
      one transaction, which deletes the window the reconciliation compensates
      for. It is a protocol change with one implementation and no deployed
      rows, and it will never be cheaper.
- [x] A lane that builds and tests on the platform most operators run, so the
      system library prerequisite is proved by something that runs rather than
      described in a document.
- [ ] A small executable the tests can stop mid-write, so durability is proved
      against a killed process rather than an abandoned handle.
- [ ] Measure a full epoch of several thousand recipients end to end and put
      the number in the operator's notes, because a payout slow enough to be
      killed half way through is the failure this design exists to prevent.
      The store's own half is now measured: a save per slot against a file on
      a local disk takes 1.3s for a thousand slots and 3.4s for two thousand,
      against 13.0s and 43.8s before the record's claim lists were made
      append-only. What is still unmeasured is an epoch with a payer in it.
- [ ] The tables deliberately left out, each with the surface that reads it:
      the holdings cache, a typed payments table, the audit log, claim offers,
      scheduled tasks, the games' rows and a saved timezone.

## Gaps

- Durability is proved by letting a handle go and by a second view of the
  storage, not by killing a process inside a write call.
- No check has a real network mount, so the volume refusal is proved against a
  supplied mount table and against the local volume being allowed, rather than
  against the thing it exists to refuse.
- Nothing measures the cost of a large epoch end to end. The store's share of
  it is measured and is roughly linear in the slots paid; the fsync count per
  recipient is still reasoned about rather than counted.
- Two processes are refused by an advisory lock, which stops another copy of
  this software and not a text editor.

## Review Sign-offs

- **Product**: pending
- **QA**: pending
- **Design**: n/a
- **Dev**: pending
