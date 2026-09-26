@preconcurrency import Foundation
import Crypto
import Verify

/// Something this surface can write down about a session, which nobody can
/// replay.
///
/// A session id is a bearer credential: whoever holds one can submit a proof
/// against that session. So it may not reach a log line, a rate limiter's
/// key table, an error body or an operator's screen. This is what goes in all
/// four places instead.
///
/// **It is built exactly the way ``Verify/RefusalHandle`` is built**, from the
/// same digest truncated to the same width, so a refusal this surface wrote
/// and a refusal the coordinator produced for the same session carry the same
/// twelve characters and an operator reading a report can line them up. That
/// type's initialiser is internal to its own module, which is why the
/// construction is repeated here rather than borrowed, and a test asserts the
/// two agree so the repetition cannot quietly drift.
public struct VerifySessionHandle: Sendable, Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// Characters in a handle.
    public static let characterCount: Int = 12

    /// The handle itself, lowercase hexadecimal.
    public let value: String

    public var description: String { value }

    // MARK: - Initializers

    /// - Parameter sessionIdentifier: The session this handle stands for.
    public init(sessionIdentifier: VerificationSessionIdentifier) {
        let digest = SHA256.hash(data: Data(sessionIdentifier.value.utf8))
        self.value = digest
            .prefix(Self.characterCount / 2)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
