import Foundation

/// The one shape of proof this module accepts.
///
/// A zero amount payment from an account to itself, carrying the session's
/// challenge in its note. Nothing else: not a signature over an arbitrary
/// message, with or without a wallet's data prefix, and there is no entry
/// point here that takes one. The implementation this was ported from accepts
/// a signature over the raw message **or** over the prefixed message, which is
/// a sensible compatibility hedge for signing an administrator in and a bad
/// property for proving a wallet, because it means one signature is valid over
/// two different byte strings and "they signed exactly this" stops being true.
///
/// The transaction is never submitted. It moves nothing and exists only as
/// something to check a signature over.
public enum ProofShape: Sendable {

    // MARK: - Properties

    /// The transaction type tag a proof must carry.
    public static let transactionType: String = "pay"

    /// The domain separation prefix the signature covers, before the
    /// transaction bytes.
    ///
    /// Two bytes, and not hashed first: every Algorand signature category
    /// signs the preimage directly. Wrapping it in a digest produces a
    /// signature the network rejects and this module would refuse.
    public static let signingPrefix: Data = Data("TX".utf8)

    /// The largest fee a proof may carry, in microAlgos.
    ///
    /// **Bounded at all** because a zero amount self payment is harmless only
    /// while its fee is. A page that builds the proof with the fee set to the
    /// member's whole balance produces something this module would otherwise
    /// bless as proof of ownership, and the page keeps the blob. That is the
    /// same argument the forbidden fields make, one field further on.
    ///
    /// **Bounded at the network minimum rather than at zero** because nobody
    /// has measured which wallets override a fee they were handed, and that
    /// uncertainty is the reason for the number rather than a caveat beside
    /// it. A checker that insists on zero locks out every wallet that raises a
    /// fee on the member's behalf, for a policy the page cannot enforce inside
    /// somebody else's wallet, and the member reads a refusal they have no way
    /// to act on. At the minimum, a blob that leaks costs a member a fraction
    /// of a cent instead of their balance, which is the whole property the
    /// bound exists for.
    ///
    /// What that gives up, written down rather than discovered: a zero fee
    /// with no group makes the blob un-submittable outright, and at the
    /// minimum it becomes submittable again. Submitting it moves nothing, from
    /// the member to the member, and costs that one minimum fee. Tightening
    /// this later is a change with a measurement behind it rather than a guess
    /// taken now.
    public static let maximumFeeMicroAlgos: UInt64 = 1000
}
