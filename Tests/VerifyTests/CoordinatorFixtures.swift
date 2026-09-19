import Foundation
import Algorand
import Verify

/// A coordinator and a connected session, so a suite about one refusal does
/// not spend twenty lines getting to it.
enum CoordinatorFixtures {

    // MARK: - Properties

    /// An instant every fixture is dated from. Fixed, because nothing in
    /// this module reads a clock and nothing in this suite should either.
    static let now: Date = Date(timeIntervalSince1970: 1_700_000_000)

    /// An operator's own words, which are nobody's in particular.
    static let label: String = "Wing and Claw verification"

    /// What one instance calls itself.
    static let instance: String = "instance-a"

    /// What another instance calls itself.
    static let otherInstance: String = "instance-b"

    /// An opaque subject, of the shape a minted member key has.
    static let subject: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f0"

    /// A second opaque subject.
    static let otherSubject: String = "112233445566778899aabbccddeeff00"

    // MARK: - Methods

    /// A coordinator over a fresh in-memory store.
    static func coordinator(
        instanceIdentity: String = instance,
        label labelText: String = label,
        limits: VerificationLimits = .standard,
        store: any VerificationSessionStore = InMemoryVerificationSessionStore()
    ) throws -> VerificationCoordinator {
        try VerificationCoordinator(
            instanceIdentity: instanceIdentity,
            challengeLabel: labelText,
            limits: limits,
            store: store
        )
    }

    /// A minted session with an account connected to it, which is where a
    /// page has got to by the time it posts anything.
    static func connectedSession(
        on coordinator: VerificationCoordinator,
        subject subjectValue: String = subject,
        account: Account,
        pinnedAddress: String? = nil,
        at instant: Date = now
    ) async throws -> VerificationSession {
        let session = try await coordinator.mint(
            subject: subjectValue,
            pinnedAddress: pinnedAddress,
            now: instant
        )
        let outcome = try await coordinator.connect(
            sessionId: session.id,
            address: account.address.description,
            now: instant
        )
        switch outcome {
        case .connected(let connected): return connected
        case .refused(let refusal): throw FixtureFailure.connectRefused(refusal.reason)
        }
    }
}

/// Why a fixture could not get a suite to the state it wanted.
enum FixtureFailure: Error {
    case connectRefused(ProofRefusalReason)
}
