import Foundation

/// An account another service says somebody controls.
///
/// The public initialiser is the point, and so is the name. A host that runs
/// the hosted flow has to be able to make one of these, because the proof was
/// checked somewhere else and all that arrived here was a claim and a shared
/// secret. Naming it for what it is keeps the one value in this module that
/// nothing here checked from being mistaken for the one that was.
///
/// The asymmetry does not go away and is not meant to. On this route the
/// shared secret is the whole trust boundary, and the software says so rather
/// than leaving an operator to work it out.
public struct AssertedAccount: Sendable, Equatable {

    // MARK: - Properties

    /// Who it is asserted for, as an opaque subject.
    public let subject: String

    /// The account, as the other service gave it.
    public let address: String

    /// When the other service said so.
    public let assertedAt: Date

    /// What the other service calls itself, so an audit line can say whose
    /// word this was.
    public let assertedBy: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - subject: Who it is asserted for.
    ///   - address: The account.
    ///   - assertedAt: When the other service said so.
    ///   - assertedBy: What the other service calls itself.
    public init(subject: String, address: String, assertedAt: Date, assertedBy: String) {
        self.subject = subject
        self.address = address
        self.assertedAt = assertedAt
        self.assertedBy = assertedBy
    }
}
