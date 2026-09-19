@preconcurrency import Foundation

/// One HTTP request, parsed.
///
/// Parsing lives here, away from any socket, because every rule the listener
/// enforces is then a unit test rather than something only a live portal can
/// exercise (`BUILD-2`).
public struct HTTPRequestHead: Sendable, Equatable {

    // MARK: - Properties

    /// Most bytes read from one connection.
    ///
    /// The listener performs **a single read of at most this many bytes and
    /// never reads that socket again**. It never looks at `Content-Length`.
    /// Whatever arrived in that one read is the whole request. That is the
    /// contract a portal author has to build against, which is why it is a
    /// named constant and documented rather than a number in a socket loop:
    /// no chunked transfer encoding, no `Expect: 100-continue`, no connection
    /// reuse.
    public static let maximumRequestBytes = 8_192

    /// `GET`, `POST`, and so on.
    public let method: String

    /// The path, query string included.
    public let path: String

    /// Header names lowercased, values trimmed.
    public let headers: [String: String]

    /// Everything after the first empty line.
    public let body: String

    // MARK: - Initializers

    /// - Parameters:
    ///   - method: The method.
    ///   - path: The path.
    ///   - headers: Header names lowercased, values trimmed.
    ///   - body: Everything after the first empty line.
    public init(method: String, path: String, headers: [String: String], body: String) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    // MARK: - Public Methods

    /// One request as text, or nil when the first line is not a request line.
    ///
    /// - Parameter raw: What the single read produced, decoded as UTF-8.
    public static func parse(_ raw: String) -> HTTPRequestHead? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        var bodyStart = lines.count
        for (index, line) in lines.enumerated().dropFirst() {
            if line.isEmpty {
                bodyStart = index + 1
                break
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<separator].lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let body = bodyStart < lines.count
            ? lines[bodyStart...].joined(separator: "\r\n")
            : ""
        return HTTPRequestHead(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            body: body
        )
    }

    /// The path with any query string taken off.
    public var route: String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }
}

/// What the listener should do about one request.
public enum CallbackRoute: Sendable, Equatable {

    /// Answer the health check. Not rate limited, not authenticated.
    case health

    /// The callback passed every check. Answer `200`, then do the work.
    case accepted(VerificationCallback)

    /// Answer this status with this JSON body, and do nothing else.
    case refuse(status: Int, body: String)
}

/// Every check a callback passes, in the order it passes them.
///
/// The order is the contract, and step seven is the one worth understanding:
/// **the payload is validated before `200` is answered.** A shared secret
/// proves who sent the request, not that the request makes sense, and a
/// portal that records a verification whenever its callback succeeds must
/// never record one this bot threw away.
///
/// `GET /health` is answered before rate limiting and before authentication,
/// because it is also what the operator's own deploy gate polls and locking
/// it behind either is how a deploy gate starts failing at three in the
/// morning for a reason nobody can see.
public enum CallbackRouting: Sendable {

    // MARK: - Public Methods

    /// The callback path, as `docs/VERIFICATION.md` writes it.
    public static let callbackPath = "/webhook/verification"

    /// The health path.
    public static let healthPath = "/health"

    /// The header the shared secret travels in. Compared without regard to
    /// case, which is why it is stored lowercased.
    public static let apiKeyHeader = "x-api-key"

    /// What to do about this request.
    ///
    /// - Parameters:
    ///   - request: What arrived.
    ///   - expectedKey: This bot's copy of the shared secret.
    ///   - servedGuildId: The one server this process serves.
    ///   - isRateLimited: Whether this source has had too many lately.
    ///   - isValidAddress: Whether an address parses on this chain.
    public static func route(
        _ request: HTTPRequestHead,
        expectedKey: String,
        servedGuildId: String,
        isRateLimited: Bool,
        isValidAddress: (String) -> Bool
    ) -> CallbackRoute {
        if request.method == "GET", request.route == healthPath {
            return .health
        }
        guard request.method == "POST", request.route == callbackPath else {
            // Not rate limited: a wrong path is somebody's typo or a scanner,
            // and counting it against the portal's budget would let a scanner
            // lock out a real callback.
            return .refuse(status: 404, body: "{\"error\":\"Not Found\"}")
        }
        guard !isRateLimited else {
            return .refuse(status: 429, body: "{\"error\":\"Too Many Requests\"}")
        }
        // No secret configured is not an open door. ``constantTimeEquals``
        // answers true for two empty strings, so a header sent empty would
        // match an unset secret and admit whoever sent it, with verification
        // switched off and nobody expecting this route to be live at all.
        guard !expectedKey.isEmpty else {
            return .refuse(status: 401, body: "{\"error\":\"Unauthorized\"}")
        }
        // Constant time, and no detail about which part was wrong.
        guard
            let presented = request.headers[apiKeyHeader],
            constantTimeEquals(presented, expectedKey)
        else {
            return .refuse(status: 401, body: "{\"error\":\"Unauthorized\"}")
        }
        guard
            let data = request.body.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(CallbackBody.self, from: data)
        else {
            return .refuse(status: 400, body: "{\"error\":\"Invalid JSON\"}")
        }
        let callback = VerificationCallback(
            externalId: decoded.discordId,
            guildId: decoded.guildId,
            address: decoded.walletAddress,
            balanceBaseUnits: decoded.balance
        )
        if let refusal = CallbackValidation.refusal(
            for: callback,
            servedGuildId: servedGuildId,
            isValidAddress: isValidAddress
        ) {
            return .refuse(status: 400, body: "{\"error\":\"\(refusal.reason)\"}")
        }
        return .accepted(callback)
    }

    /// What to do about this request, asking the rate limit only when the
    /// request is the callback.
    ///
    /// **The limit counts the callback route and nothing else.** Behind a
    /// reverse proxy every request arrives from one address, so a scanner, a
    /// stray favicon fetch or a health poller sharing that address would
    /// spend the portal's whole budget and the next real callback would be
    /// answered `429`. Asking is also recording, which is why the question
    /// is a closure awaited after the path and the method match rather than
    /// a `Bool` computed before them.
    ///
    /// - Parameters:
    ///   - request: What arrived.
    ///   - expectedKey: This bot's copy of the shared secret.
    ///   - servedGuildId: The one server this process serves.
    ///   - isValidAddress: Whether an address parses on this chain.
    ///   - isRateLimited: Asked once, and only for the callback route.
    public static func route(
        _ request: HTTPRequestHead,
        expectedKey: String,
        servedGuildId: String,
        isValidAddress: @Sendable (String) -> Bool,
        isRateLimited: @Sendable () async -> Bool
    ) async -> CallbackRoute {
        // The two checks ahead of the limit are repeated rather than shared,
        // because the form below is the one every rule is tested through and
        // it takes an answer rather than a question.
        if request.method == "GET", request.route == healthPath {
            return .health
        }
        guard request.method == "POST", request.route == callbackPath else {
            return .refuse(status: 404, body: "{\"error\":\"Not Found\"}")
        }
        return route(
            request,
            expectedKey: expectedKey,
            servedGuildId: servedGuildId,
            isRateLimited: await isRateLimited(),
            isValidAddress: isValidAddress
        )
    }

    /// Whether two secrets match, without leaking how far they matched.
    ///
    /// A `==` on strings stops at the first differing byte, and the time it
    /// took is a measurement somebody can make over and over. The comparison
    /// below always walks the whole of the longer one.
    ///
    /// - Parameters:
    ///   - presented: What arrived.
    ///   - expected: This bot's copy.
    public static func constantTimeEquals(_ presented: String, _ expected: String) -> Bool {
        let left = Array(presented.utf8)
        let right = Array(expected.utf8)
        var difference = UInt8(left.count == right.count ? 0 : 1)
        let width = max(left.count, right.count)
        guard width > 0 else { return true }
        for index in 0..<width {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }

    /// The five fields the contract requires. Extra fields are ignored, so a
    /// portal may send a breakdown alongside them without breaking anything.
    private struct CallbackBody: Decodable {
        let discordId: String
        let guildId: String
        let walletAddress: String
        let balance: UInt64
        let tier: String
    }
}

/// How many callbacks one source may send.
///
/// Ten in sixty seconds, on the callback route alone. The health route and a
/// wrong path are deliberately outside it.
public actor CallbackRateLimiter {

    // MARK: - Properties

    /// How many are allowed in one window.
    public let limit: Int

    /// How long the window is.
    public let window: TimeInterval

    /// When each source's recent requests arrived.
    private var seen: [String: [Date]] = [:]

    // MARK: - Initializers

    /// - Parameters:
    ///   - limit: How many are allowed in one window.
    ///   - window: How long the window is.
    public init(limit: Int = 10, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    // MARK: - Public Methods

    /// Records one request and says whether it is over the limit.
    ///
    /// - Parameters:
    ///   - source: Where it came from.
    ///   - now: When it arrived.
    public func isLimited(source: String, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        var recent = (seen[source] ?? []).filter { $0 > cutoff }
        guard recent.count < limit else {
            seen[source] = recent
            return true
        }
        recent.append(now)
        seen[source] = recent
        return false
    }
}
