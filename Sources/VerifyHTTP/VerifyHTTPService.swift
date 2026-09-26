@preconcurrency import Foundation
import Verify

/// Every rule this surface applies to one request, with no socket in sight.
///
/// The whole of what a host owes the verification module, minus the chat
/// command: a page to sign against, the three calls that page makes, a rate
/// limit on all of them, and a refusal that carries a reason and a handle
/// and never a session id.
///
/// **Nothing here reads a clock.** `now` arrives with the request, the same
/// way it does one layer down, so every expiry, every window and every
/// reading in the suite is the test's rather than the machine's. The
/// listener is where a clock is read, once, at the top.
///
/// **Nothing here reads anything else either.** This target links the
/// verification module and nothing else in the package: no store of members,
/// no chain reader, no chat client. The four things it cannot do for itself
/// arrive in ``VerifyHTTPHost``.
///
/// It is a value rather than an actor because it holds nothing that changes.
/// What changes lives in the three rate limiters, which are actors, and in
/// the session store, which is the coordinator's.
public struct VerifyHTTPService: Sendable {

    // MARK: - Properties

    /// What this surface will take, and from whom.
    public let limits: VerifyHTTPLimits

    private let coordinator: VerificationCoordinator
    private let sessions: any VerificationSessionStore
    private let host: VerifyHTTPHost
    private let assetLimiter: VerifyRateLimiter
    private let sourceLimiter: VerifyRateLimiter
    private let sessionLimiter: VerifyRateLimiter
    private let log: @Sendable (String) -> Void

    // MARK: - Initializers

    /// - Parameters:
    ///   - coordinator: What decides whether a proof is a proof.
    ///   - sessions: The same store that coordinator was built over. Read
    ///     here for one thing only: the card, which needs a session's
    ///     challenge, code and expiry, and which the coordinator has no
    ///     method for because nothing below this boundary shows a member
    ///     anything.
    ///   - host: The four reads this target cannot make for itself.
    ///   - limits: What it will take, and from whom.
    ///   - log: Where a line about a refusal goes. It is handed a handle and
    ///     never a session id, an address or a member's name.
    public init(
        coordinator: VerificationCoordinator,
        sessions: any VerificationSessionStore,
        host: VerifyHTTPHost,
        limits: VerifyHTTPLimits = .standard,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.sessions = sessions
        self.host = host
        self.limits = limits
        self.log = log
        self.assetLimiter = VerifyRateLimiter(
            limit: limits.assetRequestsPerSource,
            window: limits.window
        )
        self.sourceLimiter = VerifyRateLimiter(
            limit: limits.apiRequestsPerSource,
            window: limits.window
        )
        self.sessionLimiter = VerifyRateLimiter(
            limit: limits.apiRequestsPerSession,
            window: limits.window
        )
    }

    // MARK: - Public Methods

    /// What to answer one request with.
    ///
    /// - Parameters:
    ///   - request: What arrived.
    ///   - source: The peer's address, which the per-source limit is counted
    ///     against. Behind a reverse proxy this is the proxy for everybody,
    ///     which is why that limit is sized for a whole instance and why
    ///     the bound on a member is the per-session one.
    ///   - now: When it arrived.
    /// - Returns: The answer, headers and all.
    public func respond(
        to request: VerifyHTTPRequest,
        from source: String,
        now: Date
    ) async -> VerifyHTTPResponse {
        switch VerifyRouting.match(method: request.method, path: request.path) {
        case .unknown:
            // Not counted against anybody's budget. A wrong path is a
            // scanner or a typo, and counting it would let a scanner spend
            // the budget a member's own page needs.
            return refusal(status: 404, message: "There is nothing here.", retryable: false)

        case .methodNotAllowed:
            return refusal(
                status: 405,
                message: "That is not how this is asked for.",
                retryable: false
            )

        case .matched(let route):
            // Blunt on purpose, and it applies to the page as well as to the
            // calls. The one thing that must never be in a query string is
            // the session id, and a surface that serves a request carrying a
            // query has already taught somebody a shape in which it could
            // be. The cost is a link with a tracking parameter appended to
            // it being refused, which is a sentence the member can act on.
            //
            // Answered before the limiter is asked, for the same reason an
            // unknown path is: this request will not be served whatever
            // budget is left, so charging it would let somebody appending a
            // tracking parameter spend the budget a real page load needs,
            // and behind a reverse proxy that budget is the community's.
            // The question reads the target and nothing else.
            guard !request.carriesQuery else {
                log("verify: refused a request carrying a query string, route=\(route.rawValue)")
                return refusal(
                    status: 400,
                    message: "Open the link exactly as it was given to you, with nothing added after it.",
                    retryable: false
                )
            }
            // The limit comes next, before the body is looked at and before
            // any refusal that had to read one. A request this surface
            // serves at all is a request somebody can send again, and one
            // that is served for free is a request somebody can send for
            // ever.
            let carriesIdentifier = VerifyRouting.carriesSessionIdentifier(route)
            let limiter = carriesIdentifier ? sourceLimiter : assetLimiter
            guard await !limiter.isLimited(key: source, now: now) else {
                return tooManyRequests(handle: nil)
            }
            guard carriesIdentifier else { return asset(for: route) }
            return await answerCall(on: route, request: request, now: now)
        }
    }

    // MARK: - Private Methods

    /// One of this target's own static assets.
    private func asset(for route: VerifyHTTPRoute) -> VerifyHTTPResponse {
        switch route {
        case .page:
            return .asset(VerifyPage.html, contentType: "text/html; charset=utf-8")
        case .script:
            return .asset(VerifyPage.script, contentType: "text/javascript; charset=utf-8")
        case .stylesheet:
            return .asset(VerifyPage.stylesheet, contentType: "text/css; charset=utf-8")
        case .card, .connect, .submit:
            // Unreachable: the caller asked whether the route carries a
            // session id before calling this. Answered rather than trapped,
            // because a page that 500s is a member who cannot verify and a
            // crash is every member who cannot.
            return refusal(status: 404, message: "There is nothing here.", retryable: false)
        }
    }

    /// One of the three calls that carry a session id.
    private func answerCall(
        on route: VerifyHTTPRoute,
        request: VerifyHTTPRequest,
        now: Date
    ) async -> VerifyHTTPResponse {
        let call: VerifySessionCall
        switch route {
        case .card: call = .card
        case .connect: call = .connect
        case .submit: call = .submit
        case .page, .script, .stylesheet:
            return refusal(status: 404, message: "There is nothing here.", retryable: false)
        }

        guard request.body.utf8.count <= limits.maximumBodyBytes else {
            return refusal(status: 413, message: "That is more than this takes.", retryable: false)
        }
        guard
            let data = request.body.data(using: .utf8),
            let body = try? JSONDecoder().decode(VerifyCallBody.self, from: data)
        else {
            return refusal(status: 400, message: "That was not a request this understands.", retryable: false)
        }
        // A malformed id gets no handle: a handle is a digest of a session,
        // and this is a digest of whatever somebody typed.
        guard let sessionId = try? VerificationSessionIdentifier(body.session) else {
            return refusal(
                status: 400,
                message: "That link is not one this server issued. Run the command again for a new one.",
                retryable: false
            )
        }
        let handle = VerifySessionHandle(sessionIdentifier: sessionId)
        guard await !sessionLimiter.isLimited(key: handle.value, now: now) else {
            log("verify: over the per-session rate limit, handle=\(handle.value)")
            return tooManyRequests(handle: handle)
        }

        switch call {
        case .card:
            return await answerCard(sessionId: sessionId, handle: handle, now: now)
        case .connect:
            return await answerConnect(body: body, sessionId: sessionId, handle: handle, now: now)
        case .submit:
            return await answerSubmit(body: body, sessionId: sessionId, handle: handle, now: now)
        }
    }

    /// Who this session belongs to, its code and its expiry.
    private func answerCard(
        sessionId: VerificationSessionIdentifier,
        handle: VerifySessionHandle,
        now: Date
    ) async -> VerifyHTTPResponse {
        guard let session = await sessions.session(id: sessionId), session.state != .consumed else {
            return refusal(
                status: VerifyRefusalReporting.status(for: .sessionUnavailable),
                message: ProofRefusalReason.sessionUnavailable.message,
                handle: handle,
                retryable: false
            )
        }
        guard now < session.expiresAt else {
            return refusal(
                status: VerifyRefusalReporting.status(for: .sessionExpired),
                message: ProofRefusalReason.sessionExpired.message,
                handle: handle,
                retryable: false
            )
        }
        // Refused rather than rendered without a name. The name is the whole
        // mitigation for a relayed prompt, and a page that quietly drops it
        // is that defence switched off with nothing saying so.
        guard let account = await host.chatAccountName(session.subject) else {
            log("verify: a live session has no chat account name, card refused, handle=\(handle.value)")
            return refusal(
                status: 503,
                message: "This page cannot show who the link is for, so it will not go on. Try again shortly.",
                handle: handle,
                retryable: true
            )
        }
        let card = VerifyCardReply(
            account: account,
            code: session.challenge.code,
            expiresAt: Int(session.expiresAt.timeIntervalSince1970),
            challenge: session.challenge.text,
            connectedAddress: session.connectedAddress,
            pinnedAddress: session.pinnedAddress,
            maximumFeeMicroAlgos: ProofShape.maximumFeeMicroAlgos
        )
        return .json(status: 200, body: encode(card))
    }

    /// The address a wallet connected, recorded once.
    private func answerConnect(
        body: VerifyCallBody,
        sessionId: VerificationSessionIdentifier,
        handle: VerifySessionHandle,
        now: Date
    ) async -> VerifyHTTPResponse {
        guard let address = body.address, !address.isEmpty else {
            return refusal(
                status: 400,
                message: "No account arrived with that. Connect a wallet, or type the address.",
                handle: handle,
                retryable: true
            )
        }
        let outcome: ConnectionOutcome
        do {
            outcome = try await coordinator.connect(sessionId: sessionId, address: address, now: now)
        } catch {
            // The module throws rather than refusing here, because an
            // address no Algorand tool would accept is the page's mistake or
            // a typo, not a proof that failed.
            return refusal(
                status: 400,
                message: "That is not an Algorand address. Check it and try again.",
                handle: handle,
                retryable: true
            )
        }
        switch outcome {
        case .refused(let refused):
            log("verify: connect refused at step \(refused.reason.step), handle=\(handle.value)")
            return refusal(
                status: VerifyRefusalReporting.status(for: refused.reason),
                message: refused.message,
                handle: handle,
                retryable: VerifyRefusalReporting.isRetryable(refused.reason)
            )

        case .connected(let session):
            // Asked after the bind, never before, so the question is about
            // the address the member actually connected rather than any
            // address a session id holder cares to type. It is asked again
            // on the winning path, because this answer and the submission
            // are two requests and a caller is free to ignore this one.
            if let claimed = await claimRefusal(
                address: address,
                subject: session.subject,
                handle: handle,
                sessionIsSpent: false
            ) {
                return claimed
            }
            return .json(status: 200, body: encode(VerifyConnectReply(connectedAddress: address)))
        }
    }

    /// How to refuse an address the host says belongs elsewhere, or could not
    /// answer for at all, and nil when it is free to use.
    ///
    /// - Parameters:
    ///   - address: The address, which is only ever one a session is
    ///     already bound to.
    ///   - subject: Who is asking, so the host can answer about everybody
    ///     else.
    ///   - handle: What a refusal may say about the session.
    ///   - sessionIsSpent: Whether a proof has already been consumed, which
    ///     is what decides whether the same page could try again.
    private func claimRefusal(
        address: String,
        subject: String,
        handle: VerifySessionHandle,
        sessionIsSpent: Bool
    ) async -> VerifyHTTPResponse? {
        switch await host.addressAlreadyClaimed(address, subject) {
        case .some(false):
            return nil

        case .some(true):
            log("verify: refused, the account belongs to another member, handle=\(handle.value)")
            return refusal(
                status: 409,
                message: "That account is already linked to another member here. "
                    + "Ask whoever runs this server if that is wrong.",
                handle: handle,
                retryable: false
            )

        case .none:
            // Unreadable is not "nobody holds it". The program's own record
            // is what keeps one account to one member, and a surface that
            // treats a failed read as a free account is a surface that
            // links somebody else's wallet the first time a database is
            // busy.
            log("verify: could not read whether the account is already linked, handle=\(handle.value)")
            guard sessionIsSpent else {
                return refusal(
                    status: 503,
                    message: "This server cannot tell whether that account is already linked here, "
                        + "so it will not go on. Try again shortly.",
                    handle: handle,
                    retryable: true
                )
            }
            return refusal(
                status: 503,
                message: "Your signature checked out and this server cannot tell whether that account "
                    + "is already linked to somebody else. Run the command again.",
                handle: handle,
                retryable: false
            )
        }
    }

    /// The signed blob.
    private func answerSubmit(
        body: VerifyCallBody,
        sessionId: VerificationSessionIdentifier,
        handle: VerifySessionHandle,
        now: Date
    ) async -> VerifyHTTPResponse {
        guard let blob = body.blob, !blob.isEmpty else {
            return refusal(
                status: 400,
                message: "Nothing signed arrived with that. Sign the prompt and try again.",
                handle: handle,
                retryable: true
            )
        }
        let outcome: VerificationOutcome
        do {
            outcome = try await coordinator.submit(blob: blob, to: sessionId, now: now)
        } catch {
            // Only one thing throws here and it is this target's own
            // mistake, not the member's: a key of the wrong width, which
            // this call did not even pass. Reported as ours.
            log("verify: submit could not be decided, handle=\(handle.value)")
            return refusal(
                status: 500,
                message: "Something on this side went wrong. Try again.",
                handle: handle,
                retryable: true
            )
        }

        // The one retry, on the one refusal it could explain, from the one
        // place a key may come from. A rekeyed account cannot prove anything
        // without it, and a key from anywhere else would make the checker
        // accept whatever the caller handed it.
        if case .refused(let refused) = outcome,
            case .signatureInvalid(true) = refused.reason,
            let readAuthorizingKey = host.authorizingKey {
            return await retryUnderAuthorizingKey(
                blob: blob,
                sessionId: sessionId,
                handle: handle,
                refused: refused,
                readAuthorizingKey: readAuthorizingKey,
                now: now
            )
        }
        return await settle(outcome, handle: handle)
    }

    /// Reads the account's authorising key once and asks again.
    private func retryUnderAuthorizingKey(
        blob: String,
        sessionId: VerificationSessionIdentifier,
        handle: VerifySessionHandle,
        refused: ProofRefusal,
        readAuthorizingKey: @Sendable (String) async -> Data?,
        now: Date
    ) async -> VerifyHTTPResponse {
        guard
            let address = await sessions.session(id: sessionId)?.connectedAddress,
            let key = await readAuthorizingKey(address)
        else {
            return await settle(.refused(refused), handle: handle)
        }
        do {
            let retried = try await coordinator.submit(
                blob: blob,
                to: sessionId,
                authorizingKey: key,
                now: now
            )
            return await settle(retried, handle: handle)
        } catch {
            // A key of the wrong width. The program read it, so the program
            // is what is wrong, and the member is told so rather than being
            // told their signature was bad.
            log("verify: an authorising key was not 32 bytes, handle=\(handle.value)")
            return refusal(
                status: 500,
                message: "Something on this side went wrong. Try again.",
                handle: handle,
                retryable: true
            )
        }
    }

    /// What to answer once there is an outcome.
    private func settle(
        _ outcome: VerificationOutcome,
        handle: VerifySessionHandle
    ) async -> VerifyHTTPResponse {
        switch outcome {
        case .refused(let refused):
            log("verify: submit refused at step \(refused.reason.step), handle=\(handle.value)")
            return refusal(
                status: VerifyRefusalReporting.status(for: refused.reason),
                message: refused.message,
                handle: handle,
                retryable: VerifyRefusalReporting.isRetryable(refused.reason)
            )

        case .proved(let proved):
            // Asked again, here, about the address the session itself is
            // bound to. The question at the connect and the submission that
            // follows it are two requests, and the page honouring the
            // refusal is the page's manners rather than this surface's
            // rule: a caller that posts the next request anyway would
            // otherwise hand the program a proof for an account another
            // member holds.
            if let claimed = await claimRefusal(
                address: proved.address,
                subject: proved.subject,
                handle: handle,
                sessionIsSpent: true
            ) {
                return claimed
            }
            switch await host.recordPendingProof(proved) {
            case .awaitingConfirmation:
                log("verify: a proof was checked and is waiting to be confirmed, handle=\(handle.value)")
                return .json(
                    status: 200,
                    body: encode(
                        VerifyProvedReply(
                            status: "awaiting-confirmation",
                            message: "That account is proved. Go back to where you ran the command and "
                                + "confirm it to finish. Nothing is linked until you do."
                        )
                    )
                )

            case .unavailable:
                // The proof was real and the session is spent, so there is
                // nothing to try again with on this page. Said plainly,
                // because the alternative is a member who saw a success
                // page and has no role.
                log("verify: a checked proof could not be held, handle=\(handle.value)")
                return refusal(
                    status: 503,
                    message: "Your signature checked out and this server could not record it. "
                        + "Run the command again.",
                    handle: handle,
                    retryable: false
                )
            }
        }
    }

    /// The one shape every refusal takes.
    private func refusal(
        status: Int,
        message: String,
        handle: VerifySessionHandle? = nil,
        retryable: Bool
    ) -> VerifyHTTPResponse {
        .json(
            status: status,
            body: encode(
                VerifyRefusalReply(error: message, handle: handle?.value, retryable: retryable)
            )
        )
    }

    /// The answer to a request over a limit.
    private func tooManyRequests(handle: VerifySessionHandle?) -> VerifyHTTPResponse {
        refusal(
            status: 429,
            message: "That is faster than this page is answered. Wait a moment and try again.",
            handle: handle,
            retryable: true
        )
    }

    /// One value as JSON, with its keys in a fixed order.
    ///
    /// Sorted so that what a suite asserts is what a browser receives, and
    /// slashes left alone so a challenge line reads as it was written.
    private func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            // Unreachable for every type in this file, all of which are
            // strings, integers and optionals of both. An empty object
            // rather than a trap: this runs while a member is waiting.
            return "{}"
        }
        return text
    }
}
