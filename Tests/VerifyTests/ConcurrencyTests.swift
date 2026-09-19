import Foundation
import Testing
import Algorand
import Verify

/// A store that makes a race happen the same way on every run.
///
/// Every reader is held at ``session(id:)`` until the callers a case is
/// racing have all arrived, so an interleaving that otherwise depends on
/// which task the scheduler picks is the interleaving every run gets.
///
/// **It lets go by itself after a grace.** Once the coordinator refuses a
/// second caller before that caller reads anything, only one reader ever
/// arrives, and a barrier that opened only on a full house would hang the
/// suite rather than pass it.
///
/// It is armed rather than always on, because the mint and the connect a
/// case does before the race read the store too, and a barrier that ate
/// those would be open again by the time the race started.
actor RendezvousSessionStore: VerificationSessionStore {

    // MARK: - Properties

    private let backing = InMemoryVerificationSessionStore()
    private let expected: Int
    private let graceNanoseconds: UInt64
    private var isArmed: Bool = false
    private var isOpen: Bool = false
    private var arrived: Int = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializers

    /// - Parameters:
    ///   - expected: How many readers the case is racing.
    ///   - graceNanoseconds: How long one reader waits for company before
    ///     the barrier gives up on it.
    init(expected: Int, graceNanoseconds: UInt64 = 100_000_000) {
        self.expected = expected
        self.graceNanoseconds = graceNanoseconds
    }

    // MARK: - VerificationSessionStore

    func store(_ session: VerificationSession) async {
        await backing.store(session)
    }

    func session(id: VerificationSessionIdentifier) async -> VerificationSession? {
        // Held **after** the read, so every racing caller is holding the
        // same copy before any of them acts on it. Held before it, they
        // queue on the backing store and one reads the other's write,
        // which is the race not happening.
        let found = await backing.session(id: id)
        await hold()
        return found
    }

    func update(_ session: VerificationSession) async {
        await backing.update(session)
    }

    func prune(now: Date, subjectWindow: TimeInterval) async {
        await backing.prune(now: now, subjectWindow: subjectWindow)
    }

    func tally(forSubject subject: String, now: Date, subjectWindow: TimeInterval) async -> SubjectTally {
        await backing.tally(forSubject: subject, now: now, subjectWindow: subjectWindow)
    }

    func countSubmission(forSubject subject: String, now: Date, subjectWindow: TimeInterval) async {
        await backing.countSubmission(forSubject: subject, now: now, subjectWindow: subjectWindow)
    }

    func countRetryOffered(forSubject subject: String, now: Date, subjectWindow: TimeInterval) async {
        await backing.countRetryOffered(forSubject: subject, now: now, subjectWindow: subjectWindow)
    }

    // MARK: - Methods

    /// Holds every reader from here until the race has been run.
    func arm() {
        isArmed = true
        isOpen = false
        arrived = 0
    }

    /// The session as the store holds it, read past the barrier.
    func held(id: VerificationSessionIdentifier) async -> VerificationSession? {
        await backing.session(id: id)
    }

    // MARK: - Private Methods

    private func hold() async {
        guard isArmed, !isOpen else { return }
        arrived += 1
        if arrived >= expected {
            open()
            return
        }
        if arrived == 1 {
            // The barrier inherits this actor, so the grace runs here and
            // needs no hop back.
            Task {
                try? await Task.sleep(nanoseconds: graceNanoseconds)
                open()
            }
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func open() {
        isOpen = true
        let queued = waiting
        waiting = []
        for continuation in queued { continuation.resume() }
    }
}

/// What holds when two calls arrive on one session at once (VERIFY-1,
/// VERIFY-2, RUN-11).
///
/// An HTTP route hands a host concurrency for free: posting the same body
/// twice at once is not an attack anybody has to construct. The coordinator
/// is an actor, which advertises mutual exclusion, and every hop into the
/// store releases it, so a bound read before a hop and written after it is
/// no bound at all.
@Suite("Two calls at once on one session")
struct ConcurrencyTests {

    // MARK: - Single use

    @Test("Two submissions of one valid proof in flight do not both prove the session")
    func oneProofIsAcceptedOnce() async throws {
        // Goes red against reading the session, suspending, and only then
        // testing whether it was consumed: both callers see a live session,
        // both check the signature, and one session mints two proved
        // accounts.
        let store = RendezvousSessionStore(expected: 2)
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let blob = try ProofFixtures.blob(payment, signedBy: account)
        await store.arm()

        async let first = coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        async let second = coordinator.submit(blob: blob, to: session.id, now: CoordinatorFixtures.now)
        let outcomes = try await [first, second]

        #expect(outcomes.filter { $0.refusalReason == nil }.count == 1)
        // And the blob that was accepted is not a blob that keeps working.
        let again = try await coordinator.submit(
            blob: blob,
            to: session.id,
            now: CoordinatorFixtures.now
        )
        #expect(again.refusalReason == .sessionUnavailable)
    }

    // MARK: - The connected address

    @Test("Two connects in flight with different addresses do not both bind")
    func oneAddressIsBoundOnce() async throws {
        // Goes red against reading the session, suspending, and only then
        // testing `connectedAddress`. Both callers are told their own
        // address was accepted, which hands back the enumeration oracle
        // binding the question to a session was there to close.
        let store = RendezvousSessionStore(expected: 2)
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let one = try ProofFixtures.account()
        let other = try ProofFixtures.account()
        let session = try await coordinator.mint(
            subject: CoordinatorFixtures.subject,
            now: CoordinatorFixtures.now
        )
        await store.arm()

        async let first = coordinator.connect(
            sessionId: session.id,
            address: one.address.description,
            now: CoordinatorFixtures.now
        )
        async let second = coordinator.connect(
            sessionId: session.id,
            address: other.address.description,
            now: CoordinatorFixtures.now
        )
        let outcomes = try await [first, second]

        let accepted = Set(outcomes.compactMap { $0.session?.connectedAddress })
        #expect(accepted.count == 1)
        let held = await store.held(id: session.id)
        #expect(held?.connectedAddress == accepted.first)
    }

    // MARK: - The bounds

    @Test("A burst of submissions in flight cannot outspend the session's allowance")
    func theSessionBoundHoldsUnderABurst() async throws {
        // The shape that costs the host a chain read every time: field
        // correct, signed by a throwaway key, refused only at the
        // signature. Against a bound read before a store hop and written
        // after it, all of them do the work (RUN-11).
        let outcomes = try await Self.burstOfStrangerProofs(count: 8)
        let reachedTheSignature = outcomes.filter {
            if case .signatureInvalid = $0.refusalReason { return true }
            return false
        }
        #expect(reachedTheSignature.count <= VerificationLimits.maximumSubmissionsPerSession)
    }

    @Test("The authorising key retry is reported as available at most once under a burst")
    func theRetryIsOfferedOnceUnderABurst() async throws {
        // Each offer invites the host to read an authorising address. "At
        // most once per session" that only holds when the calls happen to
        // be in a row is a habit rather than a bound (RUN-11).
        let outcomes = try await Self.burstOfStrangerProofs(count: 8)
        let offered = outcomes.filter {
            $0.refusalReason == .signatureInvalid(authorizingKeyRetryAvailable: true)
        }
        #expect(offered.count <= 1)
    }

    // MARK: - Private Methods

    /// A burst of field correct proofs signed by a throwaway key, every one
    /// of them in flight at once.
    private static func burstOfStrangerProofs(count: Int) async throws -> [VerificationOutcome] {
        let store = RendezvousSessionStore(expected: count)
        let coordinator = try CoordinatorFixtures.coordinator(store: store)
        let account = try ProofFixtures.account()
        let stranger = try ProofFixtures.account()
        let session = try await CoordinatorFixtures.connectedSession(
            on: coordinator,
            account: account
        )
        let payment = ProofFixtures.proofPayment(for: account, note: session.challenge.bytes)
        let blob = try ProofFixtures.blobSignedByStranger(payment, signedBy: stranger)
        await store.arm()

        return try await withThrowingTaskGroup(of: VerificationOutcome.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await coordinator.submit(
                        blob: blob,
                        to: session.id,
                        now: CoordinatorFixtures.now
                    )
                }
            }
            var collected: [VerificationOutcome] = []
            for try await outcome in group { collected.append(outcome) }
            return collected
        }
    }
}
