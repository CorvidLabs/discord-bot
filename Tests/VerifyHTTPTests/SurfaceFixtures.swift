import Foundation
import Algorand
import Verify
@testable import VerifyHTTP

/// A whole surface with nothing real behind it: no chat service, no store of
/// members, no chain and no socket.
///
/// Every key is generated inside the test from the platform's own randomness
/// and every signature is produced by the dependency's own signing path, so
/// the production path runs unchanged (BUILD-2, BUILD-2.a).
enum SurfaceFixtures {

    // MARK: - Properties

    /// An instant every fixture is dated from. Fixed, because the surface
    /// takes `now` as a parameter and no reading here should depend on when
    /// the suite ran.
    static let now: Date = Date(timeIntervalSince1970: 1_700_000_000)

    /// An operator's own words, which are nobody's in particular.
    static let label: String = "Wing and Claw verification"

    /// What one instance calls itself.
    static let instance: String = "instance-a"

    /// An opaque subject, of the shape a minted member key has.
    static let subject: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f0"

    /// The display name a chat client would show for that subject.
    static let accountName: String = "heron of the north"

    /// A peer address for the rate limit to count against.
    static let source: String = "203.0.113.7"

    // MARK: - Methods

    /// A store, a coordinator and a service over both.
    static func surface(
        host: VerifyHTTPHost? = nil,
        limits: VerifyHTTPLimits = .standard,
        log: LogSpy? = nil
    ) throws -> (
        service: VerifyHTTPService,
        coordinator: VerificationCoordinator,
        store: InMemoryVerificationSessionStore
    ) {
        let store = InMemoryVerificationSessionStore()
        let coordinator = try VerificationCoordinator(
            instanceIdentity: instance,
            challengeLabel: label,
            store: store
        )
        var record: @Sendable (String) -> Void = { _ in }
        if let log {
            record = log.record
        }
        let service = VerifyHTTPService(
            coordinator: coordinator,
            sessions: store,
            host: host ?? HostSpy().host(),
            limits: limits,
            log: record
        )
        return (service, coordinator, store)
    }

    /// A `GET` for one of the static assets.
    static func get(_ path: String) -> VerifyHTTPRequest {
        VerifyHTTPRequest(method: "GET", target: path, headers: [:], body: "")
    }

    /// A `POST` carrying a JSON body.
    static func post(_ path: String, body: String) -> VerifyHTTPRequest {
        VerifyHTTPRequest(
            method: "POST",
            target: path,
            headers: ["content-type": "application/json", "content-length": String(body.utf8.count)],
            body: body
        )
    }

    /// A card call for one session.
    static func card(_ session: VerificationSessionIdentifier) -> VerifyHTTPRequest {
        post(VerifyRouting.cardPath, body: "{\"session\":\"\(session.value)\"}")
    }

    /// A connect call for one session and address.
    static func connect(
        _ session: VerificationSessionIdentifier,
        address: String
    ) -> VerifyHTTPRequest {
        post(
            VerifyRouting.connectPath,
            body: "{\"session\":\"\(session.value)\",\"address\":\"\(address)\"}"
        )
    }

    /// A submit call for one session and blob.
    static func submit(_ session: VerificationSessionIdentifier, blob: String) -> VerifyHTTPRequest {
        post(
            VerifyRouting.submitPath,
            body: "{\"session\":\"\(session.value)\",\"blob\":\"\(blob)\"}"
        )
    }

    /// One JSON body as a dictionary, so a test asserts the wire shape
    /// rather than a Swift type that could drift from it.
    static func fields(_ response: VerifyHTTPResponse) -> [String: Any] {
        guard
            let data = response.body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}

/// The four reads a host owes, each one recording what it was asked.
actor HostSpy {

    // MARK: - Properties

    /// What the naming closure answers.
    var name: String? = SurfaceFixtures.accountName

    /// Whether the address is claimed by somebody else, or nil for a
    /// program that could not tell.
    var claimed: Bool? = false

    /// The key an authorising address read answers, or nil for no reader.
    var authorizingKey: Data?

    /// Whether this host has an authorising key reader at all.
    var hasAuthorizingKeyReader: Bool = false

    /// What holding a proof answers.
    var handoff: ProofHandoff = .awaitingConfirmation

    /// The proofs it was handed.
    private(set) var held: [ProvedAccount] = []

    /// How many times an authorising address was read.
    private(set) var authorizingKeyReads = 0

    /// The addresses it was asked about.
    private(set) var claimQuestions: [String] = []

    // MARK: - Methods

    func set(name: String?) { self.name = name }

    func set(claimed: Bool?) { self.claimed = claimed }

    func set(handoff: ProofHandoff) { self.handoff = handoff }

    func setAuthorizingKey(_ key: Data?) {
        authorizingKey = key
        hasAuthorizingKeyReader = true
    }

    /// The host value the service is built with.
    nonisolated func host() -> VerifyHTTPHost {
        VerifyHTTPHost(
            chatAccountName: { [self] _ in await self.name },
            addressAlreadyClaimed: { [self] address, _ in await self.askClaimed(address) },
            authorizingKey: { [self] address in await self.readAuthorizingKey(address) },
            recordPendingProof: { [self] proved in await self.hold(proved) }
        )
    }

    /// A host with no authorising key reader at all, which is what an
    /// operator with no chain read configured has.
    nonisolated func hostWithoutAuthorizingKeyReader() -> VerifyHTTPHost {
        VerifyHTTPHost(
            chatAccountName: { [self] _ in await self.name },
            addressAlreadyClaimed: { [self] address, _ in await self.askClaimed(address) },
            authorizingKey: nil,
            recordPendingProof: { [self] proved in await self.hold(proved) }
        )
    }

    private func askClaimed(_ address: String) -> Bool? {
        claimQuestions.append(address)
        return claimed
    }

    private func readAuthorizingKey(_ address: String) -> Data? {
        authorizingKeyReads += 1
        return authorizingKey
    }

    private func hold(_ proved: ProvedAccount) -> ProofHandoff {
        held.append(proved)
        return handoff
    }
}

/// Everything the surface tried to log.
///
/// A stream rather than an actor, and that is the point rather than a
/// flourish: the log seam is synchronous, so an actor would have to be
/// written to from a detached task and a suite reading it afterwards would
/// be racing whatever the scheduler decided. Yielding to a stream happens on
/// the calling thread, so what the assertion reads is what the call wrote.
final class LogSpy: Sendable {

    // MARK: - Properties

    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    /// What the service is handed.
    var record: @Sendable (String) -> Void {
        let continuation = self.continuation
        return { line in continuation.yield(line) }
    }

    // MARK: - Initializers

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: String.self)
    }

    // MARK: - Methods

    /// Everything logged so far, as one string. Closes the stream, so it is
    /// asked once at the end of a test.
    func joined() async -> String {
        continuation.finish()
        var lines: [String] = []
        for await line in stream {
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

/// A real signer, with no network and no wallet.
enum ProofFixtures {

    // MARK: - Properties

    /// A genesis that belongs to nobody, made up here so no network's own
    /// identifier is carried into this repository.
    static let genesisIdentifier: String = "verify-http-suite"

    /// Thirty two bytes that are not all zero, so the canonical encoder
    /// keeps the field.
    static let genesisHash: Data = Data(repeating: 0x2A, count: 32)

    // MARK: - Methods

    /// A fresh account from the platform's randomness.
    static func account() throws -> Account {
        try Account()
    }

    /// The shape the page asks for: a zero amount self payment carrying the
    /// challenge in its note.
    static func proof(for account: Account, note: Data) -> PaymentTransaction {
        PaymentTransaction(
            sender: account.address,
            receiver: account.address,
            amount: MicroAlgos(0),
            fee: MicroAlgos(0),
            firstValid: 1_000,
            lastValid: 2_000,
            genesisID: genesisIdentifier,
            genesisHash: genesisHash,
            note: note
        )
    }

    /// A signed envelope, base64, exactly as the page would post it.
    static func blob(_ transaction: any Transaction, signedBy account: Account) throws -> String {
        try SignedTransaction.sign(transaction, with: account).encode().base64EncodedString()
    }

    /// A signature over the right preimage by the wrong key, in an envelope
    /// that does not name its signer.
    static func blobSignedByStranger(
        _ transaction: any Transaction,
        signedBy stranger: Account
    ) throws -> String {
        let signature = try stranger.sign(try transaction.bytesToSign())
        return try SignedTransaction(transaction: transaction, signature: signature)
            .encode()
            .base64EncodedString()
    }
}
