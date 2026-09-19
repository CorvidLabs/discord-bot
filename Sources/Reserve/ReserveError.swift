import Foundation

/// Why a reserve epoch cannot be planned, or cannot be paid.
///
/// Every case is a refusal, and every refusal is total: nothing here clamps an
/// amount down to fit or pays the part of a list that would have worked. A short
/// payout cannot be undone and looks like favouritism, so the choice is always
/// to pay everybody or nobody.
public enum ReserveError: Error, Equatable, LocalizedError, Sendable {
    /// No duration chosen yet. Nothing pays until one is.
    case scheduleNotSelected
    /// The schedule has started; the duration is fixed for the rest of it.
    case scheduleLocked(scheduleId: String, paidEpochs: UInt64)
    /// A duration nobody configured.
    case unknownSchedule(String)
    /// A stream nobody configured.
    case unknownStream(String)
    /// Asked for an epoch outside `1...epochCount`.
    case epochOutOfRange(epoch: UInt64, count: UInt64)
    /// Every epoch of this stream has been paid.
    case scheduleComplete(streamId: String, epochs: UInt64)
    /// More eligible units than the fixed denominator has slots.
    case tooManyUnits(streamId: String, eligible: UInt64, denominator: UInt64)
    /// Paying this epoch would spend past the allocation.
    case allocationExhausted(streamId: String, spent: UInt64, allocation: UInt64)
    /// This epoch is already finished; a second run would pay twice.
    case epochAlreadyPaid(streamId: String, epoch: UInt64)
    /// Nobody left to pay in this epoch.
    case nothingToPay(streamId: String, epoch: UInt64)
    /// Another epoch is mid-flight. Two at once would pay everyone twice.
    case alreadyRunning
    /// This stream already paid an epoch in this period.
    case periodAlreadyPaid(streamId: String, periodKey: String)
    /// Asked to pay an epoch that is not the one the ledger says is next.
    case notTheNextEpoch(streamId: String, requested: UInt64, next: UInt64)
    /// The eligibility list has holes, so it pays nobody.
    case incompleteRecipients(Int)
    /// One payment is over the per-payment limit.
    case overPaymentLimit(requested: UInt64, limit: UInt64)
    /// The epoch is over what is left of the period's limit.
    case overPeriodLimit(total: UInt64, remaining: UInt64, limit: UInt64)

    public var errorDescription: String? {
        switch self {
        case .scheduleNotSelected:
            return "No schedule selected. Choose a duration before anything can pay."
        case .scheduleLocked(let scheduleId, let paidEpochs):
            return "The schedule is already running as `\(scheduleId)` — \(paidEpochs) epoch(s) paid. "
                + "The duration is fixed once the schedule begins, because changing it would move every "
                + "remaining payment."
        case .unknownSchedule(let raw):
            return "Unknown schedule `\(raw)`. Nothing falls back to a default: a duration that quietly "
                + "became another one would halve or double every payment for the rest of the schedule."
        case .unknownStream(let raw):
            return "Unknown stream `\(raw)`."
        case .epochOutOfRange(let epoch, let count):
            return "Epoch \(epoch) is outside this schedule's 1…\(count)."
        case .scheduleComplete(let streamId, let epochs):
            return "Stream `\(streamId)` is finished: all \(epochs) epochs are paid."
        case .tooManyUnits(let streamId, let eligible, let denominator):
            return "\(ReserveFormatting.grouped(eligible)) eligible units exceed stream `\(streamId)`'s fixed "
                + "denominator of \(ReserveFormatting.grouped(denominator)). Paying them all would spend past "
                + "the allocation, so nothing is sent. Raise the denominator deliberately or shorten the list."
        case .allocationExhausted(let streamId, let spent, let allocation):
            return "Stream `\(streamId)`'s allocation is spent: \(ReserveFormatting.grouped(spent)) of "
                + "\(ReserveFormatting.grouped(allocation)) smallest units. Nothing is sent."
        case .epochAlreadyPaid(let streamId, let epoch):
            return "Stream `\(streamId)` epoch \(epoch) is already paid. A second run would pay twice."
        case .nothingToPay(let streamId, let epoch):
            return "Stream `\(streamId)` epoch \(epoch) has nobody left to pay."
        case .alreadyRunning:
            return "An epoch is already running. Two at once would pay every recipient twice. "
                + "Wait for it to finish."
        case .periodAlreadyPaid(let streamId, let periodKey):
            return "Stream `\(streamId)` already paid an epoch in \(periodKey). One epoch per period; "
                + "the next one is due next period."
        case .notTheNextEpoch(let streamId, let requested, let next):
            return "Stream `\(streamId)` epoch \(requested) is not next — the ledger is on \(next). "
                + "An epoch can be finished, never skipped."
        case .incompleteRecipients(let count):
            return "Aborted: \(count) recipient(s) could not be read. Working from a list with holes in it "
                + "pays a short list, which cannot be undone. Nothing is sent."
        case .overPaymentLimit(let requested, let limit):
            return "A payment of \(ReserveFormatting.grouped(requested)) whole units exceeds the per-payment "
                + "limit of \(ReserveFormatting.grouped(limit)). Aborting; not clamped."
        case .overPeriodLimit(let total, let remaining, let limit):
            return "The epoch charges \(ReserveFormatting.grouped(total)) whole units against this period's "
                + "limit of \(ReserveFormatting.grouped(limit)), of which "
                + "\(ReserveFormatting.grouped(remaining)) is left. Aborting; not clamped."
        }
    }
}
