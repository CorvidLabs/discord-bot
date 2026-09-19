import Foundation

/// Why a reserve cannot be configured.
///
/// Every one of these is raised by an initializer, before anything exists that
/// could pay anybody. That is deliberate: a split that does not add up is a
/// mistake to find while typing the configuration, not on the morning of the
/// first payout when there is an audience.
public enum ReserveConfigurationError: Error, Equatable, LocalizedError, Sendable {
    /// Ten to the twentieth does not fit in `UInt64`.
    case unsupportedDecimals(UInt8)
    /// Converting whole units to smallest units overflowed.
    case amountOverflows(whole: UInt64, decimals: UInt8)
    /// A reserve with no streams has nobody to pay.
    case noStreams
    /// Two streams answering to the same id would share a ledger row.
    case duplicateStreamId(String)
    /// A reserve with no selectable durations can never start.
    case noSchedules
    /// Two durations answering to the same id.
    case duplicateScheduleId(String)
    /// A schedule of zero epochs would divide by zero.
    case invalidEpochCount(scheduleId: String)
    /// A denominator of zero would divide by zero.
    case invalidDenominator(streamId: String)
    /// The share does not divide the reserve into whole smallest units, or the
    /// arithmetic overflowed.
    case indivisibleShare(streamId: String, share: String)
    /// The streams' shares do not add up to the reserve.
    case sharesDoNotSumToReserve(sum: UInt64, reserve: UInt64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedDecimals(let decimals):
            return "An asset cannot have \(decimals) decimals: ten to that power does not fit in 64 bits. "
                + "The maximum is 19."
        case .amountOverflows(let whole, let decimals):
            return "\(ReserveFormatting.grouped(whole)) whole units at \(decimals) decimals overflows 64 bits. "
                + "Use a smaller reserve or an asset with fewer decimals."
        case .noStreams:
            return "A reserve needs at least one stream; there is nobody to pay otherwise."
        case .duplicateStreamId(let id):
            return "Two streams share the id `\(id)`. Ids key the ledger, so duplicates would share a row "
                + "and pay each other's epochs."
        case .noSchedules:
            return "A reserve needs at least one schedule to choose from before it can start."
        case .duplicateScheduleId(let id):
            return "Two schedules share the id `\(id)`."
        case .invalidEpochCount(let scheduleId):
            return "Schedule `\(scheduleId)` has no epochs. A schedule is a count of epochs and must be at least 1."
        case .invalidDenominator(let streamId):
            return "Stream `\(streamId)` has a denominator of 0. The denominator is what a share is divided by."
        case .indivisibleShare(let streamId, let share):
            return "Stream `\(streamId)`'s share of \(share) is not a whole number of smallest units of the "
                + "reserve. Pick a split that divides exactly, or the units that will not divide would be "
                + "lost without anybody being able to account for them."
        case .sharesDoNotSumToReserve(let sum, let reserve):
            return "The streams' shares add up to \(ReserveFormatting.grouped(sum)) smallest units, but the "
                + "reserve is \(ReserveFormatting.grouped(reserve)). A reserve that is not fully allocated "
                + "has a slice nobody owns; one that is over-allocated cannot be paid."
        }
    }
}
