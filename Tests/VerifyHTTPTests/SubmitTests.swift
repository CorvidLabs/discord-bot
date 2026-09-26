import Foundation
import Testing
import Crypto
import Algorand
import Verify
@testable import VerifyHTTP

/// Taking a signed blob over HTTP, end to end, with no network and no wallet
/// (REQ-verify-009, BUILD-2).
@Suite("The submission")
struct SubmitTests {

    // MARK: - A proof that holds

    @Test("A real signature is checked, held for confirmation, and binds nothing yet")
    func aProofWaitsForTheMemberToConfirm() async throws {
        // Adoption needs a confirmation by the member after the proof has
        // been checked. What this surface does with a proof is hand it over
        // and say so; nothing is linked until the member says so where they
        // started (REQ-verify-009).
        let spy = HostSpy()
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let blob = try ProofFixtures.blob(
            ProofFixtures.proof(for: account, note: session.challenge.bytes),
            signedBy: account
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 200)
        #expect(SurfaceFixtures.fields(answered)["status"] as? String == "awaiting-confirmation")

        let held = await spy.held
        #expect(held.count == 1)
        #expect(held.first?.address == account.address.description)
        #expect(held.first?.subject == SurfaceFixtures.subject)
        #expect(held.first?.usedAuthorizingKey == false)
    }

    @Test("A checked proof the program cannot hold is said plainly, not shown as a success")
    func aProofThatCouldNotBeHeldSaysSo() async throws {
        let spy = HostSpy()
        await spy.set(handoff: .unavailable)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let blob = try ProofFixtures.blob(
            ProofFixtures.proof(for: account, note: session.challenge.bytes),
            signedBy: account
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 503)
        #expect(answered.body.contains("\"retryable\":false"))
    }

    // MARK: - The account somebody else holds

    @Test("A proof for an account another member holds is refused, however the connect was answered")
    func aClaimedAccountIsRefusedOnTheWinningPathToo() async throws {
        // The connect and the submission are two requests. The page honours
        // the `409` and hides the rest of the flow, and that is the page's
        // manners rather than this surface's rule: a caller that posts the
        // next request anyway must not have a proof for somebody else's
        // account taken. Goes red against asking the question only at the
        // connect.
        let spy = HostSpy()
        await spy.set(claimed: true)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let connected = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(connected.status == 409)

        let blob = try ProofFixtures.blob(
            ProofFixtures.proof(for: account, note: session.challenge.bytes),
            signedBy: account
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 409)
        let held = await spy.held
        #expect(held.isEmpty)
    }

    @Test("A checked proof is not handed over while the program cannot say who holds the account")
    func anUnreadableClaimStopsTheHandover() async throws {
        let spy = HostSpy()
        await spy.set(claimed: nil)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let blob = try ProofFixtures.blob(
            ProofFixtures.proof(for: account, note: session.challenge.bytes),
            signedBy: account
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 503)
        // The session is spent by then, so the same page has nothing left
        // to try: the sentence says to run the command again.
        #expect(answered.body.contains("\"retryable\":false"))
        let held = await spy.held
        #expect(held.isEmpty)
    }

    // MARK: - Refusals

    @Test("A blob that is not a signed transaction is a 422, and a member sentence comes with it")
    func anUnreadableBlobIsTheMembersToActOn() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: "not-base64-at-all!!"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 422)
        #expect(SurfaceFixtures.fields(answered)["error"] as? String
            == ProofRefusalReason.blobUnreadable.message)
        #expect(answered.body.contains("\"retryable\":true"))
    }

    @Test("A submission against a session nothing was connected to says nothing about it")
    func anUnconnectedSessionSaysNothing() async throws {
        let surface = try SurfaceFixtures.surface()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: "AAAA"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 404)
        #expect(SurfaceFixtures.fields(answered)["error"] as? String
            == ProofRefusalReason.sessionUnavailable.message)
    }

    @Test("The session's three attempts end in a 429 that says a new link is what fixes it")
    func aSpentLinkIsItsOwnAnswer() async throws {
        // A rate limit and an allowance are different bounds with the same
        // status code, so the sentence is what tells them apart: one is
        // fixed by waiting and one by a new link.
        let limits = try VerifyHTTPLimits(
            assetRequestsPerSource: 30,
            apiRequestsPerSource: 100,
            apiRequestsPerSession: 100,
            window: 60,
            maximumBodyBytes: 8_192
        )
        let surface = try SurfaceFixtures.surface(limits: limits)
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let wrong = try ProofFixtures.blobSignedByStranger(
            ProofFixtures.proof(for: account, note: session.challenge.bytes),
            signedBy: stranger
        )
        for _ in 0..<VerificationLimits.maximumSubmissionsPerSession {
            let refused = await surface.service.respond(
                to: SurfaceFixtures.submit(session.id, blob: wrong),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
            #expect(refused.status == 422)
        }
        let spent = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: wrong),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(spent.status == 429)
        #expect(SurfaceFixtures.fields(spent)["error"] as? String
            == ProofRefusalReason.submissionsExhausted(.session).message)
        #expect(spent.body.contains("\"retryable\":false"))
    }

    @Test("A prompt minted for somebody else is a hard stop rather than something to retry")
    func aRelayedPromptIsNotRetryable() async throws {
        let surface = try SurfaceFixtures.surface()
        let account = try ProofFixtures.account()
        let mine = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let theirs = try VerificationChallenge(
            label: SurfaceFixtures.label,
            instanceIdentity: SurfaceFixtures.instance,
            subject: "112233445566778899aabbccddeeff00",
            code: "ABC234",
            nonce: String(repeating: "b", count: 32)
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(mine.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let blob = try ProofFixtures.blob(
            ProofFixtures.proof(for: account, note: theirs.bytes),
            signedBy: account
        )
        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(mine.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(SurfaceFixtures.fields(answered)["error"] as? String
            == ProofRefusalReason.subjectMismatch.message)
        #expect(answered.body.contains("\"retryable\":false"))
    }

    // MARK: - The one retry

    @Test("A rekeyed account proves itself when the program can read an authorising address")
    func theOneRetryIsTaken() async throws {
        // The key comes from the program's own read of that exact account's
        // authorising address field, on the one refusal it could explain,
        // and from nowhere else (REQ-verify-008, REQ-verify-009).
        let signer = Curve25519.Signing.PrivateKey()
        let spy = HostSpy()
        await spy.setAuthorizingKey(signer.publicKey.rawRepresentation)
        let surface = try SurfaceFixtures.surface(host: spy.host())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let transaction = ProofFixtures.proof(for: account, note: session.challenge.bytes)
        let signature = try signer.signature(for: try transaction.bytesToSign())
        let blob = try SignedTransaction(transaction: transaction, signature: Data(signature))
            .encode()
            .base64EncodedString()

        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 200)
        let reads = await spy.authorizingKeyReads
        #expect(reads == 1)
        let held = await spy.held
        #expect(held.first?.usedAuthorizingKey == true)
    }

    @Test("With no chain read configured, the same submission is refused and nothing is asked")
    func noReaderMeansNoRetry() async throws {
        // Said plainly rather than left to be discovered: without a chain
        // read a rekeyed account cannot verify, and that is a smaller
        // failure than accepting a key from anywhere else.
        let signer = Curve25519.Signing.PrivateKey()
        let spy = HostSpy()
        let surface = try SurfaceFixtures.surface(host: spy.hostWithoutAuthorizingKeyReader())
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.connect(session.id, address: account.address.description),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let transaction = ProofFixtures.proof(for: account, note: session.challenge.bytes)
        let signature = try signer.signature(for: try transaction.bytesToSign())
        let blob = try SignedTransaction(transaction: transaction, signature: Data(signature))
            .encode()
            .base64EncodedString()

        let answered = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: blob),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(answered.status == 422)
        let reads = await spy.authorizingKeyReads
        #expect(reads == 0)
        let held = await spy.held
        #expect(held.isEmpty)
    }
}
