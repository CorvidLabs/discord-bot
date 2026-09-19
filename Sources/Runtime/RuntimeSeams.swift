import Chain
import Foundation

/// Where the chain reader and the provider probe come from.
///
/// A seam, so the whole boot can be driven from a test with a stub data
/// source and no network. The live implementation builds
/// ``Chain/NodeAccountDataSource``, and it lives in the executable, which is
/// the only place a live thing is constructed.
public protocol ChainSourceProviding: Sendable {

    /// The data source to read accounts and assets through.
    ///
    /// - Parameter configuration: What the operator configured.
    func dataSource(for configuration: ChainConfiguration) throws -> any AccountDataSource

    /// The probe whose response headers are copied onto a health answer as
    /// proof of which provider served a request, or nil for none.
    ///
    /// Nil is the ordinary answer when no proof headers are configured. The
    /// probe deliberately does not go through the request governor, because a
    /// health check must keep working when the day's budget is spent.
    ///
    /// - Parameter configuration: What the operator configured.
    func proofProbe(for configuration: ChainConfiguration) -> (any HTTPHeaderProbe)?
}

/// Everything live that the boot sequence is handed rather than builds.
///
/// The composition root can therefore be driven entirely from a test, and the
/// executable is the only place a live thing is constructed. Nothing in here
/// reaches the machine's settings: those arrive separately, as one
/// ``Settings`` value, because there is exactly one place in `Sources/` that
/// reads the process environment and it is not this module (RT-003).
public struct RuntimeSeams: Sendable {

    // MARK: - Properties

    /// Where the durable store comes from.
    public let store: any StoreOpening

    /// Where the chain reader and the provider probe come from.
    public let chain: any ChainSourceProviding

    /// The chat service, when this build has one. Nothing conforms to
    /// ``ChatGateway`` at this commit, so this is nil in every real build.
    public let chat: (any ChatGateway)?

    /// Where the report and the refusals go.
    public let output: any RuntimeOutput

    /// Whether this build can move anything.
    ///
    /// A **parameter**, never a reading of the settings. See
    /// ``SpendCapability``.
    public let spending: SpendCapability

    /// The clock, injected so a test pins the day the budget belongs to.
    public let now: @Sendable () -> Date

    // MARK: - Initializers

    /// - Parameters:
    ///   - store: Where the durable store comes from.
    ///   - chain: Where the chain reader and the probe come from.
    ///   - chat: The chat service, when this build has one.
    ///   - output: Where the report and the refusals go.
    ///   - spending: Whether this build can move anything.
    ///   - now: The clock.
    public init(
        store: any StoreOpening,
        chain: any ChainSourceProviding,
        chat: (any ChatGateway)? = nil,
        output: any RuntimeOutput = StandardStreams(),
        spending: SpendCapability = .cannotSpend,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.chain = chain
        self.chat = chat
        self.output = output
        self.spending = spending
        self.now = now
    }
}
