import Foundation

/// The per second brake.
///
/// One of the two things that stop the chain being read too much, and the one
/// that answers to the provider's published rate. **It is not the other one.**
/// At nine hundred requests a second a free daily quota is gone in minutes, and
/// this limiter would have allowed every one of them: it is doing its job
/// perfectly while the day's budget disappears. That is why
/// ``DailyRequestBudget`` exists alongside it, and why removing either one
/// leaves a hole the other does not cover.
public actor RequestRateLimiter {

    // MARK: - Properties

    private var bucket: TokenBucket
    private var lastRefill: ContinuousClock.Instant
    private let clock = ContinuousClock()

    // MARK: - Initializers

    /// - Parameter requestsPerSecond: The rate to hold to.
    public init(requestsPerSecond: Double) {
        self.bucket = TokenBucket(requestsPerSecond: requestsPerSecond)
        self.lastRefill = ContinuousClock().now
    }

    /// - Parameter limits: Takes the configured rate.
    public init(limits: ChainLimits) {
        self.init(requestsPerSecond: limits.requestsPerSecond)
    }

    // MARK: - Public Methods

    /// Waits until one request is allowed, then takes it.
    public func acquire() async {
        await acquire(count: 1)
    }

    /// Waits until `count` requests are allowed, then takes them.
    ///
    /// A monotonic clock, not a wall clock: a host that corrects its time
    /// backwards mid sweep would otherwise hand the bucket a negative elapsed
    /// stretch, or a step forward would fill it in one go.
    ///
    /// **Asking for more than the bucket can ever hold is not an error.** It is
    /// taken a bucketful at a time, which is slow and finishes. Waiting for the
    /// whole amount in one go does not finish: the bucket is capped at a
    /// second's worth on purpose, so a pool read asking for two requests
    /// against a configured rate of one would sleep, refill, ask again, and go
    /// on doing that for as long as the process lived. No error, no notice, and
    /// a role sweep that never came back.
    public func acquire(count: Int) async {
        var remaining = Double(max(count, 1))
        refill()
        while remaining > 0 {
            let chunk = Swift.min(remaining, bucket.requestsPerSecond)
            if bucket.take(chunk) {
                remaining -= chunk
                continue
            }
            // Never more than a second, because `chunk` is never more than the
            // bucket holds. Clamped all the same: an unchecked conversion to
            // `Int64` traps, and a trap here is the whole process.
            let wait = Swift.min(Swift.max(bucket.waitSeconds(for: chunk), 0), 1)
            // At least a millisecond, so a vanishing deficit cannot spin.
            let duration = Duration.milliseconds(Int64(wait * 1_000) + 1)
            try? await clock.sleep(for: duration)
            refill()
        }
    }

    /// Takes one request if it is available, without waiting.
    public func tryAcquire() -> Bool {
        tryAcquire(count: 1)
    }

    /// Takes `count` requests if they are available, without waiting.
    public func tryAcquire(count: Int) -> Bool {
        refill()
        return bucket.take(Double(max(count, 1)))
    }

    /// Requests available right now.
    public var availableRequests: Double {
        bucket.tokens
    }

    /// Runs `operation` once a request is allowed.
    public func execute<Output: Sendable>(
        _ operation: @Sendable () async throws -> Output
    ) async rethrows -> Output {
        await acquire()
        return try await operation()
    }

    // MARK: - Private Methods

    private func refill() {
        let now = clock.now
        let elapsed = now - lastRefill
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        bucket.refill(elapsedSeconds: seconds)
        lastRefill = now
    }
}
