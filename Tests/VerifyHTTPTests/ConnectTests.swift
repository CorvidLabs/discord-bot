import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// Naming an account before anything is signed (VERIFY-2, REQ-verify-009).
@Suite("The connect")
struct ConnectTests {

    // MARK: - Recording one address

    @Test("The address a wallet connected is recorded and answered back")
    func oneAddressIsRecorded() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 200)
        #expect(SurfaceFixtures.fields(answered)["connectedAddress"] as? String
            == account.address.description)
    }

    @Test("A second, differing address is refused without answering anything about it")
    func theSecondAddressLearnsNothing() async throws {
        let surface = try SurfaceFixtures.surface()
        let first = try ProofFixtures.account()
        let second = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: first.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: second.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 409)
        #expect(!answered.body.contains(second.address.description))
        #expect(!answered.body.contains(first.address.description))
    }

    @Test("A pinned session refuses a different account here, before a wallet asks anybody to sign")
    func aPinnedSessionRefusesEarly() async throws {
        // The whole value of naming a wallet up front: the mismatch costs
        // the member a retyped command rather than a signature.
        let surface = try SurfaceFixtures.surface()
        let pinned = try ProofFixtures.account()
        let other = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            pinnedAddress: pinned.address.description,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: other.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 409)
        #expect(SurfaceFixtures.fields(answered)["error"] as? String
            == ProofRefusalReason.pinnedAddressMismatch.message)
    }

    // MARK: - The claim question

    @Test("An account another member already proved is refused, and the question is asked once")
    func anAccountIsAskedAboutOnce() async throws {
        // Asked after the bind, never before. Asked freely it answers "does
        // this address belong to a member here?" for any address anybody
        // cares to type, which is an afternoon's walk from a public holder
        // list to this community's membership.
        let spy = HostSpy()
        await spy.set(claimed: true)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 409)

        let stranger = try ProofFixtures.account()
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: stranger.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let asked = await spy.claimQuestions
        #expect(asked == [account.address.description])
    }

    @Test("An account the program could not read about is refused, not treated as free")
    func anUnreadableClaimIsRefused() async throws {
        // A read that threw is a fact this process does not have, and a
        // lock that reports itself open because the key could not be found
        // is a lock that is open. Goes red against a closure that can only
        // answer yes or no, where a host has nothing to return but false.
        let spy = HostSpy()
        await spy.set(claimed: nil)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 503)
        #expect(answered.body.contains("\"retryable\":true"))
        #expect(!answered.body.contains(account.address.description))
    }

    // MARK: - Refusals

    @Test("An address no Algorand tool would accept is the page's mistake, not a failed proof")
    func aBadAddressIsNotAFailedProof() async throws {
        let surface = try SurfaceFixtures.surface()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: "NOTANADDRESS"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 400)
        #expect(answered.body.contains("\"retryable\":true"))
    }

    @Test("A connect with no address in it is refused and costs the session nothing")
    func anEmptyConnectIsRefused() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.post(
                VerifyRouting.connectPath,
                body: "{\"session\":\"\(session.id.value)\"}"
            ),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 400)

        let afterwards = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(afterwards.status == 200)
    }
}
