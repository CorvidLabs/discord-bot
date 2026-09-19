---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
module: chain
---

# Semantic delta: chain

## Added

### REQUIREMENT REQ-chain-020

Every reservation of a request SHALL name the caller it is made for, with no
default value, and that caller SHALL be a closed set of cases separating work
done on behalf of a member from the instance's own work. A member caller
SHALL be held to a share of the day's request budget, configured as a
percentage of that budget together with a maximum burst, and that share
SHALL refill as the day passes rather than being withheld until the next day.
A member caller who has drawn their share SHALL be refused at once with a
typed error carrying the instant at which their next request would be allowed,
and SHALL NOT be queued. A refusal at the share SHALL spend nothing of the
day's budget, SHALL NOT pause the instance, SHALL NOT appear in the notice
buffer an operator drains, and SHALL leave every other caller unaffected. The
instance's own work SHALL carry no share, because a sweep, a scheduled payout
and anything an operator ordered are already bounded by their own batch and
interval and are not one person typing. Where no daily request budget is set
there SHALL be no share at all, since there is no day's budget to take a part
of, and this SHALL be stated where an operator reads the defaults rather than
left to be discovered. A configured share above one hundred percent SHALL be
refused at boot, naming the variable to correct. A pause SHALL be checked
before a share, so an instance that is refusing everybody tells every caller
the same reason. The caller identifier SHALL be opaque to this module,
SHALL NOT be logged, persisted or repeated in an error or a notice, and this
module SHALL bound one caller only, never a crowd.

The tracking itself SHALL be bounded in memory. A caller whose share has
refilled completely carries no information and SHALL be forgotten, so that the
table holds only callers currently drawing on the day and cannot grow with
every member who touched the bot since midnight. Forgetting a caller
SHALL NOT hand them a fresh share beyond what refilling had already restored.
Where the number of tracked callers reaches a bound, a caller not already
tracked SHALL be refused rather than admitted untracked, and a caller already
tracked SHALL NOT be evicted to make room, because evicting the caller who is
drawing hardest is the way an attacker buys themselves a new allowance.

Throttling SHALL be visible to an operator in the same snapshot every other
budget figure comes from, naming how many callers are currently held and how
much of the day their shares have taken. A guard that refuses quietly is one
an operator cannot tell from a provider outage, and the negative rule above,
that a share refusal writes no notice, is about not drowning the notice buffer
rather than about hiding the fact that throttling is happening.

Acceptance Criteria
- `CallerShareTests` proves one member caller exhausts their own share and is
  then refused, while the day's counter shows only what they actually took
  (RUN-11).
- `CallerShareTests` proves a caller refused at their share leaves a second
  caller and the instance's own work succeeding at the same instant (RUN-11).
- `CallerShareTests` proves reaching a share is not a pause: no pause is
  reported by the snapshot and no notice is recorded, however many times the
  caller is refused (RUN-11, SEE-5).
- `CallerShareTests` proves a share refills during the day, refills only to
  its burst however long a caller has been idle, and that an all-or-nothing
  reservation larger than what a caller has left takes nothing from the caller
  and nothing from the day (RUN-11, SEE-9).
- `CallerShareTests` proves the tracking is bounded: a caller whose share has
  refilled is no longer held, a newcomer at the bound is refused rather than
  admitted untracked, and a caller already drawing is never evicted to make
  room for one arriving (RUN-11).
- `CallerShareTests` proves the snapshot an operator reads names the callers
  currently held and what their shares have taken, so throttling cannot be
  happening invisibly (RUN-11, SEE-9).
- `CallerShareTests` proves that with no daily budget configured no caller is
  ever refused by a share, and that a restart hands a caller at most one fresh
  burst while the day's own count is restored from the store (RUN-11,
  RUN-8.b).
- `ChainConfigurationTests` proves the share and the burst take their
  documented defaults as literals, and that a share above one hundred percent
  refuses the boot naming the variable (ADOPT-1, ADOPT-2).

### REQUIREMENT REQ-chain-021

This module SHALL offer a health answer that can be assembled without
reserving a request from the day's budget and without touching any
`AccountDataSource`, and that answer SHALL still be produced once the day's
budget is spent or the provider has refused. A spent budget or a tripped
breaker SHALL be reported as a field of the answer, naming which of the two it
is and when reading resumes, and SHALL NOT change the health status, which
stays a statement about whether every declared component has been reached. The
budget figures on the answer SHALL come from the same `RequestBudgetSnapshot`
every other surface reports, so a health answer and a status reply cannot
disagree about what is left. An instance for which no provider proof is
configured SHALL produce an answer that opens no socket of any kind, and a
proof that could not be taken SHALL leave the answer without proof rather than
failing it.

Acceptance Criteria
- `ChainHealthTests` proves the governor's snapshot is identical in every
  field before and after an answer is assembled, and that a recording data
  source double is never called (SEE-1.b).
- `ChainHealthTests` proves an answer still comes back with the day's budget
  spent and the breaker tripped by a provider refusal, naming which it is and
  when it ends, with the status still reporting reachability (SEE-1.b,
  SEE-1.a).
- `ChainHealthTests` proves an instance with no budget configured reads as
  having no budget rather than as having none left (SEE-9).
- `ChainHealthTests` proves an answer assembled for an instance with no proof
  configured makes no call at all, and that a proof which failed leaves the
  answer without a provider section and invents nothing (SEE-1.b, SEE-10.a).

### REQUIREMENT REQ-chain-022

Lifting a pause by hand SHALL return no part of the day's spent request
budget. The day's count, what is left of it, the configured limit and the
start of the day SHALL each be unchanged across an unpause, whichever cause
tripped the pause and however many times the pause is lifted, including when
there was no pause to lift. An unpause SHALL NOT write to
`RequestBudgetStore`, so that a restart cannot read back a count an unpause
lowered, and SHALL return no part of any caller's share. The tests holding
this SHALL name the criterion they protect, so that a later author can see
they are looking at a promise rather than at behaviour that holds by accident.

Acceptance Criteria
- `RequestGovernorTests` proves the whole budget snapshot is equal either side
  of an unpause that follows a provider quota refusal, with the day's counter
  part way through rather than at its ceiling (RUN-10.a).
- `RequestGovernorTests` proves that lifting the same pause many times in a
  row at one pinned instant moves nothing, and that lifting a pause that was
  never set is not a refund either (RUN-10.a).
- `RequestGovernorTests` proves an unpause writes nothing to the budget store,
  and that a second governor restoring from that store starts with the same
  count already spent (RUN-10.a, RUN-8.b).
- `CallerShareTests` proves a caller who has drawn their share is still at
  their share after an unpause (RUN-10.a, RUN-11).

### REQUIREMENT REQ-chain-023

`ProviderProofProbe` SHALL offer a read that answers from the proof it already
holds, making no request and leaving its cache exactly as it was, and the
assembly that promises to spend nothing SHALL take its proof from that read
rather than from the one that refreshes a stale value. A held proof that has
passed its configured lifetime SHALL be reported as absent by that read rather
than refreshed by it, which is the rule this module already follows for a
stale proof.

Acceptance Criteria
- `ChainHealthTests` proves the held read makes no probe call and leaves the
  cached proof unchanged (SEE-1.b).
- `ChainHealthTests` proves a proof past its lifetime reads as absent through
  that read rather than being refreshed by it (SEE-1.b, SEE-10.a).
- `ChainHealthTests` proves the assembled answer takes its proof from that
  read, so nothing on the path that promises to spend nothing can make a
  request (SEE-1.b).
