@preconcurrency import Foundation
import Surface
import Testing

@testable import SurfaceDiscord

/// What answers on the callback port, with no socket and no gateway.
///
/// Three rules live here and each of them is a way to lose somebody's
/// verification without anything appearing to be wrong.
@Suite("The callback responder")
struct CallbackResponderTests {

    private let secret = "a-shared-secret-value"
    private let guildId = "100000000000000002"

    private func request(
        method: String = "POST",
        path: String = "/webhook/verification",
        key: String? = nil
    ) -> HTTPRequestHead {
        var headers: [String: String] = ["content-type": "application/json"]
        if let key { headers["x-api-key"] = key }
        let body = """
            {"discordId":"100000000000000001","guildId":"\(guildId)",\
            "walletAddress":"ACCOUNT-ONE","balance":12,"tier":"whatever"}
            """
        return HTTPRequestHead(method: method, path: path, headers: headers, body: body)
    }

    private func responder(
        sharedSecret: String? = "a-shared-secret-value",
        limit: Int = 10,
        health: HealthState = HealthState()
    ) -> CallbackResponder {
        CallbackResponder(
            health: health,
            limiter: CallbackRateLimiter(limit: limit, window: 60),
            sharedSecret: sharedSecret,
            servedGuildId: guildId,
            isValidAddress: { _ in true },
            // The store is not open, which is what a callback arriving
            // during the boot meets.
            handler: { nil }
        )
    }

    @Test("A callback that arrives before the store is open is refused, not accepted and dropped")
    func earlyCallbackIsRefused() async {
        // The ports bind inside the boot and the store is handed over when
        // the boot returns. A `200` in that window tells the portal to
        // record a verification this bot threw away, and the member is never
        // told anything.
        let reply = await responder().respond(to: request(key: secret), from: "10.0.0.1")
        #expect(reply.status == 503)
        #expect(reply.body.contains("starting"))
        #expect(reply.afterReply == nil)
    }

    @Test("A wrong path never spends the portal's budget")
    func aScannerCannotLockOutThePortal() async {
        // Behind a reverse proxy every request arrives from one address, so
        // ten of anything would answer the next real callback with a 429.
        let responder = responder(limit: 2)
        for _ in 0..<5 {
            _ = await responder.respond(to: request(method: "GET", path: "/nope"), from: "10.0.0.1")
        }
        _ = await responder.respond(to: request(method: "GET", path: "/health"), from: "10.0.0.1")

        let reply = await responder.respond(to: request(key: secret), from: "10.0.0.1")
        // 503 because the store is not open here; 429 would mean the budget
        // had been spent on the requests above.
        #expect(reply.status == 503)
    }

    @Test("The callback route is counted, so a flood of real callbacks is refused")
    func theCallbackRouteIsCounted() async {
        let responder = responder(limit: 2)
        for _ in 0..<2 {
            _ = await responder.respond(to: request(key: secret), from: "10.0.0.1")
        }
        let reply = await responder.respond(to: request(key: secret), from: "10.0.0.1")
        #expect(reply.status == 429)
    }

    @Test("With verification off the callback route does not exist, whatever key is sent")
    func verificationOffClosesTheRoute() async {
        // Two empty strings compare equal, so an unset secret and an empty
        // header used to be a match: the bot admitted a member, proved an
        // account and granted roles for whoever asked.
        let responder = responder(sharedSecret: nil)
        for key in [nil, "", "anything"] {
            let reply = await responder.respond(to: request(key: key), from: "10.0.0.1")
            #expect(reply.status == 404)
            #expect(reply.afterReply == nil)
        }
    }

    @Test("Health is answered on this port too, before anything else")
    func healthIsStillAnswered() async {
        let health = HealthState()
        let responder = responder(sharedSecret: nil, health: health)
        var reply = await responder.respond(to: request(method: "GET", path: "/health"), from: "10.0.0.1")
        #expect(reply.status == 503)

        await health.setStore(.up)
        await health.setDiscord(.up)
        await health.setVerification(.off)
        reply = await responder.respond(to: request(method: "GET", path: "/health"), from: "10.0.0.1")
        #expect(reply.status == 200)
    }
}
