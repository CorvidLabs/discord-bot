---
spec: reserve.spec.md
---

## Key Decisions

- The reserve is a ceiling the calculation cannot cross, not a balance it spends
  down. Topping the paying account up funds what was already promised; it never
  resizes the reserve or changes a payout.
- A stream is a value the host configures, not a case in an enum, so a reserve
  can have one stream or six without a code change.
- The ceilings an epoch was measured against are a **list**, not one key. A
  single value is simpler and reads well in the ordinary case, and it is wrong
  in exactly the case SPEND-9.c was written for: an epoch that crashed on one
  side of a boundary and resumed on the other really was charged to two
  ceilings, and naming only the first would be a confident lie in the one
  situation an operator opens the row for. A list costs one table and a loop.
- The charge records the **spending** period, from the limits the host stated,
  and never the cadence period. The cadence gap is real and is left open: the
  state keeps only the latest cadence key per stream, so "which week did epoch
  seven pay in" is still unanswerable. It is a one-line addition to the same
  row and it is deliberately not taken here, because SPEND-9.c asks about the
  ceiling.
- Denominators are fixed constants. Dividing by the eligible count would mean
  every arrival shrinks and every departure grows everybody's payment, and
  nobody could be told in advance what they will receive.
- Every epoch of a schedule pays the identical figure. Spreading the remainder
  so that a few epochs pay one unit more would make that promise impossible, so
  the remainder is reported as residue and never paid.
- The claim is written before the payment. A crash then under-pays and leaves
  the value in the reserve, which is the recoverable direction.
- One gate covers every stream rather than one gate each, because `ReserveState`
  is a single value saved whole and two concurrent saves would lose one stream's
  completed epoch while its epoch row still said complete.
- Persistence and payment are protocols. When payment lives inside a concrete
  type that holds a key and talks to a network, none of the failure paths can be
  exercised by a test, and those are the paths that matter.

## Files to Read First

- `Sources/Reserve/ReserveConfiguration.swift`: the split, the validation and the
  projections.
- `Sources/Reserve/ReserveRunner.swift`: the four guards in the order they have
  to happen in.
- `Sources/Reserve/ReserveEpochSplit.swift`: the per-epoch figure and the
  residue.
- `Sources/Reserve/ReserveStore.swift` and `Sources/Reserve/ReservePayer.swift`:
  the two seams a host implements.
- `hi/reserve.md`: the 52 criteria the tests cite by id.

## Current Status

Implemented and covered by 105 tests. This is the only library target in the
package. There is no bot target yet: no gateway, no commands and no chain
access, so nothing here is wired to a live payout.

## Notes

- The tests cite criterion ids from `hi/reserve.md` in their names, so a failing
  test names the promise it broke.
- `InMemoryReserveStore` stores rows as encoded text rather than live values, so
  it exercises the same encode and decode path a durable store would and the
  "unreadable row throws" rule is genuinely tested.
