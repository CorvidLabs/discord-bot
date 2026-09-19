import Foundation

/// An account somebody proved they control, by a signature this module
/// checked.
///
/// **There is no public initialiser, and no public interface returns one
/// without taking a submitted proof and a session.** Both halves matter and
/// an earlier shape had only the first. A value that any caller can mint is a
/// proof that was never checked, and every test of the checking is then
/// decorative; a value that only one non-public initialiser makes, beside a
/// public factory for the other route, is the same hole reached one call
/// later. So there are two types: this one, which a signature makes, and
/// ``AssertedAccount``, which says in its own name that nothing here checked
/// it.
public struct ProvedAccount: Sendable, Equatable {

    // MARK: - Properties

    /// Who it was proved for, as the opaque subject the session was minted
    /// for.
    public let subject: String

    /// The account, in its canonical rendering.
    public let address: String

    /// When the proof was checked, from the instant the caller supplied.
    public let provedAt: Date

    /// Whether the signature checked out against a key the caller vouched
    /// for rather than against the account's own.
    ///
    /// Recorded so an audit can tell the two apart afterwards. Where that key
    /// may come from is the caller's obligation and a strict one: the host's
    /// own read of that exact account's authorising address, never the
    /// submission and never the blob. Without it this is "if the caller hands
    /// you a key, accept a signature by that key for any address".
    public let usedAuthorizingKey: Bool

    // MARK: - Initializers

    /// Not public, and not called from anywhere but the one path that has
    /// just consumed a signature and a session.
    internal init(subject: String, address: String, provedAt: Date, usedAuthorizingKey: Bool) {
        self.subject = subject
        self.address = address
        self.provedAt = provedAt
        self.usedAuthorizingKey = usedAuthorizingKey
    }
}
