import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// The session id is a bearer credential, and this is where that is proved
/// rather than promised (VERIFY-7, REQ-verify-003, REQ-verify-009).
@Suite("The bearer credential")
struct BearerCredentialTests {

    // MARK: - It never comes back out

    @Test("No answer this surface gives, on any route, carries the session id")
    func noAnswerCarriesTheIdentifier() async throws {
        // One test over a whole flow rather than one per route, because the
        // property is about every byte that leaves this process and a
        // per-route test is a per-route hole.
        let log = LogSpy()
        let surface = try SurfaceFixtures.surface(log: log)
        let account = try ProofFixtures.account()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let identifier = session.id.value

        var answers: [VerifyHTTPResponse] = []
        answers.append(
            await surface.service.respond(
                to: SurfaceFixtures.get(VerifyRouting.pagePath),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        answers.append(
            await surface.service.respond(
                to: SurfaceFixtures.card(session.id),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        answers.append(
            await surface.service.respond(
                to: SurfaceFixtures.connect(session.id, address: account.address.description),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        answers.append(
            await surface.service.respond(
                to: SurfaceFixtures.submit(session.id, blob: "not a proof"),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        answers.append(
            await surface.service.respond(
                to: SurfaceFixtures.submit(
                    session.id,
                    blob: try ProofFixtures.blob(
                        ProofFixtures.proof(for: account, note: session.challenge.bytes),
                        signedBy: account
                    )
                ),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        )
        // Every one of them mattered: a suite that quietly refused all five
        // would pass this without proving anything.
        #expect(answers.last?.status == 200)
        for answer in answers {
            #expect(!String(decoding: answer.wireBytes, as: UTF8.self).contains(identifier))
        }
    }

    @Test("No line this surface logs carries the session id, and the refusals do carry a handle")
    func nothingLoggedCarriesTheIdentifier() async throws {
        let log = LogSpy()
        let surface = try SurfaceFixtures.surface(log: log)
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.submit(session.id, blob: "not a proof"),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        _ = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath + "?session=" + session.id.value),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        let written = await log.joined()
        #expect(!written.isEmpty)
        #expect(!written.contains(session.id.value))
        #expect(written.contains(VerifySessionHandle(sessionIdentifier: session.id).value))
    }

    // MARK: - The handle

    @Test("A handle here and a handle from the module below are the same twelve characters")
    func oneHandleForOneSession() async throws {
        // The construction is repeated rather than borrowed, because the
        // module's own initialiser is internal to it. A repetition that
        // drifts is an operator holding two references to one session and
        // no way to know it, so the two are pinned against each other.
        let surface = try SurfaceFixtures.surface()
        let session = try await surface.coordinator.mint(
            subject: SurfaceFixtures.subject,
            now: SurfaceFixtures.now
        )
        let outcome = try await surface.coordinator.submit(
            blob: "nonsense",
            to: session.id,
            now: SurfaceFixtures.now
        )
        guard case .refused(let refusal) = outcome else {
            Issue.record("a submission against an unconnected session should be refused")
            return
        }
        let ours = VerifySessionHandle(sessionIdentifier: session.id)
        #expect(ours.value == refusal.handle.value)
        #expect(ours.value.count == VerifySessionHandle.characterCount)
        #expect(ours.value.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("A handle cannot be walked back to an id that was never minted by this process")
    func theHandleIsNotAnAbbreviation() throws {
        // Twelve characters of a digest of a hundred and twenty eight bit
        // value, rather than the first twelve characters of the id itself,
        // which would be an abbreviation with fewer characters to guess.
        let identifier = try VerificationSessionIdentifier(String(repeating: "c", count: 32))
        let handle = VerifySessionHandle(sessionIdentifier: identifier)
        #expect(!identifier.value.hasPrefix(handle.value))
        #expect(!identifier.value.contains(handle.value))
    }

    // MARK: - The link

    @Test("The link puts the id after the hash, which is the part a browser never sends")
    func theLinkUsesAFragment() throws {
        let identifier = try VerificationSessionIdentifier(String(repeating: "d", count: 32))
        let link = try VerifyLink.link(base: "https://verify.example.test", sessionId: identifier)
        #expect(link == "https://verify.example.test/verify#" + identifier.value)
        #expect(!link.contains("?"))
        // Whatever precedes the fragment is what a server, a proxy and a
        // referrer header would see, and the id is not in it.
        #expect(!(link.split(separator: "#").first.map(String.init) ?? "").contains(identifier.value))
    }

    @Test("A base that could not carry a fragment, or is not https, is refused naming the variable")
    func aBaseThatWouldLoseTheIdentifierIsRefused() throws {
        let identifier = try VerificationSessionIdentifier(String(repeating: "e", count: 32))
        #expect(throws: VerifyLinkError.baseMissing(field: "VERIFY_BASE_URL")) {
            _ = try VerifyLink.link(base: "  ", sessionId: identifier, field: "VERIFY_BASE_URL")
        }
        #expect(throws: VerifyLinkError.baseCarriesQueryOrFragment(field: "VERIFY_BASE_URL")) {
            _ = try VerifyLink.link(
                base: "https://verify.example.test?a=1",
                sessionId: identifier,
                field: "VERIFY_BASE_URL"
            )
        }
        #expect(throws: VerifyLinkError.baseNotSecure(field: "VERIFY_BASE_URL")) {
            _ = try VerifyLink.link(
                base: "http://verify.example.test",
                sessionId: identifier,
                field: "VERIFY_BASE_URL"
            )
        }
        // Loopback is the one plain-HTTP base that is allowed, and the host
        // is compared whole: a name that merely starts with it is somebody
        // else's machine.
        let local = try VerifyLink.link(base: "http://127.0.0.1:8080", sessionId: identifier)
        #expect(local == "http://127.0.0.1:8080/verify#" + identifier.value)
        #expect(throws: VerifyLinkError.baseNotSecure(field: "verify base URL")) {
            _ = try VerifyLink.link(base: "http://localhost.example.test", sessionId: identifier)
        }

        let trailing = try VerifyLink.link(
            base: "https://verify.example.test/",
            sessionId: identifier
        )
        #expect(trailing == "https://verify.example.test/verify#" + identifier.value)
    }
}
