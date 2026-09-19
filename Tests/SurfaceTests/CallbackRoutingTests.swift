@preconcurrency import Foundation
import Testing

@testable import Surface

/// Everything the listener does to a request, in the order it does it.
@Suite("Callback routing")
struct CallbackRoutingTests {

    private let secret = "a-shared-secret-value"
    private let guildId = "100000000000000002"

    private func request(
        method: String = "POST",
        path: String = "/webhook/verification",
        key: String? = nil,
        body: String = ""
    ) -> HTTPRequestHead {
        var headers: [String: String] = ["content-type": "application/json"]
        if let key { headers["x-api-key"] = key }
        return HTTPRequestHead(method: method, path: path, headers: headers, body: body)
    }

    private func route(
        _ head: HTTPRequestHead,
        limited: Bool = false,
        validAddress: Bool = true
    ) -> CallbackRoute {
        CallbackRouting.route(
            head,
            expectedKey: secret,
            servedGuildId: guildId,
            isRateLimited: limited,
            isValidAddress: { _ in validAddress }
        )
    }

    private func body(
        discordId: String = "100000000000000001",
        guild: String? = nil,
        address: String = "ACCOUNT-ONE"
    ) -> String {
        """
        {"discordId":"\(discordId)","guildId":"\(guild ?? guildId)","walletAddress":"\(address)",\
        "balance":1234,"tier":"whatever"}
        """
    }

    // MARK: - Parsing

    @Test("A request is one read: line, headers and body together")
    func parsing() throws {
        let raw = "POST /webhook/verification HTTP/1.1\r\nHost: bot\r\nX-API-Key: abc\r\n\r\n{\"a\":1}"
        let head = try #require(HTTPRequestHead.parse(raw))
        #expect(head.method == "POST")
        #expect(head.path == "/webhook/verification")
        // Names lowercased, values trimmed, so a header's case never decides
        // whether a secret is found.
        #expect(head.headers["x-api-key"] == "abc")
        #expect(head.body == "{\"a\":1}")
    }

    @Test("A first line that is not a request line is not a request")
    func unparseable() {
        #expect(HTTPRequestHead.parse("garbage") == nil)
        #expect(HTTPRequestHead.parse("") == nil)
    }

    @Test("A query string is not part of the route")
    func queryIsNotRoute() throws {
        let head = try #require(HTTPRequestHead.parse("GET /health?x=1 HTTP/1.1\r\n\r\n"))
        #expect(head.route == "/health")
    }

    // MARK: - The order

    @Test("Health is answered before rate limiting and before the key (SEE-1)")
    func healthIsOutsideEverything() {
        // It is also what the operator's own deploy gate polls, and putting
        // it behind either is how a gate starts failing for a reason nobody
        // can see.
        #expect(route(request(method: "GET", path: "/health"), limited: true) == .health)
    }

    @Test("A wrong path is 404 and is not counted against the rate limit")
    func wrongPathIsNotRateLimited() {
        // Counting a scanner's requests would let a scanner lock out a real
        // callback.
        guard case .refuse(let status, _) = route(request(path: "/nope"), limited: false) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(status == 404)
    }

    @Test("Too many from one source is 429")
    func rateLimited() {
        guard case .refuse(let status, _) = route(request(key: secret), limited: true) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(status == 429)
    }

    @Test("A missing or wrong key is 401, with no detail about which")
    func keyIsChecked() {
        for presented in [nil, "", "wrong", secret + "x"] {
            guard case .refuse(let status, let message) = route(request(key: presented)) else {
                Issue.record("expected a refusal for \(presented ?? "nothing")")
                return
            }
            #expect(status == 401)
            #expect(message == "{\"error\":\"Unauthorized\"}")
        }
    }

    @Test("A body that will not decode is 400, after the key and before the work")
    func badJSONIsRefused() {
        guard case .refuse(let status, let message) = route(request(key: secret, body: "{")) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(status == 400)
        #expect(message == "{\"error\":\"Invalid JSON\"}")
    }

    @Test("A valid key does not make a payload valid: the payload is checked before 200")
    func payloadIsCheckedBeforeSuccess() {
        // A portal that records a verification whenever its callback
        // succeeds must never record one this bot threw away.
        guard case .refuse(let status, let message) = route(
            request(key: secret, body: body(guild: "999999999999999999"))
        ) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(status == 400)
        #expect(message.contains("Wrong guildId"))
    }

    @Test("A malformed member id and a malformed account are each named")
    func eachRefusalIsNamed() {
        guard case .refuse(_, let member) = route(request(key: secret, body: body(discordId: "abc"))) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(member.contains("Invalid discordId"))

        guard case .refuse(_, let account) = route(
            request(key: secret, body: body()),
            validAddress: false
        ) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(account.contains("Invalid walletAddress"))
    }

    @Test("A good callback is accepted, and extra fields do not break it")
    func accepted() {
        let extra = """
        {"discordId":"100000000000000001","guildId":"\(guildId)","walletAddress":"ACCOUNT-ONE",\
        "balance":1234,"tier":"whatever","direct":1000,"pooled":234}
        """
        guard case .accepted(let callback) = route(request(key: secret, body: extra)) else {
            Issue.record("expected it to be accepted")
            return
        }
        #expect(callback.externalId == "100000000000000001")
        #expect(callback.address == "ACCOUNT-ONE")
        #expect(callback.balanceBaseUnits == 1_234)
    }

    @Test("An unset secret refuses everybody rather than admitting anybody")
    func anEmptySecretIsNotAnOpenDoor() {
        // Two empty strings compare equal, so a bot with verification
        // switched off and an empty header would admit whoever sent one,
        // prove an account for them and grant them roles.
        for presented in [nil, "", "anything"] {
            let route = CallbackRouting.route(
                request(key: presented, body: body()),
                expectedKey: "",
                servedGuildId: guildId,
                isRateLimited: false,
                isValidAddress: { _ in true }
            )
            guard case .refuse(let status, _) = route else {
                Issue.record("expected a refusal for \(presented ?? "nothing")")
                return
            }
            #expect(status == 401)
        }
    }

    // MARK: - What the limit counts

    /// Counts how many times it was asked, because asking is also recording.
    private actor CountingLimit {
        private(set) var asked = 0
        private let answer: Bool

        init(answer: Bool = false) {
            self.answer = answer
        }

        func isLimited() -> Bool {
            asked += 1
            return answer
        }
    }

    @Test("Health and a wrong path never spend the callback's budget")
    func onlyTheCallbackIsCounted() async {
        // Behind a reverse proxy every request shares one address, so a
        // scanner or a health poller counted here would answer the next real
        // callback with a 429 and lose somebody's verification.
        let limit = CountingLimit()
        for head in [request(method: "GET", path: "/health"), request(path: "/nope"),
                     request(method: "GET", path: "/webhook/verification")] {
            _ = await CallbackRouting.route(
                head,
                expectedKey: secret,
                servedGuildId: guildId,
                isValidAddress: { _ in true },
                isRateLimited: { await limit.isLimited() }
            )
        }
        #expect(await limit.asked == 0)

        _ = await CallbackRouting.route(
            request(key: secret, body: body()),
            expectedKey: secret,
            servedGuildId: guildId,
            isValidAddress: { _ in true },
            isRateLimited: { await limit.isLimited() }
        )
        #expect(await limit.asked == 1)
    }

    @Test("The callback route itself is counted, and refused when it is over")
    func theCallbackIsCounted() async {
        let limit = CountingLimit(answer: true)
        let route = await CallbackRouting.route(
            request(key: secret, body: body()),
            expectedKey: secret,
            servedGuildId: guildId,
            isValidAddress: { _ in true },
            isRateLimited: { await limit.isLimited() }
        )
        guard case .refuse(let status, _) = route else {
            Issue.record("expected a refusal")
            return
        }
        #expect(status == 429)
        #expect(await limit.asked == 1)
    }

    // MARK: - The secret comparison

    @Test("Secrets are compared without stopping at the first difference")
    func constantTimeCompare() {
        #expect(CallbackRouting.constantTimeEquals("abc", "abc"))
        #expect(CallbackRouting.constantTimeEquals("abc", "abd") == false)
        #expect(CallbackRouting.constantTimeEquals("abc", "abcd") == false)
        #expect(CallbackRouting.constantTimeEquals("", ""))
        #expect(CallbackRouting.constantTimeEquals("a", "") == false)
    }

    // MARK: - The rate limit itself

    @Test("Ten in a window are allowed and the eleventh is not")
    func limiterCounts() async {
        let limiter = CallbackRateLimiter(limit: 10, window: 60)
        let start = Date(timeIntervalSince1970: 0)
        for index in 0..<10 {
            #expect(await limiter.isLimited(source: "1.2.3.4", now: start.addingTimeInterval(Double(index))) == false)
        }
        #expect(await limiter.isLimited(source: "1.2.3.4", now: start.addingTimeInterval(10)))
        // Another source has its own budget.
        #expect(await limiter.isLimited(source: "5.6.7.8", now: start.addingTimeInterval(10)) == false)
        // And the window moves.
        #expect(await limiter.isLimited(source: "1.2.3.4", now: start.addingTimeInterval(120)) == false)
    }
}
