---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
module: store
---

# Semantic delta: store

## Added

### REQUIREMENT REQ-store-016

A store SHALL persist the charges an epoch record carries and SHALL return
them in the order they were written, in every backend, including when the same
epoch is saved again with a further charge appended. An epoch row written by a
build from before the charges existed SHALL read as an epoch with no charges,
and SHALL NOT throw and SHALL NOT have a period invented for it from a
timestamp. That is not an exception to the rule that a row which exists and
cannot be read throws: a field absent from a record an older build encoded is
not an unreadable row, and a backend SHALL NOT treat it as one. Where a
backend keeps the charges under a name of their own, that name SHALL be one of
the shared table names, so a forgetting and an unreadable row report it the
same way whichever backend is running.

Acceptance Criteria
- The shared conformance behaviour covering an epoch round trip, extended with
  charges, proves every backend returns them whole and in the order they were
  written (RESERVE-8.a).
- A new shared conformance behaviour proves an epoch saved a second time with
  a further charge reads back with both charges, in order (SPEND-9.c).
- `InMemoryConformanceTests` and `SQLiteConformanceTests` prove both
  behaviours against each backend rather than proving them once (RESERVE-8.a).
- `SQLiteFileTests` proves a file written by the build before this one keeps
  every epoch row across the pending migration, and that those epochs read as
  charged to no period rather than failing to load (ADOPT-5, RUN-9).

### REQUIREMENT REQ-store-017

The charges SHALL arrive as a new migration rather than as an edit to a
migration already shipped, because a shipped migration is fingerprinted and
editing one refuses the start for everybody who already ran it. The reverse of
that migration SHALL run on the oldest SQLite version this package admits at
open, and SHALL NOT depend on dropping a column, because that floor is older
than the release which learned to drop one. A reverse SHALL therefore drop
whole objects the migration created, leaving the earlier schema exactly as it
was.

Acceptance Criteria
- The existing reverse-everything test proves that applying every migration
  and reversing every one, including the new one, leaves nothing but the
  bookkeeping table (RUN-9).
- `SQLiteFileTests` proves the new migration takes a copy of the file before
  it runs, and refuses to run when the copy fails (RUN-9).
- `SQLiteFileTests` proves no shipped migration's reverse uses a column drop,
  so every reverse runs on the oldest SQLite the package declares it supports
  (RUN-9).
