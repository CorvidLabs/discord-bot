import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// The socket, over loopback, with nothing mocked between the request and
/// the answer.
@Suite("The listener")
struct ListenerTests {

    // MARK: - Serving

    @Test("The page is served over a socket, with the headers it is supposed to carry")
    func thePageIsServedForReal() async throws {
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let answer = try LoopbackClient.request("GET /verify HTTP/1.1", to: bound)
        #expect(answer.contains("HTTP/1.1 200 OK"))
        #expect(answer.contains("Referrer-Policy: no-referrer"))
        #expect(answer.contains("Content-Type: text/html; charset=utf-8"))
        #expect(answer.contains("Only go on if that is your own account"))

        let missing = try LoopbackClient.request("GET /metrics HTTP/1.1", to: bound)
        #expect(missing.contains("HTTP/1.1 404 Not Found"))
    }

    @Test("A body that arrives after its headers is read, rather than answered as empty")
    func aSplitRequestIsWaitedFor() async throws {
        // The one place this listener departs from the callback listener
        // beside it, which takes whatever a single read produced. That is
        // right for one cooperating service and wrong for a browser, which
        // is free to put the headers in one segment and the body in the
        // next. Goes red against reading once.
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: Date()
        )
        let answer = try LoopbackClient.send(
            LoopbackClient.split(
                "POST /verify/card HTTP/1.1",
                body: "{\"session\":\"\(session.id.value)\"}"
            ),
            to: bound
        )
        #expect(answer.contains("HTTP/1.1 200 OK"))
        #expect(answer.contains(SurfaceFixtures.accountName))
        #expect(!answer.contains(session.id.value))
    }

    @Test("A request that is not a request at all is answered and the connection closed")
    func rubbishIsAnswered() async throws {
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        // Exactly one of the two, named: this one does parse, as a request
        // for "http" by a method called "not", so it is a path this surface
        // does not serve. Accepting either status here would pass a
        // listener that answered `404` to everything.
        let parsed = try LoopbackClient.send(["not http at all\r\n\r\n"], to: bound)
        #expect(parsed.contains("HTTP/1.1 404 Not Found"))

        // This one does not parse: the header block has ended and the line
        // endings are not a request's, so nothing that arrives later could
        // make it one.
        let unparsed = try LoopbackClient.send(["GET /verify HTTP/1.1\n\n"], to: bound)
        #expect(unparsed.contains("HTTP/1.1 400 Bad Request"))
    }

    @Test("A request that can never parse is answered as soon as that is known")
    func anUnparseableRequestIsNotWaitedOut() async throws {
        // The read loop only ever stopped early on a request that parsed,
        // and a request line with one word in it, or line endings that are
        // not a request's, never will however much more arrives. Waiting
        // for the budget to run out is what let four bytes hold a
        // connection, and a worker with it, for the whole of it.
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service, peerTimeoutSeconds: 4)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let answered = try LoopbackClient.drip(["GET /verify HTTP/1.1\n\n"], to: bound, pausing: 0)
        #expect(answered.answer.contains("HTTP/1.1 400 Bad Request"))
        #expect(answered.seconds < 1.5, "answered after \(answered.seconds) seconds of a four second budget")
    }

    // MARK: - Peers that do not say anything

    @Test("A peer that drips a byte at a time is answered on the budget, not on its own schedule")
    func aDripIsBoundedByTheRequestRatherThanTheRead() async throws {
        // `SO_RCVTIMEO` bounds one `recv`, so every byte a peer sends
        // restarts it and the documented budget bounds nothing. Goes red
        // against a read loop with no deadline of its own: the answer then
        // waits for the peer to stop dripping.
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service, peerTimeoutSeconds: 1)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let head = "POST /verify/card HTTP/1.1\r\nHost: localhost\r\nContent-Length: 9000\r\n\r\n"
        let dripped = try LoopbackClient.drip(
            [head, " ", " ", " ", " ", " ", " ", " ", " "],
            to: bound,
            pausing: 0.4
        )
        #expect(dripped.seconds < 2.5, "held for \(dripped.seconds) seconds against a one second budget")
        #expect(dripped.answer.contains("HTTP/1.1 400 Bad Request"))
    }

    @Test("Connections being read at once are bounded, and the rest are closed rather than parked")
    func aFloodIsRefusedAtAcceptRatherThanHeld() async throws {
        // The three rate limiters are asked once a whole request has been
        // read, so none of them can see a peer that never sends one. The
        // bound on connections in flight is what can: without it these
        // connections sit on the queue's finite workers and the page goes
        // unanswered with nothing refused and nothing logged.
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(
            service: surface.service,
            peerTimeoutSeconds: 4,
            maximumConcurrentReads: 2
        )
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let silent = try [LoopbackClient.hold(to: bound), LoopbackClient.hold(to: bound)]
        try await Task.sleep(nanoseconds: 200_000_000)
        let waited = try LoopbackClient.secondsUntilClosed(to: bound, giveUpAfter: 2)
        #expect(waited < 1, "a connection over the bound was held for \(waited) seconds")

        // And the slots come back: the silent peers go away, and the page
        // is served again on the same port.
        for connection in silent { LoopbackClient.release(connection) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let answer = try LoopbackClient.request("GET /verify HTTP/1.1", to: bound)
        #expect(answer.contains("HTTP/1.1 200 OK"))
    }

    // MARK: - Binding

    @Test("Port zero is accepted, so a test binds without choosing a number")
    func portZeroIsAccepted() async throws {
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        #expect(bound.port != 0)
        #expect(bound.address == "127.0.0.1")
        let serving = await listener.isServing
        #expect(serving)
        await listener.stop()
        let afterwards = await listener.isServing
        #expect(!afterwards)
    }

    @Test("An address this machine cannot bind is refused before anything is served")
    func aBadAddressIsRefused() async throws {
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service)
        await #expect(throws: VerifyHTTPListenerError.addressUnusable(address: "not-an-address")) {
            _ = try await listener.bind(address: "not-an-address", port: 0)
        }
    }

    @Test("A second bind of the same port is refused, which is how a second copy finds out")
    func aTakenPortIsRefused() async throws {
        let first = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: first.service)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        defer { Task { await listener.stop() } }

        let second = try SurfaceFixtures.surface()
        let duplicate = VerifyHTTPListener(service: second.service)
        await #expect(throws: VerifyHTTPListenerError.addressInUse(address: "127.0.0.1", port: bound.port)) {
            _ = try await duplicate.bind(address: "127.0.0.1", port: bound.port)
        }
    }

    @Test("Stopping gives the port back, so the next bind of it succeeds")
    func stoppingGivesThePortBack() async throws {
        let surface = try SurfaceFixtures.surface()
        let listener = VerifyHTTPListener(service: surface.service)
        let bound = try await listener.bind(address: "127.0.0.1", port: 0)
        await listener.stop()

        let again = VerifyHTTPListener(service: surface.service)
        let rebound = try await again.bind(address: "127.0.0.1", port: bound.port)
        #expect(rebound.port == bound.port)
        await again.stop()
    }
}
