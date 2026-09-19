import Foundation

/// A finite reserve, split into named streams, paid over a chosen number of
/// epochs.
///
/// This type is the arithmetic and nothing else. It reads no clock, no network,
/// no database and no user. Every figure it produces is a whole number of the
/// asset's smallest unit, and every one of them can be pinned in a test, which
/// is the only reason anybody should trust a payout engine.
///
/// The governing idea is that **the reserve is a ceiling the calculation cannot
/// cross, not a balance it spends down**. A balance invites the question "how
/// much is left, and who gets it"; a ceiling has the same answer on the first
/// day as the last. So each stream divides its allocation by a denominator fixed
/// in advance, and a slot nobody claims stays unclaimed rather than enlarging
/// anybody else's payment.
///
/// ```swift
/// let reserve = try ReserveConfiguration(
///     asset: ReserveAsset(symbol: "TOKEN", decimals: 6),
///     totalWholeUnits: 10_000_000_000,
///     streams: [
///         ReserveStream(id: "members", share: .percent(70), denominator: 1_000,
///                       rule: .oncePerRecipient),
///         ReserveStream(id: "passes", share: .percent(30), denominator: 4_096,
///                       rule: .oncePerHeldUnit)
///     ],
///     schedules: [ReserveSchedule(id: "1y", epochCount: 52)]
/// )
/// ```
public struct ReserveConfiguration: Sendable, Equatable {

    // MARK: - Properties

    /// What the reserve is denominated in.
    public let asset: ReserveAsset

    /// The whole reserve, in whole units of ``asset``.
    public let totalWholeUnits: UInt64

    /// The whole reserve, in smallest units. Nothing may cross this.
    public let totalBaseUnits: UInt64

    /// The streams, in the order they were configured.
    public let streams: [ReserveStream]

    /// The durations an operator may choose between.
    public let schedules: [ReserveSchedule]

    /// Each stream's allocation in smallest units, keyed by stream id.
    private let allocations: [String: UInt64]

    // MARK: - Initializers

    /// Builds a reserve, refusing anything that does not add up.
    ///
    /// The validation is the interesting part. A split whose shares do not sum
    /// to exactly the reserve is refused, because an under-allocated reserve has
    /// a slice nobody owns and an over-allocated one cannot be paid. A share
    /// that does not divide into whole smallest units is refused for the same
    /// reason the residue is reported rather than swallowed: an amount nobody
    /// can account for is an amount somebody will eventually be accused of
    /// taking.
    ///
    /// - Parameters:
    ///   - asset: What the reserve is denominated in.
    ///   - totalWholeUnits: The whole reserve, in whole units.
    ///   - streams: At least one, with unique ids and shares summing to the whole.
    ///   - schedules: At least one selectable duration, with unique ids.
    public init(
        asset: ReserveAsset,
        totalWholeUnits: UInt64,
        streams: [ReserveStream],
        schedules: [ReserveSchedule]
    ) throws {
        guard !streams.isEmpty else { throw ReserveConfigurationError.noStreams }
        guard !schedules.isEmpty else { throw ReserveConfigurationError.noSchedules }

        var seenStreams: Set<String> = []
        for stream in streams {
            guard seenStreams.insert(stream.id).inserted else {
                throw ReserveConfigurationError.duplicateStreamId(stream.id)
            }
            guard stream.denominator > 0 else {
                throw ReserveConfigurationError.invalidDenominator(streamId: stream.id)
            }
        }

        var seenSchedules: Set<String> = []
        for schedule in schedules {
            guard seenSchedules.insert(schedule.id).inserted else {
                throw ReserveConfigurationError.duplicateScheduleId(schedule.id)
            }
            guard schedule.epochCount >= 1 else {
                throw ReserveConfigurationError.invalidEpochCount(scheduleId: schedule.id)
            }
        }

        let total = try asset.baseUnits(whole: totalWholeUnits)
        var table: [String: UInt64] = [:]
        var sum: UInt64 = 0
        for stream in streams {
            guard let allocation = stream.share.amount(of: total) else {
                throw ReserveConfigurationError.indivisibleShare(
                    streamId: stream.id,
                    share: stream.share.description
                )
            }
            let (running, overflow) = sum.addingReportingOverflow(allocation)
            guard !overflow else {
                throw ReserveConfigurationError.sharesDoNotSumToReserve(sum: UInt64.max, reserve: total)
            }
            sum = running
            table[stream.id] = allocation
        }
        guard sum == total else {
            throw ReserveConfigurationError.sharesDoNotSumToReserve(sum: sum, reserve: total)
        }

        self.asset = asset
        self.totalWholeUnits = totalWholeUnits
        self.totalBaseUnits = total
        self.streams = streams
        self.schedules = schedules
        self.allocations = table
    }

    // MARK: - Public Methods

    /// The configured stream with this id, or a refusal.
    public func stream(_ id: String) throws -> ReserveStream {
        guard let found = streams.first(where: { $0.id == id }) else {
            throw ReserveError.unknownStream(id)
        }
        return found
    }

    /// The configured schedule with this id, or a refusal.
    public func schedule(id: String) throws -> ReserveSchedule {
        guard let found = schedules.first(where: { $0.id == id }) else {
            throw ReserveError.unknownSchedule(id)
        }
        return found
    }

    /// The schedule a typed string names, or a refusal.
    ///
    /// Nothing falls back to a default here. Getting the duration wrong is the
    /// one configuration mistake that silently changes every payment for a year.
    public func schedule(matching raw: String) throws -> ReserveSchedule {
        guard let found = schedules.first(where: { $0.matches(raw) }) else {
            throw ReserveError.unknownSchedule(raw)
        }
        return found
    }

    /// One stream's allocation in smallest units.
    public func allocationBaseUnits(_ streamId: String) throws -> UInt64 {
        guard let allocation = allocations[streamId] else {
            throw ReserveError.unknownStream(streamId)
        }
        return allocation
    }

    /// Smallest units one slot is owed across a whole schedule, whatever its
    /// length.
    ///
    /// The allocation divided by the fixed denominator. Independent of the
    /// schedule by construction: a shorter schedule pays more per epoch, not
    /// more in total.
    public func shareBaseUnits(_ streamId: String) throws -> UInt64 {
        let stream = try stream(streamId)
        return try allocationBaseUnits(streamId) / stream.denominator
    }

    /// How one slot's share is cut into a schedule's epochs.
    public func epochSplit(streamId: String, schedule: ReserveSchedule) throws -> ReserveEpochSplit {
        let share = try shareBaseUnits(streamId)
        return ReserveEpochSplit(
            streamId: streamId,
            epochCount: schedule.epochCount,
            perEpochBaseUnits: share / schedule.epochCount,
            residueBaseUnits: share % schedule.epochCount
        )
    }

    /// Smallest units one slot is paid in `epoch`, numbered from 1.
    public func epochPayoutBaseUnits(
        streamId: String,
        schedule: ReserveSchedule,
        epoch: UInt64
    ) throws -> UInt64 {
        guard epoch >= 1, epoch <= schedule.epochCount else {
            throw ReserveError.epochOutOfRange(epoch: epoch, count: schedule.epochCount)
        }
        return try epochSplit(streamId: streamId, schedule: schedule).payout(epoch: epoch)
    }

    // MARK: - Projections

    /// What a stream would spend over a full schedule at this eligible count.
    ///
    /// Linear in the eligible count, because each slot's total is fixed. Eligible
    /// units past the denominator are reported as overflow rather than paid:
    /// paying them would cross the allocation, and the projection's job is to
    /// show that before a run discovers it.
    public func project(
        streamId: String,
        schedule: ReserveSchedule,
        eligibleUnits: UInt64
    ) throws -> ReserveStreamProjection {
        let stream = try stream(streamId)
        let allocation = try allocationBaseUnits(streamId)
        let share = try shareBaseUnits(streamId)
        let split = try epochSplit(streamId: streamId, schedule: schedule)
        let payable = min(eligibleUnits, stream.denominator)
        // Both products are provably inside `UInt64`: `payable` is at most the
        // denominator and `share` is the allocation floor-divided by it, so
        // `payable × share` is at most the allocation, which is at most the
        // reserve. `split.totalBaseUnits` is at most `share`.
        let inUse = payable * share
        let spend = payable * split.totalBaseUnits
        return ReserveStreamProjection(
            stream: stream,
            schedule: schedule,
            eligibleUnits: eligibleUnits,
            denominator: stream.denominator,
            allocationBaseUnits: allocation,
            perUnitShareBaseUnits: share,
            perUnitPaidBaseUnits: split.totalBaseUnits,
            split: split,
            allocationInUseBaseUnits: inUse,
            projectedSpendBaseUnits: spend,
            projectedResidueBaseUnits: inUse - spend,
            unusedAllocationBaseUnits: allocation - inUse,
            unusedSlots: stream.denominator - payable,
            overflowUnits: eligibleUnits > stream.denominator
                ? eligibleUnits - stream.denominator
                : 0,
            undividedAllocationBaseUnits: allocation % stream.denominator
        )
    }

    /// The whole reserve previewed at one moment, before anything moves.
    ///
    /// - Parameters:
    ///   - schedule: The chosen duration, or nil when none has been chosen.
    ///   - eligibleUnits: Eligible slots per stream id. Missing means zero.
    ///   - nextEpoch: The epoch each stream would pay next. Missing means 1.
    ///   - spentBaseUnits: Smallest units each stream has already paid.
    ///   - incompleteRecipients: Recipients that could not be read, per stream.
    ///     Any is an abort for a live run.
    ///   - potBaseUnits: What the paying account holds, or nil when not read.
    ///   - limits: Spending limits, or nil when not read.
    public func audit(
        schedule: ReserveSchedule?,
        eligibleUnits: [String: UInt64],
        nextEpoch: [String: UInt64] = [:],
        spentBaseUnits: [String: UInt64] = [:],
        incompleteRecipients: [String: Int] = [:],
        potBaseUnits: UInt64? = nil,
        limits: ReserveSpendLimits? = nil
    ) throws -> ReserveAudit {
        // With no duration chosen the shape of the reserve is still worth
        // seeing, so the preview illustrates with the first configured schedule
        // and says in as many words that nothing is selected.
        guard let effective = schedule ?? schedules.first else {
            throw ReserveConfigurationError.noSchedules
        }
        let projections = try streams.map { stream in
            try project(
                streamId: stream.id,
                schedule: effective,
                eligibleUnits: eligibleUnits[stream.id] ?? 0
            )
        }
        return ReserveAudit(
            asset: asset,
            reserveBaseUnits: totalBaseUnits,
            selectedSchedule: schedule,
            effectiveSchedule: effective,
            projections: projections,
            nextEpoch: nextEpoch,
            spentBaseUnits: spentBaseUnits,
            incompleteRecipients: incompleteRecipients,
            potBaseUnits: potBaseUnits,
            limits: limits
        )
    }

    // MARK: - Guards

    /// Refuses an eligible list the fixed denominator cannot cover.
    ///
    /// The alternative, paying the first `denominator` of them, is a short
    /// payout chosen by sort order, which is the worst possible way to decide
    /// who misses out.
    public func requireWithinDenominator(streamId: String, eligibleUnits: UInt64) throws {
        let denominator = try stream(streamId).denominator
        guard eligibleUnits <= denominator else {
            throw ReserveError.tooManyUnits(
                streamId: streamId,
                eligible: eligibleUnits,
                denominator: denominator
            )
        }
    }

    /// Refuses a planned epoch spend that would cross the allocation.
    public func requireWithinAllocation(
        streamId: String,
        alreadySpentBaseUnits: UInt64,
        plannedBaseUnits: UInt64
    ) throws {
        let allocation = try allocationBaseUnits(streamId)
        let (total, overflow) = alreadySpentBaseUnits.addingReportingOverflow(plannedBaseUnits)
        guard !overflow, total <= allocation else {
            throw ReserveError.allocationExhausted(
                streamId: streamId,
                spent: alreadySpentBaseUnits,
                allocation: allocation
            )
        }
    }

    /// How many more epochs a pot can pay for, or nil when nothing is due.
    ///
    /// Advisory only: it never refuses anything. The per-epoch preflight is what
    /// stops a run, and this is the notice beforehand. Nil rather than a
    /// sentinel, because a `UInt64.max` runway flowed into `nextEpoch + runway`
    /// on a card and overflowed.
    public static func runwayEpochs(potBaseUnits: UInt64, epochSpendBaseUnits: UInt64) -> UInt64? {
        guard epochSpendBaseUnits > 0 else { return nil }
        return potBaseUnits / epochSpendBaseUnits
    }
}
