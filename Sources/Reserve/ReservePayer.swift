import Foundation

/// Raised by a payer when an attempt **provably moved nothing**.
///
/// This is the only signal that gives a claim back, so the bar for raising it is
/// deliberately high: the refusal must have happened before anything was handed
/// over. Not opted in, frozen, over a limit, an unfunded account: all fine.
///
/// An attempt that was dispatched and then got no answer is **not** this. It may
/// have gone through, and a claim released on a payment that actually landed is
/// a payment made twice. When in doubt, throw something else: keeping a claim
/// costs one recipient one epoch, and the value stays in the reserve.
public struct ReservePaymentRefusal: Error, Equatable, Sendable {

    // MARK: - Properties

    /// Why nothing moved, for the operator's report.
    public let reason: String

    // MARK: - Initializers

    public init(reason: String) {
        self.reason = reason
    }
}

/// Who actually moves the value.
///
/// The engine never sends anything. It works out what is owed, writes down that
/// it is about to be paid, and then asks the host to pay it. Everything about
/// how the host pays, over a chain, through a bank, as a ledger entry, into a
/// spreadsheet, is on the other side of this protocol, which is why the engine
/// can be tested end to end without a network.
///
/// The seam also exists for a blunter reason: when payment lives inside a
/// concrete type that holds a key and talks to a network, none of the failure
/// paths can be exercised by a test at all, and they are the paths that matter.
public protocol ReservePayer: Sendable {

    /// Pays one line.
    ///
    /// Called **after** the claim is durably recorded. Throw
    /// ``ReservePaymentRefusal`` when nothing moved and the claim should be
    /// given back; throw anything else to keep the claim.
    ///
    /// - Returns: A reference the operator can check the payment against: a
    ///   transaction id, a receipt number, anything that is evidence rather than
    ///   an assurance.
    func pay(entry: ReserveEpochEntry, streamId: String, epoch: UInt64) async throws -> String

    /// What the paying account may move, or nil when there are no limits.
    ///
    /// Read once per epoch, before the first payment.
    func spendLimits() async throws -> ReserveSpendLimits?

    /// What the paying account holds in smallest units, or nil when unknown.
    ///
    /// Advisory: used for the runway warning, never to refuse anything.
    func availableBaseUnits() async throws -> UInt64?
}

extension ReservePayer {

    /// Most hosts have no limits to declare.
    public func spendLimits() async throws -> ReserveSpendLimits? { nil }

    /// Most hosts do not need the runway warning.
    public func availableBaseUnits() async throws -> UInt64? { nil }
}
