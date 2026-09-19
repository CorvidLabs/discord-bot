---
spec: sweep.spec.md
---

# Context

The role sweep is the loop that makes ROLE-1 true without anybody asking: the
role beside your name matches what you hold, half an hour later, for ever.
Everything in this module is the impure half of that. The decision lives in
`Gating` and is deliberately not repeated here.

## Design Decisions

- **The decision is imported, never re-derived.** `RoleRules.decide` and
  `RoleRules.orphanSweep` are the only things that turn facts into roles. A
  second copy of either inside a loop is how the original ended up with four
  always-false comparisons that the compiler warned about and nobody read.
- **A read that did not complete is `unknown`, not zero.** The original's
  worst incident was a transient provider error that read a liquidity position
  as zero, which read as a member who had sold up, which stripped roles from
  somebody who had done nothing. `Chain.ChainReading` and `Gating.Reading`
  both exist for that, and `Chain.GatingBridge` is the one join between them.
  This module adds the third shape of the same rule: **an account absent from
  the batch entirely is substituted with an explicitly unread reading**, so a
  member is never quietly made of their remaining wallets.
- **The verified badge is decidable even when nothing else is.** It is this
  bot's own record rather than something a provider can fail to answer, so a
  member whose every chain fact went unread still receives it on their first
  sweep. That is why a test of holding has to give the member the badge
  already, and it is worth knowing before reading a tally.
- **The orphan pass is opt-in.** Listing a whole server is a different
  permission and a different cost from reading one member, so a host that
  supplies no `ServerRoster` simply has no orphan pass. Absent is the safe
  direction, and every other refusal here takes the same direction.
- **The baseline travels with the decision.** `RoleRules.orphanSweep` answers
  with a run carrying a baseline or a refusal carrying none. A caller that
  recorded the count observed during a refusal would lower the bar to a wrong
  store's own tiny count, and the next pass would pass the halving check
  against itself. With a decision there is no count to record, so the mistake
  cannot be written.
- **A corrupt baseline throws rather than reading as nil.** `Store` already
  made that choice; this module honours it by refusing the pass instead of
  falling back to the zero floor.
- **Two journal writes per sweep, not one.** A record with no finish is an
  unfinished sweep. Without the first write, the newest thing on disk after a
  crash mid-sweep is the previous sweep's success, and a check reports a
  healthy bot for as long as nobody notices. That is exactly how the outage in
  `hi/see.md` read.
- **One journal entry about skips per sweep, not one per member.** The problem
  list is capped, and a sweep that held two hundred members would push out the
  overnight failure an operator came to read.
- **`memberId` is this instance's own key, not the chat account id.** Log
  lines and journal rows then carry nothing belonging to a person. The orphan
  pass is the exception, because an orphan has no key by definition, and it
  says so.
- **The log is `async`.** A synchronous seam forces every implementation that
  has to serialise its lines into a lock, and lines that arrive out of order
  cannot be used to reconstruct what happened. An `async` method lets a log be
  an actor.
- **Chain reads pass `RequestCaller.system`.** A sweep is not a person: it
  cannot type fast, it is bounded by its batch size and its interval, and
  rationing it against one member's share would break the product's main job
  in order to protect it.
- **One batched read for the whole pass.** Reading per member would read each
  pool's reserves once per member, which is one request per person for a
  number that does not change between them.
- **A snapshot decides; a re-read writes.** The pass reads the records once,
  then spends minutes on the chain and the chat service, so everything it
  believes is that old by the time it writes. Both directions of a record
  changing underneath it take roles off a real person, so both are closed by
  reading again at the last possible moment: the member's accounts
  immediately before the per-member write, and the whole record list
  immediately before the orphan filter. The second is a union with the first,
  because a second reading can only ever protect somebody; the halving guard
  keeps comparing the opening snapshot, so the check it performs is unchanged.
- **The re-check before a write refuses only on a positive fact.** An
  emptied account list holds the member; a store that will not answer does
  not. Everywhere else here an unread fact holds roles, but here the decision
  has already been made from a complete chain reading, so holding on a
  storage hiccup would be the demotion rather than the protection.
- **A pass is not a child of the loop.** `stop()` cancels the loop, and
  cancellation reaches every child: a cancelled pass throws at the first real
  chat call and writes down every member it had not reached as missed, whose
  sentence blames a permission problem at the chat service. An ordinary
  redeploy would then put an outage that never happened into the one record
  SEE-2 and SEE-5 exist to make trustworthy. An unstructured task does not
  inherit cancellation, which is the whole of the fix.
- **The member's own account list is deduplicated too.** `addresses(of:)`
  deduplicates what is asked of the chain, and that was originally read as a
  budget concern. It is not only one: walking the member's list unfiltered
  afterwards looks the duplicate up twice in the batch and sums the same
  balance twice, which promotes somebody on money they do not have.
- **Balances are written back only from complete readings.** A short figure
  written back becomes the stored figure the linking arithmetic adds to next
  time, so one bad minute would outlive itself.

## Deliberate Differences From The Original

- The original kept a cached balance to fall back on when a read failed, and
  used a `fromCache` flag to say so. Here the fallback is not needed: an
  unread fact holds the roles it decides, so there is nothing to substitute
  and nothing to flag. What replaces it is `unknowns`, which names the fact
  rather than the freshness.
- The original recorded "when the last sweep spent its requests" in a separate
  state row. Here the journal's own record carries the start, so the restart
  delay reads the record that already exists.
- The original's per-member work happened one at a time with a fixed pause
  between members. Here members are handled in batches with a pause between
  batches, which is the same brake with fewer round trips.
- Test mode is not carried across. The original used it to skip the write; a
  host that wants a dry run supplies a gateway that reports and does not
  write, which is a seam that already exists rather than a flag inside the
  money path of roles.
