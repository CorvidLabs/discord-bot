@preconcurrency import Foundation
import Surface

/// What answers on the port the other half calls back on.
///
/// A value of its own rather than a closure built inside the surface,
/// because three rules live here that are worth a test each and none of them
/// needs a gateway, a token or a socket: health is answered before anything
/// else, the rate limit counts the callback route and nothing else, and a
/// callback that arrives before the store is open is refused rather than
/// accepted and dropped.
public struct CallbackResponder: Sendable {

    // MARK: - Properties

    /// What health reports.
    private let health: HealthState

    /// How many callbacks one source may send.
    private let limiter: CallbackRateLimiter

    /// This bot's copy of the shared secret, or nil when verification is off.
    private let sharedSecret: String?

    /// The one server this process serves.
    private let servedGuildId: String

    /// Whether an address parses on this chain.
    private let isValidAddress: @Sendable (String) -> Bool

    /// The handler, or nil while the store is not open yet.
    private let handler: @Sendable () async -> VerificationCallbackHandler?

    /// What a message is reported through.
    private let log: @Sendable (String) -> Void

    // MARK: - Initializers

    /// - Parameters:
    ///   - health: What health reports.
    ///   - limiter: How many callbacks one source may send.
    ///   - sharedSecret: This bot's copy, or nil when verification is off.
    ///   - servedGuildId: The one server this process serves.
    ///   - isValidAddress: Whether an address parses on this chain.
    ///   - handler: The handler, or nil while the store is not open yet.
    ///   - log: What a message is reported through.
    public init(
        health: HealthState,
        limiter: CallbackRateLimiter,
        sharedSecret: String?,
        servedGuildId: String,
        isValidAddress: @escaping @Sendable (String) -> Bool,
        handler: @escaping @Sendable () async -> VerificationCallbackHandler?,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.health = health
        self.limiter = limiter
        self.sharedSecret = sharedSecret
        self.servedGuildId = servedGuildId
        self.isValidAddress = isValidAddress
        self.handler = handler
        self.log = log
    }

    // MARK: - Public Methods

    /// Answers one request.
    ///
    /// - Parameters:
    ///   - request: What arrived.
    ///   - source: Where it came from, which is what the rate limit counts
    ///     against.
    public func respond(to request: HTTPRequestHead, from source: String) async -> HTTPListenerReply {
        if request.method == "GET", request.route == CallbackRouting.healthPath {
            return await healthReply()
        }

        // Verification switched off means this route does not exist, rather
        // than existing with nothing to prove. The secret would be the empty
        // string, an empty header matches it, and the bot would admit a
        // member, prove an account and grant roles for whoever asked.
        guard let secret = sharedSecret, !secret.isEmpty else {
            return HTTPListenerReply(status: 404, body: "{\"error\":\"Not Found\"}")
        }

        let limiter = self.limiter
        let route = await CallbackRouting.route(
            request,
            expectedKey: secret,
            servedGuildId: servedGuildId,
            isValidAddress: isValidAddress,
            isRateLimited: { await limiter.isLimited(source: source) }
        )

        switch route {
        case .health:
            return await healthReply()

        case .refuse(let status, let body):
            return HTTPListenerReply(status: status, body: body)

        case .accepted(let callback):
            // The ports are bound inside the boot and the store is handed
            // over when the boot returns, so a callback can arrive with
            // nowhere to put it. Answering `200` then is the one outcome the
            // contract forbids: the portal records a verification this bot
            // threw away, and the member is never told.
            guard let ready = await handler() else {
                log("A verification callback arrived before the store was open. It was refused "
                    + "with 503 so the portal retries rather than recording a success.")
                return HTTPListenerReply(status: 503, body: "{\"status\":\"starting\"}")
            }
            let log = self.log
            // Answered first, worked second. A portal waiting on a chain read
            // and a role update times out and retries, and a retried callback
            // is a second verification of the same account.
            return HTTPListenerReply(status: 200, body: "{\"success\":true}") {
                do {
                    let outcome = try await ready.handle(callback)
                    for note in outcome.notes {
                        log(note)
                    }
                } catch {
                    log("A verification callback could not be completed: \(error)")
                }
            }
        }
    }

    // MARK: - Private Methods

    /// What health says now.
    private func healthReply() async -> HTTPListenerReply {
        let snapshot = await health.snapshot()
        return HTTPListenerReply(status: snapshot.statusCode, body: snapshot.jsonBody)
    }
}
