import Foundation

/// The one-at-a-time gate on reserve epochs.
///
/// Running an epoch means reading the ledger, planning against it, then paying,
/// and every step of that suspends. If two runs start while the ledger still
/// says the epoch is untouched, both build the identical plan, both pay, and
/// **every eligible recipient is paid twice**: precisely the failure the epoch
/// record exists to prevent, walked straight past because the record is only
/// read once at the start.
///
/// That is not a hypothetical. A host that dispatches each command in its own
/// task, and also fires the same work on a timer, will eventually overlap the
/// two. It takes one operator running a payout by hand at the moment the
/// scheduled one fires.
///
/// **One gate for every stream, not one per stream.** ``ReserveState`` is a
/// single value written back whole, so two streams running at once would each
/// save a snapshot taken before the other's: the loser's finished epoch vanishes
/// while its epoch row still says "complete", and that stream refuses to pay
/// ever again.
///
/// It refuses rather than queues. A second payout that waits its turn is a
/// second payout nobody asked for; the operator should be told to come back.
public actor ReserveGate {

    // MARK: - Properties

    private var isRunning = false

    // MARK: - Initializers

    public init() {}

    // MARK: - Public Methods

    /// True when the caller now holds the gate and must ``release()`` it.
    public func acquire() -> Bool {
        if isRunning { return false }
        isRunning = true
        return true
    }

    /// Hands the gate back.
    public func release() {
        isRunning = false
    }

    /// Whether an epoch is mid-flight.
    public var busy: Bool { isRunning }
}
