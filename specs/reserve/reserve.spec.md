---
module: reserve
version: 1
status: active
files:
  - Sources/Reserve/ReserveAsset.swift
  - Sources/Reserve/ReserveAudit.swift
  - Sources/Reserve/ReserveCoding.swift
  - Sources/Reserve/ReserveConfiguration.swift
  - Sources/Reserve/ReserveConfigurationError.swift
  - Sources/Reserve/ReserveEpochOutcome.swift
  - Sources/Reserve/ReserveEpochPlan.swift
  - Sources/Reserve/ReserveEpochRecord.swift
  - Sources/Reserve/ReserveEpochSplit.swift
  - Sources/Reserve/ReserveError.swift
  - Sources/Reserve/ReserveFormatting.swift
  - Sources/Reserve/ReserveGate.swift
  - Sources/Reserve/ReservePayer.swift
  - Sources/Reserve/ReservePeriod.swift
  - Sources/Reserve/ReservePlanner.swift
  - Sources/Reserve/ReserveRecipient.swift
  - Sources/Reserve/ReserveRunner.swift
  - Sources/Reserve/ReserveSchedule.swift
  - Sources/Reserve/ReserveShare.swift
  - Sources/Reserve/ReserveSpendLimits.swift
  - Sources/Reserve/ReserveState.swift
  - Sources/Reserve/ReserveStore.swift
  - Sources/Reserve/ReserveStream.swift
  - Sources/Reserve/ReserveStreamProjection.swift
db_tables: []
depends_on: []
---

# Reserve

## Purpose

Plan and record the payout of a finite reserve, split into named streams, to a
crowd of recipients over a fixed number of epochs. The module computes what is
owed in whole numbers of the asset's smallest unit, keeps the record that stops
a period being paid twice, and refuses whole runs rather than paying part of
one.

It does not send anything, store anything, or read a clock to decide anything.
Payment is a protocol the host implements, persistence is a protocol the host
implements, and periods and timestamps arrive as parameters. The library has no
dependency beyond Foundation and no knowledge of Discord, of any chain, or of
any database.

## Public API

Every exported symbol of the `Reserve` library target, in source order.

| Export | Description |
|--------|-------------|
| `ReserveAsset` | What the reserve is denominated in. |
| `symbol` | What the asset is called on a card: `USDC`, `credits`, `points`. |
| `decimals` | Decimal places. Six means one whole unit is 1,000,000 smallest units. |
| `baseUnitsPerWholeUnit` | Smallest units in one whole unit: ten to the power of `decimals`. |
| `baseUnits` | Whole units converted to smallest units. |
| `wholeUnitsRoundingUp` | Smallest units as whole units, rounded **up**. |
| `format` | The amount written out with every digit intact. |
| `formatWithSymbol` | The amount written out with the symbol after it. |
| `init` | Builds an asset from its symbol and decimal count, refusing more than 19 decimals. |
| `ReserveAudit` | The whole reserve previewed at one moment, having moved nothing. |
| `asset` | What the reserve is denominated in. |
| `reserveBaseUnits` | The whole reserve in smallest units. |
| `selectedSchedule` | The chosen duration, or nil when nobody has chosen one yet. |
| `effectiveSchedule` | The duration the figures below were computed with. Equal to `selectedSchedule` when there is one; otherwise an illustration, and the nil above is what says so. |
| `projections` | One projection per configured stream, in configuration order. |
| `nextEpoch` | The epoch each stream would pay next, keyed by stream id. |
| `spentBaseUnits` | Smallest units already paid out of each allocation. |
| `incompleteRecipients` | Recipients whose eligibility could not be read, per stream. Any is an abort for a live run. |
| `potBaseUnits` | What the paying account holds, or nil when it was not read. |
| `limits` | Spending limits, or nil when they were not read. |
| `projection` | The projection for one stream, if it is configured. |
| `projectedSpendBaseUnits` | Projected full-schedule spend across every stream. |
| `allocationInUseBaseUnits` | Allocation in use across every stream: the round figure before rounding. |
| `projectedResidueBaseUnits` | Rounding across every stream that is never paid. |
| `unusedReserveBaseUnits` | Reserve minus the allocation in use. |
| `nextEpochSpendBaseUnits` | Smallest units every stream pays in the epoch each is next due to run. |
| `nextEpochLimitCostWholeUnits` | Whole units the next epoch charges against a whole-unit limit. |
| `runwayEpochs` | Epochs the pot can still cover at the current counts, or nil when the pot was not read or nothing is due. |
| `epochsRemaining` | Epochs of this schedule no stream has run yet. |
| `totalIncompleteRecipients` | Recipients that could not be read, across every stream. |
| `wouldAbortLiveRun` | True when a live run would abort on an incomplete eligibility list. |
| `ReserveCoding` | Turning ledger values into text and back. |
| `encode` | A value as JSON text. |
| `decode` | JSON text back into a value, **throwing** rather than reading as empty. |
| `ReserveConfiguration` | A finite reserve, split into named streams, paid over a chosen number of epochs. |
| `totalWholeUnits` | The whole reserve, in whole units of `asset`. |
| `totalBaseUnits` | The whole reserve, in smallest units. Nothing may cross this. |
| `streams` | The streams, in the order they were configured. |
| `schedules` | The durations an operator may choose between. |
| `stream` | The configured stream with this id, or a refusal. |
| `schedule` | The configured schedule with this id, or a refusal. |
| `allocationBaseUnits` | One stream's allocation in smallest units. |
| `shareBaseUnits` | Smallest units one slot is owed across a whole schedule, whatever its length. |
| `epochSplit` | How one slot's share is cut into a schedule's epochs. |
| `epochPayoutBaseUnits` | Smallest units one slot is paid in `epoch`, numbered from 1. |
| `project` | What a stream would spend over a full schedule at this eligible count. |
| `audit` | The whole reserve previewed at one moment, before anything moves. |
| `requireWithinDenominator` | Refuses an eligible list the fixed denominator cannot cover. |
| `requireWithinAllocation` | Refuses a planned epoch spend that would cross the allocation. |
| `ReserveConfigurationError` | Why a reserve cannot be configured. |
| `errorDescription` | The refusal written out for a person, naming what does not add up and why it is refused. |
| `unsupportedDecimals` | Ten to the twentieth does not fit in `UInt64`. |
| `amountOverflows` | Converting whole units to smallest units overflowed. |
| `noStreams` | A reserve with no streams has nobody to pay. |
| `duplicateStreamId` | Two streams answering to the same id would share a ledger row. |
| `noSchedules` | A reserve with no selectable durations can never start. |
| `duplicateScheduleId` | Two durations answering to the same id. |
| `invalidEpochCount` | A schedule of zero epochs would divide by zero. |
| `invalidDenominator` | A denominator of zero would divide by zero. |
| `indivisibleShare` | The share does not divide the reserve into whole smallest units, or the arithmetic overflowed. |
| `sharesDoNotSumToReserve` | The streams' shares do not add up to the reserve. |
| `ReserveReceipt` | Evidence that one line was paid. |
| `entry` | What was owed. |
| `reference` | What the payer gave back as proof, a transaction id, a receipt number. |
| `ReserveFailedPayment` | One line that did not get paid, and what happened to its claim. |
| `reason` | What went wrong, for the operator's report. |
| `claimReleased` | Whether the claim was handed back. |
| `ReserveEpochOutcome` | What one run of one epoch actually did. |
| `streamId` | The stream paid. |
| `epoch` | Epoch number, from 1. |
| `periodKey` | The period this run claimed. |
| `perUnitBaseUnits` | Smallest units one slot was paid. |
| `paid` | Lines that were paid, with their evidence. |
| `failed` | Lines that were not. |
| `skipped` | Recipients the plan left out, with reasons. |
| `paidBaseUnits` | Smallest units that actually went out. |
| `isComplete` | True when the run reached the end of the list and closed the epoch. |
| `paidCount` | How many lines were paid. |
| `paidUnits` | Slots paid across every line. |
| `isClean` | True when every planned line was paid. |
| `ReserveSkipReason` | Why a recipient was left out of a planned epoch. |
| `ReserveEpochEntry` | One account's line in a planned epoch. |
| `recipientId` | The person being paid. |
| `account` | Where the payment goes. |
| `units` | Slots this line claims. One for a once-per-recipient stream; the number of unclaimed holdings for a per-unit stream. |
| `baseUnitsAmount` | Smallest units this line pays. |
| `claimedHoldingIds` | The holding ids this line consumes for the epoch. |
| `ReserveSkippedRecipient` | A recipient left out of a plan, and why. |
| `ReserveEpochPlan` | One planned epoch: who is paid, how much, and what it consumes. |
| `entries` | The lines to pay, in account order. |
| `totalUnits` | Slots this epoch claims. |
| `limitCostWholeUnits` | Whole units the epoch charges against a whole-unit limit, rounded up per payment rather than once on the total. |
| `accountAlreadyPaid` | This account already took a payment in this epoch. |
| `recipientAlreadyPaid` | This person was already paid this epoch on another account, and the stream pays once per recipient. |
| `holdingsAlreadyClaimed` | Every qualifying thing on this account was already paid this epoch, somewhere else. |
| `holdsNothing` | This account holds nothing that qualifies. |
| `ReserveEpochRecord` | What one epoch of one stream has already paid. |
| `paidAccounts` | Accounts already paid this epoch. |
| `paidRecipientIds` | People already paid this epoch. A once-per-recipient stream pays a person once however many accounts they spread their holdings across. |
| `startedAt` | When the epoch first claimed anybody. |
| `completedAt` | When the epoch ran to the end, or nil while it is unfinished. |
| `paidAccountSet` | Accounts paid, as a set. |
| `paidRecipientIdSet` | People paid, as a set. |
| `claimedHoldingIdSet` | Holdings claimed, as a set. |
| `claim` | Claims one line's slots, to be called **before** the payment is attempted. |
| `claimingAll` | The record this epoch would end with if every entry were paid. |
| `release` | Gives a claim back after an attempt that provably moved nothing. |
| `ReserveEpochSplit` | How one slot's whole-schedule share is cut into epochs. |
| `epochCount` | Epochs the share was cut for. |
| `perEpochBaseUnits` | Smallest units every epoch pays. The same number in every epoch. |
| `residueBaseUnits` | Smallest units of the share that will not divide. Never paid. |
| `payout` | Smallest units one slot is paid in `epoch`, numbered from 1. |
| `isEven` | True when the share divides evenly and nothing stays behind. |
| `residueNote` | One line an operator can check the arithmetic against. |
| `ReserveError` | Why a reserve epoch cannot be planned, or cannot be paid. |
| `scheduleNotSelected` | No duration chosen yet. Nothing pays until one is. |
| `scheduleLocked` | The schedule has started; the duration is fixed for the rest of it. |
| `unknownSchedule` | A duration nobody configured. |
| `unknownStream` | A stream nobody configured. |
| `epochOutOfRange` | Asked for an epoch outside `1...epochCount`. |
| `scheduleComplete` | Every epoch of this stream has been paid. |
| `tooManyUnits` | More eligible units than the fixed denominator has slots. |
| `allocationExhausted` | Paying this epoch would spend past the allocation. |
| `epochAlreadyPaid` | This epoch is already finished; a second run would pay twice. |
| `nothingToPay` | Nobody left to pay in this epoch. |
| `alreadyRunning` | Another epoch is mid-flight. Two at once would pay everyone twice. |
| `periodAlreadyPaid` | This stream already paid an epoch in this period. |
| `notTheNextEpoch` | Asked to pay an epoch that is not the one the ledger says is next. |
| `overPaymentLimit` | One payment is over the per-payment limit. |
| `overPeriodLimit` | The epoch is over what is left of the period's limit. |
| `ReserveFormatting` | Writing integer smallest units out for a person to read. |
| `grouped` | `1234567` as `1,234,567`. |
| `amount` | Smallest units written as a decimal amount, with no digit lost. |
| `ReserveGate` | The one-at-a-time gate on reserve epochs. |
| `acquire` | True when the caller now holds the gate and must `release()` it. |
| `busy` | Whether an epoch is mid-flight. |
| `ReservePaymentRefusal` | Raised by a payer when an attempt **provably moved nothing**. |
| `ReservePayer` | Who actually moves the value. |
| `spendLimits` | What the paying account may move, or nil when there are no limits. |
| `availableBaseUnits` | What the paying account holds in smallest units, or nil when unknown. |
| `pay` | Pays one line. |
| `ReservePeriod` | Naming the period an epoch was paid in. |
| `isoWeek` | The ISO-8601 week containing `date`, as `2026-W38`. |
| `month` | The calendar month containing `date`, as `2026-09`. |
| `day` | The calendar day containing `date`, as `2026-09-18`. |
| `isoWeekStart` | Midnight UTC on the Monday of the ISO week containing `date`. |
| `isoWeekEnd` | Midnight UTC on the Monday after the ISO week containing `date`. |
| `ReservePlanner` | Works out what one epoch still owes. |
| `configuration` | The reserve being paid out. |
| `eligibleUnits` | Eligible slots in a recipient list, under one rule. |
| `planEpoch` | Plans what one epoch still owes. |
| `planGuardedEpoch` | Plans an epoch and refuses it if it would cross a denominator, an allocation, or an epoch that is already finished. |
| `requireWithinLimits` | Refuses an epoch the paying account's limits cannot carry. |
| `ReserveRecipient` | One account, who it belongs to, and what it is currently known to hold. |
| `id` | The person. Two accounts owned by one person share this. |
| `holdingIds` | Ids of the qualifying things this account is known to hold, unique and sorted so a plan built from the same facts is byte-for-byte the same. |
| `ReserveRecipientList` | Who is payable for one stream, and who could not be read. |
| `recipients` | Every account that could be read, with what it holds. |
| `incompleteRecipientIds` | People with at least one account that could not be read. |
| `ineligibleCount` | People read successfully who hold nothing qualifying. |
| `eligibleRecipientIds` | People with at least one payable account. |
| `requireComplete` | The recipients, or a refusal when anything could not be read. |
| `ReserveRunner` | Runs one epoch, end to end, with all four guards in the right order. |
| `state` | The reserve's state as the store has it. |
| `activate` | Chooses the duration, or refuses because the schedule has begun. |
| `rehearse` | Plans the next epoch and stops, having written and moved nothing. |
| `run` | Pays one epoch of one stream. |
| `ReserveSchedule` | How long the reserve takes to pay out, as a count of epochs. |
| `label` | What a person reads: `six months`. |
| `cadence` | What one epoch is called: `weekly`, `monthly`. Display only, the engine never reads a clock, so the cadence is the host's to enforce. |
| `aliases` | Extra spellings `matches(_:)` accepts. |
| `summary` | One line for a card: `six months · 26 weekly epochs`. |
| `matches` | Whether a typed string names this schedule. |
| `ReserveShare` | One stream's slice of the reserve, as an exact fraction. |
| `numerator` | The top of the fraction. |
| `denominator` | The bottom of the fraction. Never zero. |
| `percent` | `ReserveShare.percent(70)`. |
| `whole` | The whole reserve, for a single-stream configuration. |
| `description` | `70/100` for a card. |
| `ReserveSpendLimits` | What the paying account is allowed to move, in whole units. |
| `maxPerPaymentWholeUnits` | Most one payment may move. |
| `maxPerPeriodWholeUnits` | Most the account may move in one period. |
| `spentThisPeriodWholeUnits` | What has already gone this period, from every source, not just this reserve. That is the point: an ordinary transfer earlier in the same period has already eaten some of the ceiling. |
| `periodEnd` | When the period rolls over, when the host knows. |
| `remainingThisPeriodWholeUnits` | What is left of this period's ceiling. Never negative. |
| `ReserveState` | The reserve's own state: the chosen duration, and what each stream has spent. |
| `scheduleId` | The chosen duration's id, or nil before anybody chooses. |
| `activatedAt` | When the duration was chosen. |
| `completedEpochs` | Epochs each stream has run to the end, keyed by stream id. |
| `lastPeriodKeys` | The period each stream last paid an epoch in, keyed by stream id. |
| `spent` | Smallest units this stream has committed. |
| `paidEpochs` | Epochs finished across every stream. Non-zero locks the duration. |
| `isLockable` | True while the duration can still be changed: before anything has paid. |
| `requireScheduleId` | The chosen duration's id, or a refusal when nobody has chosen. |
| `selecting` | A copy with the duration chosen. Refuses once an epoch has paid. |
| `markingComplete` | A copy with one epoch marked finished, so the next run moves on. |
| `lastPeriodKey` | The period a stream last paid an epoch in, or nil if it never has. |
| `claimingPeriod` | A copy recording that this stream paid an epoch in `periodKey`. |
| `recordingSpend` | A copy with one payment's smallest units added, without closing the epoch. |
| `releasingSpend` | A copy with a recorded spend given back, after an attempt that moved nothing. Never below zero, whatever order the writes land in. |
| `ReserveStore` | Where the ledger lives. |
| `InMemoryReserveStore` | A ledger in memory, for tests and for trying things out. |
| `stateKey` | The row key holding the reserve's state. |
| `epochKey` | The row key holding one epoch's record. |
| `loadState` | The reserve's state, or a fresh empty one if nothing has been saved. |
| `save` | Saves the reserve's state. |
| `loadEpoch` | One epoch's record, or a fresh unpaid one if nothing has been saved. |
| `setRaw` | Writes a row verbatim, for tests that need to see what a corrupt one does. |
| `raw` | Reads a row verbatim. |
| `rowCount` | How many rows exist, for tests that care about write volume. |
| `ReservePayoutRule` | How a stream turns eligibility into slots. |
| `ReserveStream` | One named part of the reserve. |
| `name` | What a person reads on a card. |
| `share` | This stream's fraction of the whole reserve. |
| `rule` | How slots are counted for this stream. |
| `unitName` | What one payable slot is, singular: `member`, `pass`, `seat`. |
| `unitNamePlural` | Plural of `unitName`. |
| `oncePerRecipient` | One slot per recipient, however many units they hold and however many accounts they hold them across. |
| `oncePerHeldUnit` | One slot for every unit held, across every account. |
| `ReserveStreamProjection` | What one stream would spend over a whole schedule, and what it leaves behind. |
| `perUnitShareBaseUnits` | One slot's nominal share: what the denominator entitles it to. |
| `perUnitPaidBaseUnits` | What one slot is actually paid across the schedule. |
| `split` | How that share is cut into epochs. |
| `unusedAllocationBaseUnits` | Allocation for slots nobody claims, plus anything the denominator itself would not divide. Stays in the reserve. |
| `unusedSlots` | Denominator slots no eligible unit claims. |
| `overflowUnits` | Eligible units beyond the denominator. Non-zero means the stream cannot pay them all, and a live run will refuse rather than pay a short list. |
| `undividedAllocationBaseUnits` | What the denominator would not divide: `allocation % denominator`. |
| `staysInReserveBaseUnits` | Everything that stays behind: unclaimed slots plus rounding residue. |
| `perUnitPayoutBaseUnits` | Smallest units one slot is paid in `epoch`. |
| `epochSpendBaseUnits` | Smallest units the whole stream pays in `epoch` at the current count. |
| `epochLimitCostWholeUnits` | Whole units this stream's `epoch` charges against a whole-unit limit. |

## Invariants

1. Every monetary figure is a whole number of the asset's smallest unit. No
   `Double`, no `NumberFormatter`, and no locale-sensitive formatting is used
   anywhere in the module.
2. A stream divides its allocation by its fixed `denominator`, never by the
   number of recipients eligible on the day. An unclaimed slot stays unclaimed
   and never enlarges another recipient's payment.
3. The streams' shares sum to exactly the reserve in smallest units, and each
   share divides into whole smallest units, or `ReserveConfiguration.init`
   throws before anything exists that could pay anybody.
4. Every epoch of a schedule pays the identical per-slot figure. The remainder
   that will not divide by the epoch count is reported as
   `ReserveEpochSplit.residueBaseUnits` and is never paid. Paid plus residue
   equals the per-slot share exactly.
5. `ReserveRunner.run` holds `ReserveGate` for the whole epoch. One gate covers
   every stream, because `ReserveState` is a single value saved whole and two
   concurrent saves would lose one stream's completed epoch.
6. A stream pays at most one epoch per period key. The period is an ISO week, a
   month, or a day from `ReservePeriod`, never a timestamp, so two runs inside
   one period collide and a missed period is still paid late.
7. Each entry's claim is written to the store and the spend recorded in state
   **before** `ReservePayer.pay` is called. A crash between the two under-pays
   and leaves the value in the reserve.
8. A claim is released only for `ReservePaymentRefusal`, which asserts that
   nothing moved. Any other error keeps the claim, because a payment that might
   have gone through must never be retried.
9. Spending limits are checked against the whole planned epoch before the first
   payment, and the period limit is measured against
   `ReserveSpendLimits.remainingThisPeriodWholeUnits` rather than the raw
   ceiling. Nothing is clamped to fit.
10. An epoch is closed only by a loop that ran to the end, and only if it is the
    epoch the ledger says is next. `ReserveState.markingComplete` refuses to
    move backwards or to skip, so an epoch can be finished but never skipped.
11. `ReserveRecipientList.requireComplete` aborts the run when any recipient
    could not be read. A list with holes pays nobody.
12. `ReserveRunner.rehearse` plans through the same guards a live run uses,
    writes nothing, claims no slot, and refuses with the same error a live run
    would raise.
13. The module reads no clock of its own for any decision. `now` and the period
    key are parameters, so every figure in the test suite is pinned.

## Behavioral Examples

### Scenario: A stream pays the same figure in the first and last epoch

- **Given** a reserve of 10,000,000,000 whole units of a six-decimal asset,
  split 70 percent to a once-per-recipient stream with denominator 1,000 and
  30 percent to a per-unit stream with denominator 4,096, over 26 epochs
- **When** `epochPayoutBaseUnits` is asked for epoch 1 and for epoch 26 of the
  once-per-recipient stream
- **Then** both answer 269,230,769,230 smallest units, and 26 payments plus the
  20 smallest units of residue equal the per-slot share of 7,000,000,000 whole
  units exactly

### Scenario: A second concurrent run is refused rather than queued

- **Given** an epoch already running under `ReserveRunner.run`
- **When** a second `run` is started for any stream of the same reserve
- **Then** it throws `ReserveError.alreadyRunning` immediately, writes nothing,
  and pays nobody

### Scenario: A half-finished epoch resumes without paying anyone twice

- **Given** an epoch whose record already holds claims for some recipients
- **When** the same epoch is run again
- **Then** the planner skips every already-claimed recipient with
  `ReserveSkipReason`, and only the remaining slots are paid

### Scenario: An incomplete eligibility list pays nobody

- **Given** a `ReserveRecipientList` with one or more `incompleteRecipientIds`
- **When** the epoch is run
- **Then** it throws `ReserveError.incompleteRecipients` before any claim is
  written, and `ReserveAudit.wouldAbortLiveRun` reports the same state on a
  preview

## Error Cases

| Condition | Behavior |
|-----------|----------|
| Asset decimals above 19 | `ReserveConfigurationError.unsupportedDecimals` from `ReserveAsset.init` |
| Whole units that overflow 64 bits when scaled | `ReserveConfigurationError.amountOverflows` |
| No streams, or no schedules | `ReserveConfigurationError.noStreams` / `.noSchedules` |
| Two streams or two schedules sharing an id | `.duplicateStreamId` / `.duplicateScheduleId` |
| A denominator of zero, or a schedule of zero epochs | `.invalidDenominator` / `.invalidEpochCount` |
| A share that leaves a remainder in smallest units | `.indivisibleShare` |
| Shares that do not sum to the reserve | `.sharesDoNotSumToReserve` |
| Paying before a duration is chosen | `ReserveError.scheduleNotSelected` |
| Changing the duration after an epoch is paid | `ReserveError.scheduleLocked` |
| An unconfigured stream or schedule id | `.unknownStream` / `.unknownSchedule` |
| An epoch outside `1...epochCount` | `.epochOutOfRange` |
| Every epoch of the stream already paid | `.scheduleComplete` |
| More eligible units than the denominator has slots | `.tooManyUnits`, aborting the run |
| A planned epoch that would cross the allocation | `.allocationExhausted` |
| An epoch already closed, or not the next one | `.epochAlreadyPaid` / `.notTheNextEpoch` |
| A second run while one is in flight | `.alreadyRunning` |
| A second run inside one period key | `.periodAlreadyPaid` |
| An eligibility list with holes | `.incompleteRecipients`, nothing sent |
| Over the per-payment or remaining per-period limit | `.overPaymentLimit` / `.overPeriodLimit`, aborting rather than clamping |
| A stored row that will not decode | The store throws; it never reads as an unpaid epoch |
| A payer that proves nothing moved | `ReservePaymentRefusal`, and the slot is handed back |
| A payer that fails ambiguously | The claim is kept and the value stays in the reserve |

## Dependencies

- Foundation, and nothing else. The module has no package dependencies.
- The host supplies `ReserveStore` for persistence and `ReservePayer` for
  payment. `InMemoryReserveStore` ships with the module for tests.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-09-18 | maintainers | Spec written for the shipped `Reserve` library target. |
