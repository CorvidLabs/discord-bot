@preconcurrency import Foundation

/// `/ping`: is the bot awake.
///
/// `LEARN-3` is the want: a member can tell whether the bot is awake before
/// trusting an answer from it. A bot that is half up gives confident wrong
/// answers, and this is the cheapest way to find out that it is not.
///
/// **It reads nothing.** No chain, no store, no portal. That is `RUN-11` and
/// `SEE-1.b` together: no one member, however fast they type, can spend the
/// day's budget for reading the chain, and a check never costs the thing it
/// is checking on. It is also why this is not the operator's health check,
/// which is HTTP and is `SEE-1`: this one proves the gateway is delivering
/// interactions and nothing more, which is exactly what a member wants to
/// know.
public struct PingCommand: CommandHandler {

    // MARK: - Properties

    public let name = CommandCatalog.ping

    /// The clock, so the round trip is a measurement and not a guess.
    private let now: @Sendable () -> Date

    // MARK: - Initializers

    /// - Parameter now: The clock.
    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Public Methods

    public func handle(_ request: InteractionRequest) async -> SurfaceReply {
        // The interaction carries when it arrived here, so this is the time
        // between Discord handing it over and this process answering. It is
        // not a network round trip and does not claim to be one.
        let elapsed = now().timeIntervalSince(request.receivedAt)
        let milliseconds = max(0, Int((elapsed * 1000).rounded()))
        return .immediate(.ephemeral("Awake. Answered in \(milliseconds)ms."))
    }
}
