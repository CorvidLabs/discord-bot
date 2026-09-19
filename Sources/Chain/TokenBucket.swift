import Foundation

/// The arithmetic behind the per second limiter, with no clock in it.
///
/// Split out from the actor that owns it so the refill and the wait can be
/// checked by a test that finishes instantly. A limiter whose only test is
/// "it seemed to wait about the right amount of time" is a limiter nobody
/// rewrites, and the interesting cases here are the boundaries: asking for
/// more than a second's worth, asking with an empty bucket, and a long idle
/// stretch that must not bank more than one second of requests.
///
/// The counts are `Double` because a rate is a rate. Nothing here is money, and
/// nothing here is ever converted into an amount.
public struct TokenBucket: Sendable, Equatable {

    // MARK: - Properties

    /// Requests per second, which is also the most the bucket ever holds.
    ///
    /// Capacity and rate are the same number deliberately: idling for an hour
    /// must not buy an hour's worth of requests to spend in one burst, which is
    /// exactly the burst a provider's rate limit exists to refuse.
    public let requestsPerSecond: Double

    /// Requests available right now.
    public private(set) var tokens: Double

    // MARK: - Initializers

    /// - Parameter requestsPerSecond: Held at one or more. The bucket starts
    ///   full, so the first second of work is not slowed down.
    ///
    /// A capacity below a single request is not a slower limiter, it is a
    /// stopped one. ``take(_:)`` refuses anything larger than the bucket and
    /// ``RequestRateLimiter/acquire()`` waits rather than failing, so a tenth
    /// of a request a second would leave the first read of the sweep asleep
    /// for the life of the process.
    public init(requestsPerSecond: Double) {
        let rate = requestsPerSecond.isFinite ? requestsPerSecond : 1
        self.requestsPerSecond = Swift.max(rate, 1)
        self.tokens = self.requestsPerSecond
    }

    // MARK: - Public Methods

    /// Adds the requests that have accrued since the last refill.
    public mutating func refill(elapsedSeconds: Double) {
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return }
        tokens = min(requestsPerSecond, tokens + elapsedSeconds * requestsPerSecond)
    }

    /// Takes `count` requests if they are there.
    /// - Returns: Whether they were taken. Nothing is taken on a refusal.
    public mutating func take(_ count: Double) -> Bool {
        guard count <= tokens else { return false }
        tokens -= count
        return true
    }

    /// How long to wait before `count` requests would be available.
    ///
    /// Zero when they already are. A request for more than the bucket can ever
    /// hold still answers with a time rather than never: the caller waits for
    /// the whole bucket and takes what it can, which is slow but finishes.
    public func waitSeconds(for count: Double) -> Double {
        guard count > tokens else { return 0 }
        return (count - tokens) / requestsPerSecond
    }
}
