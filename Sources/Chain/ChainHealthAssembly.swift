import Foundation

/// Puts a health answer together without spending a request.
///
/// **Checking must never cost the thing being checked on** (SEE-1.b). A
/// monitoring check runs on a timer, and one that read an account would be the
/// heaviest caller in the process; worse, it would stop answering at the exact
/// moment somebody needs it, because the day's budget was gone. So this asks
/// the governor for a snapshot, which costs nothing and works while paused,
/// and asks the proof probe for what it already holds, which makes no request
/// and leaves its cache alone.
///
/// Where nothing usable is held it starts one probe in the background and
/// answers without it. That is the shape the version this was ported from
/// settled on after a synchronous probe here stalled the listener's accepts
/// for up to four seconds on a cold miss: the answering path never waits on a
/// provider, and proof arrives in time for the next answer rather than never.
///
/// Nothing here touches ``ChainReader``, ``BatchedChainReader`` or any
/// ``AccountDataSource``, and the suite proves it with a data source double
/// whose call log has to come back empty.
///
/// What this does **not** own is the listener, the route, the HTTP status
/// codes or the list of components: only a composition root knows what this
/// instance has to reach. This module has no listener and no route, and a host
/// that wants one builds it around these values.
public struct ChainHealthAssembler: Sendable {

    // MARK: - Properties

    private let governor: RequestGovernor
    private let probe: ProviderProofProbe?

    // MARK: - Initializers

    /// - Parameters:
    ///   - governor: The day's budget, asked only for its snapshot.
    ///   - probe: The provider proof, when an operator configured any headers
    ///     to copy. Nil means an answer that opens no socket of any kind,
    ///     which is the honest reading of "costs nothing" rather than a
    ///     statement about a cache.
    public init(governor: RequestGovernor, probe: ProviderProofProbe? = nil) {
        self.governor = governor
        self.probe = probe
    }

    // MARK: - Public Methods

    /// A health answer, having spent nothing.
    ///
    /// Still answers once the day's budget is gone and once the provider has
    /// refused, and says which of the two it is in
    /// ``ChainHealthReport/budget`` rather than by changing the status.
    ///
    /// A probe that has nothing to offer never fails the answer: proof simply
    /// goes missing, which is the rule the probe already follows, because a
    /// health answer that fabricates proof is worse than one that admits it
    /// has none. When nothing usable is held, one probe is started **beside**
    /// the answer rather than in front of it, so this answer costs nothing and
    /// the next one carries proof.
    ///
    /// - Parameters:
    ///   - components: What this instance has to have reached, in the order
    ///     they should be reported. Only the host knows them.
    ///   - now: Injected so a test pins the day and the proof's lifetime.
    public func report(
        components: [ChainHealthComponent],
        now: Date = Date()
    ) async -> ChainHealthReport {
        let snapshot = await governor.snapshot(now: now)
        // The held read, never `proof(now:)`, which refreshes a stale answer
        // and would put a network call on the one path that must never make
        // one: fine in every test, a surprise in production at the moment the
        // cache expires.
        let held = await probe?.heldProof(now: now)
        if held == nil {
            // The part that makes the other two worth having. Nothing else in
            // this module ever calls the probe, so without this the cache the
            // read above reads is filled by nobody and no answer can ever
            // carry proof. It returns as soon as it has started a probe, and
            // starts none while what is held is still within its lifetime.
            await probe?.refreshInBackground(now: now)
        }
        return ChainHealthReport(components: components, budget: snapshot, proof: held)
    }
}
