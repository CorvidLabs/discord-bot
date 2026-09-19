import Foundation
import Testing
@testable import Chain

/// The per second brake.
///
/// The arithmetic is tested through the bucket, with no clock, so the
/// boundaries are pinned rather than approximated: a limiter whose only test
/// sleeps and hopes is a limiter nobody dares change.
@Suite("The per second brake")
internal struct RateLimiterTests {

    // MARK: - The bucket

    @Test("A fresh bucket lets the first second of work straight through")
    internal func startsFull() {
        var bucket = TokenBucket(requestsPerSecond: 10)
        #expect(bucket.tokens == 10)
        let took = bucket.take(10)
        #expect(took)
        #expect(bucket.tokens == 0)
    }

    @Test("Asking for more than is there takes nothing at all")
    internal func refusalTakesNothing() {
        var bucket = TokenBucket(requestsPerSecond: 10)
        let took = bucket.take(4)
        let refused = bucket.take(7)
        #expect(took)
        #expect(refused == false)
        #expect(bucket.tokens == 6)
    }

    @Test("Waiting the time it says is enough to get what was asked for")
    internal func waitIsLongEnough() {
        var bucket = TokenBucket(requestsPerSecond: 10)
        _ = bucket.take(10)
        let wait = bucket.waitSeconds(for: 5)
        #expect(wait == 0.5)
        bucket.refill(elapsedSeconds: wait)
        let tookAfterWaiting = bucket.take(5)
        #expect(tookAfterWaiting)
    }

    @Test("Nothing to wait for when the requests are already there")
    internal func noWaitWhenAvailable() {
        let bucket = TokenBucket(requestsPerSecond: 10)
        #expect(bucket.waitSeconds(for: 10) == 0)
    }

    @Test("An hour of idleness does not buy an hour of requests to spend at once")
    internal func idlingDoesNotBank() {
        var bucket = TokenBucket(requestsPerSecond: 10)
        _ = bucket.take(10)
        bucket.refill(elapsedSeconds: 3_600)
        #expect(bucket.tokens == 10)
        let tookMoreThanTheBucketHolds = bucket.take(11)
        #expect(tookMoreThanTheBucketHolds == false)
    }

    @Test("Time going backwards leaves the bucket alone rather than emptying it")
    internal func backwardsTimeIsIgnored() {
        var bucket = TokenBucket(requestsPerSecond: 10)
        _ = bucket.take(6)
        bucket.refill(elapsedSeconds: -50)
        #expect(bucket.tokens == 4)
    }

    @Test("A rate too small to hold a single request is raised to one rather than stopping everything")
    internal func capacityNeverFallsBelowOneRequest() {
        // A bucket smaller than one request refuses every take, and the caller
        // of `acquire` waits instead of failing, so the first read of the
        // sweep would sleep for the life of the process.
        var bucket = TokenBucket(requestsPerSecond: 0.25)
        #expect(bucket.requestsPerSecond == 1)
        let tookOne = bucket.take(1)
        #expect(tookOne)
    }

    // MARK: - The actor

    @Test("Requests within the rate are handed out without waiting")
    internal func takesWithoutWaiting() async {
        let limiter = RequestRateLimiter(requestsPerSecond: 100)
        #expect(await limiter.tryAcquire(count: 100))
        #expect(await limiter.tryAcquire() == false)
    }

    @Test("A request past the rate waits for its turn instead of being refused")
    internal func waitsRatherThanRefusing() async {
        let limiter = RequestRateLimiter(requestsPerSecond: 200)
        #expect(await limiter.tryAcquire(count: 200))
        // Comes back rather than throwing: the caller is the bot's own sweep,
        // and slowing it down is the entire purpose.
        await limiter.acquire()
        #expect(await limiter.availableRequests < 200)
    }

    @Test("A batch bigger than the bucket is taken a bucketful at a time rather than never")
    internal func acquiringMoreThanTheBucketHoldsFinishes() async {
        // The bucket is capped at a second's worth on purpose, so a batch
        // larger than the rate can never be taken in one go. Waiting for the
        // whole amount was a permanent hang: sleep, refill to the cap, ask for
        // more than the cap, forever, with no error and no notice.
        let limiter = RequestRateLimiter(requestsPerSecond: 1_000)
        await limiter.acquire(count: 1_100)
        #expect(await limiter.availableRequests < 1_000)
    }

    @Test("The limiter takes its rate from configuration rather than a number in the source")
    internal func rateComesFromConfiguration() async throws {
        let configuration = try Fixture.configuration(limits: ChainLimits(requestsPerSecond: 3))
        let limiter = RequestRateLimiter(limits: configuration.limits)
        #expect(await limiter.tryAcquire(count: 3))
        #expect(await limiter.tryAcquire() == false)
    }
}
