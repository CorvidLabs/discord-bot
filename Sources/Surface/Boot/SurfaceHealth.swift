@preconcurrency import Foundation

/// How one thing this bot leans on is doing.
public enum ComponentHealth: String, Sendable, Equatable, CaseIterable, Codable {

    /// Not up yet.
    case starting

    /// Up.
    case up

    /// Down.
    case down

    /// Switched off by the operator, so not a fault.
    case off
}

/// What the health listener answers.
///
/// **A bound socket is not health.** The listener binds before this process
/// identifies to Discord, because binding is how a second copy discovers the
/// first (`RUN-7`). That means the port answers while the bot is still coming
/// up, and answering `200` then would make every deploy gate green a second
/// before the bot was able to do anything. So it answers `503 starting` until
/// the gateway is ready (`SEE-1.a`: a check that comes back fine never means
/// only that a process is alive somewhere).
///
/// `200` names each piece separately, because when something is down the
/// operator should not be left guessing between the chain, the part that
/// proves accounts, and Discord (`SEE-10`).
///
/// Nothing here reads the chain. `SEE-1.b` is that checking never costs the
/// thing being checked on: the answer is built from values this process
/// already holds, so it costs no request and still answers once the day's
/// budget is gone.
public struct SurfaceHealth: Sendable, Equatable {

    // MARK: - Properties

    /// The gateway.
    public let discord: ComponentHealth

    /// The store.
    public let store: ComponentHealth

    /// The half that proves accounts.
    public let verification: ComponentHealth

    // MARK: - Initializers

    /// - Parameters:
    ///   - discord: The gateway.
    ///   - store: The store.
    ///   - verification: The half that proves accounts.
    public init(
        discord: ComponentHealth = .starting,
        store: ComponentHealth = .starting,
        verification: ComponentHealth = .starting
    ) {
        self.discord = discord
        self.store = store
        self.verification = verification
    }

    // MARK: - Public Methods

    /// One word for the whole thing.
    ///
    /// `degraded` is not "alive". A process that cannot verify has lost
    /// verification and nothing else (`SEE-7`), so `/ping` and `/help` still
    /// answer, and the word says which it is.
    public var status: String {
        if discord == .starting || store == .starting {
            return "starting"
        }
        if discord == .down || store == .down {
            return "down"
        }
        if verification == .down {
            return "degraded"
        }
        return "ok"
    }

    /// What the listener answers with.
    ///
    /// `503` while starting or down, so a deploy gate polling this waits
    /// rather than declaring success. `200` for degraded, because the bot is
    /// answering and taking it out of rotation would lose the parts that work.
    public var statusCode: Int {
        switch status {
        case "starting", "down":
            return 503
        default:
            return 200
        }
    }

    /// The body, as JSON, written by hand so the key order is the order a
    /// person reads it in.
    public var jsonBody: String {
        guard status != "starting" else { return "{\"status\":\"starting\"}" }
        return "{\"status\":\"\(status)\""
            + ",\"discord\":\"\(discord.rawValue)\""
            + ",\"store\":\"\(store.rawValue)\""
            + ",\"verification\":\"\(verification.rawValue)\"}"
    }
}

/// The health this process is currently reporting.
///
/// An actor because the boot sequence, the gateway's ready event and the
/// listener all touch it, and because this package uses an actor for shared
/// mutable state rather than a lock.
public actor HealthState {

    // MARK: - Properties

    /// What is reported now.
    private var current: SurfaceHealth

    // MARK: - Initializers

    /// - Parameter initial: What is reported before anything has started.
    public init(initial: SurfaceHealth = SurfaceHealth()) {
        self.current = initial
    }

    // MARK: - Public Methods

    /// What is reported now.
    public func snapshot() -> SurfaceHealth {
        current
    }

    /// Records how the gateway is doing.
    /// - Parameter health: How it is doing.
    public func setDiscord(_ health: ComponentHealth) {
        current = SurfaceHealth(discord: health, store: current.store, verification: current.verification)
    }

    /// Records how the store is doing.
    /// - Parameter health: How it is doing.
    public func setStore(_ health: ComponentHealth) {
        current = SurfaceHealth(discord: current.discord, store: health, verification: current.verification)
    }

    /// Records how the verification half is doing.
    /// - Parameter health: How it is doing.
    public func setVerification(_ health: ComponentHealth) {
        current = SurfaceHealth(discord: current.discord, store: current.store, verification: health)
    }
}
