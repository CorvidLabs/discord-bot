import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// The half of the budget story the module below deliberately does not carry
/// (REQ-verify-004, REQ-verify-009, RUN-11).
@Suite("The rate limit")
struct RateLimitTests {

    // MARK: - The limiter

    @Test("A window slides, and asking is recording")
    func theWindowSlides() async {
        // Asking and recording are one call. Two calls leave a window
        // between them in which every request in flight is under the limit,
        // which is the bug a rate limit exists to not have.
        let limiter = VerifyRateLimiter(limit: 2, window: 60)
        let start = SurfaceFixtures.now
        #expect(await limiter.isLimited(key: "a", now: start) == false)
        #expect(await limiter.isLimited(key: "a", now: start) == false)
        #expect(await limiter.isLimited(key: "a", now: start) == true)
        // A different key is a different budget.
        #expect(await limiter.isLimited(key: "b", now: start) == false)
        // One second past the window and the first two have fallen out.
        #expect(await limiter.isLimited(key: "a", now: start.addingTimeInterval(61)) == false)
    }

    @Test("The table of keys does not grow for ever")
    func staleKeysAreDropped() async {
        let limiter = VerifyRateLimiter(limit: 1, window: 10)
        let start = SurfaceFixtures.now
        for index in 0..<50 {
            _ = await limiter.isLimited(key: "source-\(index)", now: start)
        }
        #expect(await limiter.trackedKeyCount == 50)
        await limiter.forget(before: start.addingTimeInterval(11))
        #expect(await limiter.trackedKeyCount == 0)
    }

    @Test("The ceiling holds when every key in the table is live, which is when it is needed")
    func theCeilingHoldsAgainstLiveKeys() async {
        // Dropping stale keys is all the ceiling used to do about an
        // overflow, and it frees nothing when every key is inside the
        // window: exactly what a flood of distinct sources produces, and
        // the case the ceiling exists for. Goes red against a limiter that
        // can only drop stale keys, where the table simply grows past it.
        let limiter = VerifyRateLimiter(limit: 5, window: 600)
        let start = SurfaceFixtures.now
        // The quietest key in the table: spent up, at the start of the
        // window.
        for _ in 0..<5 {
            _ = await limiter.isLimited(key: "quiet", now: start)
        }
        for index in 0..<VerifyRateLimiter.maximumTrackedKeys {
            _ = await limiter.isLimited(
                key: "source-\(index)",
                now: start.addingTimeInterval(1 + Double(index) / 1_000)
            )
        }
        // And the loudest: spent up, at the end of it.
        let latest = start.addingTimeInterval(300)
        for _ in 0..<5 {
            _ = await limiter.isLimited(key: "loud", now: latest)
        }

        #expect(await limiter.trackedKeyCount <= VerifyRateLimiter.maximumTrackedKeys)
        // What eviction costs, and who it costs it to: the key nobody has
        // heard from for longest is forgiven its history, and the one that
        // is spending right now keeps every hit of it.
        #expect(await limiter.isLimited(key: "loud", now: latest) == true)
        #expect(await limiter.isLimited(key: "quiet", now: latest) == false)
    }

    // MARK: - On the routes

    @Test("The page is rate limited, and going over it is a 429 rather than a served page")
    func thePageIsLimited() async throws {
        let limits = try VerifyHTTPLimits(
            assetRequestsPerSource: 2,
            apiRequestsPerSource: 12,
            apiRequestsPerSession: 12,
            window: 60,
            maximumBodyBytes: 8_192
        )
        let surface = try SurfaceFixtures.surface(limits: limits)
        for _ in 0..<2 {
            let served = await surface.service.respond(
                to: SurfaceFixtures.get(VerifyRouting.pagePath),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(served.status == 200)
        }
        let refused = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(refused.status == 429)
        // Another source is not held to somebody else's spending.
        let elsewhere = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath),
            from: "198.51.100.4",
            now: SurfaceFixtures.now
        )
        #expect(elsewhere.status == 200)
    }

    @Test("The submit route is rate limited per source and per session, both")
    func theSubmitRouteIsLimitedTwice() async throws {
        // Per source is the weaker of the two: behind a reverse proxy every
        // member arrives from one address. Per session is the one that
        // actually bounds a member, and it counts against a value only
        // their own link produces.
        let limits = try VerifyHTTPLimits(
            assetRequestsPerSource: 30,
            apiRequestsPerSource: 3,
            apiRequestsPerSession: 2,
            window: 60,
            maximumBodyBytes: 8_192
        )
        let surface = try SurfaceFixtures.surface(limits: limits)
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        for _ in 0..<2 {
            let answered = await surface.service.respond(
                to: SurfaceFixtures.submit(session.id, blob: "nope"),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(answered.status != 429)
        }
        let overSession = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: "nope"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(overSession.status == 429)
        #expect(SurfaceFixtures.fields(overSession)["handle"] as? String
            == VerifySessionHandle(sessionIdentifier: session.id).value)

        // A second session from the same source runs into the per-source
        // budget instead, which has one request left in it.
        let second = try await surface.coordinator.mint(
            subject: "112233445566778899aabbccddeeff00",
            now: SurfaceFixtures.now
        )
        let overSource = await surface.service.respond(
            to: SurfaceFixtures.submit(second.id, blob: "nope"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(overSource.status == 429)
        // Nothing about a session is disclosed by a per-source refusal,
        // which is reached before the body is read at all.
        #expect(SurfaceFixtures.fields(overSource)["handle"] == nil)
    }

    @Test("A request refused for its query string costs nobody anything either")
    func aQueryStringCostsNobodyAnything() async throws {
        // The same rule as a wrong path, for the same reason. This request
        // will not be served whatever budget is left, so charging it lets
        // somebody who appends a tracking parameter spend a budget that,
        // behind a reverse proxy, is the whole community's. Goes red
        // against a limiter asked before the query string is looked at:
        // the fourth of these is then a `429` and the page load after them
        // is refused as well.
        let limits = try VerifyHTTPLimits(
            assetRequestsPerSource: 3,
            apiRequestsPerSource: 3,
            apiRequestsPerSession: 3,
            window: 60,
            maximumBodyBytes: 8_192
        )
        let surface = try SurfaceFixtures.surface(limits: limits)
        for _ in 0..<20 {
            let refused = await surface.service.respond(
                to: SurfaceFixtures.get(VerifyRouting.pagePath + "?utm_source=elsewhere"),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(refused.status == 400)
        }
        for _ in 0..<20 {
            let refused = await surface.service.respond(
                to: SurfaceFixtures.post(VerifyRouting.cardPath + "?x=1", body: "{}"),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(refused.status == 400)
        }
        let served = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(served.status == 200)
    }

    @Test("The standard budgets are an instance's, not one member's, because a proxy is one source")
    func theStandardBudgetsAreSizedForEverybody() async throws {
        // Behind a reverse proxy every request arrives from the proxy, so
        // these two numbers are shared by the whole community. A page load
        // is three asset requests and a verification is three calls, so a
        // number that reads like a generous allowance for one member is
        // the minute in which everybody else is refused, with nothing in
        // the answer to say it was somebody else who spent it.
        let surface = try SurfaceFixtures.surface()
        for _ in 0..<30 {
            for path in [VerifyRouting.pagePath, VerifyRouting.stylesheetPath, VerifyRouting.scriptPath] {
                let served = await surface.service.respond(
                    to: SurfaceFixtures.get(path),
                    from: SurfaceFixtures.source,
                    now: SurfaceFixtures.now
                )
                #expect(served.status == 200)
            }
        }
        for index in 0..<30 {
            let session = try await surface.coordinator.mint(
                subject: String(format: "%032x", index),
                now: SurfaceFixtures.now
            )
            let answered = await surface.service.respond(
                to: SurfaceFixtures.card(session.id),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(answered.status == 200)
        }
    }

    @Test("A wrong path is not counted against anybody, so a scanner cannot lock a member out")
    func aWrongPathCostsNobodyAnything() async throws {
        let limits = try VerifyHTTPLimits(
            assetRequestsPerSource: 2,
            apiRequestsPerSource: 2,
            apiRequestsPerSession: 2,
            window: 60,
            maximumBodyBytes: 8_192
        )
        let surface = try SurfaceFixtures.surface(limits: limits)
        for _ in 0..<20 {
            let answered = await surface.service.respond(
                to: SurfaceFixtures.get("/wp-login.php"),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(answered.status == 404)
        }
        let served = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(served.status == 200)
    }

    // MARK: - Configuration

    @Test("A limit of nothing is refused at construction, naming the one to fix")
    func aLimitOfNothingIsRefused() {
        #expect(throws: VerifyHTTPLimitsError.countNotPositive(field: "apiRequestsPerSession")) {
            _ = try VerifyHTTPLimits(
                assetRequestsPerSource: 1,
                apiRequestsPerSource: 1,
                apiRequestsPerSession: 0,
                window: 60,
                maximumBodyBytes: 8_192
            )
        }
        #expect(throws: VerifyHTTPLimitsError.windowNotPositive(field: "window")) {
            _ = try VerifyHTTPLimits(
                assetRequestsPerSource: 1,
                apiRequestsPerSource: 1,
                apiRequestsPerSession: 1,
                window: 0,
                maximumBodyBytes: 8_192
            )
        }
    }
}
