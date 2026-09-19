import Foundation
import Testing
import Algorand
import Verify

/// What a session is, what it refuses, and what it never tells anybody
/// (VERIFY-1, VERIFY-2, VERIFY-7, RUN-11).
@Suite("The session")
struct SessionTests {

    // MARK: - Expiry

    @Test("Expiry is evaluated against a supplied instant")
    func nothingReadsAClock() async throws {
        // Goes red against reading the clock inside the check, which makes
        // a suite depend on the machine it runs on and makes the boundary
        // untestable at all.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        #expect(session.issuedAt == CoordinatorFixtures.now)
        #expect(
            session.expiresAt
                == CoordinatorFixtures.now.addingTimeInterval(VerificationLimits.standard.sessionLifetime)
        )
    }

    @Test("A proof at the expiry instant is refused and one a moment before is accepted")
    func theBoundaryIsExact() async throws {
        // Goes red against a comparison one either way, the kind of thing
        // nobody notices and nobody gets right by accident.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let blob = try ProofFixtures.blob(payment, signedBy: account)

        let atExpiry = try await coordinator.submit(blob: blob, to: session.id, now: session.expiresAt)
        #expect(atExpiry.refusalReason == .sessionExpired)

        let justBefore = try await coordinator.submit(
            blob: blob,
            to: session.id,
            now: session.expiresAt.addingTimeInterval(-0.001)
        )
        #expect(justBefore.refusalReason == nil)
    }

    @Test("A clock stepped backwards does not revive an expired session")
    func expiryIsAnAbsoluteInstant() async throws {
        // Goes red against a countdown decremented per tick, which a
        // suspended host resets. Expiry is compared against the instant
        // supplied, and the session is pruned once it has passed.
        let store = InMemoryVerificationSessionStore()
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        await coordinator.prune(now: session.expiresAt.addingTimeInterval(1))
        let backwards = try await coordinator.submit(
            blob: ProofRefusalTests.rubbish,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(backwards.refusalReason == .sessionUnavailable)
        #expect(await store.heldSessionCount == 0)
    }

    // MARK: - Consumption

    @Test("A byte identical resubmission of an accepted proof is refused")
    func consumedIsTerminal() async throws {
        // Goes red against a store that reads and never marks, and against
        // one that marks after the account is written, where a crash
        // between the two leaves a live challenge sitting behind a proved
        // account.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let blob = try ProofFixtures.blob(payment, signedBy: account)

        let first = try await coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        #expect(first.refusalReason == nil)
        let second = try await coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        #expect(second.refusalReason == .sessionUnavailable)
    }

    @Test("A refused proof does not consume the session")
    func aRefusalLeavesTheSessionUsable() async throws {
        // Goes red against consuming on submission, which turns one mis-tap
        // into a new link and a new signature, and makes a hostile
        // submission a denial of somebody else's verification.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let refused = try await coordinator.submit(
            blob: ProofRefusalTests.rubbish,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(refused.refusalReason == .blobUnreadable)

        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let accepted = try await coordinator.submit(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(accepted.refusalReason == nil)
    }

    @Test("A consumed session is pruned, challenge and all")
    func pruningLeavesNothing() async throws {
        // Goes red against keeping spent sessions, which leaves a challenge
        // and a subject in memory for no reason (VERIFY-7).
        let store = InMemoryVerificationSessionStore()
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        _ = try await coordinator.submit(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            to: session.id,
            now: CoordinatorFixtures.now
        )
        await coordinator.prune(now: CoordinatorFixtures.now)
        #expect(await store.session(id: session.id) == nil)
        #expect(await store.heldSessionCount == 0)
    }

    // MARK: - The session id

    @Test("A session id is a hundred and twenty eight bits and is compared whole")
    func theIdIsTheWholeCredential() async throws {
        // Goes red against a counter or a short token, which lets somebody
        // walk the live sessions and submit against one they did not open.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        #expect(session.id.value.count == VerificationSessionIdentifier.characterCount)
        #expect(session.id.value.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(!session.id.value.contains(CoordinatorFixtures.subject))

        var seen: Set<String> = []
        for _ in 0..<2_000 {
            seen.insert(VerificationSessionIdentifier.mint().value)
        }
        #expect(seen.count == 2_000)
    }

    @Test("A session id of the wrong shape is refused rather than truncated")
    func aMalformedIdIsRefused() {
        #expect(throws: VerifyError.malformedSessionIdentifier(characterCount: 4)) {
            _ = try VerificationSessionIdentifier("abcd")
        }
        #expect(throws: Never.self) {
            _ = try VerificationSessionIdentifier(String(repeating: "0", count: 32))
        }
    }

    @Test("A width of thirty two characters is not a width of thirty two bytes")
    func aFullwidthIdIsRefused() {
        // Goes red against `Character.isHexDigit`, which is true for the
        // fullwidth compatibility digits as well, so a string of ninety six
        // UTF-8 bytes passes a check that was written to mean thirty two.
        // Nothing this type mints looks anything like it, and an id read
        // back from somewhere is exactly what this initialiser is for.
        let fullwidth = String(repeating: "\u{FF10}", count: 32)
        #expect(fullwidth.count == VerificationSessionIdentifier.characterCount)
        #expect(fullwidth.utf8.count == 96)
        #expect(throws: VerifyError.malformedSessionIdentifier(characterCount: 32)) {
            _ = try VerificationSessionIdentifier(fullwidth)
        }
        #expect(throws: VerifyError.malformedSessionIdentifier(characterCount: 32)) {
            _ = try VerificationSessionIdentifier(String(repeating: "A", count: 32))
        }
    }

    // MARK: - The bounds

    @Test("The per-session maximum is not below three")
    func theFloorIsThree() {
        // Goes red against a maximum of one or two, which passes every
        // other case in this suite and refuses the one member the
        // authorising key seam exists for: a rekeyed account needs a
        // wrong-account attempt, a right-account attempt that fails the
        // signature check, and the retry. A ceiling with no floor is half a
        // bound.
        #expect(VerificationLimits.maximumSubmissionsPerSession >= 3)
        #expect(
            VerificationLimits.maximumSubmissionsPerSubject
                > VerificationLimits.maximumSubmissionsPerSession
        )
    }

    @Test("A session stops accepting submissions at its maximum")
    func theSessionBoundHolds() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        for _ in 0..<VerificationLimits.maximumSubmissionsPerSession {
            let refused = try await coordinator.submit(
                blob: ProofRefusalTests.rubbish,
                to: session.id,
                now: CoordinatorFixtures.now
            )
            #expect(refused.refusalReason == .blobUnreadable)
        }
        let exhausted = try await coordinator.submit(
            blob: ProofRefusalTests.rubbish,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(exhausted.refusalReason == .submissionsExhausted(.session))
    }

    @Test("Spending a session's allowance and minting a new session does not buy a new allowance")
    func theSubjectBoundSurvivesDisplacement() async throws {
        // This is the case that fails against the bound as first written.
        // A new session displaces the old one, so a per-session cap is
        // refreshed by running the command again: the member mints a fresh
        // session and a fresh allowance whenever they like, and the chain
        // reads the cap exists to limit are spent anyway (RUN-11).
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        var spent = 0
        while spent < VerificationLimits.maximumSubmissionsPerSubject {
            let session = try await CoordinatorFixtures.connectedSession(
                on: coordinator,
                account: account
            )
            for _ in 0..<VerificationLimits.maximumSubmissionsPerSession
            where spent < VerificationLimits.maximumSubmissionsPerSubject {
                _ = try await coordinator.submit(
                    blob: ProofRefusalTests.rubbish,
                    to: session.id,
                    now: CoordinatorFixtures.now
                )
                spent += 1
            }
        }
        let fresh = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let refused = try await coordinator.submit(
            blob: ProofRefusalTests.rubbish,
            to: fresh.id,
            now: CoordinatorFixtures.now
        )
        #expect(refused.refusalReason == .submissionsExhausted(.subject))
        // A link they have never tried, so the sentence that tells them to
        // fetch a new one would be false as well as useless.
        #expect(refused.refusalReason?.message.contains("Wait a while") == true)
    }

    @Test("A subject's counts are dropped once the window has passed")
    func theWindowRestarts() async throws {
        let limits = try VerificationLimits(sessionLifetime: 900, subjectWindow: 3_600)
        let coordinator = try CoordinatorFixtures.coordinator(limits: limits)
        let account = try ProofFixtures.account()
        var spent = 0
        while spent < VerificationLimits.maximumSubmissionsPerSubject {
            let session = try await CoordinatorFixtures.connectedSession(
                on: coordinator,
                account: account
            )
            for _ in 0..<VerificationLimits.maximumSubmissionsPerSession
            where spent < VerificationLimits.maximumSubmissionsPerSubject {
                _ = try await coordinator.submit(
                    blob: ProofRefusalTests.rubbish,
                    to: session.id,
                    now: CoordinatorFixtures.now
                )
                spent += 1
            }
        }
        let later = CoordinatorFixtures.now.addingTimeInterval(3_601)
        let fresh = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account,
            at: later
        )
        let refused = try await coordinator.submit(
            blob: ProofRefusalTests.rubbish,
            to: fresh.id,
            now: later
        )
        #expect(refused.refusalReason == .blobUnreadable)
    }

    @Test("An interval of nothing is refused rather than accepted")
    func anIntervalMustBePositive() {
        #expect(throws: VerifyError.intervalNotPositive(field: "sessionLifetime")) {
            _ = try VerificationLimits(sessionLifetime: 0, subjectWindow: 60)
        }
        #expect(throws: VerifyError.intervalNotPositive(field: "subjectWindow")) {
            _ = try VerificationLimits(sessionLifetime: 60, subjectWindow: -1)
        }
    }

    // MARK: - One live session per subject

    @Test("A second session for the same subject displaces the first, challenge and all")
    func mintingDisplaces() async throws {
        // Goes red against two live challenges for one member, which is two
        // links either of which proves a wallet.
        let store = InMemoryVerificationSessionStore()
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()
        let first = try await CoordinatorFixtures.connectedSession(on: coordinator, account: account)
        let second = try await CoordinatorFixtures.connectedSession(on: coordinator, account: account)
        #expect(first.id != second.id)
        #expect(await store.session(id: first.id) == nil)
        #expect(await store.heldSessionCount == 1)

        let payment = ProofFixtures.proofPayment(for: account, note: first.challenge.bytes)
        let refused = try await coordinator.submit(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            to: first.id,
            now: CoordinatorFixtures.now
        )
        #expect(refused.refusalReason == .sessionUnavailable)
    }

    @Test("Never issued, consumed, pruned and displaced are indistinguishable in the refusal")
    func oneReasonForEveryIdThatSelectsNothing() async throws {
        // Goes red against telling a holder of a stolen id whether it was
        // ever real, and against telling somebody walking ids when a member
        // is part way through.
        let store = InMemoryVerificationSessionStore()
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()

        let neverIssued = VerificationSessionIdentifier.mint()

        let consumedSession = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: consumedSession.challenge.bytes)
        _ = try await coordinator.submit(
            blob: try ProofFixtures.blob(payment, signedBy: account),
            to: consumedSession.id,
            now: CoordinatorFixtures.now
        )

        let displaced = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            subject: CoordinatorFixtures.otherSubject,
            account: account
        )
        _ = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            subject: CoordinatorFixtures.otherSubject,
            account: account
        )

        let prunedSession = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            subject: "cccccccccccccccccccccccccccccccc",
            account: account
        )
        await coordinator.prune(now: prunedSession.expiresAt.addingTimeInterval(1))

        for id in [neverIssued, consumedSession.id, displaced.id, prunedSession.id] {
            let outcome = try await coordinator.submit(
                blob: ProofRefusalTests.rubbish,
                to: id,
                now: CoordinatorFixtures.now
            )
            #expect(outcome.refusalReason == .sessionUnavailable)
        }
    }

    // MARK: - The connected address

    @Test("A session records the connected address once and refuses a second, saying nothing")
    func theAddressIsRecordedOnce() async throws {
        // Goes red against an unbound duplicate-address check, which
        // answers "does this address belong to a member here?" for any
        // address to anybody holding a session. The holder lists this
        // product publishes are public, so that is an enumeration oracle
        // over them.
        let coordinator = try CoordinatorFixtures.coordinator()
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let again = try await coordinator.connect(
            sessionId: session.id,
            address: account.address.description,
            now: CoordinatorFixtures.now
        )
        #expect(again.refusalReason == nil)

        let second = try await coordinator.connect(
            sessionId: session.id,
            address: stranger.address.description,
            now: CoordinatorFixtures.now
        )
        #expect(second.refusalReason == .addressAlreadyConnected)
        // The refusal says the session is already connected and nothing at
        // all about the address that was offered.
        #expect(second.refusalReason.map { !$0.message.contains(stranger.address.description) } == true)
    }

    @Test("A pinned session refuses the first differing address at the connect")
    func aPinnedSessionRefusesEarly() async throws {
        // Goes red against recording the address anyway and only noticing
        // at the proof, which throws away the one thing naming a wallet
        // buys: a mismatch the member finds before their wallet asks them
        // to sign.
        let coordinator = try CoordinatorFixtures.coordinator()
        let named = try ProofFixtures.account()
        let connected = try ProofFixtures.account()
        let session = try await coordinator.mint(
            subject: CoordinatorFixtures.subject,
            pinnedAddress: named.address.description,
            now: CoordinatorFixtures.now
        )
        let outcome = try await coordinator.connect(
            sessionId: session.id,
            address: connected.address.description,
            now: CoordinatorFixtures.now
        )
        #expect(outcome.refusalReason == .pinnedAddressMismatch)
        #expect(outcome.session == nil)

        let matching = try await coordinator.connect(
            sessionId: session.id,
            address: named.address.description,
            now: CoordinatorFixtures.now
        )
        #expect(matching.session?.connectedAddress == named.address.description)
    }

    @Test("A pin that is not an address is refused at the mint")
    func thePinIsAnAddressAndNeverAName() async throws {
        // Goes red against accepting a name here, which is a network read
        // and belongs above this module.
        let coordinator = try CoordinatorFixtures.coordinator()
        await #expect(throws: VerifyError.addressNotCanonical(field: "pinnedAddress")) {
            _ = try await coordinator.mint(
                subject: CoordinatorFixtures.subject,
                pinnedAddress: "somebody.algo",
                now: CoordinatorFixtures.now
            )
        }
    }

    @Test("An address no Algorand tool would accept is refused at the connect")
    func theConnectedAddressMustParse() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let session = try await coordinator.mint(
            subject: CoordinatorFixtures.subject,
            now: CoordinatorFixtures.now
        )
        await #expect(throws: VerifyError.addressNotCanonical(field: "address")) {
            _ = try await coordinator.connect(
                sessionId: session.id,
                address: "not-an-address",
                now: CoordinatorFixtures.now
            )
        }
    }

    @Test("A session nothing connected an address to takes no submission")
    func aSubmissionNeedsAConnectedAddress() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let session = try await coordinator.mint(
            subject: CoordinatorFixtures.subject,
            now: CoordinatorFixtures.now
        )
        let outcome = try await coordinator.submit(
            blob: ProofRefusalTests.rubbish,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(outcome.refusalReason == .sessionUnavailable)
    }

    // MARK: - The coordinator's own configuration

    @Test("A coordinator with a bad label refuses to exist")
    func aBadLabelStopsTheCoordinator() {
        // The offline half of the rule a host carries at startup, where the
        // variable is named. Here it is refused at the point a challenge
        // would be minted, so a host that forgets its half fails a
        // challenge rather than rendering a malformed one.
        #expect(throws: VerifyError.challengeValueCarriesLineBreak(field: "challenge label")) {
            _ = try CoordinatorFixtures.coordinator(label: "two\nlines")
        }
        #expect(throws: VerifyError.self) {
            _ = try CoordinatorFixtures.coordinator(
                label: String(repeating: "x", count: VerificationChallenge.maximumLabelByteCount + 1)
            )
        }
    }

    @Test("The challenge a session carries is the operator's label and this instance's identity")
    func theSessionCarriesTheOperatorsWords() async throws {
        let coordinator = try CoordinatorFixtures.coordinator()
        let session = try await coordinator.mint(
            subject: CoordinatorFixtures.subject,
            now: CoordinatorFixtures.now
        )
        #expect(session.challenge.label == CoordinatorFixtures.label)
        #expect(session.challenge.instanceIdentity == CoordinatorFixtures.instance)
        #expect(session.challenge.subject == CoordinatorFixtures.subject)
        #expect(session.state == .issued)
        #expect(session.connectedAddress == nil)
        #expect(session.submissionCount == 0)
        #expect(!session.authorizingKeyRetryUsed)
    }
}
