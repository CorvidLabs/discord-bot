import Foundation

/// The reserve's own state: the chosen duration, and what each stream has spent.
///
/// One value, written back whole. That is worth knowing, because it is why the
/// concurrency gate covers every stream at once rather than one stream each:
/// two streams writing this back simultaneously would each save a snapshot taken
/// before the other's, and the loser's finished epoch would vanish while its
/// epoch row still said "complete" — leaving that stream permanently refusing to
/// pay.
public struct ReserveState: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// The chosen duration's id, or nil before anybody chooses.
    public var scheduleId: String?

    /// When the duration was chosen.
    public var activatedAt: Date?

    /// Epochs each stream has run to the end, keyed by stream id.
    public var completedEpochs: [String: UInt64]

    /// Smallest units each stream has actually committed, keyed by stream id.
    public var spentBaseUnits: [String: UInt64]

    /// The period each stream last paid an epoch in, keyed by stream id.
    ///
    /// The cadence gate. The epoch row stops one epoch paying twice; this stops
    /// fifty-two epochs paying in one afternoon, which is the entire reserve. A
    /// missed period is still paid late, because the rule is one epoch per
    /// period, not one epoch per calendar slot.
    public var lastPeriodKeys: [String: String]

    // MARK: - Initializers

    public init(
        scheduleId: String? = nil,
        activatedAt: Date? = nil,
        completedEpochs: [String: UInt64] = [:],
        spentBaseUnits: [String: UInt64] = [:],
        lastPeriodKeys: [String: String] = [:]
    ) {
        self.scheduleId = scheduleId
        self.activatedAt = activatedAt
        self.completedEpochs = completedEpochs
        self.spentBaseUnits = spentBaseUnits
        self.lastPeriodKeys = lastPeriodKeys
    }

    // MARK: - Public Methods

    /// Epochs this stream has finished.
    public func completedEpochs(_ streamId: String) -> UInt64 {
        completedEpochs[streamId] ?? 0
    }

    /// Smallest units this stream has committed.
    public func spent(_ streamId: String) -> UInt64 {
        spentBaseUnits[streamId] ?? 0
    }

    /// The epoch this stream would pay next, from 1.
    public func nextEpoch(_ streamId: String) -> UInt64 {
        let done = completedEpochs(streamId)
        return done == UInt64.max ? UInt64.max : done + 1
    }

    /// Epochs finished across every stream. Non-zero locks the duration.
    public var paidEpochs: UInt64 {
        completedEpochs.values.reduce(UInt64(0)) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
    }

    /// True while the duration can still be changed: before anything has paid.
    public var isLockable: Bool { paidEpochs == 0 }

    /// The chosen duration's id, or a refusal when nobody has chosen.
    public func requireScheduleId() throws -> String {
        guard let scheduleId else { throw ReserveError.scheduleNotSelected }
        return scheduleId
    }

    /// A copy with the duration chosen. Refuses once an epoch has paid.
    public func selecting(scheduleId newScheduleId: String, at date: Date) throws -> ReserveState {
        if let scheduleId, !isLockable {
            throw ReserveError.scheduleLocked(scheduleId: scheduleId, paidEpochs: paidEpochs)
        }
        var copy = self
        copy.scheduleId = newScheduleId
        copy.activatedAt = date
        return copy
    }

    /// A copy with one epoch marked finished, so the next run moves on.
    ///
    /// Only the epoch that is actually next may be completed. This was once a
    /// high-water mark, which meant closing the last epoch first marked every
    /// earlier one finished and forfeited the whole schedule without paying
    /// anybody. Anything other than the next epoch is ignored.
    ///
    /// Spend is recorded payment by payment, not here: an epoch that stops half
    /// way through really has committed that value and the ledger has to say so.
    public func markingComplete(streamId: String, epoch: UInt64) -> ReserveState {
        guard epoch == nextEpoch(streamId) else { return self }
        var copy = self
        copy.completedEpochs[streamId] = epoch
        return copy
    }

    /// The period a stream last paid an epoch in, or nil if it never has.
    public func lastPeriodKey(_ streamId: String) -> String? {
        lastPeriodKeys[streamId]
    }

    /// A copy recording that this stream paid an epoch in `periodKey`.
    public func claimingPeriod(streamId: String, periodKey: String) -> ReserveState {
        var copy = self
        copy.lastPeriodKeys[streamId] = periodKey
        return copy
    }

    /// A copy with one payment's smallest units added, without closing the epoch.
    ///
    /// Recorded *before* the payment, like the epoch claim. An over-count is
    /// safe: it tightens the allocation ceiling. An under-count is not — it
    /// would let a later epoch spend past the allocation.
    public func recordingSpend(streamId: String, baseUnits amount: UInt64) -> ReserveState {
        var copy = self
        let (sum, overflow) = spent(streamId).addingReportingOverflow(amount)
        copy.spentBaseUnits[streamId] = overflow ? UInt64.max : sum
        return copy
    }

    /// A copy with a recorded spend given back, after an attempt that moved
    /// nothing. Never below zero, whatever order the writes land in.
    public func releasingSpend(streamId: String, baseUnits amount: UInt64) -> ReserveState {
        var copy = self
        let current = spent(streamId)
        copy.spentBaseUnits[streamId] = current >= amount ? current - amount : 0
        return copy
    }
}
