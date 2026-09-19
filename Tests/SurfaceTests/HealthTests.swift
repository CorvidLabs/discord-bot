import Foundation
import Testing

@testable import Surface

/// One check that says whether the bot is really working (`SEE-1`).
@Suite("Health")
struct HealthTests {

    @Test("A bound port is not health: it answers 503 until the gateway is ready (SEE-1.a)")
    func boundIsNotReady() {
        // The listener binds before this process identifies, because binding
        // is how a second copy discovers the first. Answering 200 then would
        // turn every deploy gate green a second before the bot could do
        // anything at all.
        let starting = SurfaceHealth()
        #expect(starting.status == "starting")
        #expect(starting.statusCode == 503)
        #expect(starting.jsonBody == "{\"status\":\"starting\"}")
    }

    @Test("A 200 names each piece separately, so an outage is not a guess (SEE-10)")
    func eachPieceIsNamed() {
        let healthy = SurfaceHealth(discord: .up, store: .up, verification: .up)
        #expect(healthy.status == "ok")
        #expect(healthy.statusCode == 200)
        #expect(healthy.jsonBody.contains("\"discord\":\"up\""))
        #expect(healthy.jsonBody.contains("\"store\":\"up\""))
        #expect(healthy.jsonBody.contains("\"verification\":\"up\""))
    }

    @Test("Verification down is degraded and still 200, because the rest still answers (SEE-7)")
    func verificationDownIsDegraded() {
        let degraded = SurfaceHealth(discord: .up, store: .up, verification: .down)
        #expect(degraded.status == "degraded")
        // Still 200: taking the process out of rotation would lose /ping and
        // /help too, and neither of them needs the portal.
        #expect(degraded.statusCode == 200)
    }

    @Test("Verification switched off is not a fault")
    func offIsNotDown() {
        let configured = SurfaceHealth(discord: .up, store: .up, verification: .off)
        #expect(configured.status == "ok")
    }

    @Test("A store that is gone is 503, because nothing this bot does survives it")
    func storeDownIs503() {
        let broken = SurfaceHealth(discord: .up, store: .down, verification: .up)
        #expect(broken.status == "down")
        #expect(broken.statusCode == 503)
    }

    @Test("Answering costs nothing that could be gone: the answer is built from held values (SEE-1.b)")
    func answeringSpendsNothing() async {
        // There is no chain reader, no store handle and no portal client in
        // this test, and the answer still comes out. That is the property:
        // the check does not spend the day's budget for reading the chain,
        // and it still answers once that budget is gone.
        let state = HealthState()
        await state.setDiscord(.up)
        await state.setStore(.up)
        await state.setVerification(.up)
        #expect(await state.snapshot().statusCode == 200)
    }

    @Test("Each piece is recorded without disturbing the others")
    func piecesAreIndependent() async {
        let state = HealthState()
        await state.setStore(.up)
        #expect(await state.snapshot().discord == .starting)
        await state.setDiscord(.up)
        #expect(await state.snapshot().store == .up)
    }
}
