import Foundation
import Chain

/// Reads one account off the chain, with how complete the reading was in the
/// answer.
///
/// A seam over `Chain` rather than the reader itself, so a handler can be
/// driven from a fixture with no node, no rate limiter and no budget
/// (`BUILD-2`). The return type is ``Chain/WalletCheck``, which carries its
/// own gaps: a read that half worked is `short`, and `short` becomes
/// ``Gating/Reading/unknown`` rather than a number.
public protocol AccountHoldingsReader: Sendable {

    /// What this account holds, and what could not be read.
    ///
    /// - Parameter address: The account.
    /// - Throws: When nothing at all could be read. A caller turns that into
    ///   ``Chain/WalletCheck/unreadable(address:gap:)`` rather than into
    ///   zeroes.
    func check(address: String, for caller: RequestCaller) async throws -> WalletCheck
}
