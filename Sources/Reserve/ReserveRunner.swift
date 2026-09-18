import Foundation

/// Runs one epoch, end to end, with all four guards in the right order.
///
/// The arithmetic elsewhere in this package is pure and easy to trust. This type
/// is where it meets a store that can fail and a payer that can hand value to
/// strangers, and it exists so that the ordering below lives in exactly one
/// place rather than being re-derived by every host.
///
/// The four guards, and why each was needed:
///
/// 1. **One epoch at a time** (``ReserveGate``). Reading the ledger, planning
///    and paying all suspend. Two overlapping runs see the same untouched ledger
///    and pay everybody twice.
/// 2. **One epoch per period** (``ReserveState/lastPeriodKeys``). Without it the
///    whole schedule can be spent in an afternoon by running the command over
///    and over; the per-epoch record would not object, because each run is a
///    different epoch.
/// 3. **The claim is written before the payment.** The crash window then
///    under-pays and leaves value in the reserve instead of paying somebody the
///    ledger has no record of.
/// 4. **Limits are checked before the first payment.** An epoch that pays a
///    hundred and eleven of two hundred recipients is the half-finished payout
///    the whole design exists to prevent.
public struct ReserveRunner: Sendable {

    // MARK: - Properties

    /// The reserve being paid out.
    public let configuration: ReserveConfiguration

    private let store: any ReserveStore
    private let payer: any ReservePayer
    private let gate: ReserveGate
    private let planner: ReservePlanner

    // MARK: - Initializers

    /// - Parameters:
    ///   - configuration: The reserve.
    ///   - store: Where the ledger lives.
    ///   - payer: Who moves the value.
    ///   - gate: The one-at-a-time gate. Injectable so a test can hold it, and
    ///     so a host running several reserves can decide for itself whether they
    ///     share one.
    public init(
        configuration: ReserveConfiguration,
        store: any ReserveStore,
        payer: any ReservePayer,
        gate: ReserveGate = ReserveGate()
    ) {
        self.configuration = configuration
        self.store = store
        self.payer = payer
        self.gate = gate
        self.planner = ReservePlanner(configuration: configuration)
    }

    // MARK: - Public Methods

    /// The reserve's state as the store has it.
    public func state() async throws -> ReserveState {
        try await store.loadState()
    }

    /// Chooses the duration, or refuses because the schedule has begun.
    ///
    /// Changeable until the first epoch is finished and fixed after, because
    /// changing it later would move every remaining payment for everybody.
    @discardableResult
    public func activate(scheduleId: String, now: Date = Date()) async throws -> ReserveState {
        let schedule = try configuration.schedule(id: scheduleId)
        let updated = try await store.loadState().selecting(scheduleId: schedule.id, at: now)
        try await store.save(state: updated)
        return updated
    }

    /// The whole reserve previewed, having moved nothing.
    ///
    /// - Parameter eligible: One recipient list per stream id. A stream with no
    ///   entry is previewed as having nobody eligible.
    public func audit(eligible: [String: ReserveRecipientList]) async throws -> ReserveAudit {
        let current = try await store.loadState()
        let schedule = try current.scheduleId.map { try configuration.schedule(id: $0) }

        var units: [String: UInt64] = [:]
        var nextEpoch: [String: UInt64] = [:]
        var spent: [String: UInt64] = [:]
        var incomplete: [String: Int] = [:]
        for stream in configuration.streams {
            let list = eligible[stream.id]
            units[stream.id] = list?.eligibleUnits(rule: stream.rule) ?? 0
            nextEpoch[stream.id] = current.nextEpoch(stream.id)
            spent[stream.id] = current.spent(stream.id)
            incomplete[stream.id] = list?.incompleteRecipientIds.count ?? 0
        }

        return try configuration.audit(
            schedule: schedule,
            eligibleUnits: units,
            nextEpoch: nextEpoch,
            spentBaseUnits: spent,
            incompleteRecipients: incomplete,
            potBaseUnits: try await payer.availableBaseUnits(),
            limits: try await payer.spendLimits()
        )
    }

    /// Plans the next epoch and stops, having written and moved nothing.
    ///
    /// Plans through the same guards a real run plans through, deliberately: a
    /// rehearsal that agreed with a separate estimate rather than with the
    /// planner would be worse than no rehearsal, because the figure would be
    /// trusted. If a real run would refuse, this refuses with the same error.
    ///
    /// It claims nobody's slot, closes no epoch, counts against no limit and
    /// leaves nothing behind that a later run would skip.
    public func rehearse(
        streamId: String,
        recipients: ReserveRecipientList
    ) async throws -> ReserveEpochPlan {
        let context = try await prepare(streamId: streamId, recipients: recipients)
        if let limits = try await payer.spendLimits() {
            try planner.requireWithinLimits(plan: context.plan, limits: limits)
        }
        return context.plan
    }

    /// Pays one epoch of one stream.
    ///
    /// - Parameters:
    ///   - streamId: The stream to pay.
    ///   - recipients: Who is eligible. A list with holes in it pays nobody.
    ///   - periodKey: Names the period this run belongs to, from
    ///     ``ReservePeriod``. A stream that already paid in this period is
    ///     refused.
    ///   - now: Injected so a test can pin every timestamp.
    public func run(
        streamId: String,
        recipients: ReserveRecipientList,
        periodKey: String,
        now: Date = Date()
    ) async throws -> ReserveEpochOutcome {
        // Guard 1. Refuses rather than queues: a second payout that waits its
        // turn is a second payout nobody asked for.
        guard await gate.acquire() else { throw ReserveError.alreadyRunning }
        do {
            let outcome = try await execute(
                streamId: streamId,
                recipients: recipients,
                periodKey: periodKey,
                now: now
            )
            await gate.release()
            return outcome
        } catch {
            await gate.release()
            throw error
        }
    }

    // MARK: - Private Methods

    /// Everything a run needs before it is allowed to pay anybody.
    private struct PreparedEpoch: Sendable {
        let schedule: ReserveSchedule
        let epoch: UInt64
        let state: ReserveState
        let record: ReserveEpochRecord
        let plan: ReserveEpochPlan
    }

    private func prepare(
        streamId: String,
        recipients: ReserveRecipientList
    ) async throws -> PreparedEpoch {
        _ = try configuration.stream(streamId)
        let current = try await store.loadState()
        let schedule = try configuration.schedule(id: try current.requireScheduleId())

        let epoch = current.nextEpoch(streamId)
        guard epoch <= schedule.epochCount else {
            throw ReserveError.scheduleComplete(streamId: streamId, epochs: schedule.epochCount)
        }

        // A record that will not parse throws here rather than reading as an
        // unpaid epoch, which would pay the whole epoch a second time.
        let record = try await store.loadEpoch(streamId: streamId, epoch: epoch)

        // A list with holes in it pays nobody. A short payout cannot be undone
        // and looks like favouritism to everybody it missed.
        let complete = try recipients.requireComplete()

        let plan = try planner.planGuardedEpoch(
            streamId: streamId,
            schedule: schedule,
            epoch: epoch,
            recipients: complete,
            record: record,
            alreadySpentBaseUnits: current.spent(streamId)
        )
        return PreparedEpoch(
            schedule: schedule,
            epoch: epoch,
            state: current,
            record: record,
            plan: plan
        )
    }

    private func execute(
        streamId: String,
        recipients: ReserveRecipientList,
        periodKey: String,
        now: Date
    ) async throws -> ReserveEpochOutcome {
        // Guard 2. Checked before the plan is built so a refused run does no
        // work at all, and before anything is written so it leaves no trace.
        let preflightState = try await store.loadState()
        if preflightState.lastPeriodKey(streamId) == periodKey {
            throw ReserveError.periodAlreadyPaid(streamId: streamId, periodKey: periodKey)
        }

        let context = try await prepare(streamId: streamId, recipients: recipients)

        // Guard 4. Before the first payment, against what is *left* of the
        // period rather than the raw ceiling.
        if let limits = try await payer.spendLimits() {
            try planner.requireWithinLimits(plan: context.plan, limits: limits)
        }

        var record = context.record
        var state = context.state
        var paid: [ReserveReceipt] = []
        var failed: [ReserveFailedPayment] = []
        var paidBaseUnits: UInt64 = 0

        for entry in context.plan.entries {
            // Guard 3. Claim, persist, and only then hand value over. Both
            // writes happen before the payment: the epoch row stops a second
            // payment to the same recipient, and the recorded spend keeps the
            // allocation ceiling honest for the next epoch even if this one
            // dies right here.
            record.claim(entry: entry, at: now)
            state = state.recordingSpend(streamId: streamId, baseUnits: entry.baseUnitsAmount)
            try await store.save(epoch: record)
            try await store.save(state: state)

            do {
                let reference = try await payer.pay(
                    entry: entry,
                    streamId: streamId,
                    epoch: context.epoch
                )
                paid.append(ReserveReceipt(entry: entry, reference: reference))
                let (sum, overflow) = paidBaseUnits.addingReportingOverflow(entry.baseUnitsAmount)
                paidBaseUnits = overflow ? UInt64.max : sum
            } catch let refusal as ReservePaymentRefusal {
                // Provably moved nothing, so the slot goes back and can be paid
                // later in this same epoch by a re-run.
                record.release(entry: entry)
                state = state.releasingSpend(streamId: streamId, baseUnits: entry.baseUnitsAmount)
                try await store.save(epoch: record)
                try await store.save(state: state)
                failed.append(
                    ReserveFailedPayment(entry: entry, reason: refusal.reason, claimReleased: true)
                )
            } catch {
                // Might have gone through. The claim stays, so nobody can be
                // paid twice for it; the value simply stays in the reserve.
                failed.append(
                    ReserveFailedPayment(
                        entry: entry,
                        reason: error.localizedDescription,
                        claimReleased: false
                    )
                )
            }
        }

        // The epoch is closed only by a loop that reached the end. Individual
        // failures do not reopen it: their value stays in the reserve, and an
        // epoch is finished rather than retried for ever.
        record.completedAt = now
        try await store.save(epoch: record)
        state = state
            .markingComplete(streamId: streamId, epoch: context.epoch)
            .claimingPeriod(streamId: streamId, periodKey: periodKey)
        try await store.save(state: state)

        return ReserveEpochOutcome(
            streamId: streamId,
            schedule: context.schedule,
            epoch: context.epoch,
            periodKey: periodKey,
            perUnitBaseUnits: context.plan.perUnitBaseUnits,
            paid: paid,
            failed: failed,
            skipped: context.plan.skipped,
            paidBaseUnits: paidBaseUnits,
            isComplete: true
        )
    }
}
