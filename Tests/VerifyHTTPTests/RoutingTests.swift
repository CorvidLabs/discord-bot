import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// What this surface answers, what it refuses before reading anything, and
/// where a session id is allowed to travel (REQ-verify-009, REQ-verify-010).
@Suite("The routes")
struct RoutingTests {

    // MARK: - The table

    @Test("Every route has one path and one method, and nothing else is served")
    func oneTableAndNoOther() {
        for route in VerifyHTTPRoute.allCases {
            let path = VerifyRouting.path(of: route)
            let method = VerifyRouting.method(of: route)
            #expect(VerifyRouting.match(method: method, path: path) == .matched(route))
        }
        #expect(VerifyRouting.match(method: "GET", path: "/") == .unknown)
        #expect(VerifyRouting.match(method: "GET", path: "/verify/app.js/") == .unknown)
        #expect(VerifyRouting.match(method: "GET", path: "/health") == .unknown)
    }

    @Test("A session id travels by POST, because a request line is what a log writes down")
    func credentialsTravelInBodies() {
        // Goes red against somebody adding a GET route that takes a session
        // id, which is the shape that puts a bearer credential in every
        // access log on the path (REQ-verify-003).
        for route in VerifyHTTPRoute.allCases where VerifyRouting.carriesSessionIdentifier(route) {
            #expect(VerifyRouting.method(of: route) == "POST")
        }
        #expect(VerifyRouting.carriesSessionIdentifier(.card))
        #expect(VerifyRouting.carriesSessionIdentifier(.connect))
        #expect(VerifyRouting.carriesSessionIdentifier(.submit))
        #expect(!VerifyRouting.carriesSessionIdentifier(.page))
    }

    @Test("The right path with the wrong method is 405, and an unknown path is 404")
    func methodsAreNotInterchangeable() async throws {
        let surface = try SurfaceFixtures.surface()
        let wrongMethod = await surface.service.respond(
            to: VerifyHTTPRequest(method: "GET", target: VerifyRouting.submitPath, headers: [:], body: ""),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(wrongMethod.status == 405)

        let unknown = await surface.service.respond(
            to: SurfaceFixtures.get("/admin"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(unknown.status == 404)
    }

    // MARK: - The query string

    @Test("A request carrying a query string is refused, on the page as well as on a call")
    func aQueryStringIsRefusedEverywhere() async throws {
        // Goes red against the obvious reading of "drop the query and match
        // the route", which serves a request that has already written a
        // session id into an access log.
        let surface = try SurfaceFixtures.surface()
        let page = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath + "?session=deadbeef"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(page.status == 400)

        let answered = await surface.service.respond(
            to: SurfaceFixtures.post(VerifyRouting.cardPath + "?x=1", body: "{}"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 400)
    }

    // MARK: - Bodies

    @Test("A body that is not JSON, and one with no session id in it, are refused without a handle")
    func bodiesAreRefusedWithoutSayingAnything() async throws {
        let surface = try SurfaceFixtures.surface()
        let notJSON = await surface.service.respond(
            to: SurfaceFixtures.post(VerifyRouting.cardPath, body: "hello"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(notJSON.status == 400)
        #expect(SurfaceFixtures.fields(notJSON)["handle"] == nil)

        let notAnIdentifier = await surface.service.respond(
            to: SurfaceFixtures.post(VerifyRouting.cardPath, body: "{\"session\":\"nope\"}"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(notAnIdentifier.status == 400)
        // No handle: a handle is a digest of a session, and this is a digest
        // of whatever somebody typed.
        #expect(SurfaceFixtures.fields(notAnIdentifier)["handle"] == nil)
    }

    @Test("A body over the ceiling is refused before anything parses it")
    func aBodyOverTheCeilingIsRefused() async throws {
        let surface = try SurfaceFixtures.surface()
        let oversized = String(repeating: "a", count: surface.service.limits.maximumBodyBytes + 1)
        let answered = await surface.service.respond(
            to: SurfaceFixtures.post(VerifyRouting.submitPath, body: oversized),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 413)
    }

    // MARK: - Parsing

    @Test("A request is not a request until its header block has been terminated")
    func aPartialRequestIsNotARequest() {
        // Goes red against a parser that answers as soon as it has a request
        // line, which is how a browser that sends its headers in one segment
        // and its body in the next gets its submission read as empty.
        #expect(VerifyHTTPRequest.parse("POST /verify/submit HTTP/1.1\r\nHost: x") == nil)
        let whole = VerifyHTTPRequest.parse(
            "POST /verify/submit HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{}"
        )
        #expect(whole?.body == "{}")
        #expect(whole?.isComplete == true)

        let truncated = VerifyHTTPRequest.parse(
            "POST /verify/submit HTTP/1.1\r\nContent-Length: 9\r\n\r\n{}"
        )
        #expect(truncated?.isComplete == false)
    }

    @Test("A message whose framing cannot be trusted is not a message")
    func framingIsNotTheSendersToChoose() {
        // RFC 9112 6.3. Two lengths that disagree is a sender picking which
        // bytes this surface reads as the body, and the read loop's own
        // "has it all arrived" question is decided by that field. Goes red
        // against a parser where the last header line simply wins.
        #expect(VerifyHTTPRequest.parse(
            "POST /verify/submit HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 9\r\n\r\n{}"
        ) == nil)
        #expect(VerifyHTTPRequest.parse(
            "POST /verify/submit HTTP/1.1\r\nContent-Length: two\r\n\r\n{}"
        ) == nil)
        #expect(VerifyHTTPRequest.parse(
            "POST /verify/submit HTTP/1.1\r\nContent-Length: -1\r\n\r\n{}"
        ) == nil)
        // A repeat that agrees is not a disagreement, and a browser is
        // allowed its own idea of how to write a header block.
        let agreeing = VerifyHTTPRequest.parse(
            "POST /verify/submit HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}"
        )
        #expect(agreeing?.declaredBodyByteCount == 2)
    }

    @Test("The path is the target with the query taken off, and the query is never read")
    func theQueryIsSeenAndNotRead() {
        let request = VerifyHTTPRequest(
            method: "GET",
            target: "/verify?a=1&b=2",
            headers: [:],
            body: ""
        )
        #expect(request.path == "/verify")
        #expect(request.carriesQuery)
    }
}
