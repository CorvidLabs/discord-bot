import Chain
import Foundation

/// What this instance has reached, kept where the listener can read it
/// without touching anything.
///
/// The vocabulary is `Chain`'s and none of it is respelled here: the status,
/// the waiting list and the JSON body are ``Chain/ChainHealthReport``'s, so a
/// monitoring check written against one of them is written against both
/// (RT-032). What this module owns is which components exist, who marks each
/// one reached, and when the provider proof is refreshed.
///
/// **A part that is off contributes no component.** ``Chain/ChainHealthComponent``
/// carries a name and whether it was reached, so an off part reported as
/// unreached would hold the instance at `starting` for ever. Off parts are
/// named in the startup report instead (ADOPT-10.a, BUILD-1.a). An instance
/// with nothing to wait for reads as `ok`, which the type already documents.
public actor HealthState {

    // MARK: - Properties

    /// The components, in the order they were declared, which is the order
    /// the waiting list prints them.
    private var components: [ChainHealthComponent]

    /// Whatever the last refresh of the probe held, or nil.
    private var proof: ProviderProof?

    /// Wakes whoever refreshes the provider proof, once per answer given.
    private let demand: AsyncStream<Void>.Continuation

    /// One element per answer given, for whoever refreshes the provider proof.
    ///
    /// **This is what keeps the probe on demand rather than on a timer.** The
    /// bot this was ported from probed its provider once at boot and then only
    /// when a health request arrived and the cached answer had gone stale, so
    /// an instance nobody checks costs the provider one request for its whole
    /// life. A refresh loop on its own timer costs one every cache lifetime
    /// for ever, whether or not anybody ever asks, and the probe deliberately
    /// does not go through the request governor, so nothing would count or
    /// stop it.
    ///
    /// The signal is sent **after** the answer has been assembled, never
    /// before, so no network call is ever on the request path (RT-017). The
    /// newest element replaces an unread one: a flood of requests during one
    /// refresh is one refresh afterwards, not a queue of them.
    public nonisolated let proofRefreshWanted: AsyncStream<Void>

    // MARK: - Initializers

    /// - Parameter componentNames: One name per part the operator switched
    ///   on. An empty list is legitimate and reads as `ok`.
    public init(componentNames: [String]) {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.components = componentNames.map { ChainHealthComponent(name: $0, reached: false) }
        self.proofRefreshWanted = stream
        self.demand = continuation
    }

    deinit {
        // Ends the sequence rather than leaving a refresh loop suspended on a
        // state nothing can write to any more.
        demand.finish()
    }

    // MARK: - Public Methods

    /// Records that a component has been reached.
    ///
    /// A name that is not a declared component is ignored rather than added,
    /// because the component list is what the operator switched on and a gate
    /// inventing one would put a part in the health answer that is not in the
    /// report.
    ///
    /// - Parameter name: The component.
    public func markReached(_ name: String) {
        guard let index = components.firstIndex(where: { $0.name == name }) else { return }
        components[index] = ChainHealthComponent(name: name, reached: true)
    }

    /// Records that a component is no longer reached.
    ///
    /// - Parameter name: The component.
    public func markUnreached(_ name: String) {
        guard let index = components.firstIndex(where: { $0.name == name }) else { return }
        components[index] = ChainHealthComponent(name: name, reached: false)
    }

    /// Stores what the last refresh of the provider probe found.
    ///
    /// Refreshed on the runtime's own schedule and never inside the handler,
    /// because ``Chain/ProviderProofProbe/proof(now:)`` refreshes when its
    /// cache is stale and answering through it would put a network call on
    /// the request path (RT-017).
    ///
    /// - Parameter proof: What the probe found, or nil for nothing usable.
    public func store(proof: ProviderProof?) {
        self.proof = proof
    }

    /// The answer, assembled from what is already held.
    ///
    /// Costs no chain request and reaches nothing, so it still answers when
    /// the day's budget is spent, which is the moment somebody is actually
    /// looking at it (SEE-1.b, SEE-10.a).
    public func report() -> ChainHealthReport {
        ChainHealthReport(components: components, proof: proof)
    }

    /// The whole answer a request gets: the code and the body.
    ///
    /// 200 when every enabled component has been reached and 503 otherwise,
    /// with the same body either way, so a check can be written once.
    ///
    /// A spent budget or a live pause is a fact in the body and never a
    /// failing check: an instance that is serving is ready, and taking it out
    /// of rotation over a provider quota is how a deploy gate rolls back a
    /// working version (RUN-3).
    public func answer() -> HealthAnswer {
        let report = report()
        let answer = HealthAnswer(
            statusCode: report.status == .ok ? 200 : 503,
            body: report.jsonBody,
            headers: report.proof?.httpHeaders ?? [:]
        )
        // After the answer, never before it. Whoever is listening may make a
        // request, and a request on this path is the one thing a health check
        // must not need (RT-017).
        demand.yield()
        return answer
    }
}

/// One answer to one health request.
public struct HealthAnswer: Sendable, Equatable {

    // MARK: - Properties

    /// 200 when everything enabled has been reached, 503 otherwise.
    public let statusCode: Int

    /// ``Chain/ChainHealthReport/jsonBody``, the same either way.
    public let body: String

    /// Provider proof headers to copy onto the answer, when there is proof.
    public let headers: [String: String]

    // MARK: - Initializers

    /// - Parameters:
    ///   - statusCode: 200 or 503.
    ///   - body: The report's JSON.
    ///   - headers: Provider proof headers.
    public init(statusCode: Int, body: String, headers: [String: String]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
}

/// The names of the components this build can declare.
///
/// Named constants rather than strings at the call sites, so the report, the
/// gates and the health answer cannot disagree about what a part is called.
/// Naming them is what lets an outage read as the provider's rather than as
/// ours (SEE-10).
public enum HealthComponent: Sendable {

    /// The durable store this instance keeps what it remembers in.
    public static let store = "store"

    /// The node, when the boot was told to confirm the asset against it.
    public static let chain = "chain"

    /// The chat service, when this build was given a surface.
    ///
    /// **Raised by the session's own opening event and by nothing else.** The
    /// chat gate returning proves only that the identify was asked for:
    /// asking for a websocket is not having one, so a gate that marked this
    /// reached would answer 200 to a deploy gate while every interaction is
    /// delivered to nobody. Lowered again when the session ends, because a
    /// green check on a deaf process is worse than no check at all (SEE-1,
    /// SEE-1.a, SEE-10).
    public static let chat = "chat"
}
