import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// What the page is told about a session, and what it is not told
/// (REQ-verify-010).
@Suite("The card")
struct CardTests {

    // MARK: - What it carries

    @Test("The card names the chat account, the code and the expiry read from the session itself")
    func theCardNamesTheAccount() async throws {
        let surface = try SurfaceFixtures.surface()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.card(session.id),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 200)
        let fields = SurfaceFixtures.fields(answered)
        #expect(fields["account"] as? String == SurfaceFixtures.accountName)
        #expect(fields["code"] as? String == session.challenge.code)
        // Read from `expiresAt` rather than from a sentence, so what the
        // member is shown and what the check enforces cannot drift.
        #expect(fields["challenge"] as? String == session.challenge.text)
        // Numbers are asserted against the bytes rather than through a
        // bridged `Any`, whose integer types differ between the two
        // platforms this suite runs on.
        #expect(answered.body.contains("\"expiresAt\":\(Int(session.expiresAt.timeIntervalSince1970))"))
        #expect(answered.body.contains("\"maximumFeeMicroAlgos\":\(ProofShape.maximumFeeMicroAlgos)"))
    }

    @Test("A session with no address connected says so, and one with an address names it")
    func theCardReportsWhereTheSessionHasGot() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let before = SurfaceFixtures.fields(
            await surface.service.respond(
                to: SurfaceFixtures.card(session.id),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        #expect(before["connectedAddress"] == nil)

        _ = try await surface.coordinator.connect(
            sessionId: session.id,
            address: account.address.description,
            now: SurfaceFixtures.now
        )
        let after = SurfaceFixtures.fields(
            await surface.service.respond(
                to: SurfaceFixtures.card(session.id),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        #expect(after["connectedAddress"] as? String == account.address.description)
    }

    @Test("A pinned session names the account the member already chose")
    func aPinnedSessionSaysSo() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            pinnedAddress: account.address.description,
            now: SurfaceFixtures.now
        )
        let fields = SurfaceFixtures.fields(
            await surface.service.respond(
                to: SurfaceFixtures.card(session.id),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        #expect(fields["pinnedAddress"] as? String == account.address.description)
    }

    // MARK: - What it refuses

    @Test("With no name for the member, the card refuses rather than rendering the page without one")
    func anUnnamedSessionIsRefused() async throws {
        // Goes red against the accommodating version, which renders the
        // page with an empty name when the chat service cannot be reached.
        // That page has the relayed-prompt mitigation switched off and
        // nothing on it says so (REQ-verify-010).
        let spy = HostSpy()
        await spy.set(name: nil)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.card(session.id),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 503)
        #expect(SurfaceFixtures.fields(answered)["handle"] as? String
            == VerifySessionHandle(sessionIdentifier: session.id).value)
    }

    @Test("An id that selects nothing, and one that has expired, are told apart")
    func expiryIsItsOwnAnswer() async throws {
        let surface = try SurfaceFixtures.surface()
        let unknown = try VerificationSessionIdentifier(String(repeating: "a", count: 32))
        let missing = await surface.service.respond(
            to: SurfaceFixtures.card(unknown),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(missing.status == 404)
        #expect(missing.body.contains("\"retryable\":false"))

        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let expired = await surface.service.respond(
            to: SurfaceFixtures.card(session.id),
            from: SurfaceFixtures.source,
            now: session.expiresAt
        )
        // A member needs to know that a new link is what fixes this, which
        // is why it is not folded into the reason that says nothing.
        #expect(expired.status == 410)
        #expect(SurfaceFixtures.fields(expired)["error"] as? String
            == ProofRefusalReason.sessionExpired.message)
    }

    @Test("A spent session is the reason that says nothing, not its own answer")
    func aSpentSessionDisclosesNothing() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = try await surface.coordinator.connect(
            sessionId: session.id,
            address: account.address.description,
            now: SurfaceFixtures.now
        )
        let blob = try ProofFixtures.blob(
            ProofFixtures.proof(for: account, note: session.challenge.bytes),
            signedBy: account
        )
        _ = try await surface.coordinator.submit(blob: blob, to: session.id, now: SurfaceFixtures.now)

        let answered = await surface.service.respond(
            to: SurfaceFixtures.card(session.id),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 404)
        #expect(SurfaceFixtures.fields(answered)["error"] as? String
            == ProofRefusalReason.sessionUnavailable.message)
    }
}
