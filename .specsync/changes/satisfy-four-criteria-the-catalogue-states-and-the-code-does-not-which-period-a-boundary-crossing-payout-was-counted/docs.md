---
change: satisfy-four-criteria-the-catalogue-states-and-the-code-does-not-which-period-a-boundary-crossing-payout-was-counted
artifact: docs
---

# Docs

Three module contracts move, the intent catalogue gains two sentences, and four
top level documents have a claim in them that stops being true. Everything here
lands in the same pull request as the code, because that is the repository's own
rule: "A module's spec lives in `specs/<module>/` and changes in the same pull
request as the code it describes, never after" (`AGENTS.md`, "The order of
work").

The one document this change is mostly about is the one nobody reads until
something has gone wrong. An operator halfway through a twenty six week schedule
opens their store with `sqlite3` and wants to know which week epoch 14 was
charged to. Every edit below is judged by whether it helps that person, and by
whether the next contributor can tell what was decided rather than having to
infer it from a diff.

## The intent catalogue

### `hi/run.md`

RUN-11 is one sentence with no sub-criteria: "No one member, however fast they
type, can spend the day's budget for reading the chain on their own." It says
nothing about what happens when they reach their share, and it says nothing
about the two callers that are not members at all. This change decides both.

**No `hi/` file is edited by this change.** `context.md` and `plan.md` both say
the catalogue is the authority and is not being touched here, and a criterion
is drafted, agreed with the person and only then built (`hi/AGENTS.md`). So the
two sentences below are drafts raised for that conversation, to be landed by a
workspace of their own, and until they land no test and no spec row may cite
them: an id the catalogue does not have is a citation nobody can follow.

- **RUN-11.a** When somebody reaches their share for the day they are told so
  and told when it comes back, and everybody else carries on unaffected. The
  bot does not stop, and it does not make them wait for tomorrow's answer to
  arrive tomorrow.
- **RUN-11.b** The work the bot does for itself, the sweep of everyone's roles
  and a payout, is not one person's share and is never refused as though it
  were.

Ids are appended and never reused, and `hi check` is run after the merge because
two branches can pick the same id and git will merge both in silence
(`hi/AGENTS.md`). Until then everything this change builds is cited against
RUN-11 itself, which exists and says enough.

SPEND-9.c, RUN-10.a and SEE-1.b are already written, already agreed, and must
not be reworded. Rewording a criterion so the code satisfies it is the failure
mode this whole directory exists to prevent, and it is the one to watch for on
SEE-1.b, where the obvious temptation is to narrow "the check" to mean only the
part of the check that happens to be cheap.

### `INTENT.md`

The family index counts criteria: "[run](hi/run.md): RUN (17 criteria)". It is
generated from `hi/`, so it moves with the two sub-criteria if and when they
land in their own workspace, and not in this change. Nothing in that file moves
here.

## `specs/reserve/`

### `reserve.spec.md`

- **Public API.** Every exported symbol is listed in source order, so
  `ReserveEpochCharge` gets a row and so do the new members on
  `ReserveEpochRecord` and `ReserveEpochOutcome`. The charge's row has to say,
  in one line, that its period is the **spending ceiling's** period and not the
  cadence period, because those are two different facts that are the same string
  for most hosts and the table is where a reader finds out.
- **The rename.** `ReserveEpochOutcome.periodKey` and the runner's parameter are
  renamed to say cadence. Both rows in the table move, and the change log says
  why in one sentence: the two senses of "period" otherwise sit on the same line
  of the same report, and this repository has already retired a criterion over
  two things sharing one word (`Sources/Chain/DailyRequestBudget.swift:5` to
  `:11` tells that story about budget and cap).
- **Invariants.** Three new numbered entries. First: an epoch record names every
  spending period the epoch was measured against, in the order it was measured,
  and the ordinary epoch names exactly one. Second: the charge is written after
  the limits check and before the first claim, for the same reason the claim is
  written before the payment, so a crash leaves a record of the measurement
  rather than losing it at the moment somebody starts looking. Third: a run
  against no stated limits records no charge, which is the honest answer and
  also the limit of what this change delivers.
- **Invariant 9a needs a sentence, not a rewrite.** It currently ends by
  explaining that a long epoch crossing the boundary is the milder case and that
  no figure available before the run can rule it out. That argument stands. What
  changes is the end of it: the crossing is no longer only reasoned about, it is
  recorded, and the record is what an operator reads afterwards. One sentence,
  citing SPEND-9.c.
- **Behavioral Examples.** One new scenario, and it is the one that carries the
  whole change: given an epoch that paid three of eight recipients before the
  machine stopped, when it is resumed in the following week, then both weeks are
  named on the record in the order they were charged, with what each one
  committed, and the ceiling each was measured against. Written in the given,
  when, then shape the other six use.
- **Change Log.** One row, dated, saying that the epoch record now names the
  periods it was charged to, and that a record written before this build reads
  as a period nobody wrote down rather than as no period at all.

### `specs/reserve/requirements.md`

A new `REQ-reserve-009` with a SHALL statement and acceptance criteria, citing
SPEND-9.c and SPEND-9.a. The statement has to be specific enough to be wrong:
that the module SHALL record, on the durable epoch record, an ordered entry per
run that was measured against stated spending limits, naming the period key of
those limits and the whole-unit figure they were checked for, written before the
first payment of that run, and SHALL NOT derive the period from a clock of its
own. The last clause matters because invariant 13 says the module reads no clock
for any decision and the easy implementation of a period key is
`ReservePeriod.isoWeek(Date())`.

The acceptance criteria must also state the negative, or the requirement
over-promises: a run against no stated limits records nothing, so this
requirement answers SPEND-9.c only for a host that states limits.

Also add a user story in the operator's voice, in the style of the existing
ones: as an operator reconciling a weekly ceiling, I want the record to tell me
which week a payout that ran past midnight was counted against, rather than
having me work it out from two timestamps and a guess about my own timezone.

### `specs/reserve/testing.md` and `context.md`

`testing.md` gains the new runner and store tests by name in its test table, and
new rows in "Edge Cases & Boundary Conditions": an epoch resumed in the next
period, an epoch run against no limits, a record written before the field
existed, a charge that differs from what was paid. `context.md` records the two
decisions and why, because both are ones a later contributor will want to
reopen: a list rather than a single field, since a single field cannot describe
an epoch measured twice without lying about one of them and that epoch is the
case the criterion is about; and the ceiling's period rather than the cadence
period, since SPEND-9 is about a ceiling and the cadence key already has a home.

## `specs/store/`

### `store.spec.md`

- **Public API.** `StoreTable` grows a name if the charges become their own
  table, and the new name has to be listed there because the forgetting reports
  rows by table and reads the same whichever backend is running.
- **Invariants.** The persistence half of the reserve invariant: a store returns
  the charges in the order they were written, and a row written before this
  build reads as no charges rather than as an error. The second half is the one
  to write carefully, because it is the only exception anybody is allowed to the
  rule that an unreadable row throws, and it is not really an exception: an
  absent optional field is not an unreadable row. Saying that explicitly is what
  stops the next contributor "fixing" the decoder.
- **Behavioral Examples.** The existing "an operator takes a newer build, then
  goes back to the old one" scenario stays exactly as it is, and gains nothing,
  because it is already the promise this change has to keep. A new scenario for
  the upgrade: given a file written by the previous build in the middle of a
  schedule, when the new build opens it, then a copy is taken first, the pending
  migration applies, every epoch row is still there, and the epochs it already
  paid read as charged to a period nobody recorded.
- **Error Cases.** No new row unless the storage shape adds a failure. If the
  charges become a new table, the table name appears in `unreadableRow`
  messages and nothing else changes.
- **Change Log.** One row naming the new schema version and what it adds.

### `specs/store/requirements.md`

`REQ-store-016`, citing SPEND-9.c from the storage side: the store SHALL persist
and return the epoch charges in order, and SHALL read an epoch written before
the charges existed as an epoch with none, rather than throwing or inventing
one.

### `specs/store/testing.md`

The conformance behaviours are listed there by name, so the new ones go in, with
the note that each one is three runs rather than one: the in-memory store and
both SQLite configurations. The migration test in `SQLiteFileTests` gets a row.

## `specs/chain/`

This spec carries two of the four criteria and takes the most editing.

### `chain.spec.md`

- **Public API.** Rows for the caller token type, for the reserve methods that
  now take a caller, for the new error case, and for the health assembler. Two
  of these rows are doing real work and should not be written as restatements
  of the symbol name:
  - The caller row says what a caller is **not**: not a chat account id, not
    anything the caller chose for themselves, and not optional. `Chain` cannot
    name a member, because `Store` depends on `Chain` and not the other way
    round, and nothing below the chat boundary holds an identifier that came
    from a person (`AGENTS.md`, "Rules that bite").
  - The health assembler row says that it is pure and that nothing on its path
    reserves a request or touches an `AccountDataSource`.
- **Invariants.** Three new ones:
  1. A caller's requests count against both that caller's allowance and the
     day's budget, and the allowance is a share of that same day's budget, so an
     instance with no day budget has no shares. That last clause is the one to
     write plainly rather than leave implicit, because the default configuration
     has no day budget and a reader should not have to work out that the default
     configuration is therefore unprotected.
  2. Reaching a share refuses that caller and nothing else. It is not a pause,
     it does not spend anything, and it does not appear in the notice buffer,
     which is reserved for things an operator has to act on.
  3. A health answer is assembled without reserving a request and is still
     produced once the day's budget is spent. The provider proof probe is
     outside the governor on purpose, and the reason is already written at
     `Sources/Chain/ProviderProofProbe.swift:22`: a check that goes dark exactly
     when the budget runs out is dark at the moment somebody is looking at it.
- **Behavioral Examples.** Two new scenarios, in the file's existing shape:
  - Given a member who has used their share for the day, when they run the
    command again, then they are told when their share comes back, the next
    member's command still works, and nothing about the instance is paused.
  - Given an instance whose day's budget is spent and whose breaker is tripped,
    when the health check is asked, then it answers, says the budget is gone and
    when it returns, and still reports the instance as working, because it is.
- **Error Cases.** A row for the share refusal, naming that it is neither
  `requestBudgetSpent` nor `requestBudgetCannotCover`. That table already draws
  precisely this distinction between the two existing refusals and the third one
  belongs beside them.
- **Change Log.** Two rows: the per-caller share, and the health answer that
  costs nothing. The first is source-breaking and says so.

### `specs/chain/requirements.md`

Two new entries:

- `REQ-chain-020`, citing RUN-11, and the two sub-criteria only if they have
  landed by then: the governor SHALL
  refuse a member caller who has drawn their share of the day's budget, without
  pausing the instance, without spending from the day's budget and without
  affecting any other caller; SHALL refill that allowance over the day rather
  than holding it until the next one; and SHALL apply no share to the
  instance's own work. The acceptance criteria say plainly that with no day
  budget there is no share, so nobody reads the requirement as a promise it does
  not make.
- `REQ-chain-021`, citing SEE-1.b and SEE-1.a: the module SHALL offer a health
  answer assembled without reserving a request, which still answers once the
  day's budget is spent, and which reports a spent budget as a fact in the body
  rather than as a failing check.

Two user stories to match, in the operator's voice. The existing file already
has the SEE-1 story ("a health check that means the instance is working rather
than that a process is listening"), so SEE-1.b extends it rather than repeating
it. The RUN-11 story is new: as an operator, I want one impatient member to be
able to use up their own share and nobody else's, without me finding out because
the roles stopped moving.

### `specs/chain/testing.md` and `context.md`

`testing.md` gains `CallerShareTests.swift` in the test table, new rows in the
"Requirement Coverage" table for the two new requirements, and new
"Edge Cases & Boundary Conditions" rows: an allowance that refills rather than
running out for the day, an idle caller holding a burst rather than the whole
day, no day budget and therefore no share, an all-or-nothing reservation larger
than what a caller has left, a restart handing back one burst, and a health
answer on an instance with no budget configured. Its stated test counts are
already stale (it says 594 for the package and the README says 635), so this is
the pull request that corrects them rather than adding to the drift.

`context.md` records the arguable decisions and their reasons, because these are
the ones a future contributor will want to reopen: a share expressed as a
percentage of the day's budget rather than an absolute count, a burst alongside
it because "however fast they type" is a rate problem and a plain quota locks a
member out for the rest of the day, an allowance held in memory rather than
persisted per member per day, and no share at all when no day budget is set. The
last one is the one with a visible cost: the package's default configuration has
no day budget, so the default configuration has no per-caller brake either.

## `README.md`

- **The `Chain` section** says today that there are two brakes. There are now
  three, and the third is a different kind: the first two bound how hard the
  instance reads, and the third bounds how much of that one person can cause.
  Two or three sentences, saying which caller has a share and which work does
  not, because a reader who only ever reads the README should not be surprised
  later by a sweep that is exempt.
- **The same section** gains a sentence on the health answer: the instance can
  say whether it is working without spending any of the budget it is reporting
  on, and it still answers once that budget is gone. Keep it to the claim; the
  endpoint is not here yet.
- **The State section** quotes `swift test # 635 tests in 47 suites`. That
  number moves, and the sentence below it about the conformance suite being one
  test with thirty three behaviours run against three backends moves with it.
- **"What is missing"** must keep saying there is no health surface, and should
  now say who owns it: the answer can be assembled, and nothing serves it,
  because there is no executable. That sentence is the anti-dote to the failure
  this change was written to avoid, where two changes each assume the other
  builds the endpoint.

## `AGENTS.md`

- **"Where things live"** quotes the same test count as the README. Both move
  together or they contradict each other within a week.
- **"Rules that bite"** gains two lines, in the voice of the ones already there,
  which are all consequences of something that went wrong rather than style
  preferences:
  - Every read of the chain says whose it is. There is no default caller,
    because a default is silent either way: default to a member and the sweep
    gets throttled, default to the instance and the next command written is
    unlimited.
  - Nothing on the health path spends a request. A check that costs the thing it
    is checking on is a check nobody can run when it matters.

## `CHANGELOG.md`

Everything goes under `Unreleased`, and the entries are written for somebody
deciding whether to take the change, not for somebody reading the diff.

- **Added**: the epoch record naming the periods it was charged to; the
  per-caller share of the day; the health answer that can be assembled without
  spending a request.
- **Changed**, and this section exists precisely for these, since the file
  already keeps a source-breaking list with the reason for each:
  - `ReserveEpochRecord` gains a field and `ReserveEpochOutcome.periodKey` is
    renamed, so a memberwise initialiser call and any reader of that property
    written against the old shape no longer compile. Stated with the reason: the
    record is the only durable thing an operator can read after the fact, so the
    period belongs on it and not only on the returned outcome, and the rename is
    what stops the cadence period and the ceiling's period sharing a word on the
    same report.
  - The store schema gains a version. A file written by this build is refused by
    the previous one, by name, pointing at the copy taken before the migration.
    That is the existing promise being kept, not a new hazard, and saying so is
    the difference between an operator rolling back calmly and one thinking the
    file is damaged.
  - `RequestGovernor`'s reserve methods take a caller. Breaking on purpose: a
    defaulted parameter would have made the sweep or the next new command wrong
    in silence.
  - A new `ChainError` case, which breaks an exhaustive switch. The file has
    already had to say this twice about `spendLimitsExpired` and
    `requestBudgetCannotCover`, so the sentence has a house style to follow.
- **Known gaps**: the existing line says there is no way to ask a running
  instance what it has been reaching, because there is nothing running. It stays,
  and gains the half that is now true: the answer can be assembled, and nothing
  serves it yet.

## `docs/WHAT-IT-TALKS-TO.md`

This document is derived from the source and a pull request that adds an
outbound call, a host, a dependency or a secret edits it in the same pull
request. This change adds none of the four, and the document should say so
rather than being left silent:

- **"The provider proof probe"** gains a sentence: the probe is the only network
  call on the health path, it is outside the day's budget on purpose, and
  assembling the answer makes no request at all. A reader checking "does asking
  whether the bot is alive cost me anything with my provider" currently has to
  work that out from two source files.
- **"Secrets, and everything else it reads"** gains both new environment
  variables, the share and the burst, in the same table as the other brakes,
  with their defaults written out and the sentence that neither does anything
  unless a day budget is set. Every number an operator can set is listed there,
  and a brake whose defaults are undocumented is the worst of both.
- The grep commands in that file are claims a reader can run. None of them
  changes, because no new host, no new outbound method and no new secret is
  added, and the pull request should confirm that by running them rather than by
  assuming.

## What must not change

- The wording of SPEND-9.c, RUN-10.a, RUN-11 and SEE-1.b. The code moves to meet
  them.
- Any id in `hi/`. Appended, never reused, never renumbered.
- The text of the shipped store migrations. They are fingerprinted
  (`Sources/StoreSQLite/SchemaMigration.swift:40`), so an edit makes every
  existing file refuse to open. New schema arrives as a new migration.
- The claim in `ReserveCoding` that an unreadable row throws rather than reading
  as empty (`Sources/Reserve/ReserveCoding.swift:33`). A new optional field is
  not an exception to it and the docs should not let it read as one.
- Anything naming the private project this was ported from, and any real
  address, asset id, chat snowflake, personal path or live URL. This repository
  is public and the specs and the changelog are part of it.

## What a reader should be able to answer afterwards

- **An operator reconciling a ceiling:** which period did the payout that ran
  past midnight count against, and how much landed in each. From the record,
  through `reserve.spec.md` and the store's table names.
- **An operator whose members are complaining:** why was one member refused
  while everyone else was fine, when does their share come back, and is the bot
  paused. From `chain.spec.md`'s error cases and the README's `Chain` section.
- **An operator upgrading:** what does the new version change about my file, can
  I go back, and where is the copy. From the store spec's scenarios and the
  changelog.
- **A contributor adding the next command:** whose share does this read count
  against, and do I have to say. From `AGENTS.md`'s rules that bite, in one
  line, before they have read any of the specs.

## Unsettled, and named here so it is not discovered later

- The exact names of the two share variables. `design.md` fixes their meaning
  and their defaults, five percent and a burst of ten, and each default is then
  written out in three places that have to agree: `chain.spec.md`'s public API
  table, `docs/WHAT-IT-TALKS-TO.md`, and the test that pins the literal. The
  existing defaults are pinned that way already, which is the only reason they
  have not drifted.
- Whether the documentation should recommend setting a day budget, given that
  without one there is no share. It reads as advice rather than as contract, and
  this repository has so far avoided telling operators what to choose. The
  compromise on offer is to state the consequence and let them choose, which is
  what the edits above do.
- Whether the health answer's budget section is required by SEE-1.b or is this
  change's judgement. It is judgement: the criterion asks that checking costs
  nothing and still answers, not that the answer carries the budget. It is worth
  doing and it should be recorded as a decision in `specs/chain/context.md`
  rather than presented as the criterion's own demand.
