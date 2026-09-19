@preconcurrency import Foundation

/// What the other half sends when a member has signed.
public struct VerificationCallback: Sendable, Equatable {

    // MARK: - Properties

    /// The member's chat account id, as a decimal string.
    public let externalId: String

    /// The server they proved it in.
    public let guildId: String

    /// The account they proved.
    public let address: String

    /// What the portal saw it holding, in base units. A starting value only.
    public let balanceBaseUnits: UInt64

    // MARK: - Initializers

    /// - Parameters:
    ///   - externalId: The member's chat account id.
    ///   - guildId: The server.
    ///   - address: The account they proved.
    ///   - balanceBaseUnits: What the portal saw it holding.
    public init(externalId: String, guildId: String, address: String, balanceBaseUnits: UInt64) {
        self.externalId = externalId
        self.guildId = guildId
        self.address = address
        self.balanceBaseUnits = balanceBaseUnits
    }
}

/// Why a callback was thrown away.
///
/// Every case is answered `400` **before** the listener answers at all, so a
/// portal that records a verification on a successful callback never records
/// one this bot discarded.
public enum CallbackRefusal: String, Sendable, Equatable, CaseIterable, Codable {

    /// No server was named.
    case missingGuild

    /// A server this instance does not serve (`HOST-6`, `HOST-10`).
    case foreignGuild

    /// The chat account id is not one to twenty digits.
    case malformedMemberId

    /// The account is not a shape this chain uses.
    case malformedAddress

    // MARK: - Public Methods

    /// The sentence sent back, which the contract says is echoed in the body.
    public var reason: String {
        switch self {
        case .missingGuild:
            return "Missing guildId"
        case .foreignGuild:
            return "Wrong guildId"
        case .malformedMemberId:
            return "Invalid discordId"
        case .malformedAddress:
            return "Invalid walletAddress"
        }
    }
}

/// Checks a callback before anything acts on it.
///
/// A shared secret proves who sent a request. It does not prove the request
/// makes sense, and these four are the ones that do damage if they are
/// believed: a foreign server id would write one community's member into
/// another's store, and a malformed account would be proved against a member
/// for ever.
public enum CallbackValidation: Sendable {

    // MARK: - Public Methods

    /// Nothing, or why this callback is refused.
    ///
    /// - Parameters:
    ///   - callback: What arrived.
    ///   - servedGuildId: The one server this process serves.
    ///   - isValidAddress: Whether an address parses on this chain. A
    ///     parameter because address shape belongs to the chain layer, and
    ///     because a test should be able to drive both answers.
    public static func refusal(
        for callback: VerificationCallback,
        servedGuildId: String,
        isValidAddress: (String) -> Bool
    ) -> CallbackRefusal? {
        guard !callback.guildId.isEmpty else { return .missingGuild }
        guard callback.guildId == servedGuildId else { return .foreignGuild }
        guard DiscordUserId(externalId: callback.externalId) != nil else { return .malformedMemberId }
        guard isValidAddress(callback.address) else { return .malformedAddress }
        return nil
    }
}
