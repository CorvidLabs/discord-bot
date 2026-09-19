---
spec: chain.spec.md
---

## Tasks

- [x] Read one account, one asset and one pool through a seam that a test can
      stand in for.
- [x] Carry completeness on every figure, so a short answer cannot be spent as
      a whole one.
- [x] Value a pool position in integers that cannot overflow on the way.
- [x] Hold to the provider's rate with a monotonic clock, and to the day's
      request budget with one counter shared by reading and signing.
- [x] Persist the day's count and restore it, so a restart does not hand the
      process a fresh budget.
- [x] Answer a health check with what the instance has reached, plus proof of
      which provider served the last probe.
- [x] Take the operator's token as one value from `Gating` and delete this
      module's second copy of it.
- [x] Take the pool and the combined total from `Gating` too, and delete this
      module's second copy of each.
- [x] Join the two readings: a `ChainReading` to a `Gating.Reading`, and a
      `[WalletCheck]` to a `Gating.MemberHoldings`.
- [x] Read the environment through `Gating.NumberedEnvironment`, so there is
      one set of rules for one environment.
- [ ] Give `Gating` a contract of its own, so `depends_on` can name it. Until
      then this spec names types it does not own, and nothing checks that
      `Gating`'s side of them has not moved.
- [ ] Wire a host to the module: nothing here is reached by a live sweep, a
      live health endpoint or a live payout yet.

## Gaps

- `LiquidityPool.validate(_:)` is called by nothing in this module, because
  nothing here loads a pool. A host has to call it at boot, and until there is
  a host nothing enforces that.
- `hi/` has no criterion that says outright "a restart must not hand the
  process a fresh budget for reading the chain". RUN-8.a is the nearest, and
  it is about not repeating a sweep rather than about the counter surviving.
  The behaviour is tested and was learned from a crash loop; the want behind
  it is not written down.
- Nothing checks that the node an operator configured is the network they
  think it is. ADOPT-12.b wants the settled network readable at startup, and
  this module reports no chain id or genesis hash.
- `ChainHealthReport` names components a host declares. Nothing here can tell
  a host it has declared the wrong ones, so SEE-10's promise that an outage
  names the piece it belongs to holds only as far as the host's list.
- The proof probe is outside the governor on purpose, so a misconfigured
  probe lifetime of zero turns every health check into a request to the node
  that the budget never sees.
- `ProviderProof.parse(responseHeaders:names:)` takes `[AnyHashable: Any]` and
  unwraps by casting. It is the one place in the module reaching into an
  untyped dictionary, and it exists only because `HTTPURLResponse` hands its
  headers back that way.
- `specsync`'s export extractor does not see `public private(set) var`, so
  `ProviderProofProbe.lastFailure`, `InMemoryRequestBudgetStore.writeCount`
  and `TokenBucket.tokens` are documented in prose under the Public API table
  rather than in it.

## Review Sign-offs

- **Product**: pending
- **QA**: pending
- **Design**: n/a
- **Dev**: pending
