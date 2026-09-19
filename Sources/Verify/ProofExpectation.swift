import Foundation
import Algorand

/// What a proof has to match.
///
/// Built from a session, and holding nothing a session does not already know.
/// Both addresses are addresses: this module never holds a name and never
/// resolves one, because resolving a name is an outbound call and this is the
/// module that makes none.
public struct ProofExpectation: Sendable, Equatable {

    // MARK: - Properties

    /// The account that was connected, in its canonical rendering.
    public let address: String

    /// The exact bytes the member was asked to sign.
    public let challenge: VerificationChallenge

    /// The account the member named before anything was signed, if they named
    /// one.
    public let pinnedAddress: String?

    /// A key the caller vouched for, so a rekeyed account can still prove
    /// ownership.
    ///
    /// **It comes from here and from nowhere else.** Not from the submission,
    /// not from a signer named inside the blob, and not derived from the
    /// address. Whether the account actually names this key is the caller's
    /// to establish, from its own read of that exact account's authorising
    /// address field: without that obligation this reduces to "if the caller
    /// hands you a key, accept a signature by that key for any address",
    /// which is a test-mode bypass reached through a parameter instead of a
    /// setting.
    public let authorizingKey: Data?

    /// The connected account's raw bytes, which are its public key.
    internal let addressBytes: Data

    /// The pinned account's raw bytes, if there is one.
    internal let pinnedAddressBytes: Data?

    // MARK: - Initializers

    /// - Parameters:
    ///   - address: The account that was connected.
    ///   - challenge: The exact bytes the member was asked to sign.
    ///   - pinnedAddress: The account the member named, if they named one.
    ///   - authorizingKey: A key the caller vouched for, or nil.
    /// - Throws: ``VerifyError/addressNotCanonical(field:)`` for an address
    ///   that is not the rendering every Algorand tool accepts, because
    ///   taking whatever base32 decodes accepts a typo as a different
    ///   account; or
    ///   ``VerifyError/authorizingKeyWrongLength(byteCount:)``.
    public init(
        address: String,
        challenge: VerificationChallenge,
        pinnedAddress: String? = nil,
        authorizingKey: Data? = nil
    ) throws {
        guard let parsed = try? Address(string: address) else {
            throw VerifyError.addressNotCanonical(field: "address")
        }
        var pinnedBytes: Data?
        if let pinnedAddress {
            guard let parsedPin = try? Address(string: pinnedAddress) else {
                throw VerifyError.addressNotCanonical(field: "pinnedAddress")
            }
            pinnedBytes = parsedPin.bytes
        }
        if let authorizingKey, authorizingKey.count != Self.keyByteCount {
            throw VerifyError.authorizingKeyWrongLength(byteCount: authorizingKey.count)
        }
        self.address = address
        self.challenge = challenge
        self.pinnedAddress = pinnedAddress
        self.authorizingKey = authorizingKey
        self.addressBytes = parsed.bytes
        self.pinnedAddressBytes = pinnedBytes
    }

    // MARK: - Private Methods

    /// Bytes in an Ed25519 public key, which is also what an address is.
    private static let keyByteCount: Int = 32
}
