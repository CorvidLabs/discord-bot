@preconcurrency import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One cheap request whose response headers are what is wanted.
///
/// A seam, so that the caching and the never-invent-a-success rule below are
/// testable without a network, and so that a host can probe whatever endpoint
/// its provider stamps.
public protocol HTTPHeaderProbe: Sendable {

    /// Makes the request and returns its response headers.
    func probeHeaders() async throws -> [String: String]
}

/// The last thing a provider said about itself, kept for a little while.
///
/// Cached because a health endpoint is called by monitoring on a timer, and
/// turning every one of those into a request to the node makes the health
/// check itself the heaviest caller in the process.
///
/// The probe deliberately does **not** go through the request governor. A
/// health check must keep working when the day's budget is spent, because that
/// is exactly the moment somebody is looking at it, and it must not be the
/// thing that spends the last of the budget either.
public actor ProviderProofProbe {

    // MARK: - Properties

    private let probe: any HTTPHeaderProbe
    private let headerNames: [String]
    private let lifetime: TimeInterval
    private var cachedProof: ProviderProof?
    private var cachedUntil: Date?
    private var isRefreshing = false
    private var refreshTask: Task<Void, Never>?

    /// Why the last probe failed, when it did. Kept so a health surface can
    /// say what is wrong rather than only that proof is missing.
    public private(set) var lastFailure: String?

    // MARK: - Initializers

    /// - Parameters:
    ///   - probe: Makes the request.
    ///   - headerNames: Which headers to copy. Empty means never probe at all,
    ///     which is the right answer for a provider that stamps nothing.
    ///   - lifetime: Seconds an answer is reused.
    public init(probe: any HTTPHeaderProbe, headerNames: [String], lifetime: TimeInterval) {
        self.probe = probe
        self.headerNames = headerNames
        self.lifetime = max(lifetime, 0)
    }

    /// - Parameters:
    ///   - probe: Makes the request.
    ///   - configuration: Takes the configured header names and lifetime.
    public init(probe: any HTTPHeaderProbe, configuration: ChainConfiguration) {
        self.init(
            probe: probe,
            headerNames: configuration.proofHeaderNames,
            lifetime: configuration.cacheLifetimes.healthProbe
        )
    }

    // MARK: - Public Methods

    /// Proof from the last successful probe, refreshing it when it is stale.
    ///
    /// **A failed probe never invents a success.** If nothing usable has been
    /// seen, this answers nil and the health body simply has no provider
    /// section. The one thing it must never do is report the paid path as
    /// active because the paid path was active half an hour ago.
    public func proof(now: Date = Date()) async -> ProviderProof? {
        guard !headerNames.isEmpty else { return nil }
        if let cachedUntil, now < cachedUntil {
            return cachedProof
        }
        do {
            let headers = try await probe.probeHeaders()
            cachedProof = ProviderProof.parse(headers: headers, names: headerNames)
            cachedUntil = now.addingTimeInterval(lifetime)
            lastFailure = nil
        } catch {
            // The stale answer is dropped rather than served on: proof that a
            // provider served a request half an hour ago is not proof that it
            // is serving them now, and the whole point of the field is that it
            // is evidence.
            //
            // The failure itself is kept for the same lifetime a success gets.
            // A monitoring check runs on a timer, and a provider that is down
            // would otherwise be probed once per check for as long as it is
            // down, which is the health check becoming the load at the moment
            // the node can least take it.
            cachedProof = nil
            cachedUntil = now.addingTimeInterval(lifetime)
            lastFailure = error.localizedDescription
        }
        return cachedProof
    }

    /// The proof already held, making no request and changing nothing.
    ///
    /// Separate from ``proof(now:)`` because that one refreshes a stale
    /// answer, and a health answer routed through it would put a network call
    /// on the one path that must never make one: fine in every test, and a
    /// surprise in production at the moment the cache expires. This is the
    /// read the health assembly uses, and a reviewer should be able to name it
    /// and see that the assembly calls this one.
    ///
    /// A held answer past its lifetime reads as absent rather than being
    /// refreshed here, which is the rule this type already follows for a stale
    /// answer: proof that a provider served a request half an hour ago is not
    /// proof that it is serving them now.
    ///
    /// What fills the cache this reads is ``refreshInBackground(now:)``, off
    /// the answering path. A read that never probes and nothing else probing
    /// is a health answer that can never carry proof at all.
    ///
    /// - Parameter now: Injected so a test pins the lifetime.
    /// - Returns: The proof, or nil when none is held or what is held is past
    ///   its lifetime.
    public func heldProof(now: Date = Date()) -> ProviderProof? {
        guard let cachedUntil, now < cachedUntil else { return nil }
        return cachedProof
    }

    /// Starts one probe in the background when nothing usable is held.
    ///
    /// The third part of the health path, and the one without which the other
    /// two answer nothing. ``heldProof(now:)`` never goes and gets proof, so
    /// something has to, and it must not be the call that is answering: a
    /// synchronous probe on that path stalled the accepts of the listener this
    /// was ported from for up to four seconds on a cold miss. So the answer
    /// goes out with whatever is held, this starts a probe beside it, and the
    /// next answer has proof.
    ///
    /// One at a time, and never while what is held is still within its
    /// lifetime, so a check on a timer does not become a queue of probes. An
    /// operator who named no headers is never probed at all, here as
    /// everywhere else.
    ///
    /// - Parameter now: Injected so a test pins the lifetime, and stamped on
    ///   whatever the probe brings back.
    /// - Returns: Whether a probe was started, which is what a test asserts on
    ///   rather than on a sleep.
    @discardableResult
    public func refreshInBackground(now: Date = Date()) -> Bool {
        guard !headerNames.isEmpty, !isRefreshing else { return false }
        if let cachedUntil, now < cachedUntil { return false }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            await self?.refresh(now: now)
        }
        return true
    }

    /// Waits for a background probe already started to finish.
    ///
    /// Tests wait on this, and so should a host shutting down deliberately.
    public func flushRefresh() async {
        await refreshTask?.value
    }

    /// Drops whatever is cached, so the next call probes.
    public func invalidate() {
        cachedProof = nil
        cachedUntil = nil
    }

    // MARK: - Private Methods

    private func refresh(now: Date) async {
        _ = await proof(now: now)
        isRefreshing = false
    }
}

/// A probe that makes a plain HTTP request and reads the response headers.
///
/// A raw request rather than a call through the node client, because the
/// headers are the point and a typed client hands back a decoded body with the
/// headers thrown away.
public struct URLSessionHeaderProbe: HTTPHeaderProbe {

    // MARK: - Properties

    private let url: URL
    private let headers: [String: String]
    private let timeout: TimeInterval

    // MARK: - Initializers

    /// - Parameters:
    ///   - url: What to request. Something cheap: a status endpoint, not a
    ///     query over an account.
    ///   - headers: Request headers, such as the provider's token.
    ///   - timeout: Seconds to wait. Short, because a health check that hangs
    ///     is reported as a failure by whatever called it anyway.
    public init(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 5) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
    }

    // MARK: - Public Methods

    public func probeHeaders() async throws -> [String: String] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChainError.network("the probe's answer was not an HTTP response")
        }
        var found: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String, let text = value as? String else { continue }
            found[name] = text
        }
        return found
    }
}
