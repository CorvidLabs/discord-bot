import Foundation
import Algorand

/// Mint a session, record a connection, take a blob, produce an outcome.
///
/// This is the deliberate scope decision of the module. It would have been
/// smaller to ship a signature checker and let a host own sessions, expiry,
/// single use and the order of the reasons. That is also how every one of
/// those properties gets quietly reimplemented and quietly got wrong. Putting
/// them here means a host's whole job is: bind a route, read a body, call one
/// method, render one page.
///
/// **Nothing here reads a clock.** Every instant arrives as a parameter, the
/// same way a game takes its clock and a time parser takes `now`, so every
/// reading in a suite is pinned by the test rather than by when the test ran.
///
/// **Nothing here reads anything else either.** No network, no database, no
/// setting from outside the process, no key. The one thing it depends on that
/// could reach a chain is an address parser, and a suite reads these sources
/// to prove nothing else came with it.
///
/// **One call at a time per session, and the actor is not what does it.**
/// Being an actor bounds one method's uninterrupted run, not one method: the
/// store is a separate actor, so every hop into it releases this one and a
/// second call on the same session runs inside the first. Every bound here
/// is read, then acted on after a hop, so without a claim of its own the
/// single use, the two submission bounds and the one authorising key retry
/// are all advisory. ``inFlight`` is that claim. A host whose store is
/// shared between processes needs the same claim in the store, because an
/// in-actor one covers one process.
public actor VerificationCoordinator {

    // MARK: - Properties

    /// What this instance calls itself inside the signed bytes, which is what
    /// makes a proof worthless in another community.
    public let instanceIdentity: String

    /// The operator's own words, the first line a member reads in the wallet.
    public let challengeLabel: String

    /// How long a session lives and how long a subject's counts are kept.
    public let limits: VerificationLimits

    private let store: any VerificationSessionStore

    /// The sessions a call is part way through deciding.
    ///
    /// An actor is not a lock around a method. Every `await` into the store
    /// releases this one, so a second call on the same session runs between
    /// a bound being read and the counter being written, and every guard in
    /// ``submit(blob:to:authorizingKey:now:)`` and
    /// ``connect(sessionId:address:now:)`` is a check against a copy that is
    /// already stale by the time it acts. An HTTP route hands a host that
    /// concurrency for free: posting the same body twice at once needs no
    /// tooling. Claimed here because `Set.insert` on actor isolated state,
    /// with no suspension between the test and the insert, is the one
    /// atomic step the rest of the method cannot be.
    private var inFlight: Set<String> = []

    // MARK: - Initializers

    /// - Parameters:
    ///   - instanceIdentity: What this instance calls itself.
    ///   - challengeLabel: The operator's own words.
    ///   - limits: How long a session lives and a window lasts.
    ///   - store: Where sessions are kept.
    /// - Throws: ``VerifyError`` when the label or the identity would not
    ///   render as one line, or the label is over the bound. Refused here as
    ///   well as at the mint, so a host that starts with a bad label finds
    ///   out before a member does rather than at the first verification.
    public init(
        instanceIdentity: String,
        challengeLabel: String,
        limits: VerificationLimits = .standard,
        store: any VerificationSessionStore
    ) throws {
        // Minting one and throwing it away is the cheapest way to hold the
        // constructor to exactly the rule the mint is held to, with no second
        // copy of the rule to drift.
        _ = try VerificationChallenge.mint(
            label: challengeLabel,
            instanceIdentity: instanceIdentity,
            subject: ""
        )
        self.instanceIdentity = instanceIdentity
        self.challengeLabel = challengeLabel
        self.limits = limits
        self.store = store
    }

    // MARK: - Public Methods

    /// A new session and the challenge that goes with it, displacing whatever
    /// the subject had.
    ///
    /// - Parameters:
    ///   - subject: The opaque subject, which this module never interprets.
    ///     Above this boundary it is an identifier that was minted rather
    ///     than derived from a person.
    ///   - pinnedAddress: The account the member named before anything was
    ///     signed, if they named one. An address, never a name: turning a
    ///     name into an address is an outbound call and belongs to the host.
    ///   - now: The instant to date the session from.
    /// - Returns: The session.
    /// - Throws: ``VerifyError`` for a value that would not render as one
    ///   line, or a pinned address that is not canonical.
    public func mint(
        subject: String,
        pinnedAddress: String? = nil,
        now: Date
    ) async throws -> VerificationSession {
        if let pinnedAddress, (try? Address(string: pinnedAddress)) == nil {
            throw VerifyError.addressNotCanonical(field: "pinnedAddress")
        }
        let challenge = try VerificationChallenge.mint(
            label: challengeLabel,
            instanceIdentity: instanceIdentity,
            subject: subject
        )
        let session = VerificationSession(
            id: VerificationSessionIdentifier.mint(),
            subject: subject,
            challenge: challenge,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(limits.sessionLifetime),
            pinnedAddress: pinnedAddress
        )
        await store.store(session)
        return session
    }

    /// Records the address a wallet connected, once.
    ///
    /// A second, differing address on the same session is refused **without
    /// answering anything about it**. A host's check for an address another
    /// member has already proved is the right behaviour and, asked freely, it
    /// answers "does this address belong to a member here?" for any address
    /// anybody cares to type, which is an afternoon's walk from a public
    /// holder list to a list of which addresses belong to members here. Bound
    /// to the session, the question is asked once, about the address the
    /// member actually connected.
    ///
    /// On a session pinned at the mint, the first address that is not the pin
    /// is refused here rather than recorded, which is the earlier mismatch a
    /// named wallet buys: the member finds out before their wallet asks them
    /// to sign.
    ///
    /// A second call arriving while one is still being decided is refused
    /// too, and with the same reason that says nothing. Without that, two
    /// connects presented together both read an unconnected session and both
    /// are told their own address was accepted, which is the oracle binding
    /// the question to a session was there to close.
    ///
    /// - Parameters:
    ///   - sessionId: The session.
    ///   - address: The account the wallet connected.
    ///   - now: The instant to measure expiry against.
    /// - Returns: The session, or a refusal.
    /// - Throws: ``VerifyError/addressNotCanonical(field:)`` for an address
    ///   no Algorand tool would accept, which is a page's mistake rather than
    ///   a member's.
    public func connect(
        sessionId: VerificationSessionIdentifier,
        address: String,
        now: Date
    ) async throws -> ConnectionOutcome {
        guard (try? Address(string: address)) != nil else {
            throw VerifyError.addressNotCanonical(field: "address")
        }
        let handle = RefusalHandle(sessionIdentifier: sessionId)
        guard inFlight.insert(sessionId.value).inserted else {
            return .refused(ProofRefusal(reason: .sessionUnavailable, handle: handle))
        }
        defer { inFlight.remove(sessionId.value) }
        guard var session = await store.session(id: sessionId), session.state != .consumed else {
            return .refused(ProofRefusal(reason: .sessionUnavailable, handle: handle))
        }
        guard now < session.expiresAt else {
            return .refused(ProofRefusal(reason: .sessionExpired, handle: handle))
        }
        if let pinned = session.pinnedAddress, pinned != address {
            return .refused(ProofRefusal(reason: .pinnedAddressMismatch, handle: handle))
        }
        if let connected = session.connectedAddress {
            guard connected == address else {
                return .refused(ProofRefusal(reason: .addressAlreadyConnected, handle: handle))
            }
            return .connected(session)
        }
        session.connect(address)
        await store.update(session)
        return .connected(session)
    }

    /// Takes a submitted blob and decides whether it proves the account the
    /// session is connected to.
    ///
    /// The session's own connected address is what the proof is held to, and
    /// the submission does not get to name one. That is what keeps the
    /// question "does this address already belong to somebody here?" bound to
    /// one address per session rather than answerable for any address a
    /// session id holder cares to type.
    ///
    /// A refused proof does **not** consume the session, so a member who
    /// picked the wrong account in their wallet may try again, and a hostile
    /// submission is not a denial of somebody else's verification. It does
    /// spend an attempt, which is what keeps trying again finite.
    ///
    /// - Parameters:
    ///   - blob: What the page posted, base64.
    ///   - sessionId: The session it was posted against.
    ///   - authorizingKey: A key the caller read from that exact account's
    ///     authorising address field, on a signature refusal that reported a
    ///     retry as available. From nowhere else, ever.
    ///   - now: The instant to measure expiry and date the proof from.
    /// - Returns: A proved account, or the first reason in the order that
    ///   held.
    /// - Throws: ``VerifyError/authorizingKeyWrongLength(byteCount:)`` for a
    ///   key the caller supplied at the wrong width. The caller's mistake is
    ///   raised to the caller and costs the member no attempt: dressed up as
    ///   a refusal it reads as a dead link, and the new link a member is
    ///   told to fetch reproduces it exactly.
    public func submit(
        blob: String,
        to sessionId: VerificationSessionIdentifier,
        authorizingKey: Data? = nil,
        now: Date
    ) async throws -> VerificationOutcome {
        let handle = RefusalHandle(sessionIdentifier: sessionId)

        // Refused rather than queued, and refused with the reason that says
        // nothing: telling whoever holds an id that somebody else is part
        // way through this session is the disclosure `sessionUnavailable`
        // exists to avoid.
        guard inFlight.insert(sessionId.value).inserted else {
            return .refused(ProofRefusal(reason: .sessionUnavailable, handle: handle))
        }
        defer { inFlight.remove(sessionId.value) }

        // 1. Session state. One reason for every way an id selects nothing,
        //    its own reason for an allowance that is spent.
        guard var session = await store.session(id: sessionId), session.state != .consumed else {
            return .refused(ProofRefusal(reason: .sessionUnavailable, handle: handle))
        }
        guard let address = session.connectedAddress else {
            return .refused(ProofRefusal(reason: .sessionUnavailable, handle: handle))
        }
        guard session.submissionCount < VerificationLimits.maximumSubmissionsPerSession else {
            return .refused(ProofRefusal(reason: .submissionsExhausted(.session), handle: handle))
        }
        let tally = await store.tally(
            forSubject: session.subject,
            now: now,
            subjectWindow: limits.subjectWindow
        )
        guard tally.submissions < VerificationLimits.maximumSubmissionsPerSubject else {
            return .refused(ProofRefusal(reason: .submissionsExhausted(.subject), handle: handle))
        }

        // 2. Expiry, named whatever else is wrong with the submission,
        //    because a new link is what fixes it and debugging a wallet is
        //    not.
        guard now < session.expiresAt else {
            return .refused(ProofRefusal(reason: .sessionExpired, handle: handle))
        }

        // Built before the attempt is spent. Nothing that can be wrong here
        // is a member's doing: both addresses were parsed before they were
        // recorded, and the key's width is the caller's to get right.
        let expectation = try ProofExpectation(
            address: address,
            challenge: session.challenge,
            pinnedAddress: session.pinnedAddress,
            authorizingKey: authorizingKey
        )

        // The attempt is spent before the work, so a submission that fails
        // part way through still counts against the allowance it used.
        session.countSubmission()
        await store.update(session)
        await store.countSubmission(
            forSubject: session.subject,
            now: now,
            subjectWindow: limits.subjectWindow
        )

        // The retry is offered on the one refusal it could explain, at most
        // once per session, and never when this call already is the retry.
        let retryAvailable = !session.authorizingKeyRetryUsed && authorizingKey == nil

        switch ProofChecker.check(
            blob: blob,
            against: expectation,
            authorizingKeyRetryAvailable: retryAvailable
        ) {
        case .refused(let reason):
            if case .signatureInvalid(true) = reason {
                session.markAuthorizingKeyRetryUsed()
                await store.update(session)
                await store.countRetryOffered(
                    forSubject: session.subject,
                    now: now,
                    subjectWindow: limits.subjectWindow
                )
            }
            return .refused(ProofRefusal(reason: reason, handle: handle))
        case .accepted(let usedAuthorizingKey):
            session.consume()
            await store.update(session)
            return .proved(
                ProvedAccount(
                    subject: session.subject,
                    address: address,
                    provedAt: now,
                    usedAuthorizingKey: usedAuthorizingKey
                )
            )
        }
    }

    /// Drops spent and expired sessions with their challenges, and subject
    /// counts whose window has passed.
    ///
    /// - Parameter now: The instant to measure against.
    public func prune(now: Date) async {
        await store.prune(now: now, subjectWindow: limits.subjectWindow)
    }
}
