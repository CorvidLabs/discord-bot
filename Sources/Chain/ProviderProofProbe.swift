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
            cachedProof = nil
            cachedUntil = nil
            lastFailure = error.localizedDescription
        }
        return cachedProof
    }

    /// Drops whatever is cached, so the next call probes.
    public func invalidate() {
        cachedProof = nil
        cachedUntil = nil
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
