@preconcurrency import Foundation
import Chain
import Reserve

/// The precision every instant is written down at.
///
/// Whole seconds since 1970 UTC, as an integer, with no formatter anywhere near
/// it. A store that writes a date as text acquires a locale, a calendar and a
/// platform difference, and then acquires the repair migrations that go with
/// them; a store that writes a floating point interval acquires a value whose
/// last bits differ between the machine that wrote it and the machine that read
/// it back.
///
/// The cost is real and is stated rather than hidden: sub-second precision is
/// dropped, so an instant handed to a store comes back rounded down to its
/// second. Nothing in the payout engine, the ladder or the request budget reads
/// an instant more finely than that, and the conformance suite asserts the
/// rounding rather than leaving a reader to discover it.
public enum StoreDate: Sendable {

    // MARK: - Public Methods

    /// `date` rounded down to a whole second.
    ///
    /// Down rather than to nearest, so a recorded instant is never later than
    /// the instant that actually happened. A claim written down as later than
    /// it was is a claim that can read as belonging to the next period.
    public static func whole(_ instant: Date) -> Date {
        date(seconds: seconds(instant))
    }

    /// `date` rounded down to a whole second, or nil.
    public static func whole(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return whole(date)
    }

    /// Whole seconds since 1970 UTC, as the integer a column holds.
    ///
    /// Clamped rather than converted blindly. An instant far outside any
    /// calendar, or one built from an interval that overflowed somewhere
    /// upstream, would take the process down on the conversion, and a store
    /// that stops a bot because somebody passed an absurd date is worse than
    /// one that writes the furthest date it can hold.
    public static func seconds(_ date: Date) -> Int64 {
        let interval = (date.timeIntervalSince1970).rounded(.down)
        guard interval.isFinite else { return interval < 0 ? Int64.min : Int64.max }
        if interval >= Double(Int64.max) { return Int64.max }
        if interval <= Double(Int64.min) { return Int64.min }
        return Int64(interval)
    }

    /// The instant an integer column holds.
    public static func date(seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// The reserve's state as a store records it.
    ///
    /// Applied by every backend, including the one in memory, so a test that
    /// passes against the store a contributor can run means the same thing as a
    /// test that passes against a file.
    ///
    /// A stream entered as having finished nothing or spent nothing is dropped,
    /// because the value itself already answers zero for a stream it has never
    /// heard of. A backend keeping one row per stream cannot tell that entry
    /// from an absent one, so it is settled here rather than guessed at on the
    /// way back out, and two backends hand back the same value instead of two
    /// values that only mean the same.
    public static func recorded(_ state: ReserveState) -> ReserveState {
        var copy = state
        copy.activatedAt = whole(state.activatedAt)
        copy.completedEpochs = state.completedEpochs.filter { $0.value != 0 }
        copy.spentBaseUnits = state.spentBaseUnits.filter { $0.value != 0 }
        return copy
    }

    /// One epoch's record as a store records it.
    ///
    /// The instant on each charge is rounded here too, rather than left to
    /// each backend. A charge is an instant like every other in this store, and
    /// a backend that rounded it on the way to disk while the value in memory
    /// kept its fraction would make a saved record unequal to the record it
    /// was handed.
    public static func recorded(_ record: ReserveEpochRecord) -> ReserveEpochRecord {
        var copy = record
        copy.startedAt = whole(record.startedAt)
        copy.completedAt = whole(record.completedAt)
        copy.charges = record.charges.map {
            ReserveEpochCharge(
                periodKey: $0.periodKey,
                checkedWholeUnits: $0.checkedWholeUnits,
                recordedAt: whole($0.recordedAt)
            )
        }
        return copy
    }

    /// The day's request count as a store records it.
    public static func recorded(_ usage: RequestBudgetUsage) -> RequestBudgetUsage {
        RequestBudgetUsage(usedRequests: usage.usedRequests, dayStart: whole(usage.dayStart))
    }
}
