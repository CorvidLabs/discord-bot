import Foundation

/// How a bot came to believe an account belongs to a member.
///
/// Carried into the audit so an operator can tell them apart afterwards.
/// Nothing downstream may branch on it except the audit line and the report
/// of it an operator reads: a role rule or a payout that reads this would
/// make one bot into two products.
public enum ProofRoute: String, Sendable, Equatable, CaseIterable {

    /// A signature this module checked.
    case inProcess

    /// Another service's word, believed because it presented a shared secret.
    case asserted
}

/// The one value both routes meet at.
///
/// Two producers, one seam. A ``ProvedAccount`` becomes one of these tagged
/// ``ProofRoute/inProcess``; an ``AssertedAccount`` becomes one tagged
/// ``ProofRoute/asserted``, through a call a host has to write and that names
/// the route while it writes it. One type for both, constructible either way,
/// is the shape that hides from a reviewer which values were checked here and
/// which were somebody else's word.
public struct VerifiedAccount: Sendable, Equatable {

    // MARK: - Properties

    /// Who it belongs to, as an opaque subject.
    public let subject: String

    /// The account, in the rendering the route gave it.
    public let address: String

    /// When it was proved or asserted.
    public let verifiedAt: Date

    /// Which of the two it was.
    public let route: ProofRoute

    // MARK: - Initializers

    /// From a signature this module checked.
    ///
    /// - Parameter proved: The account the signature proved.
    public init(proved: ProvedAccount) {
        self.subject = proved.subject
        self.address = proved.address
        self.verifiedAt = proved.provedAt
        self.route = .inProcess
    }

    /// From another service's word, taken deliberately.
    ///
    /// - Parameter asserted: What the other service said.
    public init(asserted: AssertedAccount) {
        self.subject = asserted.subject
        self.address = asserted.address
        self.verifiedAt = asserted.assertedAt
        self.route = .asserted
    }
}
